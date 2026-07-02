// Recorder.qml — bar indicator for wf-recorder.
//
// Invisible (and takes no layout space) when idle. While a recording is
// running it shows a pulsing red REC dot; clicking it stops the recording.
// State is polled from `pgrep -x wf-recorder`; start/stop go through the same
// scripts/record.sh the SUPER+SHIFT+R keybind uses.
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root

    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14
    property bool recording: false

    readonly property string script: "/home/wuhlheide/.config/quickshell/scripts/record.sh"

    // Layouts skip invisible items entirely, so this reserves no space when idle.
    visible: recording
    implicitWidth: recRow.implicitWidth + 8
    implicitHeight: 26

    Process {
        id: check
        command: ["pgrep", "-x", "wf-recorder"]
        onExited: (code) => root.recording = (code === 0)
    }
    Timer {
        interval: 1500; repeat: true; running: true; triggeredOnStart: true
        onTriggered: check.running = true
    }

    Row {
        id: recRow
        anchors.centerIn: parent
        spacing: 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10; height: 10; radius: 5
            color: Colors.error
            SequentialAnimation on opacity {
                running: root.recording; loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 700 }
                NumberAnimation { to: 1.0; duration: 700 }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "REC"
            color: Colors.error
            font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["bash", root.script, "toggle"])
    }
}
