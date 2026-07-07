// Recorder.qml — bar indicator + audio-mode chooser for wf-recorder.
//
// Invisible (and takes no layout space) when idle. SUPER+SHIFT+R goes through
// `qs ipc call record toggle`: while recording it stops; while idle it opens a
// small chooser (desktop / mic / both / none) and picking a mode starts the
// recording via scripts/record.sh. Clicking the pulsing REC dot also stops.
//
// State checks are event-driven (after our own start/stop) plus a slow safety
// poll — not the old always-on 1.5s pgrep loop.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var barWindow
    property string fontFamily: "Adwaita Sans"
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
    Component.onCompleted: check.running = true
    // confirm shortly after we start/stop something ourselves
    Timer { id: recheck; interval: 700; onTriggered: check.running = true }
    // while recording: notice an external stop or a wf-recorder crash quickly
    Timer { interval: 2000;  repeat: true; running: root.recording;  onTriggered: check.running = true }
    // while idle: slow safety net for recordings started outside the shell
    Timer { interval: 15000; repeat: true; running: !root.recording; onTriggered: check.running = true }

    function stop() {
        Quickshell.execDetached(["bash", root.script, "toggle"])
        recheck.restart()
    }
    function start(mode) {
        Quickshell.execDetached(["bash", root.script, "start", mode])
        PopupBus.close()
        recheck.restart()
    }

    // CLI access: qs ipc call record toggle (wired to SUPER+SHIFT+R)
    IpcHandler {
        target: "record"
        function toggle(): void {
            if (root.recording) root.stop()
            else PopupBus.toggle("record")
        }
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
        onClicked: root.stop()
    }

    // ---------------------------------------------------------------
    // Audio-mode chooser (centered card; Esc / click-outside dismisses)
    PanelWindow {
        id: chooser
        visible: PopupBus.current === "record"
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }
        Item { focus: true; Keys.onEscapePressed: PopupBus.close() }

        Rectangle {
            anchors.centerIn: parent
            width: 280
            height: chooserCol.implicitHeight + 34
            radius: 18
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            opacity: chooser.visible ? 1 : 0
            scale: chooser.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // swallow inside clicks

            ColumnLayout {
                id: chooserCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 17 }
                spacing: 4

                Text {
                    text: "Record screen"
                    color: Colors.on_surface
                    font { family: root.fontFamily; pixelSize: root.fontSize + 1; bold: true }
                }
                Text {
                    text: "Focused monitor · pick the audio"
                    color: Colors.on_surface_variant
                    Layout.bottomMargin: 8
                    font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                }

                Repeater {
                    model: [
                        { g: "\uf028", t: "Desktop audio",    m: "desktop" },
                        { g: "\uf130", t: "Microphone",       m: "mic" },
                        { g: "\uf025", t: "Desktop + mic",    m: "both" },
                        { g: "\uf026", t: "No audio",         m: "none" }
                    ]
                    Rectangle {
                        id: modeRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 10
                        color: modeArea.containsMouse ? Colors.surface_container_high : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                        MouseArea {
                            id: modeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.start(modeRow.modelData.m)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12
                            Text {
                                Layout.preferredWidth: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: modeRow.modelData.g
                                color: Colors.on_surface_variant
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: root.fontSize }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modeRow.modelData.t
                                color: Colors.on_surface
                                font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                            }
                        }
                    }
                }
            }
        }
    }
}
