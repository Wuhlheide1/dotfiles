import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Outline speaker glyph (Codicon) for the default sink. Scroll = adjust,
// click = mute. Exact level + slider live in the ControlCenter menu.
Item {
    id: root

    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14
    property real step: 0.05

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real vol: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // Width is pinned to the widest glyph (volume-up) so muting/changing level
    // never resizes the widget and shifts the rest of the bar.
    implicitWidth: metric.implicitWidth + 6
    implicitHeight: 26

    function setVol(v) {
        if (!root.ready) return
        root.sink.audio.volume = Math.max(0, Math.min(1.0, v))
    }

    Text {
        id: icon
        anchors.centerIn: parent
        // nf-fa volume-off / volume-down / volume-up
        text: root.muted || root.vol <= 0 ? "\uf026" : (root.vol < 0.5 ? "\uf027" : "\uf028")
        color: root.muted || root.vol <= 0 ? Colors.outline : Colors.on_surface
        font { family: root.fontFamily; pixelSize: root.fontSize + 1 }
    }

    // invisible width reference: the widest of the three speaker glyphs
    Text {
        id: metric
        visible: false
        text: ""
        font { family: root.fontFamily; pixelSize: root.fontSize + 1 }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: if (root.ready) root.sink.audio.muted = !root.sink.audio.muted

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (ev) => {
                if (ev.angleDelta.y > 0) root.setVol(root.vol + root.step)
                else if (ev.angleDelta.y < 0) root.setVol(root.vol - root.step)
            }
        }
    }
}
