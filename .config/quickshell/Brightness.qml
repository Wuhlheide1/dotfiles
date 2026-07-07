pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single source of truth for screen brightness. Shared by the ControlCenter
// slider, the SUPER+F1/F2 / XF86MonBrightness keys (via the "brightness" IPC
// handler in shell.qml) and the OSD. Clamped to 20–100% so the screen can
// never be driven fully dark.
//
// Two backends, picked automatically at load:
//   ddc   — REAL monitor backlight over DDC/CI (ddcutil). Used when ddcutil
//           and /dev/i2c-* are usable. Conservative by design: buses are
//           detected ONCE (never re-probed in a loop), writes are debounced
//           and serialized in one shell, DP-2 first, --noverify keeps i2c
//           traffic minimal. Any failed write drops back to gamma for the
//           session. While ddc is active, hyprsunset gamma is parked at 100.
//   gamma — hyprsunset GPU gamma ramp (previous behaviour; never touches the
//           monitor). Automatic fallback when ddc isn't available.
Singleton {
    id: brightness

    property int value: 100          // percent; synced from the real level on load
    readonly property int minValue: 20
    readonly property int step: 5
    property string mode: "gamma"    // "gamma" | "ddc"
    property var ddcBuses: []        // i2c bus numbers, DP-2 first

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/quickshell"
    // gamma level: autostart.lua reads this for hyprsunset's initial --gamma
    readonly property string gammaStateFile: stateDir + "/brightness"
    // backlight level: restored by the ddc read-back on load (monitor keeps it anyway)
    readonly property string ddcStateFile: stateDir + "/backlight"

    function clamp(v) { return Math.max(minValue, Math.min(100, Math.round(v))) }

    function set(v) {
        var p = clamp(v)
        if (p === value) return
        value = p
        if (mode === "ddc") ddcDebounce.restart()
        else applyGamma()
    }
    function up()   { set(value + step) }
    function down() { set(value - step) }

    // --- gamma backend -----------------------------------------------------
    function applyGamma() {
        gammaProc.command = ["sh", "-c",
            "hyprctl hyprsunset gamma " + value
            + " && printf '%s\\n' " + value + " > '" + gammaStateFile + "'"]
        gammaProc.running = true
    }
    Process { id: gammaProc }

    // --- ddc backend ---------------------------------------------------------
    // Debounce slider drags: at most one serialized write burst per 300ms.
    Timer { id: ddcDebounce; interval: 300; onTriggered: brightness.applyDdc() }
    property bool ddcDirty: false
    function applyDdc() {
        if (ddcProc.running) { ddcDirty = true; return }
        var cmd = ""
        for (var i = 0; i < ddcBuses.length; i++)
            cmd += "ddcutil setvcp 10 " + value + " --bus " + ddcBuses[i] + " --noverify && "
        cmd += "printf '%s\\n' " + value + " > '" + ddcStateFile + "'"
        ddcProc.command = ["sh", "-c", cmd]
        ddcProc.running = true
    }
    Process {
        id: ddcProc
        onExited: (code) => {
            if (code !== 0) {
                // a wedged DDC write must never leave brightness dead:
                // fall back to gamma and re-read what the gamma level truly is
                console.warn("Brightness: ddcutil write failed, falling back to gamma")
                brightness.mode = "gamma"
                brightness.sync()
                return
            }
            if (brightness.ddcDirty) { brightness.ddcDirty = false; brightness.applyDdc() }
        }
    }

    // --- backend detection (ONCE at load; `qs ipc call brightness redetect` to re-run) ---
    function redetect() { detectProc.running = true }
    Process {
        id: detectProc
        running: true
        command: ["sh", "-c",
            "command -v ddcutil >/dev/null 2>&1 && ls /dev/i2c-* >/dev/null 2>&1 "
            + "&& ddcutil detect --brief 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var found = []   // { bus, conn }
                var bus = -1
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var mb = /I2C bus:\s+\/dev\/i2c-(\d+)/.exec(lines[i])
                    if (mb) { bus = parseInt(mb[1]); continue }
                    var mc = /DRM connector:\s+card\d+-(\S+)/.exec(lines[i])
                    if (mc && bus >= 0) { found.push({ bus: bus, conn: mc[1] }); bus = -1 }
                }
                if (found.length === 0) { brightness.syncGamma(); return }
                // DP-2 (main) first: if a synced write only half-works, the
                // monitor that matters is the one that got it
                found.sort((a, b) => (b.conn === "DP-2") - (a.conn === "DP-2"))
                brightness.ddcBuses = found.map(f => f.bus)
                brightness.mode = "ddc"
                // backlight is now the only dimmer: park gamma at 100
                Quickshell.execDetached(["sh", "-c",
                    "hyprctl hyprsunset gamma 100; printf '100\\n' > '"
                    + brightness.gammaStateFile + "'"])
                brightness.syncDdc()
            }
        }
    }

    // --- read back the real level on load (no more "assume 100") -------------
    property int syncTries: 0
    function sync() { if (mode === "ddc") syncDdc(); else syncGamma() }

    function syncGamma() { gammaSyncProc.running = true }
    Process {
        id: gammaSyncProc
        command: ["hyprctl", "hyprsunset", "gamma"]
        stdout: StdioCollector {
            onStreamFinished: {
                var g = parseInt(text)
                if (!isNaN(g)) {
                    if (brightness.mode === "gamma") brightness.value = brightness.clamp(g)
                } else if (brightness.syncTries++ < 3) {
                    retryTimer.start()   // hyprsunset's socket may not be up yet
                }
            }
        }
    }
    Timer { id: retryTimer; interval: 2000; onTriggered: brightness.syncGamma() }

    function syncDdc() { ddcSyncProc.running = true }
    Process {
        id: ddcSyncProc
        // real command is set by onDdcBusesChanged; --brief: "VCP 10 C <cur> <max>"
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = /VCP 10 C (\d+) (\d+)/.exec(text)
                if (m) {
                    var cur = parseInt(m[1]), max = parseInt(m[2]) || 100
                    brightness.value = brightness.clamp(cur * 100 / max)
                }
            }
        }
    }
    onDdcBusesChanged: {
        if (ddcBuses.length > 0)
            ddcSyncProc.command = ["ddcutil", "getvcp", "10", "--brief",
                                   "--bus", String(ddcBuses[0])]
    }
}
