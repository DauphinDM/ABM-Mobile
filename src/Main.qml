import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true; width: 412; height: 860; minimumWidth: 320; minimumHeight: 440
    title: "ABM Mobile"; color: "#10141b"; font.pixelSize: 14
    property int page: 4
    onPageChanged: dismissKeyboard()
    property bool metric: true
    readonly property var game: remote.state
    readonly property var telemetry: game.telemetry || ({})
    readonly property var workshop: game.workshop || ({})
    readonly property bool live: remote.connected && game.connected === true
    readonly property bool stopped: typeof telemetry.speed === "number" && telemetry.speed <= 1
    readonly property bool canChange: live && !remote.busy && game.controlsAvailable === true && game.sandboxAllowed === true && game.vehicleOwned === true && !game.joining && !game.policyCleanup && stopped
    readonly property bool canSpawn: live && !remote.busy && game.controlsAvailable === true && game.sandboxAllowed === true && !game.joining && !game.policyCleanup && !!game.map && (typeof game.vehicleId === "undefined" || win.canChange)
    readonly property string identity: JSON.stringify(remote.target)
    onIdentityChanged: {
        if (power) power.text = "100"
        if (rpm) rpm.text = ""
        if (ratios) ratios.text = ""
        selectedConfig = ""
    }
    property string selectedModel: ""
    property string selectedConfig: ""
    readonly property bool editing: !!activeFocusItem && typeof activeFocusItem.cursorPosition === "number"
    function request(action, args, title) {
        dismissKeyboard()
        remote.command(action,args || ({}))
    }
    function dismissKeyboard() { if (activeFocusItem) activeFocusItem.focus=false; Qt.inputMethod.hide() }
    Shortcut { sequence: "Escape"; enabled: Qt.inputMethod.visible; onActivated: win.dismissKeyboard() }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: width < 380 ? 12 : 20; spacing: 14
        RowLayout {
            Layout.fillWidth: true
            Rectangle { Layout.preferredWidth: 36; Layout.preferredHeight: 36; color: theme.accent; radius: 6
                PlainLabel { anchors.centerIn: parent; text: "A"; color: "#10141b"; font.pixelSize: 22; font.bold: true }
            }
            ColumnLayout { spacing: 0; Layout.fillWidth: true
                PlainLabel { text: "ABM Mobile"; font.pixelSize: 18; font.weight: Font.DemiBold; color: "#edf1f7" }
                PlainLabel { text: qsTr("YOUR GAME. YOUR PHONE."); font.pixelSize: 9; color: "#a0aabb"; font.letterSpacing: 1 }
            }
            StatusPill { text: remote.connected ? qsTr("PAIRED") : qsTr("OFFLINE"); active: remote.connected }
            Button { objectName: "dismissKeyboard"; text: qsTr("Done"); visible: Qt.inputMethod.visible || win.editing; onClicked: win.dismissKeyboard() }
        }
        NavDock { Layout.fillWidth: true; currentPage: win.page; labels: [qsTr("Drive"),qsTr("Car"),qsTr("Garage"),qsTr("Session"),qsTr("Connect")]; onSelected: function(page) { win.page = page } }
        PlainLabel { text: [qsTr("Drive"),qsTr("Workshop"),qsTr("Garage"),qsTr("Session"),qsTr("Connect")][win.page]; color: "#edf1f7"; font.pixelSize: 26; font.weight: Font.DemiBold }
        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0; currentIndex: win.page
            ScrollView {
                clip: true; contentWidth: availableWidth
                ColumnLayout { width: parent.width; spacing: 12
                    PlainLabel { text: win.game.vehicle || qsTr("Waiting for your game"); color: "#a0aabb"; font.pixelSize: 14; Layout.fillWidth: true }
                    HeroCluster { Layout.fillWidth: true; live: win.live; accentColor: theme.accent
                        speedValue: (win.telemetry.speed || 0) * (win.metric ? 3.6 : 2.23694)
                        speedText: win.live ? String(Math.round(speedValue)) : "—"; unit: win.metric ? "km/h" : "mph"
                        rpm: win.telemetry.rpm || 0; redline: win.telemetry.maxRPM || 8000; gearText: String(win.telemetry.gear === undefined ? "—" : win.telemetry.gear)
                    }
                    GridLayout { columns: 2; Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                        MetricCard { label: qsTr("ENGINE"); value: win.live ? String(Math.round(win.telemetry.rpm || 0)) : "—"; unit: "RPM" }
                        MetricCard { label: qsTr("FUEL"); value: typeof win.telemetry.fuel === "number" ? String(Math.round(win.telemetry.fuel*100)) : "—"; unit: "%" }
                        MetricCard { label: qsTr("COOLANT"); value: typeof win.telemetry.waterTemp === "number" ? String(Math.round(win.telemetry.waterTemp)) : "—"; unit: "°C" }
                        MetricCard { label: qsTr("LATENCY"); value: typeof win.game.ping === "number" ? String(Math.round(win.game.ping)) : "—"; unit: "ms" }
                        MetricCard { label: qsTr("PHONE ↔ PC"); value: remote.roundTripMs >= 0 ? String(remote.roundTripMs) : "—"; unit: "ms" }
                    }
                    Button { Layout.fillWidth: true; implicitHeight: 48; text: win.metric ? qsTr("Use mph") : qsTr("Use km/h"); onClicked: win.metric = !win.metric }
                    PlainLabel { Layout.fillWidth: true; text: qsTr("Telemetry comes from your PC. This is not a steering wheel or a throttle controller."); color: "#a0aabb"; font.pixelSize: 12 }
                }
            }
            ScrollView {
                clip: true; contentWidth: availableWidth
                ColumnLayout { width: parent.width; spacing: 12
                    PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; font.pixelSize: 13
                        text: win.canChange ? qsTr("Stopped, owned vehicle. Every change is checked again by the PC and game.") : qsTr("Connect a live game and stop an owned vehicle on a permitted server to change settings.") }
                    SectionPanel { Layout.fillWidth: true
                        PlainLabel { text: qsTr("Engine power"); color: "#edf1f7"; font.pixelSize: 18 }
                        TextField { id: power; objectName: "powerInput"; Layout.fillWidth: true; implicitHeight: 48; text: "100"; placeholderText: qsTr("Power percent"); inputMethodHints: Qt.ImhFormattedNumbersOnly; validator: DoubleValidator { bottom: 1; top: 2000; locale: "C" } }
                        Button { objectName: "applyPower"; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply power %"); enabled: win.canChange && power.acceptableInput && (win.game.capabilities || {}).power === true; onClicked: win.request("power", {value:Number(power.text)/100}, qsTr("Change engine power?")) }
                        TextField { id: rpm; Layout.fillWidth: true; implicitHeight: 48; placeholderText: qsTr("Maximum RPM (100–30000)"); inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 100; top: 30000 } }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply RPM limit"); enabled: win.canChange && rpm.acceptableInput; onClicked: win.request("rpm",{value:Number(rpm.text)},qsTr("Change RPM limit?")) }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Enable clutch protection"); enabled: win.canChange; onClicked: win.request("clutch",{enabled:true},qsTr("Enable clutch protection?")) }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Disable clutch protection"); enabled: win.canChange; onClicked: win.request("clutch",{enabled:false},qsTr("Disable clutch protection?")) }
                    }
                    SectionPanel { Layout.fillWidth: true
                        PlainLabel { text: qsTr("Gearbox"); color: "#edf1f7"; font.pixelSize: 18 }
                        PlainLabel { Layout.fillWidth: true; text: qsTr("Forward ratios, separated by spaces. Readback and transmission support are enforced by the game."); color: "#a0aabb"; font.pixelSize: 12 }
                        TextField { id: ratios; Layout.fillWidth: true; implicitHeight: 48; placeholderText: "3.5 2.1 1.4 1.0 0.8"; maximumLength: 24000 }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Apply ratios"); enabled: win.canChange && ratios.text.trim().length > 0; onClicked: win.request("gears",{ratios:ratios.text},qsTr("Change gearbox ratios?")) }
                    }
                    SectionPanel { Layout.fillWidth: true
                        PlainLabel { text: qsTr("Vehicle actions"); color: "#edf1f7"; font.pixelSize: 18 }
                        Repeater { model: [{a:"repair",t:qsTr("Repair")},{a:"extinguish",t:qsTr("Extinguish")},{a:"stability",t:qsTr("Stabilize")},{a:"fullReset",t:qsTr("Clear ABM tuning & reset")}]
                            Button { required property var modelData; Layout.fillWidth: true; implicitHeight: 48; text: modelData.t; enabled: win.canChange; onClicked: win.request(modelData.a,{},modelData.t+"?") }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.minimumWidth: 0; spacing: 12
                RowLayout { Layout.fillWidth: true
                    Button { text: win.selectedModel ? qsTr("Models") : qsTr("Refresh"); implicitHeight: 48; enabled: remote.connected && !remote.busy; onClicked: { win.selectedModel = ""; win.selectedConfig = ""; remote.command("catalog") } }
                    PlainLabel { Layout.fillWidth: true; text: win.selectedModel || qsTr("Vehicle library"); color: "#a0aabb"; font.pixelSize: 13; elide: Text.ElideRight }
                }
                PlainLabel { Layout.fillWidth: true; color: "#a0aabb"; font.pixelSize: 12; text: qsTr("Thumbnails load securely on demand from the PC. Refresh, choose a model, then select a configuration to spawn.") }
                GridView {
                    id: garage; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    readonly property int columns: width >= 400 ? 2 : 1
                    cellWidth: width/columns; cellHeight: cellWidth*.6+64
                    model: win.selectedModel ? (remote.configsModel === win.selectedModel ? remote.configs : []) : remote.catalog
                    delegate: VariantCard { required property var modelData; width: garage.cellWidth-10; height: garage.cellHeight-10; modelCard: !win.selectedModel; selected: win.selectedConfig === modelData.id
                        Component.onCompleted: remote.requestThumbnail(modelData)
                        onModelDataChanged: remote.requestThumbnail(modelData)
                        onChosen: if (!win.selectedModel) { win.selectedModel = modelData.id; remote.command("configs",{model:modelData.id}) } else win.selectedConfig = modelData.id
                    }
                }
                RowLayout { Layout.fillWidth: true
                    Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Spawn"); enabled: win.canSpawn && !!win.selectedConfig; onClicked: win.request("spawn",{config:win.selectedConfig},qsTr("Spawn selected configuration?")) }
                    Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Replace"); enabled: win.canChange && !!win.selectedConfig; onClicked: win.request("replace",{config:win.selectedConfig},qsTr("Replace current vehicle?")) }
                }
            }
            ScrollView {
                clip: true; contentWidth: availableWidth
                ColumnLayout { width: parent.width; spacing: 12
                    SectionPanel { Layout.fillWidth: true
                        PlainLabel { Layout.fillWidth: true; text: win.game.server || (win.live ? qsTr("Single player") : qsTr("No live game")); color: "#edf1f7"; font.pixelSize: 18 }
                        PlainLabel { Layout.fillWidth: true; text: qsTr("Player session IDs are temporary. The phone cannot grant server permission or control another player's vehicle."); color: "#a0aabb"; font.pixelSize: 12 }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Copy server address"); enabled: !!win.game.serverIp && !!win.game.serverPort; onClicked: remote.copyText((win.game.serverIp.indexOf(":") >= 0 ? "["+win.game.serverIp+"]" : win.game.serverIp)+":"+win.game.serverPort) }
                    }
                    Repeater { model: win.game.players || []
                        SectionPanel { required property var modelData; Layout.fillWidth: true
                            PlainLabel { Layout.fillWidth: true; text: modelData.rawName || modelData.name || qsTr("Player"); color: "#edf1f7"; font.pixelSize: 16 }
                            PlainLabel { text: modelData.sessionPlayerId === undefined ? qsTr("Session ID unavailable") : qsTr("Session ID: %1").arg(modelData.sessionPlayerId); color: "#a0aabb"; font.pixelSize: 12 }
                            Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Copy name"); onClicked: remote.copyText(modelData.rawName || modelData.name) }
                        }
                    }
                    Repeater { model: (win.game.activeVehicles || []).filter(function(v) { return v.owned === true })
                        Button { required property var modelData; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Switch to %1").arg(modelData.name || modelData.id); enabled: win.canChange; onClicked: win.request("switch",{id:modelData.id},qsTr("Switch owned vehicle?")) }
                    }
                    Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Reset trip"); enabled: win.canChange; onClicked: win.request("resetTrip",{},qsTr("Reset trip statistics?")) }
                }
            }
            ScrollView {
                clip: true; contentWidth: availableWidth
                ColumnLayout { width: parent.width; spacing: 16
                    SectionPanel { visible: remote.remembered; Layout.fillWidth: true
                        PlainLabel { text: qsTr("Remembered PC"); color: "#edf1f7"; font.pixelSize: 18 }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Reconnect without pairing"); enabled: !remote.connected; onClicked: { win.dismissKeyboard(); remote.reconnectPC() } }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Forget saved PC"); onClicked: remote.forgetPC() }
                    }
                    SectionPanel { Layout.fillWidth: true
                        PlainLabel { text: qsTr("Connect to PC ABM"); color: "#edf1f7"; font.pixelSize: 20 }
                        PlainLabel { Layout.fillWidth: true; text: qsTr("1. Put phone and PC on the same private Wi-Fi.\n2. In PC ABM → Connect, enable access and copy its pairing link.\n3. Paste it below, connect, then approve this phone on the PC."); color: "#a0aabb"; font.pixelSize: 14 }
                        TextField { id: deviceName; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("My Android phone"); maximumLength: 64; placeholderText: qsTr("Device name (shown on PC)") }
                        TextArea { id: invitation; objectName: "pairingLinkInput"; Layout.fillWidth: true; Layout.preferredHeight: 110; placeholderText: "abm://pair/…"; wrapMode: TextEdit.WrapAnywhere; selectByMouse: true; inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData }
                        Button { objectName: "pairPhone"; Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Connect & request PC approval"); highlighted: true; enabled: invitation.text.trim().length > 0 && !remote.connected
                            onClicked: { win.dismissKeyboard(); remote.pair(invitation.text.trim(),deviceName.text); invitation.text = "" }
                        }
                        Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Disconnect"); onClicked: remote.disconnectPhone() }
                    }
                    UpdatesPane { Layout.fillWidth: true; updater: typeof appUpdates !== "undefined" ? appUpdates : null }
                    SectionPanel { Layout.fillWidth: true
                        PlainLabel { text: qsTr("Private, encrypted, revocable"); color: "#edf1f7"; font.pixelSize: 16 }
                        PlainLabel { Layout.fillWidth: true; text: qsTr("First pairing requires PC approval. If Remember device is selected on PC, a credential is stored in this app's private storage (Android backup is disabled). Reconnect only works while PC access is enabled; Forget devices on PC revokes it. Android USB: select Android USB on PC, authorize adb over your cable, and paste its loopback link. No commands are queued offline. Never forward the port."); color: "#a0aabb"; font.pixelSize: 13 }
                    }
                }
            }
        }
        PlainLabel { Layout.fillWidth: true; text: remote.message || qsTr("Open Connect to pair with your PC."); color: theme.accent; font.pixelSize: 12; maximumLineCount: 3; elide: Text.ElideRight }
        PlainLabel { visible: !!remote.actionMessage && win.page !== 4; Layout.fillWidth: true; text: remote.actionMessage; color: "#a0aabb"; font.pixelSize: 12; maximumLineCount: 2; elide: Text.ElideRight }
    }
}
