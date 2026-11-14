import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: editor
    property string inputName: ""
    property string label: ""
    property real minimum: 0
    property real maximum: 100
    property bool integer: false
    property alias text: input.text
    readonly property real number: input.text.trim().length ? Number(input.text) : NaN
    readonly property bool valid: isFinite(number) && number >= minimum && number <= maximum && (!integer || number === Math.floor(number))
    PlainLabel { Layout.fillWidth: true; text: parent.label; color: "#edf1f7"; font.pixelSize: 14 }
    TextField { id: input; objectName: editor.inputName; Layout.fillWidth: true; implicitHeight: 48; inputMethodHints: Qt.ImhFormattedNumbersOnly; selectByMouse: true; maximumLength: 32; Accessible.name: editor.label }
}
