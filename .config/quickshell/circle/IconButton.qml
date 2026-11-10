import QtQuick

// Round Material Symbols button, Caelestia-style state layer on hover/press.
Item {
    id: root

    required property string icon
    property bool active
    property bool enabledState: true
    signal clicked

    implicitWidth: 40
    implicitHeight: 40
    opacity: enabledState ? 1 : 0.38

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.active ? Theme.primary : Theme.text
        opacity: root.active ? 1 : area.pressed ? 0.12 : area.containsMouse ? 0.08 : 0

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: Theme.icons
        font.pixelSize: 22
        font.variableAxes: ({ FILL: root.active ? 1 : 0, wght: 400, GRAD: 0, opsz: 24 })
        color: root.active ? Theme.textOnPrimary : Theme.textVariant
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabledState
        onClicked: root.clicked()
    }
}
