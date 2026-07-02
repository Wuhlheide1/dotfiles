pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single source of truth for software (GPU-gamma) brightness via hyprsunset.
// Shared by the ControlCenter slider, the XF86MonBrightness keys (through the
// "brightness" IPC handler in shell.qml), and the OSD. Clamped to 20–100% so
// the screen can never be driven fully black. hyprsunset only ever touches the
// GPU gamma ramp, never the monitor hardware.
Singleton {
    id: brightness

    property int value: 100          // percent
    readonly property int minValue: 20
    readonly property int step: 5

    function clamp(v) { return Math.max(minValue, Math.min(100, Math.round(v))) }

    function set(v) {
        var p = clamp(v)
        if (p === value) return
        value = p
        apply()
    }
    function up()   { set(value + step) }
    function down() { set(value - step) }

    function apply() {
        proc.command = ["hyprctl", "hyprsunset", "gamma", String(value)]
        proc.running = true
    }

    Process { id: proc }
}
