import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Bottom-centre on-screen display for volume + brightness changes. Reacts to
// PipeWire sink changes (so the media keys / scroll all trigger it) and to the
// Brightness singleton. Auto-hides after a short delay.
Item {
    id: root

    property var barWindow
    property string fontFamily: "JetBrainsMono Nerd Font"

    property string glyph: ""
    property real level: 0      // 0..1

    // ignore the initial property values emitted at startup
    property bool ready: false
    Timer { running: true; interval: 1500; onTriggered: root.ready = true }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.ready && sink.audio !== null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    function flash(g, lvl) {
        if (!root.ready) return
        root.glyph = g
        root.level = lvl
        osd.visible = true
        hideTimer.restart()
    }

    function volGlyph() {
        if (!root.sinkReady || root.sink.audio.muted || root.sink.audio.volume <= 0) return "\uf026"
        return root.sink.audio.volume < 0.5 ? "\uf027" : "\uf028"
    }

    // volume changes from any source (keys, scroll, ControlCenter)
    Connections {
        target: root.sinkReady ? root.sink.audio : null
        function onVolumeChanged() { root.flash(root.volGlyph(), root.sink.audio.volume) }
        function onMutedChanged()  { root.flash(root.volGlyph(), root.sink.audio.muted ? 0 : root.sink.audio.volume) }
    }

    // brightness changes (skip while the ControlCenter slider is the one driving)
    Connections {
        target: Brightness
        function onValueChanged() {
            if (PopupBus.current === "control") return
            root.flash("\uf185", Brightness.value / 100)
        }
    }

    Timer { id: hideTimer; interval: 1500; onTriggered: osd.visible = false }

    PanelWindow {
        id: osd
        visible: false
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        // anchored to the bottom only → wlr-layer-shell centres it horizontally
        anchors { bottom: true }
        margins.bottom: 140
        implicitWidth: 300
        implicitHeight: 58
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            // fade in/out with visibility
            opacity: osd.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                spacing: 14

                Text {
                    text: root.glyph
                    color: Colors.on_surface
                    font { family: root.fontFamily; pixelSize: 20 }
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 8; radius: 4
                        color: Colors.surface_container_high
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.level))
                            height: parent.height; radius: 4
                            color: Colors.primary
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                }
                Text {
                    text: Math.round(root.level * 100) + "%"
                    color: Colors.on_surface_variant
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    font { family: root.fontFamily; pixelSize: 13 }
                }
            }
        }
    }
}
