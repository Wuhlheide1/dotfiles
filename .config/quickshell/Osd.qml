import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Bottom-centre on-screen display for volume + brightness changes. Reacts to
// PipeWire sink changes (so the media keys / scroll all trigger it) and to the
// Brightness singleton. Auto-hides after a short delay.
// Also shows caps/num-lock state, driven by non-consuming Hyprland binds on
// the keys themselves (qs ipc call osd caps/num); truth comes from the
// compositor (hyprctl devices -j), not the keyboard LED — LEDs update
// asynchronously and lag behind rapid presses.
Item {
    id: root

    property var barWindow
    property string fontFamily: "Adwaita Sans"

    property string glyph: ""
    property real level: 0      // 0..1
    property string label: ""   // non-empty → text mode (no progress bar)

    // ignore the initial property values emitted at startup
    property bool ready: false
    Timer { running: true; interval: 1500; onTriggered: root.ready = true }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.ready && sink.audio !== null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // shown drives the fade/scale animation; osd.visible unmaps only after the
    // fade-out finishes. A new flash mid-fade cancels the unmap and swaps the
    // content instantly.
    property bool shown: false

    function pop() {
        unmapTimer.stop()
        root.shown = true
        osd.visible = true
        hideTimer.restart()
        pulseAnim.restart()   // visible "tick" even when the text barely changes
    }

    function flash(g, lvl) {
        if (!root.ready) return
        root.glyph = g
        root.level = lvl
        root.label = ""
        root.statePill = ""
        pop()
    }

    function flashText(g, txt) {
        root.glyph = g
        root.label = txt
        root.statePill = ""
        pop()
    }

    // --- caps/num lock ---------------------------------------------------
    // Once we've seen a key's state, every further press flips it
    // OPTIMISTICALLY (a keypress always toggles), so the fly-out updates the
    // instant you hit the key. Shortly after, hyprctl devices -j is read as a
    // correction; it only re-renders if the guess was wrong. Every press bumps
    // lockGen, and a check result is discarded if lockGen moved on \u2014 otherwise
    // an in-flight read from press N would "correct" press N+1 with old state.
    property string lockPending: ""   // "capslock" | "numlock"
    property var lockState: ({})      // which -> bool (last known)
    property int lockGen: 0
    property bool stateOn: false      // styles the ON/OFF pill
    property string statePill: ""     // "" = not a lock flash

    function lockFlash(which) {
        root.lockGen++
        if (root.lockState[which] !== undefined) {
            root.lockState[which] = !root.lockState[which]
            root.showLock(which)
        }
        root.lockPending = which
        lockDelay.restart()
        lockConfirm.restart()
    }

    function showLock(which) {
        var on = root.lockState[which]
        root.flashText(on ? "\uf023" : "\uf09c",   // lock / unlock
                       which === "capslock" ? "Caps Lock" : "Num Lock")
        root.stateOn = on
        root.statePill = on ? "ON" : "OFF"
    }

    function runLockCheck() {
        lockCheck.gen = root.lockGen
        lockCheck.running = false
        lockCheck.running = true
    }

    Timer { id: lockDelay;   interval: 80;  onTriggered: root.runLockCheck() }
    // second pass: the compositor's lock state can update later than 80ms
    // after the press (this made the fly-out show the wrong state); a late
    // confirming read fixes the guess without a visible flicker if it matched
    Timer { id: lockConfirm; interval: 450; onTriggered: root.runLockCheck() }

    // seed initial state so even the very first press flips optimistically
    Component.onCompleted: { lockCheck.gen = root.lockGen; lockCheck.running = true }

    Process {
        id: lockCheck
        property int gen: -1
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (lockCheck.gen !== root.lockGen) return  // superseded by a newer press
                // Aggregate across ALL keyboards: the device flagged "main" is
                // not necessarily the sub-device whose lock state flips (e.g.
                // sonix-usb-device is main, but sonix-usb-device-keyboard is
                // the one that types), so any-keyboard-on is the reliable truth.
                var truth = null
                try {
                    var kbs = JSON.parse(text).keyboards
                    truth = { capslock: kbs.some(k => k.capsLock),
                              numlock:  kbs.some(k => k.numLock) }
                } catch (e) {}
                if (!truth) return
                for (var w in truth) {
                    if (root.lockState[w] === truth[w]) continue
                    root.lockState[w] = truth[w]
                    // visible re-render only for the key that was flashed
                    if (w === root.lockPending) root.showLock(w)
                }
            }
        }
    }

    // CLI access: qs ipc call osd caps|num (wired to non-consuming binds)
    IpcHandler {
        target: "osd"
        function caps(): void { root.lockFlash("capslock") }
        function num():  void { root.lockFlash("numlock") }
    }

    function volGlyph() {
        if (!root.sinkReady || root.sink.audio.muted || root.sink.audio.volume <= 0) return "\uf026"
        return root.sink.audio.volume < 0.5 ? "\uf027" : "\uf028"
    }

    // volume changes from any source (keys, scroll) — but not while the
    // ControlCenter's own sliders are driving; its menu already shows the level
    Connections {
        target: root.sinkReady ? root.sink.audio : null
        function onVolumeChanged() {
            if (PopupBus.current === "control") return
            root.flash(root.volGlyph(), root.sink.audio.volume)
        }
        function onMutedChanged() {
            if (PopupBus.current === "control") return
            root.flash(root.volGlyph(), root.sink.audio.muted ? 0 : root.sink.audio.volume)
        }
    }

    // brightness changes (skip while the ControlCenter slider is the one driving)
    Connections {
        target: Brightness
        function onValueChanged() {
            if (PopupBus.current === "control") return
            root.flash("\uf185", Brightness.value / 100)
        }
    }

    Timer { id: hideTimer; interval: 1500; onTriggered: { root.shown = false; unmapTimer.restart() } }
    Timer { id: unmapTimer; interval: 200; onTriggered: osd.visible = false }

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

            // small pop in / fade-and-shrink out
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.9
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            RowLayout {
                id: contentRow
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                spacing: 14

                // quick scale tick on every flash so repeated presses register
                SequentialAnimation {
                    id: pulseAnim
                    NumberAnimation { target: contentRow; property: "scale"; to: 1.06; duration: 60; easing.type: Easing.OutQuad }
                    NumberAnimation { target: contentRow; property: "scale"; to: 1.0;  duration: 120; easing.type: Easing.OutQuad }
                }

                Text {
                    text: root.glyph
                    // lock flashes tint the glyph with the state
                    color: root.statePill === "" ? Colors.on_surface
                         : (root.stateOn ? Colors.primary : Colors.outline)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 20 }
                }
                Item {
                    visible: root.label === ""
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
                    visible: root.label === ""
                    text: Math.round(root.level * 100) + "%"
                    color: Colors.on_surface_variant
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    font { family: root.fontFamily; pixelSize: 13 }
                }
                // text mode (caps/num lock): label instead of bar + %
                Text {
                    visible: root.label !== ""
                    Layout.fillWidth: true
                    text: root.label
                    color: Colors.on_surface
                    font { family: root.fontFamily; pixelSize: 15 }
                }
                // loud ON/OFF pill so the state flip is unmissable
                Rectangle {
                    visible: root.statePill !== ""
                    implicitWidth: pillText.implicitWidth + 18
                    implicitHeight: 24
                    radius: 12
                    color: root.stateOn ? Colors.primary : "transparent"
                    border.color: root.stateOn ? Colors.primary : Colors.outline
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: root.statePill
                        color: root.stateOn ? Colors.on_primary : Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: 11; bold: true }
                    }
                }
            }
        }
    }
}

