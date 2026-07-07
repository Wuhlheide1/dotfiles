import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Quick-settings flyout. Three pages inside one card:
//   main — wifi/bt tiles, volume, brightness, media, collapsible stats, power
//   wifi — connection card (ip + live speeds) + network list w/ password entry
//   bt   — paired devices + live discovery of nearby devices
Item {
    id: root

    property var barWindow
    // the bar's NotificationCenter (shell.qml passes it in) — the DND tile
    // reads/flips its manual toggle
    property var notifCenter: null
    property string fontFamily: "Adwaita Sans"
    property string glyphFont: "JetBrainsMono Nerd Font"
    property int fontSize: 14

    // which page the card shows; reset to main whenever the menu closes
    property string page: "main"

    implicitWidth: gear.implicitWidth + 8
    implicitHeight: 26

    // bumped by the status timer so list-derived labels (e.g. "N connected")
    // re-evaluate even when only a device property changed
    property int tick: 0

    // Default sink + source, tracked so their audio props are live & writable.
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.ready && sink.audio !== null
    readonly property real vol: sinkReady ? sink.audio.volume : 0
    readonly property var mic: Pipewire.defaultAudioSource
    readonly property bool micReady: mic !== null && mic.ready && mic.audio !== null
    PwObjectTracker { objects: [root.sink, root.mic].filter(o => o !== null) }

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter !== null && btAdapter.enabled

    // device sinks (HDMI, BT buds, …) for the output switcher in the mixer —
    // playback STREAMS are isStream && isSink, so real devices are the rest
    readonly property var outSinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)

    // --- game mode: strip animations/blur/gaps/rounding for gaming ---
    // keyword doesn't work with the Lua config parser; hl.config via eval
    // does. Off = hyprctl reload (the config is the source of truth).
    // The state file lets wallpaper.sh re-apply game mode right after its own
    // hyprctl reload, so a mid-game wallpaper shuffle no longer silently
    // un-games — keep the eval string here and in wallpaper.sh identical.
    property bool gameMode: false
    FileView {
        id: gameFile
        path: "/home/wuhlheide/.local/state/quickshell/gamemode"
        blockLoading: true
        printErrors: false
    }
    function setGameMode(on) {
        gameMode = on
        if (on) Quickshell.execDetached(["sh", "-c",
            "printf 1 > ~/.local/state/quickshell/gamemode; hyprctl eval "
            + "\"hl.config({ general = { gaps_in = 0, gaps_out = 0 }, "
            + "decoration = { rounding = 0, blur = { enabled = false } }, "
            + "animations = { enabled = false } })\""])
        else Quickshell.execDetached(["sh", "-c",
            "rm -f ~/.local/state/quickshell/gamemode; hyprctl reload"])
    }

    // --- keep awake: park hypridle so nothing dims/locks during movies ---
    property bool awakeOn: false
    function setAwake(on) {
        awakeOn = on
        if (on) Quickshell.execDetached(["pkill", "-x", "hypridle"])
        else Quickshell.execDetached(["hypridle"])
    }

    // --- night light (hyprsunset color temperature; gamma untouched) ---
    // Click cycles strength — one fixed 4000K was "too extreme" (user,
    // 2026-07-06), so it starts soft. State persists in the same file
    // autostart.lua reads at login ("0" = manually off tonight, don't
    // re-auto). NEVER use `hyprctl hyprsunset identity` here — it would
    // also reset the gamma the brightness slider manages.
    //
    // Schedule: Soft turns on at sunset, off at sunrise — sunrise/sunset are
    // computed astronomically (NOAA approximation, ±5 min), no fixed clock
    // times and no geoclue. A manual tile press wins until the next boundary.
    readonly property var nightLevels: [0, 5500, 4750, 4000]   // index 0 = off
    readonly property var nightNames: ["Off", "Soft", "Medium", "Strong"]
    property int nightIdx: 0
    readonly property real nightLat: 51.0   // ~central Germany; tweak when the
    readonly property real nightLon: 10.0   // config moves to another city
    property bool isNight: false
    property string nextSunset: ""          // "21:28", for the tile subtitle

    function sunTimes(d) {
        var rad = Math.PI / 180
        var n = Math.floor((d - new Date(d.getFullYear(), 0, 0)) / 86400000)
        var B = 2 * Math.PI * (n - 81) / 364
        var eot = 9.87 * Math.sin(2 * B) - 7.53 * Math.cos(B) - 1.5 * Math.sin(B)
        var decl = 23.44 * rad * Math.sin(2 * Math.PI * (284 + n) / 365)
        var cosW = -Math.tan(nightLat * rad) * Math.tan(decl)
        var w = Math.acos(Math.max(-1, Math.min(1, cosW))) / rad     // degrees
        var noon = 720 - nightLon * 4 - eot                          // min UTC
        function at(mins) {
            var t = new Date(d)
            t.setUTCHours(0, 0, 0, 0)
            t.setUTCMinutes(Math.round(mins))
            return t
        }
        return { rise: at(noon - w * 4), set: at(noon + w * 4) }
    }
    function fmtClock(t) {
        return ("0" + t.getHours()).slice(-2) + ":" + ("0" + t.getMinutes()).slice(-2)
    }
    function nightTick() {
        var now = new Date()
        var s = sunTimes(now)
        nextSunset = fmtClock(s.set)
        var n = now < s.rise || now > s.set
        if (n === isNight) return
        isNight = n
        if (n) { if (nightIdx === 0) setNight(1, false) }   // sunset → Soft
        else   { if (nightIdx > 0)  setNight(0, false) }    // sunrise → off
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.nightTick() }
    FileView {
        id: nightFile
        path: "/home/wuhlheide/.local/state/quickshell/nightlight"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        ppCheck.running = true   // probe power-profiles-daemon for the Power tile
        // game mode survives shell restarts (the hypr config is still gamed;
        // the tile must show that instead of silently reading "Off")
        gameMode = (gameFile.text() || "").trim() === "1"
        // snap whatever temp was persisted to the nearest level
        var raw = (nightFile.text() || "").trim()
        var t = parseInt(raw) || 0
        var now = new Date()
        var s = sunTimes(now)
        isNight = now < s.rise || now > s.set
        nextSunset = fmtClock(s.set)
        if (t > 0) {
            nightIdx = 1
            for (var i = 2; i < nightLevels.length; i++)
                if (Math.abs(nightLevels[i] - t) < Math.abs(nightLevels[nightIdx] - t))
                    nightIdx = i
        } else if (raw !== "0" && isNight) {
            // shell (re)started after sunset with no manual-off marker → Soft
            setNight(1, false)
        }
    }
    function setNight(i, manual) {
        nightIdx = i
        var t = nightLevels[i]
        Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature",
                                 String(t === 0 ? 6500 : t)])
        // "0" marks a MANUAL off, so a shell restart tonight doesn't auto-Soft
        // it right back on; the sunrise auto-off clears the file entirely.
        nightFile.setText(t === 0 ? (manual ? "0" : "") : String(t))
    }
    function cycleNight() { setNight((nightIdx + 1) % nightLevels.length, true) }

    // --- page 3: display & power tiles ---------------------------------
    // Screen magnifier: cycle the Hyprland cursor zoom. Transient (not
    // persisted — a stuck 3x zoom surviving a reboot would be baffling).
    readonly property var zoomLevels: [1.0, 1.5, 2.0, 3.0]
    property int zoomIdx: 0
    function cycleZoom() {
        zoomIdx = (zoomIdx + 1) % zoomLevels.length
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.config({ cursor = { zoom_factor = " + zoomLevels[zoomIdx] + " } })"])
    }

    // Colour filter: cycle a full-screen GLSL shader (files in hypr/shaders).
    // Also transient — no one wants to boot into inverted colours.
    readonly property string shaderDir: "/home/wuhlheide/.config/hypr/shaders/"
    readonly property var filterNames:   ["Off", "Grayscale", "Invert", "Sepia"]
    readonly property var filterShaders: ["", "grayscale.frag", "invert.frag", "sepia.frag"]
    property int filterIdx: 0
    function cycleFilter() {
        filterIdx = (filterIdx + 1) % filterNames.length
        var s = filterShaders[filterIdx]
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.config({ decoration = { screen_shader = '"
            + (s === "" ? "" : shaderDir + s) + "' } })"])
    }

    // one-tap wallpaper shuffle (same script the picker / keybind use)
    readonly property string wallScript: "/home/wuhlheide/.config/quickshell/scripts/wallpaper.sh"

    // Power profiles (UPower): only meaningful with power-profiles-daemon,
    // which isn't on the desktop — probe once so the tile stays hidden here
    // and simply lights up on the laptop after the daemon is installed.
    property bool hasPowerProfiles: false
    Process {
        id: ppCheck
        command: ["systemctl", "is-active", "power-profiles-daemon"]
        stdout: SplitParser { onRead: line => { if (line.trim() === "active") root.hasPowerProfiles = true } }
    }
    readonly property var ppNames: ["Saver", "Balanced", "Performance"]
    function ppLabel() {
        var p = PowerProfiles.profile
        return p === PowerProfile.PowerSaver ? "Saver"
             : p === PowerProfile.Performance ? "Performance" : "Balanced"
    }
    function cyclePower() {
        var p = PowerProfiles.profile
        // Saver -> Balanced -> Performance -> Saver; skip Performance if the
        // hardware doesn't offer it (most laptops on battery still do)
        if (p === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced
        else if (p === PowerProfile.Balanced)
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile
                ? PowerProfile.Performance : PowerProfile.PowerSaver
        else PowerProfiles.profile = PowerProfile.PowerSaver
    }

    // --- pending updates (repo via checkupdates + AUR via paru) ---
    // Checked 90s after shell start, then every 2h; also re-checked when the
    // menu opens if the last result is >15min old. checkupdates syncs a temp
    // DB (network), so it must never run per-open unconditionally.
    property int updCount: 0
    property double updLast: 0
    Process {
        id: updProc
        command: ["sh", "-c",
            "{ checkupdates 2>/dev/null; paru -Qua 2>/dev/null; } | grep -c ."]
        stdout: SplitParser {
            onRead: line => {
                root.updCount = parseInt(line) || 0
                root.updLast = Date.now()
            }
        }
    }
    Timer { interval: 90000; running: true; onTriggered: updProc.running = true }
    Timer { interval: 7200000; repeat: true; running: true; onTriggered: updProc.running = true }

    // scan for nearby devices only while the bluetooth page is actually open
    function syncBtScan() {
        if (root.btAdapter)
            root.btAdapter.discovering =
                centerPopup.visible && root.page === "bt" && root.btAdapter.enabled
    }
    onPageChanged: {
        syncBtScan()
        if (page === "wifi" && wifiUsable) {
            Quickshell.execDetached(["bash", wifiScript, "scan"])
            wifiListProc.running = true
            wifiKnownProc.acc = []; wifiKnownProc.running = true
        }
    }
    Connections {
        target: root.btAdapter
        function onEnabledChanged() { root.syncBtScan() }
    }

    // Active MPRIS player: prefer one that's actually playing, else the first.
    readonly property var mprisPlayer: {
        var ps = Mpris.players ? Mpris.players.values : []
        if (!ps || ps.length === 0) return null
        for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
        return ps[0]
    }

    function setVol(frac) {
        if (root.sinkReady) root.sink.audio.volume = Math.max(0, Math.min(1.0, frac))
    }

    // --- per-app playback streams (mixer page) ---
    // In Quickshell's model a PLAYBACK stream is isStream && isSink (it sits on
    // the sink side of the graph); capture streams are isStream && !isSink.
    // Tracking binds audio properties so the sliders are live and writable.
    readonly property var appStreams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink)
    PwObjectTracker { objects: root.appStreams }

    // --- power actions (with a confirm step, since they're irreversible) ---
    property string pendingCmd: ""
    property string pendingLabel: ""
    function askPower(cmd, label) { root.pendingCmd = cmd; root.pendingLabel = label }
    function clearPower() { root.pendingCmd = ""; root.pendingLabel = "" }
    function runPower() {
        powerProc.command = ["sh", "-c", root.pendingCmd]
        powerProc.running = true
        root.clearPower()
    }
    Process { id: powerProc }

    // --- active network readout (polled only while menu open) ---
    property string netIface: ""
    property string netIp: ""
    readonly property bool netUp: root.netIp.length > 0
    Process {
        id: netProc
        command: ["sh", "-c",
            "ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i==\"dev\")d=$(i+1); if($i==\"src\")s=$(i+1)} print d\" \"s; exit}'"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(/\s+/)
                root.netIface = p[0] || ""
                root.netIp = p[1] || ""
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible
        onTriggered: netProc.running = true
    }

    // --- live throughput for the active interface (wifi page only) ---
    property double spdPrevRx: 0
    property double spdPrevTx: 0
    property double spdPrevT: 0
    property real rxRate: 0
    property real txRate: 0
    onNetIfaceChanged: { spdPrevT = 0; rxRate = 0; txRate = 0 }

    function fmtRate(b) {
        if (b < 1024) return Math.round(b) + " B/s"
        if (b < 1048576) return (b / 1024).toFixed(b < 102400 ? 1 : 0) + " KB/s"
        return (b / 1048576).toFixed(1) + " MB/s"
    }

    Process {
        id: spdProc
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(/\s+/)
                if (p.length < 2) return
                var rx = parseFloat(p[0]), tx = parseFloat(p[1])
                var now = Date.now()
                if (root.spdPrevT > 0 && now > root.spdPrevT) {
                    var dt = (now - root.spdPrevT) / 1000
                    root.rxRate = Math.max(0, (rx - root.spdPrevRx) / dt)
                    root.txRate = Math.max(0, (tx - root.spdPrevTx) / dt)
                }
                root.spdPrevRx = rx; root.spdPrevTx = tx; root.spdPrevT = now
            }
        }
    }
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible && root.page === "wifi" && root.netIface !== ""
        onTriggered: {
            spdProc.command = ["sh", "-c",
                "echo $(cat /sys/class/net/" + root.netIface + "/statistics/rx_bytes 2>/dev/null || echo 0) "
                + "$(cat /sys/class/net/" + root.netIface + "/statistics/tx_bytes 2>/dev/null || echo 0)"]
            spdProc.running = true
        }
        onRunningChanged: if (!running) root.spdPrevT = 0   // no stale-delta spike on reopen
    }

    // --- Wi-Fi via iwd (scripts/wifi.sh) — section hides itself until a
    // backend + wireless device exist, so this is inert pre-install ---
    readonly property string wifiScript: "/home/wuhlheide/.config/quickshell/scripts/wifi.sh"
    property string wifiState: "nobackend"   // nobackend | nodev | off | on | connected
    property string wifiDev: ""
    property string wifiSsid: ""
    property var wifiNets: []                // { conn, ssid, sec, bars }
    property var wifiKnown: []
    property string wifiExpanded: ""         // ssid with the password field open
    property string wifiBusy: ""             // ssid currently connecting
    property string wifiError: ""            // ssid whose last connect failed
    property string wifiAttempt: ""
    readonly property bool wifiUsable: wifiState === "on" || wifiState === "connected"
    readonly property bool wifiPresent: wifiState !== "nobackend" && wifiState !== "nodev"

    function wifiConnect(ssid, pw) {
        wifiError = ""
        wifiAttempt = ssid
        wifiBusy = ssid
        // env timestamp so identical retries still re-run the Process
        var cmd = ["env", "T=" + Date.now(), "bash", wifiScript, "connect", ssid]
        // the passphrase travels over stdin, never argv — /proc/*/cmdline is
        // world-readable while the connect is in flight
        var hasPw = !!(pw && pw.length > 0)
        if (hasPw) cmd.push("--pw-stdin")
        wifiConnectProc.pendingPw = hasPw ? pw : ""
        wifiConnectProc.stdinEnabled = hasPw
        wifiConnectProc.command = cmd
        wifiConnectProc.running = true
    }

    Process {
        id: wifiStatusProc
        command: ["bash", root.wifiScript, "status"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(/\s+/)
                if (p.length === 0 || p[0] === "") return
                root.wifiState = p[0]
                root.wifiDev = p[1] || ""
                root.wifiSsid = p.slice(2).join(" ")
            }
        }
    }
    Process {
        id: wifiListProc
        command: ["bash", root.wifiScript, "list"]
        property var acc: []
        stdout: SplitParser {
            onRead: line => {
                var p = line.split("\t")
                if (p.length === 4)
                    wifiListProc.acc.push({ conn: p[0] === "1", ssid: p[1],
                                            sec: p[2], bars: parseInt(p[3]) || 0 })
            }
        }
        onExited: {
            var batch = acc
            acc = []   // always start the next run clean
            // NEVER touch the model while a password field is open: reassigning
            // it rebuilds the delegates and wipes whatever was typed.
            if (root.wifiExpanded !== "") return
            batch.sort((a, b) => (b.conn - a.conn) || (b.bars - a.bars))
            // overlapping triggers can stack two scans in one batch — dedupe,
            // keeping the first (connected/strongest) entry per ssid
            var seen = ({}), uniq = []
            for (var i = 0; i < batch.length; i++) {
                if (seen[batch[i].ssid]) continue
                seen[batch[i].ssid] = true
                uniq.push(batch[i])
            }
            var next = uniq.slice(0, 10)
            if (JSON.stringify(next) !== JSON.stringify(root.wifiNets))
                root.wifiNets = next
        }
    }
    Process {
        id: wifiKnownProc
        command: ["bash", root.wifiScript, "known"]
        property var acc: []
        stdout: SplitParser {
            onRead: line => { if (line.trim() !== "") wifiKnownProc.acc.push(line.trim()) }
        }
        onExited: root.wifiKnown = acc
    }
    Process {
        id: wifiConnectProc
        property string pendingPw: ""
        onStarted: {
            if (pendingPw !== "") {
                write(pendingPw + "\n")
                pendingPw = ""
                stdinEnabled = false   // close stdin so the script's read sees EOF after the line
            }
        }
        onExited: (code) => {
            root.wifiBusy = ""
            if (code !== 0) {
                root.wifiError = root.wifiAttempt
                root.wifiExpanded = root.wifiAttempt   // keep the field open to retry
            } else {
                root.wifiError = ""
                root.wifiExpanded = ""
            }
            wifiStatusProc.running = true
            wifiListProc.running = true
            wifiKnownProc.acc = []; wifiKnownProc.running = true
        }
    }
    // status poll runs on every page (feeds the tile subtitles too)
    Timer {
        interval: 3000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible
        onTriggered: {
            root.tick++
            wifiStatusProc.running = true
        }
    }
    // network list refresh: only on the wifi page, and frozen while typing a
    // password (root.wifiExpanded) so the entry field never gets rebuilt
    Timer {
        interval: 4000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible && root.page === "wifi"
                 && root.wifiUsable && root.wifiExpanded === ""
        onTriggered: wifiListProc.running = true
    }
    Timer {
        interval: 15000; repeat: true
        running: centerPopup.visible && root.page === "wifi"
                 && root.wifiUsable && root.wifiExpanded === ""
        onTriggered: {
            Quickshell.execDetached(["bash", root.wifiScript, "scan"])
            wifiKnownProc.acc = []; wifiKnownProc.running = true
        }
    }
    // --- Phone via Valent (scripts/phone.sh) — polled only on the phone page ---
    readonly property string phoneScript: "/home/wuhlheide/.config/quickshell/scripts/phone.sh"
    property string phoneId: ""
    property int phoneState: 0        // Valent flags: bit0 connected, bit1 paired
    property int phoneBatt: -1
    property bool phoneCharging: false
    property string phoneName: ""
    readonly property bool phoneConnected: (phoneState & 1) === 1
    property bool phoneTyping: false  // share-text input holds the keyboard

    Process {
        id: phoneStatusProc
        command: ["bash", root.phoneScript, "status"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.split("\t")
                if (p.length < 5) return
                root.phoneId = p[0]
                root.phoneState = parseInt(p[1]) || 0
                root.phoneBatt = p[2] === "" ? -1 : parseInt(p[2])
                root.phoneCharging = p[3] === "1"
                root.phoneName = p[4]
            }
        }
    }
    Timer {
        // whole-menu poll (not just the phone page): the main-page Phone tile
        // shows battery/state, so it needs fresh data too. Two gdbus calls / 5s.
        interval: 5000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible
        onTriggered: phoneStatusProc.running = true
    }
    function phoneAction(a) {
        if (root.phoneId === "") return
        Quickshell.execDetached(["bash", root.phoneScript, "action", root.phoneId, a])
    }
    // text goes over stdin (same no-argv pattern as the Wi-Fi passphrase)
    Process {
        id: phoneShareProc
        property string pending: ""
        onStarted: {
            if (pending !== "") {
                write(pending + "\n")
                pending = ""
                stdinEnabled = false
            }
        }
    }
    function phoneShareText(t) {
        if (t.trim() === "" || root.phoneId === "") return
        phoneShareProc.pending = t
        phoneShareProc.stdinEnabled = true
        phoneShareProc.command = ["env", "T=" + Date.now(),
                                  "bash", root.phoneScript, "share-text", root.phoneId]
        phoneShareProc.running = true
    }

    // reset transient UI state whenever the menu closes
    Connections {
        target: centerPopup
        function onVisibleChanged() {
            if (!centerPopup.visible) {
                root.page = "main"
                root.wifiExpanded = ""
                root.wifiError = ""
                root.clearPower()
            }
            root.syncBtScan()
        }
    }

    // --- system usage (polled only while the menu is open) ---
    property int cpu: 0
    property int mem: 0
    property int lastTotal: 0
    property int lastIdle: 0
    // AMD GPU via kernel sysfs (globbed: card/hwmon numbering drifts across boots)
    property int gpu: 0
    property int gpuTemp: 0
    property int vramPct: 0
    property string vramText: ""
    property int cpuTemp: 0
    property string fanText: ""

    Process {
        id: sysProc
        command: ["sh", "-c",
            "awk 'NR==1{print \"cpu\", $2, $3, $4, $5, $6, $7, $8}' /proc/stat; " +
            "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"mem %d\\n\", (t-a)*100/t}' /proc/meminfo; " +
            "printf 'gpu %s ' \"$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)\"; " +
            "printf '%s ' \"$(cat /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)\"; " +
            "printf '%s ' \"$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1)\"; " +
            "printf '%s\\n' \"$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)\"; " +
            // CPU die temp (k10temp Tctl) + case fan RPMs (nct6795 fan2/fan3);
            // hwmon numbering drifts across boots, so match by chip name
            "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); " +
            "case $n in k10temp) echo cput $(cat $h/temp1_input);; " +
            "nct6795) echo fans $(cat $h/fan2_input 2>/dev/null) $(cat $h/fan3_input 2>/dev/null);; esac; done"]
        stdout: SplitParser {
            onRead: line => {
                if (!line) return
                var p = line.trim().split(/\s+/)
                if (p[0] === "cpu") {
                    var idle = parseInt(p[4]) + parseInt(p[5])
                    var total = 0
                    for (var i = 1; i <= 7; i++) total += parseInt(p[i])
                    if (root.lastTotal > 0 && total > root.lastTotal)
                        root.cpu = Math.round(100 * (1 - (idle - root.lastIdle) / (total - root.lastTotal)))
                    root.lastTotal = total
                    root.lastIdle = idle
                } else if (p[0] === "mem") {
                    root.mem = parseInt(p[1])
                } else if (p[0] === "gpu" && p.length >= 5) {
                    root.gpu = parseInt(p[1]) || 0
                    root.gpuTemp = Math.round((parseInt(p[2]) || 0) / 1000)
                    var used = parseInt(p[3]) || 0
                    var total2 = parseInt(p[4]) || 1
                    root.vramPct = Math.round(100 * used / total2)
                    root.vramText = (used / 1073741824).toFixed(1) + " / "
                                  + (total2 / 1073741824).toFixed(1) + " GiB"
                } else if (p[0] === "cput") {
                    root.cpuTemp = Math.round((parseInt(p[1]) || 0) / 1000)
                } else if (p[0] === "fans") {
                    root.fanText = (parseInt(p[1]) || 0) + " / " + (parseInt(p[2]) || 0) + " rpm"
                }
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible && root.page === "main"
        onTriggered: {
            sysProc.running = true
            // opportunistic update re-check while the menu is open, throttled
            if (Date.now() - root.updLast > 900000) updProc.running = true
        }
    }

    // --- reusable pill toggle (smoother, slightly springy knob) ---
    component Toggle: Rectangle {
        property bool on: false
        signal toggled()
        implicitWidth: 44; implicitHeight: 24; radius: 12
        color: on ? Colors.primary : Colors.surface_container_high
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            width: 18; height: 18; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: parent.on ? parent.width - width - 3 : 3
            color: parent.on ? Colors.on_primary : Colors.outline
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on color { ColorAnimation { duration: 180 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled() }
    }

    // --- spinner for in-flight connect/pair states ---
    component Spinner: Text {
        id: spin
        text: "\uf110"   // nf-fa-spinner
        color: Colors.on_surface_variant
        font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
        NumberAnimation on rotation {
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
            running: spin.visible
        }
    }

    // --- reusable labelled progress bar (CPU / RAM) ---
    component StatBar: RowLayout {
        id: statBar
        property string label: ""
        property int value: 0
        property color barColor: Colors.primary
        Layout.fillWidth: true
        spacing: 10
        Text {
            text: statBar.label
            color: Colors.on_surface_variant
            Layout.preferredWidth: 38
            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6; radius: 3
                color: Colors.surface_container_high
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, statBar.value / 100))
                    height: parent.height; radius: 3
                    color: statBar.barColor
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }
        }
        Text {
            text: statBar.value + "%"
            color: Colors.on_surface_variant
            Layout.preferredWidth: 36
            horizontalAlignment: Text.AlignRight
            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
        }
    }

    // --- subtle icon-only power action ---
    component PowerIcon: Text {
        id: pIcon
        property bool danger: false
        property string action: ""
        property string actionLabel: ""
        text: ""
        color: pIconArea.containsMouse ? (danger ? Colors.error : Colors.on_surface)
                                       : Colors.outline
        opacity: pIconArea.containsMouse ? 1.0 : 0.7
        font { family: root.glyphFont; pixelSize: root.fontSize + 1 }
        Behavior on color { ColorAnimation { duration: 100 } }
        MouseArea {
            id: pIconArea
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.askPower(pIcon.action, pIcon.actionLabel)
        }
    }

    // --- phone-style squircle toggle tile: body toggles, chevron strip opens ---
    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string title: ""
        property string subtitle: ""
        property bool on: false
        property bool openable: true   // false = no sub-page (hides the chevron strip)
        signal toggled()
        signal opened()
        Layout.fillWidth: true
        implicitHeight: 64
        radius: 20
        // full accent fill when on (user tried a muted primary_container fill
        // 2026-07-06 and reverted it — keep the loud fill)
        color: tile.on ? Colors.primary : Colors.surface_container_high
        Behavior on color { ColorAnimation { duration: 200 } }
        scale: bodyArea.pressed || chevArea.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // whole tile toggles; the chevron strip (declared later, on top) opens
        MouseArea {
            id: bodyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggled()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 4
            spacing: 10
            Text {
                text: tile.glyph
                color: tile.on ? Colors.on_primary : Colors.on_surface_variant
                Behavior on color { ColorAnimation { duration: 200 } }
                font { family: root.glyphFont; pixelSize: root.fontSize + 2 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: tile.title
                    color: tile.on ? Colors.on_primary : Colors.on_surface
                    Behavior on color { ColorAnimation { duration: 200 } }
                    font { family: root.fontFamily; pixelSize: root.fontSize - 1; weight: Font.Medium }
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.subtitle
                    elide: Text.ElideRight
                    color: tile.on ? Qt.alpha(Colors.on_primary, 0.75) : Colors.on_surface_variant
                    Behavior on color { ColorAnimation { duration: 200 } }
                    font { family: root.fontFamily; pixelSize: root.fontSize - 4 }
                }
            }
            Rectangle {
                visible: tile.openable
                implicitWidth: 1
                Layout.preferredHeight: 26
                color: tile.on ? Qt.alpha(Colors.on_primary, 0.25) : Colors.outline_variant
            }
            Item {
                visible: tile.openable
                Layout.preferredWidth: 28
                Layout.fillHeight: true
                Text {
                    anchors.centerIn: parent
                    text: "\uf054" // nf-fa-chevron-right
                    color: tile.on ? Colors.on_primary : Colors.outline
                    opacity: chevArea.containsMouse ? 1.0 : 0.6
                    font { family: root.glyphFont; pixelSize: root.fontSize - 4 }
                }
                MouseArea {
                    id: chevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.opened()
                }
            }
        }
    }

    // --- sub-page header: back chevron + title + optional trailing item ---
    component PageHeader: RowLayout {
        id: pageHeader
        property string title: ""
        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            implicitWidth: 28; implicitHeight: 28; radius: 8
            color: backArea.containsMouse ? Colors.surface_container_high : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\uf053" // nf-fa-chevron-left
                color: Colors.on_surface_variant
                font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.page = "main"
            }
        }
        Text {
            text: pageHeader.title
            color: Colors.on_surface
            font { family: root.fontFamily; pixelSize: root.fontSize + 1; bold: true }
        }
        Item { Layout.fillWidth: true }
    }

    // CLI access: qs ipc call control toggle | qs ipc call control page <main|wifi|bt>
    IpcHandler {
        target: "control"
        function toggle(): void { PopupBus.toggle("control") }
        function page(p: string): void {
            if (["main", "wifi", "bt", "mixer", "phone"].indexOf(p) >= 0) root.page = p
            PopupBus.current = "control"
        }
    }

    // --- bar button (sliders glyph) ---
    Text {
        id: gear
        anchors.centerIn: parent
        text: "\uf1de" // nf-fa-sliders
        color: PopupBus.current === "control" ? Colors.primary : Colors.on_surface
        opacity: 0.85
        font { family: root.glyphFont; pixelSize: root.fontSize }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: PopupBus.toggle("control")
    }

    // ---------------------------------------------------------------
    // Fullscreen transparent overlay: the card + its click-catcher live in the
    // SAME window, so clicking outside the card reliably dismisses (no protocol).
    PanelWindow {
        id: centerPopup
        visible: PopupBus.current === "control"
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        // While a Wi-Fi password field is open the menu MUST hold the keyboard
        // exclusively, or the TextInput would be dead (overlay-popup pattern).
        // Otherwise OnDemand: enough for Esc-to-close without a hard grab.
        WlrLayershell.keyboardFocus: (root.wifiExpanded !== "" || root.phoneTyping)
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // click anywhere outside the card → close
        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }
        Item { focus: true; Keys.onEscapePressed: PopupBus.close() }

        Rectangle {
            id: card
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6   // overlay already starts below the bar's reserved zone
            anchors.rightMargin: 12
            width: 336
            height: implicitHeight
            implicitHeight: col.implicitHeight + 34

            // subtle drop-in when the menu opens
            transformOrigin: Item.TopRight
            opacity: centerPopup.visible ? 1 : 0
            scale: centerPopup.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // swallow clicks inside the card so they don't reach the dismiss area
            MouseArea { anchors.fill: parent }
            radius: 18
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 17 }
                spacing: 16

                // =====================================================
                // PAGE: main
                // =====================================================
                ColumnLayout {
                    id: mainPage
                    visible: root.page === "main"
                    onVisibleChanged: if (visible) mainFade.restart()
                    NumberAnimation on opacity {
                        id: mainFade
                        from: 0; to: 1; duration: 200
                        easing.type: Easing.OutCubic
                        running: false
                    }
                    Layout.fillWidth: true
                    spacing: 16

                    // --- System usage (RAM + temperature only surface when hot) ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 9
                        StatBar { label: "CPU"; value: root.cpu; barColor: Colors.primary }
                        StatBar { label: "GPU"; value: root.gpu; barColor: Colors.tertiary }
                        StatBar { label: "VRAM"; value: root.vramPct; barColor: Colors.secondary }
                        StatBar {
                            label: "RAM"; value: root.mem; barColor: Colors.error
                            visible: root.mem >= 85   // hidden unless it's a problem
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: root.gpuTemp >= 85   // hidden unless it's a problem
                            text: root.gpuTemp + "\u00b0C \u00b7 " + root.vramText
                            color: Colors.error
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                        }

                        // quiet temps + case-fan readout (the CoolerControl
                        // glance without opening its GUI)
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: root.cpuTemp > 0
                            text: "cpu " + root.cpuTemp + "\u00b0 \u00b7 gpu " + root.gpuTemp + "\u00b0"
                                  + (root.fanText !== "" ? " \u00b7 fans " + root.fanText : "")
                            color: Colors.on_surface_variant
                            opacity: 0.8
                            font { family: root.fontFamily; pixelSize: root.fontSize - 4 }
                        }

                        // pending system updates (repo + AUR); click = update in kitty
                        Item {
                            Layout.fillWidth: true
                            visible: root.updCount > 0
                            implicitHeight: updRow.implicitHeight + 4
                            RowLayout {
                                id: updRow
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7
                                Text {
                                    text: "\uf019" // nf-fa-download
                                    color: Colors.primary
                                    font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                                }
                                Text {
                                    text: root.updCount + (root.updCount === 1 ? " update" : " updates")
                                          + " \u00b7 click to install"
                                    color: updArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                }
                            }
                            MouseArea {
                                id: updArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["kitty", "--title", "System update",
                                        "sh", "-c", "paru -Syu; echo; echo 'Done \u2014 press Enter to close'; read _"])
                                    PopupBus.close()
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // --- Media (MPRIS: whatever is playing — Spotify, mpv, browser…) ---
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.mprisPlayer !== null
                        spacing: 12

                        // album art, or a music-note fallback. ClippingRectangle
                        // (Quickshell.Widgets) clips to the rounded corners —
                        // plain `clip: true` only clips to the bounding box.
                        ClippingRectangle {
                            Layout.preferredWidth: 42; Layout.preferredHeight: 42
                            radius: 10
                            color: Colors.surface_container_high
                            Image {
                                id: art
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: root.mprisPlayer && root.mprisPlayer.trackArtUrl ? root.mprisPlayer.trackArtUrl : ""
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !art.visible
                                text: "\uf001" // nf-fa-music
                                color: Colors.on_surface_variant
                                font { family: root.glyphFont; pixelSize: root.fontSize + 2 }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: root.mprisPlayer ? (root.mprisPlayer.trackTitle || "Unknown") : ""
                                color: Colors.on_surface
                                elide: Text.ElideRight
                                font { family: root.fontFamily; pixelSize: root.fontSize - 1; bold: true }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: root.mprisPlayer && root.mprisPlayer.trackArtist
                                text: root.mprisPlayer ? root.mprisPlayer.trackArtist : ""
                                color: Colors.on_surface_variant
                                elide: Text.ElideRight
                                font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                            }
                        }

                        // transport controls
                        Text {
                            text: "\uf048" // prev
                            color: (root.mprisPlayer && root.mprisPlayer.canGoPrevious) ? Colors.on_surface : Colors.outline
                            font { family: root.glyphFont; pixelSize: root.fontSize }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.mprisPlayer) root.mprisPlayer.previous()
                            }
                        }
                        Text {
                            text: (root.mprisPlayer && root.mprisPlayer.isPlaying) ? "\uf04c" : "\uf04b" // pause / play
                            color: Colors.primary
                            font { family: root.glyphFont; pixelSize: root.fontSize + 3 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.mprisPlayer) return
                                    if (root.mprisPlayer.isPlaying) root.mprisPlayer.pause()
                                    else root.mprisPlayer.play()
                                }
                            }
                        }
                        Text {
                            text: "\uf051" // next
                            color: (root.mprisPlayer && root.mprisPlayer.canGoNext) ? Colors.on_surface : Colors.outline
                            font { family: root.glyphFont; pixelSize: root.fontSize }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.mprisPlayer) root.mprisPlayer.next()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 1
                        color: Colors.outline_variant; opacity: 0.35
                        visible: root.mprisPlayer !== null
                    }

                    // --- Volume ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: root.sinkReady && root.sink.audio.muted ? "\uf026" : "\uf028"
                            color: Colors.on_surface
                            font { family: root.glyphFont; pixelSize: root.fontSize + 2 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.sinkReady) root.sink.audio.muted = !root.sink.audio.muted
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 22
                            Rectangle {
                                id: volTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 6; radius: 3
                                color: Colors.surface_container_high
                                Rectangle {
                                    width: parent.width * root.vol
                                    height: parent.height; radius: 3
                                    color: Colors.primary
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(volTrack.width - 14, volTrack.width * root.vol - 7))
                                width: 14; height: 14; radius: 7
                                color: Colors.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (m) => root.setVol(m.x / width)
                                onPositionChanged: (m) => { if (pressed) root.setVol(m.x / width) }
                            }
                        }
                        Text {
                            text: Math.round(root.vol * 100) + "%"
                            color: Colors.on_surface_variant
                            Layout.preferredWidth: 36
                            horizontalAlignment: Text.AlignRight
                            font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                        }
                        // per-app mixer sub-page
                        Item {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 22
                            Text {
                                anchors.centerIn: parent
                                text: "\uf054" // chevron-right
                                color: Colors.outline
                                opacity: mixArea.containsMouse ? 1.0 : 0.6
                                font { family: root.glyphFont; pixelSize: root.fontSize - 4 }
                            }
                            MouseArea {
                                id: mixArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.page = "mixer"
                            }
                        }
                    }

                    // --- Brightness (software GPU gamma via hyprsunset; never touches the monitor) ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: "\uf185"   // nf-fa-sun-o
                            color: Colors.on_surface
                            font { family: root.glyphFont; pixelSize: root.fontSize + 2 }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 22
                            Rectangle {
                                id: briTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 6; radius: 3
                                color: Colors.surface_container_high
                                Rectangle {
                                    width: parent.width * (Brightness.value / 100)
                                    height: parent.height; radius: 3
                                    color: Colors.primary
                                    Behavior on width { NumberAnimation { duration: 120 } }
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(briTrack.width - 14, briTrack.width * (Brightness.value / 100) - 7))
                                width: 14; height: 14; radius: 7
                                color: Colors.on_surface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (m) => Brightness.set(m.x / width * 100)
                                onPositionChanged: (m) => { if (pressed) Brightness.set(m.x / width * 100) }
                            }
                        }
                        Text {
                            text: Brightness.value + "%"
                            color: Colors.on_surface_variant
                            Layout.preferredWidth: 36
                            horizontalAlignment: Text.AlignRight
                            font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // --- tiles: paged (scroll wheel or dots to flip) ---
                    Item {
                        id: tilePager
                        Layout.fillWidth: true
                        clip: true
                        property int page: 0
                        readonly property int pages: 3
                        implicitHeight: [tilesP1, tilesP2, tilesP3][page].implicitHeight
                        Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: tilesP1
                            width: tilePager.width
                            x: -tilePager.page * tilePager.width
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            spacing: 10

                            // --- Wi-Fi / Bluetooth squircle tiles ---
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                visible: root.wifiPresent || root.btAdapter !== null

                                Tile {
                                    visible: root.wifiPresent
                                    glyph: "\uf1eb" // nf-fa-wifi
                                    title: "Wi-Fi"
                                    subtitle: root.wifiState === "connected" ? root.wifiSsid
                                            : (root.wifiUsable ? "On" : "Off")
                                    on: root.wifiUsable
                                    onToggled: Quickshell.execDetached(
                                        ["bash", root.wifiScript, "power", root.wifiUsable ? "off" : "on"])
                                    onOpened: root.page = "wifi"
                                }
                                Tile {
                                    visible: root.btAdapter !== null
                                    glyph: "\uf294" // nf-fa-bluetooth-b
                                    title: "Bluetooth"
                                    subtitle: {
                                        root.tick   // re-evaluate on the status tick
                                        if (!root.btOn) return "Off"
                                        var c = Bluetooth.devices.values.filter(d => d.connected)
                                        if (c.length === 0) return "On"
                                        var name = c[0].name || c[0].deviceName || c[0].address
                                        return c.length > 1 ? name + " +" + (c.length - 1) : name
                                    }
                                    on: root.btOn
                                    onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                                    onOpened: root.page = "bt"
                                }
                            }

                            // --- Night light + Phone: second tile row ---
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Tile {
                                    glyph: "\uf186" // nf-fa-moon-o
                                    title: "Night Light"
                                    subtitle: root.nightIdx === 0
                                        ? (root.isNight ? "Off" : "Off · auto " + root.nextSunset)
                                        : root.nightNames[root.nightIdx] + " · "
                                          + root.nightLevels[root.nightIdx] + "K"
                                    on: root.nightIdx > 0
                                    openable: false
                                    onToggled: root.cycleNight()
                                }

                                // Phone (Valent / KDE Connect protocol): battery + state
                                // live in the subtitle
                                Tile {
                                    glyph: "\uf10b" // nf-fa-mobile
                                    title: "Phone"
                                    subtitle: {
                                        if (root.phoneId === "") return "Not paired"
                                        if (!root.phoneConnected)
                                            return (root.phoneState & 2) ? "Offline" : "Not paired"
                                        var s = root.phoneBatt >= 0 ? root.phoneBatt + "%" : "Connected"
                                        if (root.phoneCharging) s += " \u00b7 charging"
                                        return s
                                    }
                                    on: false
                                    onToggled: root.page = "phone"
                                    onOpened: root.page = "phone"
                                }
                            }
                        }

                        // page 2: session toggles
                        ColumnLayout {
                            id: tilesP2
                            width: tilePager.width
                            x: tilePager.width - tilePager.page * tilePager.width
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Tile {
                                    glyph: "\uf11b" // nf-fa-gamepad
                                    title: "Game Mode"
                                    subtitle: root.gameMode ? "No eye candy" : "Off"
                                    on: root.gameMode
                                    openable: false
                                    onToggled: root.setGameMode(!root.gameMode)
                                }
                                Tile {
                                    glyph: "\uf0f4" // nf-fa-coffee
                                    title: "Keep Awake"
                                    subtitle: root.awakeOn ? "Idle lock off" : "Off"
                                    on: root.awakeOn
                                    openable: false
                                    onToggled: root.setAwake(!root.awakeOn)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Tile {
                                    glyph: "\uf1f6" // nf-fa-bell-slash
                                    title: "DND"
                                    subtitle: {
                                        if (!root.notifCenter) return "\u2014"
                                        if (root.notifCenter.dnd && !root.notifCenter.dndManual)
                                            return "Auto \u00b7 " + (root.notifCenter.autoRec ? "recording" : "fullscreen")
                                        return root.notifCenter.dndManual ? "On" : "Off"
                                    }
                                    on: root.notifCenter ? root.notifCenter.dnd : false
                                    openable: false
                                    onToggled: if (root.notifCenter)
                                        root.notifCenter.dndManual = !root.notifCenter.dndManual
                                }
                                Tile {
                                    glyph: "\uf130" // nf-fa-microphone
                                    title: "Microphone"
                                    // filled tile = mic is LIVE; muted goes neutral
                                    subtitle: !root.micReady ? "None"
                                        : root.mic.audio.muted ? "Muted"
                                        : (root.mic.nickname || root.mic.description || "Live")
                                    on: root.micReady && !root.mic.audio.muted
                                    openable: false
                                    onToggled: if (root.micReady)
                                        root.mic.audio.muted = !root.mic.audio.muted
                                }
                            }
                        }

                        // page 3: display & power
                        ColumnLayout {
                            id: tilesP3
                            width: tilePager.width
                            x: 2 * tilePager.width - tilePager.page * tilePager.width
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Tile {
                                    glyph: "\uf00e" // nf-fa-search-plus
                                    title: "Screen Zoom"
                                    subtitle: root.zoomIdx === 0 ? "Off"
                                        : root.zoomLevels[root.zoomIdx] + "\u00d7"
                                    on: root.zoomIdx > 0
                                    openable: false
                                    onToggled: root.cycleZoom()
                                }
                                Tile {
                                    glyph: "\uf042" // nf-fa-adjust
                                    title: "Colour Filter"
                                    subtitle: root.filterNames[root.filterIdx]
                                    on: root.filterIdx > 0
                                    openable: false
                                    onToggled: root.cycleFilter()
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Tile {
                                    glyph: "\uf074" // nf-fa-random (shuffle)
                                    title: "Wallpaper"
                                    subtitle: "Shuffle now"
                                    on: false
                                    openable: false
                                    onToggled: Quickshell.execDetached(["bash", root.wallScript, "random"])
                                }
                                // Power profile \u2014 hidden unless power-profiles-daemon
                                // is running (desktop: absent; laptop: lights up)
                                Tile {
                                    visible: root.hasPowerProfiles
                                    glyph: "\uf0e7" // nf-fa-bolt
                                    title: "Power"
                                    subtitle: root.hasPowerProfiles ? root.ppLabel() : "\u2014"
                                    on: root.hasPowerProfiles
                                        && PowerProfiles.profile === PowerProfile.Performance
                                    openable: false
                                    onToggled: root.cyclePower()
                                }
                            }
                        }

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (ev) => {
                                if (ev.angleDelta.y < 0)
                                    tilePager.page = Math.min(tilePager.pages - 1, tilePager.page + 1)
                                else
                                    tilePager.page = Math.max(0, tilePager.page - 1)
                            }
                        }
                    }

                    // pager dots
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -10
                        spacing: 6
                        Repeater {
                            model: tilePager.pages
                            Rectangle {
                                required property int index
                                width: 6; height: 6; radius: 3
                                color: index === tilePager.page ? Colors.primary : Colors.outline_variant
                                Behavior on color { ColorAnimation { duration: 150 } }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tilePager.page = index
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // --- Power: quiet icon row, confirm on demand ---
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 26

                        RowLayout {
                            anchors.fill: parent
                            spacing: 24
                            visible: root.pendingCmd === ""
                            Item { Layout.fillWidth: true }
                            PowerIcon { text: "\uf08b"; action: "hyprctl dispatch exit"; actionLabel: "Log out" }
                            PowerIcon { text: "\uf186"; action: "systemctl suspend";     actionLabel: "Suspend" }
                            PowerIcon { text: "\uf021"; action: "systemctl reboot";      actionLabel: "Reboot" }
                            PowerIcon { text: "\uf011"; action: "systemctl poweroff";    actionLabel: "Shut down"; danger: true }
                        }

                        // confirm step for the chosen action
                        RowLayout {
                            anchors.fill: parent
                            spacing: 8
                            visible: root.pendingCmd !== ""
                            Text {
                                Layout.fillWidth: true
                                text: root.pendingLabel + "?"
                                color: Colors.on_surface
                                font { family: root.fontFamily; pixelSize: root.fontSize; bold: true }
                            }
                            Rectangle {
                                implicitWidth: 76; implicitHeight: 26; radius: 8
                                color: Colors.error
                                Text {
                                    anchors.centerIn: parent; text: "Confirm"; color: Colors.background
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.runPower() }
                            }
                            Rectangle {
                                implicitWidth: 66; implicitHeight: 26; radius: 8
                                color: Colors.surface_container_high
                                Text {
                                    anchors.centerIn: parent; text: "Cancel"; color: Colors.on_surface
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clearPower() }
                            }
                        }
                    }
                }

                // =====================================================
                // PAGE: wifi
                // =====================================================
                ColumnLayout {
                    id: wifiPage
                    visible: root.page === "wifi"
                    onVisibleChanged: if (visible) wifiFade.restart()
                    NumberAnimation on opacity {
                        id: wifiFade
                        from: 0; to: 1; duration: 200
                        easing.type: Easing.OutCubic
                        running: false
                    }
                    Layout.fillWidth: true
                    spacing: 12

                    PageHeader {
                        title: "Wi-Fi"
                        Toggle {
                            on: root.wifiUsable
                            onToggled: Quickshell.execDetached(
                                ["bash", root.wifiScript, "power", root.wifiUsable ? "off" : "on"])
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // --- floating card: active connection + live throughput ---
                    Rectangle {
                        visible: root.netUp
                        Layout.fillWidth: true
                        radius: 16
                        color: Colors.surface_container_high
                        implicitHeight: connCol.implicitHeight + 26

                        ColumnLayout {
                            id: connCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 13 }
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    text: root.netIface.indexOf("wl") === 0 ? "\uf1eb" : "\uf1e6"
                                    color: Colors.primary
                                    font { family: root.glyphFont; pixelSize: root.fontSize }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: (root.wifiState === "connected" && root.netIface === root.wifiDev)
                                              ? root.wifiSsid : root.netIface
                                        elide: Text.ElideRight
                                        color: Colors.on_surface
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 1; weight: Font.Medium }
                                    }
                                    Text {
                                        text: "Connected · " + root.netIp
                                        color: Colors.on_surface_variant
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 4 }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.leftMargin: 26
                                spacing: 18
                                Text {
                                    text: "↓"
                                    color: Colors.primary
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                }
                                Text {
                                    Layout.leftMargin: -14
                                    text: root.fmtRate(root.rxRate)
                                    color: Colors.on_surface_variant
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                }
                                Text {
                                    text: "↑"
                                    color: Colors.tertiary
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                }
                                Text {
                                    Layout.leftMargin: -14
                                    text: root.fmtRate(root.txRate)
                                    color: Colors.on_surface_variant
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    Text {
                        visible: root.wifiUsable && root.wifiNets.length === 0
                        Layout.leftMargin: 4
                        text: "Scanning…"
                        color: Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                    }
                    Text {
                        visible: !root.wifiUsable
                        Layout.leftMargin: 4
                        text: "Wi-Fi is off"
                        color: Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                    }

                    Text {
                        visible: root.wifiUsable && root.wifiNets.length > 0
                        Layout.leftMargin: 4
                        text: "Networks"
                        color: Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.wifiUsable

                        Repeater {
                            model: root.wifiNets

                            ColumnLayout {
                                id: netEntry
                                required property var modelData
                                readonly property bool isKnown: root.wifiKnown.indexOf(modelData.ssid) >= 0
                                Layout.fillWidth: true
                                spacing: 3

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 8
                                    color: netArea.containsMouse ? Colors.surface_container_high : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    MouseArea {
                                        id: netArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var m = netEntry.modelData
                                            if (m.conn) {
                                                Quickshell.execDetached(["bash", root.wifiScript, "disconnect"])
                                            } else if (m.sec === "open" || netEntry.isKnown) {
                                                root.wifiConnect(m.ssid, "")
                                            } else {
                                                root.wifiExpanded =
                                                    (root.wifiExpanded === m.ssid) ? "" : m.ssid
                                                root.wifiError = ""
                                            }
                                        }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        Text {
                                            text: ["____", "▂___", "▂▄__",
                                                   "▂▄▆_", "▂▄▆█"]
                                                  [Math.max(0, Math.min(4, netEntry.modelData.bars))]
                                            color: Colors.on_surface_variant
                                            font { family: root.glyphFont; pixelSize: root.fontSize - 4 }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: netEntry.modelData.ssid
                                            elide: Text.ElideRight
                                            color: netEntry.modelData.conn ? Colors.primary : Colors.on_surface
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                                        }
                                        Spinner {
                                            visible: root.wifiBusy === netEntry.modelData.ssid
                                        }
                                        // forget a known network (hover-only, tiny ×)
                                        Text {
                                            visible: netEntry.isKnown && netArea.containsMouse
                                            text: "\uf00d" // nf-fa-times
                                            color: Colors.outline
                                            font { family: root.glyphFont; pixelSize: root.fontSize - 3 }
                                            MouseArea {
                                                anchors.fill: parent; anchors.margins: -5
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached(
                                                        ["bash", root.wifiScript, "forget", netEntry.modelData.ssid])
                                                    wifiKnownProc.acc = []; wifiKnownProc.running = true
                                                }
                                            }
                                        }
                                        Text {
                                            visible: netEntry.modelData.sec !== "open" && !netEntry.modelData.conn
                                            text: "\uf023" // nf-fa-lock
                                            color: Colors.outline
                                            font { family: root.glyphFont; pixelSize: root.fontSize - 4 }
                                        }
                                        Text {
                                            visible: netEntry.modelData.conn
                                            text: "✓"
                                            color: Colors.primary
                                            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                        }
                                    }
                                }

                                // inline password entry for new secured networks.
                                // While this is open the list model is frozen (see
                                // wifiListProc), so typing is never interrupted.
                                RowLayout {
                                    visible: root.wifiExpanded === netEntry.modelData.ssid
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    spacing: 6

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: 8
                                        color: Colors.surface_container_high
                                        border.width: 1
                                        border.color: root.wifiError === netEntry.modelData.ssid
                                                      ? Colors.error : "transparent"
                                        TextInput {
                                            id: pwInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 9
                                            anchors.rightMargin: 9
                                            verticalAlignment: TextInput.AlignVCenter
                                            clip: true
                                            echoMode: TextInput.Password
                                            color: Colors.on_surface
                                            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                            onVisibleChanged: if (visible) forceActiveFocus()
                                            onAccepted: root.wifiConnect(netEntry.modelData.ssid, text)
                                            // Esc closes just the password field (it held the
                                            // exclusive grab, so it must handle the key itself)
                                            Keys.onEscapePressed: { root.wifiExpanded = ""; root.wifiError = "" }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: pwInput.text.length === 0
                                                text: root.wifiError === netEntry.modelData.ssid
                                                      ? "wrong password?" : "password"
                                                color: root.wifiError === netEntry.modelData.ssid
                                                       ? Colors.error : Colors.outline
                                                font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        implicitWidth: 52
                                        implicitHeight: 28
                                        radius: 8
                                        color: Colors.primary
                                        Text {
                                            anchors.centerIn: parent
                                            visible: root.wifiBusy !== netEntry.modelData.ssid
                                            text: "Join"
                                            color: Colors.on_primary
                                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                        }
                                        Spinner {
                                            anchors.centerIn: parent
                                            visible: root.wifiBusy === netEntry.modelData.ssid
                                            color: Colors.on_primary
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.wifiConnect(netEntry.modelData.ssid, pwInput.text)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =====================================================
                // PAGE: bluetooth
                // =====================================================
                ColumnLayout {
                    id: btPage
                    visible: root.page === "bt"
                    onVisibleChanged: if (visible) btFade.restart()
                    NumberAnimation on opacity {
                        id: btFade
                        from: 0; to: 1; duration: 200
                        easing.type: Easing.OutCubic
                        running: false
                    }
                    Layout.fillWidth: true
                    spacing: 12

                    PageHeader {
                        title: "Bluetooth"
                        Toggle {
                            on: root.btOn
                            onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    Text {
                        visible: !root.btOn
                        Layout.leftMargin: 4
                        text: "Bluetooth is off"
                        color: Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                    }

                    // --- paired / trusted devices ---
                    Text {
                        visible: root.btOn
                        Layout.leftMargin: 4
                        text: "My devices"
                        color: Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.btOn

                        Repeater {
                            model: Bluetooth.devices
                            Rectangle {
                                id: btRow
                                required property var modelData
                                readonly property var dev: modelData
                                readonly property bool busy:
                                    dev.state === BluetoothDeviceState.Connecting
                                    || dev.state === BluetoothDeviceState.Disconnecting
                                visible: dev.bonded
                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: 8
                                color: btDevArea.containsMouse ? Colors.surface_container_high : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }

                                // once pairing lands, trust + connect right away.
                                // GUARD: bonded also "changes" false→true while a
                                // delegate first loads its D-Bus data (every reload),
                                // so only react while the bt page is actually in use.
                                Connections {
                                    target: btRow.dev
                                    function onBondedChanged() {
                                        if (btRow.dev.bonded && centerPopup.visible
                                                && root.page === "bt" && !btRow.dev.connected) {
                                            btRow.dev.trusted = true
                                            btRow.dev.connect()
                                        }
                                    }
                                }

                                MouseArea {
                                    id: btDevArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (btRow.busy) return
                                        if (btRow.dev.connected) btRow.dev.disconnect()
                                        else btRow.dev.connect()
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: (btRow.dev.name || btRow.dev.deviceName || btRow.dev.address)
                                             + (btRow.dev.batteryAvailable
                                                ? "  " + Math.round(btRow.dev.battery * 100) + "%" : "")
                                        color: btRow.dev.connected ? Colors.primary : Colors.on_surface
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        elide: Text.ElideRight
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                                    }
                                    Spinner { visible: btRow.busy }
                                    Text {
                                        visible: !btRow.busy
                                        text: btRow.dev.connected ? "Disconnect" : "Connect"
                                        color: btRow.dev.connected ? Colors.error : Colors.primary
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                    }
                                    // forget (unpair) — hover-only, tiny ×
                                    Text {
                                        visible: btDevArea.containsMouse
                                        text: "\uf00d" // nf-fa-times
                                        color: Colors.outline
                                        font { family: root.glyphFont; pixelSize: root.fontSize - 3 }
                                        MouseArea {
                                            anchors.fill: parent; anchors.margins: -5
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: btRow.dev.forget()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 1
                        color: Colors.outline_variant; opacity: 0.35
                        visible: root.btOn
                    }

                    // --- nearby (discovered, unpaired) devices ---
                    RowLayout {
                        visible: root.btOn
                        Layout.leftMargin: 4
                        spacing: 8
                        Text {
                            text: "Nearby"
                            color: Colors.outline
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                        }
                        Spinner {
                            visible: root.btAdapter && root.btAdapter.discovering
                            font.pixelSize: root.fontSize - 5
                            color: Colors.outline
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.btOn

                        Repeater {
                            model: Bluetooth.devices
                            Rectangle {
                                id: nearRow
                                required property var modelData
                                readonly property var dev: modelData
                                // only named, unpaired devices — unnamed ones report their
                                // MAC (XX-XX-…) as the name, which is just noise
                                visible: !dev.bonded && (dev.name || "").length > 0
                                         && !/^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/.test(dev.name)
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 8
                                color: nearArea.containsMouse ? Colors.surface_container_high : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }

                                MouseArea {
                                    id: nearArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!nearRow.dev.pairing) nearRow.dev.pair()
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: nearRow.dev.name
                                        color: Colors.on_surface
                                        elide: Text.ElideRight
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                                    }
                                    Spinner { visible: nearRow.dev.pairing }
                                    Text {
                                        visible: !nearRow.dev.pairing
                                        text: "Pair"
                                        color: Colors.primary
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                    }
                                }
                            }
                        }
                    }

                    // full Bluetooth manager (overskride) for anything the
                    // quick panel doesn't cover (audio profiles, file transfer…)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: moreBtArea.containsMouse ? Colors.surface_container_high : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                        MouseArea {
                            id: moreBtArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Quickshell.execDetached(["overskride"]); PopupBus.close() }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: "More settings…"
                                color: Colors.on_surface_variant
                                font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                            }
                            Text {
                                text: "\uf08e" // nf-fa-external_link
                                color: Colors.outline
                                font { family: root.glyphFont; pixelSize: root.fontSize - 4 }
                            }
                        }
                    }
                }

                // =====================================================
                // PAGE: mixer \u2014 master + per-app playback volumes
                // =====================================================
                ColumnLayout {
                    id: mixerPage
                    visible: root.page === "mixer"
                    Layout.fillWidth: true
                    spacing: 14

                    PageHeader { title: "Volume" }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // master (default sink) \u2014 same behaviour as the main page slider
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: root.sinkReady && root.sink.audio.muted ? "\uf026" : "\uf028"
                            color: Colors.on_surface
                            font { family: root.glyphFont; pixelSize: root.fontSize + 2 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.sinkReady) root.sink.audio.muted = !root.sink.audio.muted
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 22
                            Rectangle {
                                id: mixMasterTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 6; radius: 3
                                color: Colors.surface_container_high
                                Rectangle {
                                    width: parent.width * root.vol
                                    height: parent.height; radius: 3
                                    color: Colors.primary
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(mixMasterTrack.width - 14, mixMasterTrack.width * root.vol - 7))
                                width: 14; height: 14; radius: 7
                                color: Colors.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (m) => root.setVol(m.x / width)
                                onPositionChanged: (m) => { if (pressed) root.setVol(m.x / width) }
                            }
                        }
                        Text {
                            text: Math.round(root.vol * 100) + "%"
                            color: Colors.on_surface_variant
                            Layout.preferredWidth: 36
                            horizontalAlignment: Text.AlignRight
                            font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // --- output device switcher (one click: HDMI <-> buds) ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.outSinks.length > 1
                        spacing: 8

                        Text {
                            Layout.leftMargin: 4
                            text: "Output"
                            color: Colors.outline
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: root.outSinks
                                Rectangle {
                                    id: outRow
                                    required property var modelData
                                    readonly property bool isDefault: Pipewire.defaultAudioSink !== null
                                        && modelData.id === Pipewire.defaultAudioSink.id
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 10
                                    color: outArea.containsMouse ? Colors.surface_container_high : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8
                                        Text {
                                            text: outRow.isDefault ? "\uf192" : "\uf10c" // nf-fa dot-circle-o / circle-o
                                            color: outRow.isDefault ? Colors.primary : Colors.outline
                                            font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: outRow.modelData.description || outRow.modelData.nickname || outRow.modelData.name
                                            elide: Text.ElideRight
                                            color: outRow.isDefault ? Colors.on_surface : Colors.on_surface_variant
                                            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                        }
                                    }
                                    MouseArea {
                                        id: outArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Pipewire.preferredDefaultAudioSink = outRow.modelData
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }
                    }

                    Text {
                        Layout.leftMargin: 4
                        text: "Apps"
                        color: Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                    }

                    Text {
                        visible: root.appStreams.length === 0
                        Layout.leftMargin: 4
                        text: "Nothing is playing audio"
                        color: Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Repeater {
                            model: root.appStreams

                            ColumnLayout {
                                id: mixRow
                                required property var modelData
                                readonly property var st: modelData
                                readonly property var au: st ? st.audio : null
                                visible: au !== null
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        text: mixRow.au && mixRow.au.muted ? "\uf026" : "\uf028"
                                        color: mixRow.au && mixRow.au.muted ? Colors.outline : Colors.on_surface_variant
                                        font { family: root.glyphFont; pixelSize: root.fontSize - 1 }
                                        MouseArea {
                                            anchors.fill: parent; anchors.margins: -4
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (mixRow.au) mixRow.au.muted = !mixRow.au.muted
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            var p = mixRow.st.properties || ({})
                                            return p["application.name"] || mixRow.st.description || mixRow.st.name || "App"
                                        }
                                        color: Colors.on_surface
                                        elide: Text.ElideRight
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 2; weight: Font.Medium }
                                    }
                                    Text {
                                        text: mixRow.au ? Math.round(mixRow.au.volume * 100) + "%" : ""
                                        color: Colors.on_surface_variant
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 24
                                    implicitHeight: 16
                                    Rectangle {
                                        id: mixTrack
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 5; radius: 2.5
                                        color: Colors.surface_container_high
                                        Rectangle {
                                            width: parent.width * (mixRow.au ? Math.min(1, mixRow.au.volume) : 0)
                                            height: parent.height; radius: 2.5
                                            color: Colors.secondary
                                        }
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(mixTrack.width - 12,
                                            mixTrack.width * (mixRow.au ? Math.min(1, mixRow.au.volume) : 0) - 6))
                                        width: 12; height: 12; radius: 6
                                        color: Colors.on_surface
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: (m) => { if (mixRow.au) mixRow.au.volume = Math.max(0, Math.min(1, m.x / width)) }
                                        onPositionChanged: (m) => { if (pressed && mixRow.au) mixRow.au.volume = Math.max(0, Math.min(1, m.x / width)) }
                                    }
                                }
                            }
                        }
                    }
                }

                // =====================================================
                // PAGE: phone \u2014 Valent (KDE Connect protocol) shortcuts
                // =====================================================
                ColumnLayout {
                    id: phonePage
                    visible: root.page === "phone"
                    Layout.fillWidth: true
                    spacing: 12

                    // battery/state already live on the main page's Phone tile,
                    // so the page is just: name in the header, tiles, send box
                    PageHeader { title: root.phoneName !== "" ? root.phoneName : "Phone" }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                    // --- quick actions: quiet squircle grid, glyph + tiny label ---
                    GridLayout {
                        visible: root.phoneConnected
                        Layout.fillWidth: true
                        columns: 4
                        rowSpacing: 8
                        columnSpacing: 8

                        Repeater {
                            model: [
                                { g: "\uf0f3", t: "Ring",      dev: "findmyphone.ring", app: "",                close: false },
                                { g: "\uf0ea", t: "Send clip", dev: "clipboard.push",   app: "",                close: false },
                                { g: "\uf0c5", t: "Get clip",  dev: "clipboard.pull",   app: "",                close: false },
                                { g: "\uf07b", t: "Files",     dev: "sftp.browse",      app: "",                close: true },
                                { g: "\uf064", t: "Share",     dev: "",                 app: "share-dialog",    close: true },
                                { g: "\uf144", t: "Media",     dev: "",                 app: "media-window",    close: true },
                                { g: "\uf245", t: "Input",     dev: "",                 app: "input-remote",    close: true },
                                { g: "\uf075", t: "SMS",       dev: "",                 app: "messages-window", close: true }
                            ]
                            Rectangle {
                                id: pTile
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 56
                                radius: 16
                                color: Colors.surface_container_high
                                scale: pTileArea.pressed ? 0.95 : 1
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: pTile.modelData.g
                                        color: pTileArea.containsMouse ? Colors.primary : Colors.on_surface_variant
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        font { family: root.glyphFont; pixelSize: root.fontSize + 1 }
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: pTile.modelData.t
                                        color: Colors.on_surface_variant
                                        font { family: root.fontFamily; pixelSize: root.fontSize - 5 }
                                    }
                                }
                                MouseArea {
                                    id: pTileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (pTile.modelData.dev !== "")
                                            root.phoneAction(pTile.modelData.dev)
                                        else
                                            Quickshell.execDetached(["gapplication", "action",
                                                                     "ca.andyholmes.Valent", pTile.modelData.app])
                                        if (pTile.modelData.close) PopupBus.close()
                                    }
                                }
                            }
                        }
                    }

                    // --- send text / link to the phone ---
                    RowLayout {
                        visible: root.phoneConnected
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 8
                            color: Colors.surface_container_high
                            border.width: 1
                            border.color: phoneShareInput.activeFocus ? Colors.primary : "transparent"
                            TextInput {
                                id: phoneShareInput
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: Colors.on_surface
                                font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                onActiveFocusChanged: root.phoneTyping = activeFocus
                                onAccepted: { root.phoneShareText(text); text = "" }
                                Keys.onEscapePressed: focus = false
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: phoneShareInput.text.length === 0
                                    text: "text or link to phone\u2026"
                                    color: Colors.outline
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                }
                            }
                        }
                        Rectangle {
                            implicitWidth: 52
                            implicitHeight: 28
                            radius: 8
                            color: Colors.primary
                            Text {
                                anchors.centerIn: parent
                                text: "Send"
                                color: Colors.on_primary
                                font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.phoneShareText(phoneShareInput.text); phoneShareInput.text = "" }
                            }
                        }
                    }

                    Text {
                        visible: root.phoneId !== "" && !root.phoneConnected
                        Layout.leftMargin: 4
                        text: "Phone is offline"
                        color: Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                    }

                    // full Valent app for anything the quick tiles don't cover
                    // (same pattern as the Bluetooth page's "More settings\u2026")
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: moreValentArea.containsMouse ? Colors.surface_container_high : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                        MouseArea {
                            id: moreValentArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["gapplication", "action", "ca.andyholmes.Valent", "window"])
                                PopupBus.close()
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: "Open Valent\u2026"
                                color: Colors.on_surface_variant
                                font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                            }
                            Text {
                                text: "\uf08e" // nf-fa-external_link
                                color: Colors.outline
                                font { family: root.glyphFont; pixelSize: root.fontSize - 4 }
                            }
                        }
                    }

                    Text {
                        visible: root.phoneId === ""
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: "Pair your phone in Valent (KDE Connect app on Android)."
                        wrapMode: Text.WordWrap
                        color: Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                    }
                }
            }
        }
    }
}
