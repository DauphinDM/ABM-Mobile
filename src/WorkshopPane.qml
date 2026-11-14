import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: pane
    required property var remote
    property bool canChange: false
    signal dismissKeyboard()
    readonly property var state: remote.state
    readonly property var workshop: state.workshop || ({})
    readonly property var info: state.remoteWorkshop || ({})
    readonly property var tuning: info.tuning || ({})
    readonly property bool extended: info.version >= 2
    readonly property string identity: JSON.stringify(remote.target)
    readonly property bool ready: canChange && !workshop.restoring && !info.presetRunning
    readonly property real rpmFloor: (workshop.engines || []).reduce(function(n,e) { return Math.max(n,(e.idleRPM || 0)+100) },100)
    readonly property real rpmCeiling: (workshop.engines || []).reduce(function(n,e) { return Math.min(n,e.rpmCeiling || 0) },30000)
    function supports(name) { return (state.capabilities || {})[name] === true }
    function send(action,args) { dismissKeyboard(); remote.command(action,args || ({})) }
    function ratioValues() { return ratios.text.trim() ? ratios.text.trim().split(/[,;\s]+/).map(Number) : [] }
    function validRatios() { var values=ratioValues(); return values.length>0 && values.every(function(n){return isFinite(n) && n>=0.01 && n<=100}) }
    function suggestedRatio() {
        var values=ratioValues(),factors=[]
        if(!validRatios() || values.length<2) return NaN
        for(var i=Math.max(1,values.length-3);i<values.length;++i) { var factor=values[i]/values[i-1]; if(factor>0 && factor<1) factors.push(factor) }
        if(!factors.length) return NaN
        factors.sort(function(a,b){return a-b}); var middle=Math.floor(factors.length/2)
        var factor=factors.length%2 ? factors[middle] : (factors[middle-1]+factors[middle])/2
        var result=Number((values[values.length-1]*factor).toFixed(4)); return result>=0.01 && result<=100 ? result : NaN
    }
    function resetDrafts() {
        if (!power || !rpm || !strength || !engineProtection || !beamProtection || !consent) return
        power.text=String((workshop.enginePower === undefined ? 1 : workshop.enginePower)*100)
        rpm.text=""; strength.text="1"; engineProtection.checked=false; beamProtection.checked=false
        for (var i=0;i<handling.count;++i) handling.itemAt(i).text="1"
        for (var j=0;j<dimensions.count;++j) dimensions.itemAt(j).text="1"
        consent.checked=false
        if(ratios) ratios.text=""
        if(gravity) gravity.text="-9.81"
    }
    onIdentityChanged: resetDrafts()
    Component.onCompleted: resetDrafts()
    clip: true; contentWidth: availableWidth
    ColumnLayout {
        width: parent.width; spacing: 12
        PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: pane.ready ? qsTr("Stopped, owned vehicle. PC and game checks still apply.") : (pane.state.policyReason || qsTr("Connect a live game and stop an owned vehicle. Unsupported controls stay disabled.")) }
        PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Engine and gear values are readback. Other fields are drafts, not measured settings. Changing vehicles discards drafts.") }
        ComboBox { id: group; objectName: "workshopSection"; Layout.fillWidth: true; implicitHeight: 48; model: [qsTr("Engine & protection"),qsTr("Handling & gearbox"),qsTr("World & recovery"),qsTr("Body · experimental"),qsTr("Presets & recovery")] }
        Button { Layout.fillWidth: true; implicitHeight: 48; text: pane.workshop.persistence ? qsTr("Keep tuning on reset: ON") : qsTr("Keep tuning on reset: OFF"); enabled: pane.ready && !!pane.workshop.generation; onClicked: pane.send("persistence",{enabled:pane.workshop.persistence!==true}) }
        PlainLabel { Layout.fillWidth: true; color: pane.workshop.restoreError ? "#df6b61" : "#a0aabb"; text: (pane.workshop.restoreStatus || qsTr("Waiting for readback"))+"\n"+(pane.workshop.restoreError || "") }
        SectionPanel { visible: group.currentIndex===0; Layout.fillWidth: true
            PlainLabel { text: qsTr("Engine power"); color: "#edf1f7"; font.pixelSize: 18 }
            WorkshopNumber { id: power; inputName: "powerInput"; Layout.fillWidth: true; label: qsTr("Power percent"); text: "100"; minimum: Number.MIN_VALUE; maximum: Number.MAX_VALUE }
            Slider { Layout.fillWidth: true; implicitHeight: 48; from: 50; to: 300; stepSize: 5; enabled: pane.ready && pane.supports("power"); value: Math.max(50,Math.min(300,power.number || 100)); onMoved: power.text=String(value) }
            Button { objectName: "applyPower"; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply power %"); enabled: pane.ready && pane.supports("power") && power.valid; onClicked: pane.send("power",{value:power.number/100}) }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Engine 100%"); enabled: pane.ready && pane.supports("power"); onClicked: { power.text="100"; pane.send("power",{value:1}) } }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: pane.workshop.enginePower===undefined ? qsTr("Accepted power unavailable. Numeric entry accepts a finite positive percentage; the PC rejects overflow.") : qsTr("Accepted power: %1%").arg(pane.workshop.enginePower*100) }
            Repeater { model: pane.workshop.engines || []
                PlainLabel { required property var modelData; Layout.fillWidth: true; color: "#a0aabb"; text: modelData.name+qsTr(" · max %1 RPM · limiter %2 RPM · peak %3 Nm / %4 PS").arg(modelData.maxRPM || "—").arg(modelData.revLimiterRPM || "—").arg(modelData.maxTorque || "—").arg(modelData.maxPower || "—") }
            }
            CurveChart { Layout.fillWidth: true; visible: (pane.workshop.engines || []).length>0; points: (pane.workshop.engines || []).length ? (pane.workshop.engines[0].torqueCurve || []) : [] }
            PlainLabel { Layout.fillWidth: true; visible: (pane.workshop.engines || []).length>0; color: "#a0aabb"; text: qsTr("First supported engine torque curve. Game readback, not a measured dyno run.") }
            WorkshopNumber { id: rpm; Layout.fillWidth: true; label: qsTr("Maximum RPM (%1–%2)").arg(pane.rpmFloor).arg(pane.rpmCeiling); minimum: pane.rpmFloor; maximum: pane.rpmCeiling; integer: true }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply RPM limit"); enabled: pane.ready && pane.supports("rpm") && rpm.valid; onClicked: pane.send("rpm",{value:rpm.number}) }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Uses the existing torque curve. No synthetic power, damage-threshold change, or ESC/launch override.") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: pane.workshop.clutchProtected ? qsTr("Clutch protection: ON") : qsTr("Clutch protection: OFF"); enabled: pane.ready && pane.supports("clutch"); onClicked: pane.send("clutch",{enabled:pane.workshop.clutchProtected!==true}) }
            Repeater { model: pane.workshop.clutches || []
                PlainLabel { required property var modelData; Layout.fillWidth: true; color: "#a0aabb"; text: modelData.name+qsTr(" · temperature %1 °C · efficiency %2 · damaged: %3").arg(modelData.temperature===undefined ? "—" : modelData.temperature).arg(modelData.efficiency===undefined ? "—" : modelData.efficiency).arg(modelData.permanentlyDamaged===true) }
            }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Friction-clutch heat/wear protection raises clamp capacity 20×. No repair, DCT/automatic protection, or guarantee against drivetrain shock.") }
            WorkshopNumber { id: strength; inputName: "engineStrengthInput"; Layout.fillWidth: true; label: qsTr("Engine damage tolerance (0.1–100×)"); text: "1"; minimum: 0.1; maximum: 100 }
            CheckBox { id: engineProtection; Layout.fillWidth: true; text: qsTr("Indestructible engine"); enabled: pane.ready && pane.supports("engine") }
            Button { objectName: "applyEngine"; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply engine limits"); enabled: pane.ready && pane.supports("engine") && strength.valid; onClicked: pane.send("engine",{engineStrength:strength.number,engineIndestructible:engineProtection.checked}) }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Stock engine limits"); enabled: pane.ready && pane.supports("engine"); onClicked: { strength.text="1"; engineProtection.checked=false; pane.send("engine",{engineStrength:1,engineIndestructible:false}) } }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Protection blocks supported engine damage and hydrolocking and freezes engine heat. No repair or tire, mount, turbo, or drivetrain protection. Strength doesn't change power or RPM.") }
            CheckBox { id: beamProtection; Layout.fillWidth: true; text: qsTr("Deformation immunity"); enabled: pane.ready && pane.extended && pane.supports("deformation") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply beam limits"); enabled: beamProtection.enabled; onClicked: pane.send("deformation",{enabled:beamProtection.checked}) }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Beam limits don't protect every engine or tire. Changes may be overridden by the server or another mod.") }
        }
        SectionPanel { visible: group.currentIndex===1; Layout.fillWidth: true
            PlainLabel { text: qsTr("Grip & handling"); color: "#edf1f7"; font.pixelSize: 18 }
            Repeater { id: handling; model: [{label:qsTr("Tire grip ×"),key:"tireGrip",cap:"grip",min:0,max:10},{label:qsTr("Sliding grip ×"),key:"slidingGrip",cap:"grip",min:0,max:10},{label:qsTr("Brake strength ×"),key:"brakePower",cap:"brakes",min:0,max:10},{label:qsTr("Steering response ×"),key:"steeringResponse",cap:"steering",min:0.1,max:3}]
                WorkshopNumber { required property var modelData; Layout.fillWidth: true; label: modelData.label; text: "1"; minimum: modelData.min; maximum: modelData.max; enabled: pane.ready && pane.supports(modelData.cap) }
            }
            Button { objectName: "applyHandling"; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply handling"); enabled: pane.ready && (pane.supports("grip") || pane.supports("brakes") || pane.supports("steering")) && Array.from({length:handling.count},function(_,i) { return handling.itemAt(i) }).every(function(f) { return !f.enabled || f.valid }); onClicked: { var args={}; for(var i=0;i<handling.count;++i) { var field=handling.itemAt(i); args[field.modelData.key]=field.enabled ? field.number : 1 } pane.send("handling",args) } }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("1× = stock. Damaged tires are skipped, not repaired. Steering physical limits still apply.") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Cycle ESC / traction mode"); enabled: pane.ready && pane.supports("stability"); onClicked: pane.send("stability") }
            PlainLabel { Layout.fillWidth: true; color: "#edf1f7"; text: qsTr("Gearbox: %1").arg(pane.workshop.gearboxType || qsTr("unsupported")); font.pixelSize: 18 }
            TextField { id: ratios; Layout.fillWidth: true; implicitHeight: 48; placeholderText: qsTr("Forward ratios (no sample defaults)"); maximumLength: 24000; enabled: pane.ready && pane.supports("gears"); property bool dirty: false; onTextEdited: dirty=true }
            Repeater { model: pane.workshop.gears || []
                PlainLabel { required property var modelData; Layout.fillWidth: true; color: "#a0aabb"; text: (modelData.index<0 ? "R"+Math.abs(modelData.index) : modelData.index===0 ? "N" : String(modelData.index))+" · "+modelData.ratio }
            }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Read actual ratios"); enabled: (pane.workshop.gears || []).length>0; onClicked: ratios.text=(pane.workshop.gears || []).filter(function(g){return g.index>0}).sort(function(a,b){return a.index-b.index}).map(function(g){return g.ratio}).join(", ") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("+ Gear"); enabled: pane.ready && pane.supports("gears") && ["manual","automatic","dct","sequential"].indexOf(pane.workshop.gearboxType)>=0 && isFinite(pane.suggestedRatio()) && ratios.text.length<23980; onClicked: ratios.text+=", "+pane.suggestedRatio() }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Remove last gear"); enabled: pane.ready && pane.workshop.gearboxType!=="cvt" && pane.ratioValues().length>1; onClicked: ratios.text=pane.ratioValues().slice(0,-1).join(", ") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply ratios"); enabled: pane.ready && pane.supports("gears") && pane.validRatios(); onClicked: pane.send("gears",{ratios:ratios.text}) }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Ratios 0.01–100. Reverse and neutral stay fixed. CVT accepts one fixed ratio. Readback never silently replaces your edits.") }
        }
        SectionPanel { visible: group.currentIndex===2; Layout.fillWidth: true
            WorkshopNumber { id: gravity; Layout.fillWidth: true; label: qsTr("World gravity (m/s²)"); text: "-9.81"; minimum: -30; maximum: 0 }
            Flow { Layout.fillWidth: true; spacing: 8
                Repeater { model: [{n:qsTr("Earth"),g:-9.81},{n:qsTr("Moon"),g:-1.62},{n:qsTr("Mars"),g:-3.71},{n:qsTr("Venus"),g:-8.87},{n:qsTr("Jupiter"),g:-24.92},{n:qsTr("Pluto"),g:-0.58},{n:qsTr("Zero-g"),g:0}]
                    Button { required property var modelData; implicitHeight: 48; text: modelData.n; enabled: pane.ready && pane.extended; onClicked: { gravity.text=String(modelData.g); pane.send("gravity",{value:modelData.g}) } }
                }
            }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply gravity"); enabled: pane.ready && pane.extended && gravity.valid; onClicked: pane.send("gravity",{value:gravity.number}) }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Gravity affects the entire world, not just your car.") }
            Repeater { model: [{a:"repair",t:qsTr("Repair"),c:"repair"},{a:"ignite",t:qsTr("Fire"),c:"ignite"},{a:"extinguish",t:qsTr("Extinguish"),c:"extinguish"},{a:"deflate",t:qsTr("Deflate tires"),c:"deflate"},{a:"dealer",t:qsTr("Why This Dealer?"),c:"dealer"}]
                Button { required property var modelData; Layout.fillWidth: true; implicitHeight: 48; text: modelData.t; enabled: pane.ready && pane.extended && pane.supports(modelData.c); onClicked: pane.send(modelData.a) }
            }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Stop bouncing"); enabled: pane.remote.connected && pane.extended && pane.supports("dealer"); onClicked: pane.send("dealerStop") }
        }
        SectionPanel { visible: group.currentIndex===3; Layout.fillWidth: true
            PlainLabel { text: qsTr("Physical dimensions · experimental"); Layout.fillWidth: true; color: "#edf1f7"; font.pixelSize: 18 }
            Repeater { id: dimensions; model: [qsTr("Width ×"),qsTr("Length ×"),qsTr("Height ×")]
                WorkshopNumber { required property string modelData; Layout.fillWidth: true; label: modelData; text: "1"; minimum: 0.5; maximum: 2 }
            }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Changes nodes and beam rest lengths, not just visuals. Stop and repair broken beams first. Mass and tires stay unchanged. Suspension, wheels and props may fight resizing. BeamMP resizing is local, NOT synchronized. Persistence reapplies to clean geometry; failures suspend.") }
            CheckBox { id: consent; Layout.fillWidth: true; text: qsTr("I accept unstable physics and damage") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply physical dimensions"); enabled: pane.ready && pane.extended && pane.supports("dimensions") && consent.checked && dimensions.itemAt(0).valid && dimensions.itemAt(1).valid && dimensions.itemAt(2).valid; onClicked: pane.send("dimensions",{width:dimensions.itemAt(0).number,length:dimensions.itemAt(1).number,height:dimensions.itemAt(2).number,confirmed:true}) }
        }
        SectionPanel { visible: group.currentIndex===4; Layout.fillWidth: true
            PlainLabel { text: qsTr("PC-owned ABM presets"); color: "#edf1f7"; font.pixelSize: 18 }
            TextField { id: presetName; Layout.fillWidth: true; implicitHeight: 48; maximumLength: 80; placeholderText: qsTr("New preset name") }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Save current accepted settings"); enabled: pane.ready && pane.extended && presetName.text.trim().length>0; onClicked: pane.send("presetSave",{name:presetName.text}) }
            Repeater { model: pane.info.presets || []
                ColumnLayout { required property var modelData; Layout.fillWidth: true
                    PlainLabel { Layout.fillWidth: true; color: "#edf1f7"; text: modelData.name+" · "+((modelData.configuration || {}).label || "") }
                    PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: modelData.error || (modelData.settings || []).join(", ") }
                    Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Review & apply preset"); enabled: pane.ready && pane.extended && !modelData.error; onClicked: { presetConfirm.presetId=modelData.id; presetConfirm.presetName=modelData.name; presetConfirm.open() } }
                }
            }
            PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; text: (pane.info.presetProgress || "")+"\n"+(pane.info.presetMessage || pane.info.storeMessage || qsTr("Presets contain accepted ABM overrides, not native .pc files. Rename, notes, import and export remain on the PC.")) }
            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Cancel preset application"); enabled: pane.extended && pane.remote.connected && pane.info.presetRunning===true; onClicked: pane.send("presetCancel") }
        }
        PlainLabel { visible: !pane.extended; Layout.fillWidth: true; color: "#a0aabb"; text: qsTr("Update PC ABM for gravity, beam protection, dimensions and presets. Engine and handling commands are supported by older Connect hosts.") }
        Button { objectName: "fullResetButton"; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Full reset · clear ABM vehicle tuning"); enabled: pane.ready; onClicked: resetConfirm.open() }
    }
    Dialog { id: resetConfirm; parent: Overlay.overlay; anchors.centerIn: parent; width: Math.min(440,parent.width-24); modal: true; title: qsTr("Clear ABM tuning & reset?"); standardButtons: Dialog.Ok | Dialog.Cancel
        PlainLabel { width: parent.width; text: qsTr("Clears the accepted recipe and restores the loaded configuration. This may reset the car. Saved named presets aren't deleted. World gravity is separate."); color: "#edf1f7" }
        property string frozen: ""
        onOpened: frozen=pane.identity
        onAccepted: if(frozen===pane.identity && pane.ready) pane.send("fullReset")
    }
    Dialog { id: presetConfirm; property string presetId: ""; property string presetName: ""; property string frozen: ""; parent: Overlay.overlay; anchors.centerIn: parent; width: Math.min(440,parent.width-24); modal: true; title: qsTr("Apply %1?").arg(presetName); standardButtons: Dialog.Ok | Dialog.Cancel
        PlainLabel { width: parent.width; text: qsTr("The PC checks model/config compatibility and applies accepted steps in order. A later failure does not roll back earlier steps."); color: "#edf1f7" }
        onOpened: frozen=pane.identity
        onAccepted: if(frozen===pane.identity && pane.ready) pane.send("presetApply",{id:presetId,confirmed:true})
    }
}
