import SwiftUI
import Charts

struct WorkshopView: View {
    @ObservedObject var client: CompanionClient
    @State private var group = 0
    @State private var values: [String:String] = [:]
    @State private var engineProtection = false
    @State private var beamProtection = false
    @State private var dimensionsConsent = false
    @State private var selectedEngine = 0
    @State private var confirmAction = ""
    @State private var showConfirmation = false
    @State private var confirmArgs: [String:JSONValue] = [:]
    @State private var confirmTarget: JSONValue = .null
    @FocusState private var focused: String?
    private var state: JSONValue { client.state }
    private var workshop: JSONValue { state["workshop"] }
    private var info: JSONValue { state["remoteWorkshop"] }
    private var ready: Bool { client.canChange && !workshop["restoring"].flag && !info["presetRunning"].flag }
    private var engines: [JSONValue] { workshop["engines"].array }
    private var engine: JSONValue { engines.indices.contains(selectedEngine) ? engines[selectedEngine] : .null }
    private func supports(_ key: String) -> Bool { state["capabilities"][key].flag }
    private func text(_ key: String, _ fallback: String = "") -> String { values[key] ?? fallback }
    private func binding(_ key: String, _ fallback: String = "") -> Binding<String> {
        Binding(get: { text(key,fallback) }, set: { values[key]=$0 })
    }
    private func value(_ key: String, _ fallback: Double = 1) -> Double { Double(text(key,String(fallback))) ?? .nan }
    private func valid(_ key: String, _ range: ClosedRange<Double>, _ fallback: String = "1") -> Bool {
        WorkshopRules.number(text(key,fallback),range: range) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ready ? "Stopped, owned vehicle. PC and game checks still apply." : (state["policyReason"].text.isEmpty ? "Connect a live game and stop an owned vehicle. Unsupported controls stay disabled." : state["policyReason"].text))
                .font(.footnote).foregroundStyle(.secondary)
            Picker("Workshop section",selection: $group) {
                Text("Engine & protection").tag(0)
                Text("Handling & gearbox").tag(1)
                Text("World & recovery").tag(2)
                Text("Body · experimental").tag(3)
                Text("Presets & recovery").tag(4)
            }.pickerStyle(.menu).accessibilityIdentifier("workshopSection")
            action(workshop["persistence"].flag ? "Keep tuning on reset: ON" : "Keep tuning on reset: OFF", "persistence",
                   ["enabled":.bool(!workshop["persistence"].flag)], valid: !workshop["generation"].text.isEmpty)
            if !workshop["restoreStatus"].text.isEmpty { Text(workshop["restoreStatus"].text).font(.caption).foregroundStyle(.secondary) }
            if !workshop["restoreError"].text.isEmpty { Text(workshop["restoreError"].text).font(.footnote).foregroundStyle(.red) }
            switch group {
            case 0: engineControls
            case 1: handlingControls; gearboxControls
            case 2: worldControls
            case 3: dimensionControls
            default: presets
            }
            Text("Engine and gear values are readback. Other fields are drafts, not measured settings. A vehicle change discards drafts; telemetry never replaces edits while typing.")
                .font(.footnote).foregroundStyle(.secondary)
            if (info["version"].number ?? 0)<2 {
                Text("Update PC ABM for gravity, beam protection, dimensions and presets. Older Connect hosts support engine and handling commands.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Full reset · clear ABM vehicle tuning",role: .destructive) { confirm("fullReset") }
                .buttonStyle(.glass).frame(minHeight: 44).disabled(!ready).accessibilityIdentifier("fullResetButton")
        }
        .onAppear { resetDrafts() }
        .onChange(of: client.target) { _, _ in resetDrafts(); focused=nil; confirmAction=""; showConfirmation=false }
        .onChange(of: group) { _, _ in focused=nil }
        .confirmationDialog("Apply disruptive vehicle changes?",isPresented: $showConfirmation,titleVisibility: .visible) {
            Button("Apply",role: .destructive) {
                let action=confirmAction, args=confirmArgs, target=confirmTarget
                confirmAction=""; focused=nil
                if ready { client.command(action,args:args,frozenTarget:target) }
            }
            Button("Cancel",role: .cancel) { confirmAction="" }
        } message: {
            Text(confirmAction=="fullReset" ? "Clears the accepted recipe and restores the loaded configuration. This may reset the car. Named presets aren't deleted. World gravity is separate." : "The PC checks model/config compatibility and applies preset steps in order. A later failure doesn't roll back earlier accepted steps.")
        }
    }

    private var engineControls: some View {
        VStack(alignment: .leading,spacing:16) {
            panel("Engine power") {
                number("Power percent",key:"power",fallback:"100",enabled:supports("power"))
                Slider(value: Binding(get: { min(300,max(50,value("power",100))) },set: { values["power"]=String(Int($0)) }),in:50...300,step:5)
                    .disabled(!ready || !supports("power")).accessibilityLabel("Power percent, slider 50 to 300")
                action("Apply power","power",["value":.number(value("power",100)/100)],valid:valid("power",Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude,"100") && supports("power"))
                action("Engine 100%","power",["value":.number(1)],valid:supports("power"),identifier:"restorePower")
                Text("Numeric entry accepts any finite positive percentage. The PC rejects derived overflow. This isn't measured horsepower.").font(.footnote).foregroundStyle(.secondary)
                Text(workshop["enginePower"].number.map { "Accepted power: \(($0*100).formatted())%" } ?? "Accepted power unavailable").font(.caption).foregroundStyle(.secondary)
                if engines.count>1 {
                    Picker("Engine readback",selection:$selectedEngine) {
                        ForEach(engines.indices,id:\.self) { index in Text(engines[index]["name"].text).tag(index) }
                    }
                }
                if engine != .null {
                    Text("\(engine["name"].display) · max \(engine["maxRPM"].display) RPM · limiter \(engine["revLimiterRPM"].display) RPM").font(.footnote)
                    if engine["torqueCurve"].array.count>1 {
                        Chart(Array(engine["torqueCurve"].array.enumerated()),id:\.offset) { _, point in
                            if let rpm=point["rpm"].number, let torque=point["torque"].number {
                                LineMark(x:.value("RPM",rpm),y:.value("Torque (Nm)",torque)).foregroundStyle(.yellow)
                            }
                        }.frame(height:150).accessibilityLabel("Supported engine torque curve; game readback, not a dyno result")
                    }
                    Text("Peak \(engine["maxTorque"].display) Nm at \(engine["maxTorqueRPM"].display) RPM · \(engine["maxPower"].display) PS at \(engine["maxPowerRPM"].display) RPM. These controls apply to the supported engine set, not just the selected readback.").font(.footnote).foregroundStyle(.secondary)
                }
                number("Maximum RPM",key:"rpm",enabled:supports("rpm"))
                let range=WorkshopRules.rpmRange(workshop)
                action("Apply RPM limit","rpm",["value":.number(value("rpm",0))],valid:supports("rpm") && range.map { valid("rpm",$0,"") && value("rpm",0).rounded()==value("rpm",0) } == true)
                Text(range.map { "Allowed: \(Int($0.lowerBound))–\(Int($0.upperBound)) RPM. Uses the existing curve; no synthetic power, damage-threshold change or ESC/launch override." } ?? "Waiting for supported combustion limiter readback.").font(.footnote).foregroundStyle(.secondary)
                action(workshop["clutchProtected"].flag ? "Clutch protection: ON" : "Clutch protection: OFF","clutch",["enabled":.bool(!workshop["clutchProtected"].flag)],valid:supports("clutch"))
                ForEach(Array(workshop["clutches"].array.enumerated()),id:\.offset) { _, clutch in
                    Text("\(clutch["name"].display) · \(clutch["temperature"].display) °C · efficiency \(clutch["efficiency"].display) · damaged: \(clutch["permanentlyDamaged"].flag ? "yes" : "no")").font(.caption).foregroundStyle(.secondary)
                }
                Text("Friction-clutch heat/wear protection raises clamp capacity 20×. No repair, DCT/automatic protection, or guarantee against drivetrain shock.").font(.footnote).foregroundStyle(.secondary)
            }
            panel("Engine durability & protection") {
                number("Damage tolerance (0.1–100×)",key:"strength",fallback:"1",enabled:supports("engine"))
                Toggle("Indestructible engine",isOn:$engineProtection).disabled(!ready || !supports("engine"))
                action("Apply engine limits","engine",["engineStrength":.number(value("strength")),"engineIndestructible":.bool(engineProtection)],valid:supports("engine") && valid("strength",0.1...100))
                action("Stock engine limits","engine",["engineStrength":.number(1),"engineIndestructible":.bool(false)],valid:supports("engine"),identifier:"stockEngineLimits")
                Text("Strength doesn't change power or RPM. Protection blocks supported engine damage and hydrolocking and freezes engine heat. No repair or tire, mount, turbo, or drivetrain protection. OFF restores damage at the selected strength.").font(.footnote).foregroundStyle(.secondary)
                Toggle("Deformation immunity",isOn:$beamProtection).disabled(!ready || !supports("deformation"))
                action("Apply beam limits","deformation",["enabled":.bool(beamProtection)],valid:supports("deformation"))
                Text("Beam protection changes deformation and strength limits, not every engine or tire failure.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var handlingControls: some View {
        panel("Grip & handling") {
            number("Tire grip ×",key:"tireGrip",fallback:"1",enabled:supports("grip"))
            number("Sliding grip ×",key:"slidingGrip",fallback:"1",enabled:supports("grip"))
            number("Brake strength ×",key:"brakePower",fallback:"1",enabled:supports("brakes"))
            number("Steering response ×",key:"steeringResponse",fallback:"1",enabled:supports("steering"))
            action("Apply handling","handling",handlingArguments,valid:handlingValid)
            action("Cycle ESC / traction mode","stability",valid:supports("stability"))
            Text("1× = stock. Grip/brakes: 0–10×. Steering: 0.1–3× within physical limits. Damaged tires are skipped, not repaired. Other controllers may override changes.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var handlingArguments: [String:JSONValue] {
        ["tireGrip":.number(supports("grip") ? value("tireGrip") : 1),"slidingGrip":.number(supports("grip") ? value("slidingGrip") : 1),"brakePower":.number(supports("brakes") ? value("brakePower") : 1),"steeringResponse":.number(supports("steering") ? value("steeringResponse") : 1)]
    }
    private var handlingValid: Bool {
        (supports("grip") || supports("brakes") || supports("steering")) && (!supports("grip") || (valid("tireGrip",0...10) && valid("slidingGrip",0...10))) && (!supports("brakes") || valid("brakePower",0...10)) && (!supports("steering") || valid("steeringResponse",0.1...3))
    }
    private var gearboxControls: some View {
        panel("Gearbox & ratios") {
            Text(workshop["gearboxType"].text.isEmpty ? "No supported transmission readback" : workshop["gearboxType"].text).font(.subheadline)
            ForEach(Array(workshop["gears"].array.enumerated()),id:\.offset) { _, gear in
                Text("Gear \(gear["index"].display) · actual ratio \(gear["ratio"].display)").font(.caption.monospacedDigit())
            }
            TextField("Forward ratios",text:binding("ratios"),axis:.vertical).textFieldStyle(.roundedBorder).focused($focused,equals:"ratios").accessibilityLabel("Forward gear ratios")
            Button("Read actual ratios") { readRatios() }.buttonStyle(.glass).disabled(workshop["gears"].array.isEmpty)
            Button("+ Gear") {
                if let next=WorkshopRules.nextRatio(text("ratios")) { values["ratios"]=text("ratios")+", "+String(next) }
            }.buttonStyle(.glass).disabled(!ready || !["manual","automatic","dct","sequential"].contains(workshop["gearboxType"].text) || WorkshopRules.nextRatio(text("ratios"))==nil)
            Button("Remove last gear") {
                if var ratios=WorkshopRules.ratios(text("ratios")), ratios.count>1 { ratios.removeLast(); values["ratios"]=ratios.map(String.init(describing:)).joined(separator:", ") }
            }.buttonStyle(.glass).disabled(!ready || workshop["gearboxType"].text=="cvt" || (WorkshopRules.ratios(text("ratios"))?.count ?? 0)<=1)
            action("Apply ratios","gears",["ratios":.string(text("ratios"))],valid:supports("gears") && WorkshopRules.ratios(text("ratios")) != nil)
            Text("Ratios 0.01–100; reverse and neutral stay fixed. + Gear uses the median of the last three valid gaps, not a guaranteed optimum. CVT accepts one fixed ratio. Actual updates never replace edits automatically.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var worldControls: some View {
        panel("World & recovery") {
            number("World gravity (−30 to 0 m/s²)",key:"gravity",fallback:"-9.81")
            let planets: [(String,Double)] = [("Earth",-9.81),("Moon",-1.62),("Mars",-3.71),("Venus",-8.87),("Jupiter",-24.92),("Pluto",-0.58),("Zero-g",0)]
            ForEach(planets,id:\.0) { name, gravity in action(name,"gravity",["value":.number(gravity)],identifier:"gravity"+name) }
            action("Apply gravity","gravity",["value":.number(value("gravity",-9.81))],valid:valid("gravity",-30...0,"-9.81"))
            Text("Gravity affects the entire world, not just your vehicle.").font(.footnote).foregroundStyle(.secondary)
            action("Repair","repair",valid:supports("repair"),identifier:"repairVehicle")
            action("Fire","ignite",valid:supports("ignite"))
            action("Extinguish","extinguish",valid:supports("extinguish"))
            action("Deflate tires","deflate",valid:supports("deflate"))
            action("Why This Dealer?","dealer",valid:supports("dealer"))
            Button("Stop bouncing") { focused=nil; client.command("dealerStop") }.buttonStyle(.glass).frame(minHeight:44).disabled(!client.connected || !supports("dealer"))
        }
    }
    private var dimensionControls: some View {
        panel("Physical dimensions · experimental") {
            number("Width × (0.5–2)",key:"width",fallback:"1")
            number("Length × (0.5–2)",key:"length",fallback:"1")
            number("Height × (0.5–2)",key:"height",fallback:"1")
            Text("Changes nodes and beam rest lengths, not just visuals. Stop and repair broken beams first. Mass and tires stay unchanged. Suspension, wheels and props may fight resizing. BeamMP resizing is local, NOT synchronized. Persistence reapplies to clean reset geometry; failures suspend.").font(.footnote).foregroundStyle(.secondary)
            Toggle("I accept unstable physics and vehicle damage",isOn:$dimensionsConsent)
            action("Apply physical dimensions","dimensions",["width":.number(value("width")),"length":.number(value("length")),"height":.number(value("height")),"confirmed":.bool(true)],valid:supports("dimensions") && dimensionsConsent && ["width","length","height"].allSatisfy { valid($0,0.5...2) })
        }
    }
    private var presets: some View {
        panel("PC-owned ABM presets") {
            TextField("New preset name",text:binding("presetName")).textFieldStyle(.roundedBorder).focused($focused,equals:"presetName")
            action("Save current accepted settings","presetSave",["name":.string(text("presetName"))],valid:!text("presetName").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && text("presetName").utf16.count<=80)
            ForEach(Array(info["presets"].array.enumerated()),id:\.offset) { _, preset in
                Text(preset["name"].display).font(.headline)
                Text(preset["configuration"]["label"].display).font(.caption).foregroundStyle(.secondary)
                Text(preset["settings"].array.map(\.text).joined(separator:", ")).font(.caption).foregroundStyle(.secondary)
                Button("Review & apply preset") { confirm("presetApply",["id":preset["id"],"confirmed":.bool(true)]) }
                    .buttonStyle(.glass).frame(minHeight:44).disabled(!ready || !CompanionWire.workshopAvailable("presetApply",state:state) || !preset["error"].text.isEmpty)
            }
            Text(info["presetProgress"].text+"\n"+info["presetMessage"].text+"\n"+info["storeMessage"].text).font(.footnote).foregroundStyle(.secondary)
            Button("Cancel preset application") { client.command("presetCancel") }.buttonStyle(.glass).disabled(!client.connected || !info["presetRunning"].flag)
            Text("Presets store accepted ABM overrides, not native .pc files. Rename, notes, import and export remain on the PC. Applying a preset can partly succeed; accepted steps aren't rolled back automatically.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func resetDrafts() {
        values=["power":String(format:"%.12g",(workshop["enginePower"].number ?? 1)*100)]
        engineProtection=false; beamProtection=false; dimensionsConsent=false; selectedEngine=0
        readRatios()
    }
    private func readRatios() {
        values["ratios"]=workshop["gears"].array.filter { ($0["index"].number ?? 0)>0 }.sorted { ($0["index"].number ?? 0)<($1["index"].number ?? 0) }.compactMap { $0["ratio"].number }.map(String.init(describing:)).joined(separator:", ")
    }
    private func confirm(_ action: String,_ args: [String:JSONValue]=[:]) { focused=nil; confirmTarget=client.target; confirmArgs=args; confirmAction=action; showConfirmation=true }
    private func action(_ title: String,_ name: String,_ args: [String:JSONValue]=[:],valid:Bool=true,identifier:String="") -> some View {
        Button(title) { focused=nil; client.command(name,args:args,frozenTarget:client.target) }.buttonStyle(.glass).frame(minHeight:44)
            .disabled(!ready || !valid || !CompanionWire.workshopAvailable(name,state:state)).accessibilityIdentifier(identifier.isEmpty ? name : identifier)
    }
    private func number(_ title:String,key:String,fallback:String="",enabled:Bool=true) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.subheadline)
            TextField(title,text:binding(key,fallback)).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
                .focused($focused,equals:key).disabled(!ready || !enabled).accessibilityLabel(title).accessibilityIdentifier(key+"Input")
        }
    }
    private func panel<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:14) { Text(title).font(.title3.bold()); content() }
            .frame(maxWidth:.infinity,alignment:.leading).padding(18).background(Color.white.opacity(0.045),in:RoundedRectangle(cornerRadius:18))
    }
}
