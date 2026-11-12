import SwiftUI
import UIKit

struct DashboardView: View {
    @ObservedObject var client: CompanionClient
    @State private var tab = 4
    @State private var metric = true
    @State private var power = "100"
    @State private var rpm = ""
    @State private var ratios = ""
    @State private var model = ""
    @State private var configuration = ""
    @State private var device = "My iPhone"
    @State private var invitation = ""
    @State private var pending: GameRequest?
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]
    private var telemetry: JSONValue { client.state["telemetry"] }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Drive", systemImage: "speedometer", value: 0) { page("Drive") { drive } }
            Tab("Car", systemImage: "wrench.and.screwdriver", value: 1) { page("Workshop") { workshop } }
            Tab("Garage", systemImage: "car.2", value: 2) { page("Garage") { garage } }
            Tab("Session", systemImage: "person.2", value: 3) { page("Session") { session } }
            Tab("Connect", systemImage: "link", value: 4) { page("Connect") { connect } }
        }
        .confirmationDialog(pending?.title ?? "Confirm request", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let request = pending {
                Button("Send to PC", role: request.action == "replace" || request.action == "fullReset" ? .destructive : nil) {
                    client.command(request.action, args: request.args, frozenTarget: request.target)
                    pending = nil
                }
                .accessibilityIdentifier("confirmGameAction")
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("This can change physics or replace a vehicle. The PC and game recheck ownership, movement and server policy. A receipt is not verified game acceptance.")
        }
        .onChange(of: client.target) { _, _ in
            pending = nil; power = "100"; rpm = ""; ratios = ""; configuration = ""; model = ""
        }
        .onChange(of: client.connected) { _, connected in if !connected { pending = nil } }
        .onAppear {
            #if DEBUG
            // The simulator fixture seeds a field, never approval or game state.
            invitation = ProcessInfo.processInfo.environment["ABM_TEST_INVITATION"] ?? ""
            #endif
        }
    }

    private func page<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                    VStack(alignment: .leading, spacing: 8) {
                        Label(client.connected ? "Paired with PC" : "Not connected", systemImage: client.connected ? "checkmark.shield" : "wifi.slash")
                            .font(.caption.weight(.semibold)).foregroundStyle(client.connected ? .green : .secondary)
                        Text(client.message).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("connectionMessage")
                        if !client.actionMessage.isEmpty { Text(client.actionMessage).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.063, green: 0.078, blue: 0.106))
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Text("ABM").font(.headline).foregroundStyle(.yellow).accessibilityLabel("ABM Mobile")
            } }
        }
    }

    private var drive: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(client.state["vehicle"].text.isEmpty ? "Waiting for your game" : client.state["vehicle"].text).font(.headline).foregroundStyle(.secondary)
            panel {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speed).font(.system(size: 76, weight: .light, design: .rounded)).minimumScaleFactor(0.4).lineLimit(1).monospacedDigit()
                        Text(metric ? "km/h" : "mph").foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack {
                        Text("GEAR").font(.caption).foregroundStyle(.secondary)
                        Text(client.connected ? telemetry["gear"].display : "—").font(.system(size: 42, weight: .medium, design: .rounded)).foregroundStyle(.yellow)
                    }
                }
                ProgressView(value: rpmFraction).tint(rpmFraction > 0.9 ? .red : .yellow)
                Text("\(telemetry["rpm"].display) RPM").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                metricCard("Engine", value: telemetry["rpm"].number, unit: "RPM")
                metricCard("Fuel", value: telemetry["fuel"].number.map { $0 * 100 }, unit: "%")
                metricCard("Coolant", value: telemetry["waterTemp"].number, unit: "°C")
                metricCard("Latency", value: client.state["ping"].number, unit: "ms")
            }
            Button(metric ? "Use mph" : "Use km/h") { metric.toggle() }.buttonStyle(.glass)
            Text("Live telemetry from your PC. This app is not a steering wheel or throttle controller.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var speed: String {
        guard client.connected, let value = telemetry["speed"].number else { return "—" }
        return (value * (metric ? 3.6 : 2.23694)).formatted(.number.precision(.fractionLength(0)))
    }
    private var rpmFraction: Double {
        min(1, max(0, (telemetry["rpm"].number ?? 0) / max(100, telemetry["maxRPM"].number ?? 8000)))
    }

    private var workshop: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(client.canChange ? "Stopped, owned vehicle. Every request is checked again by the PC and game." : "Connect a live game and stop an owned vehicle on a permitted server to change settings.")
                .font(.footnote).foregroundStyle(.secondary)
            panel {
                Text("Engine").font(.title3.bold())
                TextField("Power percent (1–2000)", text: $power).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityLabel("Power percent")
                actionButton("Apply power", action: "power", args: ["value": .number((Double(power) ?? 0) / 100)], valid: validNumber(power, range: 1...2000) && client.state["capabilities"]["power"].flag)
                TextField("Maximum RPM (100–30000)", text: $rpm).keyboardType(.numberPad).textFieldStyle(.roundedBorder).accessibilityLabel("Maximum RPM")
                actionButton("Apply RPM limit", action: "rpm", args: ["value": .number(Double(rpm) ?? 0)], valid: validNumber(rpm, range: 100...30000))
                actionButton("Enable clutch protection", action: "clutch", args: ["enabled": .bool(true)])
                actionButton("Disable clutch protection", action: "clutch", args: ["enabled": .bool(false)])
            }
            panel {
                Text("Gearbox").font(.title3.bold())
                Text("Forward ratios, separated by spaces. Transmission support and readback are enforced by the game.").font(.footnote).foregroundStyle(.secondary)
                TextField("3.5 2.1 1.4 1.0 0.8", text: $ratios, axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel("Forward gear ratios")
                actionButton("Apply ratios", action: "gears", args: ["ratios": .string(ratios)], valid: !ratios.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ratios.utf8.count <= 24000)
            }
            panel {
                Text("Vehicle actions").font(.title3.bold())
                actionButton("Repair", action: "repair", identifier: "repairVehicle")
                actionButton("Extinguish", action: "extinguish")
                actionButton("Stabilize", action: "stability")
                actionButton("Clear ABM tuning & reset", action: "fullReset")
            }
        }
    }

    private var garage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(model.isEmpty ? "Refresh models" : "Back to models", systemImage: model.isEmpty ? "arrow.clockwise" : "chevron.left") {
                    model = ""; configuration = ""; client.command("catalog")
                }.buttonStyle(.glass).disabled(!client.canBrowse)
                Spacer()
            }
            Text("Your PC's vehicle library. Photos are not transferred in this first version.").font(.footnote).foregroundStyle(.secondary)
            let items = model.isEmpty ? client.snapshot["catalog"].array : (client.snapshot["configsModel"].text == model ? client.snapshot["configs"].array : [])
            if items.isEmpty { ContentUnavailableView("No vehicles loaded", systemImage: "car.2", description: Text("Connect a game, then refresh the library.")) }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        if model.isEmpty { model = item["id"].text; client.command("configs", args: ["model": .string(model)]) }
                        else { configuration = item["id"].text }
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "car.side").font(.system(size: 36)).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 80)
                            Text(item["name"].text.isEmpty ? item["id"].display : item["name"].text).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text(configuration == item["id"].text ? "Selected" : "PC catalog").font(.caption).foregroundStyle(.secondary)
                        }.padding(16).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(configuration == item["id"].text ? Color.yellow : .clear))
                    }.buttonStyle(.plain).disabled(!client.canBrowse)
                }
            }
            HStack {
                actionButton("Spawn", action: "spawn", args: ["config": .string(configuration)], valid: !configuration.isEmpty)
                actionButton("Replace", action: "replace", args: ["config": .string(configuration)], valid: !configuration.isEmpty)
            }
        }
    }

    private var session: some View {
        VStack(alignment: .leading, spacing: 16) {
            panel {
                Text(client.state["server"].text.isEmpty ? (client.state["connected"].flag ? "Single player" : "No live game") : client.state["server"].text).font(.title3.bold())
                Text("Session IDs are temporary, not permanent account IDs. The phone cannot grant server permission or control another player's vehicle.").font(.footnote).foregroundStyle(.secondary)
                Button("Copy server address", systemImage: "doc.on.doc") { UIPasteboard.general.string = CompanionWire.serverAddress(client.state) }
                    .buttonStyle(.glass).disabled(CompanionWire.serverAddress(client.state).isEmpty)
            }
            ForEach(Array(client.state["players"].array.enumerated()), id: \.offset) { _, player in
                panel {
                    let name = player["rawName"].text.isEmpty ? player["name"].text : player["rawName"].text
                    Text(name).font(.headline)
                    Text("Session ID: \(player["sessionPlayerId"].display)").font(.caption).foregroundStyle(.secondary)
                    Button("Copy name", systemImage: "doc.on.doc") { UIPasteboard.general.string = name }.buttonStyle(.glass)
                }
            }
            ForEach(Array(client.state["activeVehicles"].array.filter { $0["owned"].flag }.enumerated()), id: \.offset) { _, vehicle in
                actionButton("Switch to \(vehicle["name"].text)", action: "switch", args: ["id": vehicle["id"]])
            }
            actionButton("Reset trip", action: "resetTrip")
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 20) {
            panel {
                Label("Connect to PC ABM", systemImage: "desktopcomputer").font(.title3.bold())
                Text("1. Put your phone and PC on the same private Wi-Fi.\n2. Enable access in PC ABM → Connect and copy its pairing link.\n3. Paste it here, connect, then approve this iPhone on the PC.")
                TextField("Device name", text: $device).textFieldStyle(.roundedBorder).textInputAutocapitalization(.words).accessibilityIdentifier("deviceNameInput")
                TextField("abm://pair/…", text: $invitation, axis: .vertical)
                    .lineLimit(3...5).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().accessibilityLabel("Pairing link").accessibilityIdentifier("pairingLinkInput")
                Button("Connect & request PC approval", systemImage: "link") {
                    client.pair(link: invitation, device: device); invitation = ""
                }
                .buttonStyle(.glassProminent).frame(minHeight: 44)
                .disabled(client.connected || invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("pairPhone")
                Button("Disconnect", systemImage: "xmark.circle") { client.disconnect() }.buttonStyle(.glass).frame(minHeight: 44)
            }
            panel {
                Label("Private, encrypted, revocable", systemImage: "lock.shield").font(.headline)
                Text("The link pins your PC's TLS certificate. Access requires PC approval and expires when disconnected. No cloud, saved password, discovery broadcast or automatic reconnect. Controls disable if updates stop or this app leaves the foreground. Never publish a pairing link or forward the PC port to the internet.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Requires the Connect-enabled PC development build, not the published PC 0.12.0 release.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
    private func metricCard(_ name: LocalizedStringKey, value: Double?, unit: String) -> some View {
        panel {
            Text(name).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(value?.formatted(.number.precision(.fractionLength(0))) ?? "—").font(.title2.monospacedDigit())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func validNumber(_ text: String, range: ClosedRange<Double>) -> Bool {
        guard let value = Double(text), value.isFinite else { return false }; return range.contains(value)
    }
    private func actionButton(_ title: String, action: String, args: [String: JSONValue] = [:], valid: Bool = true, identifier: String = "") -> some View {
        Button(title) { pending = GameRequest(title: title + "?", action: action, args: args, target: client.target) }
            .buttonStyle(.glass).frame(minHeight: 44).disabled(!client.canChange || !valid)
            .accessibilityIdentifier(identifier.isEmpty ? action : identifier)
    }
}
