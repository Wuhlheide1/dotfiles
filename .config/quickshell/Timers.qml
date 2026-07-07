// Timers.qml — bar widget + flyout: countdown timers, alarms, stopwatch.
//
// Bar shows a small clock glyph as the entry point; while a timer runs it
// shows the soonest remaining time, while the stopwatch runs it shows the
// elapsed time. Click (or SUPER+T / `qs ipc call timers toggle`) opens the
// flyout. When a timer/alarm fires: critical notification + chime; entries
// marked important (star) also pulse the screen edges red.
//
// State persists to ~/.local/state/quickshell/timers.json so running timers,
// the stopwatch and all alarms survive shell restarts.
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
    readonly property string glyphFont: "JetBrainsMono Nerd Font"
    readonly property string stateFile:
        Quickshell.env("HOME") + "/.local/state/quickshell/timers.json"
    readonly property string chime:
        "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

    // --- state -----------------------------------------------------------
    property var timers: []   // { label, endAt(ms), secs, important }
    property var alarms: []   // { time "HH:MM", label, enabled, important, lastFired "yyyy-mm-dd" }
    property bool swRunning: false
    property double swStart: 0    // ms epoch of (re)start
    property double swAccum: 0    // ms accumulated across pauses
    property int tick: 0          // bumps every heartbeat so labels re-evaluate

    readonly property bool anyCountdown: timers.length > 0
    readonly property bool anyActive: swRunning || anyCountdown

    function now() { return Date.now() }
    function swElapsed() { tick; return swAccum + (swRunning ? now() - swStart : 0) }

    function fmtDur(ms) {
        var s = Math.max(0, Math.round(ms / 1000))
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
        function p(n) { return (n < 10 ? "0" : "") + n }
        return h > 0 ? h + ":" + p(m) + ":" + p(sec) : m + ":" + p(sec)
    }

    // --- heartbeat: only while something is running or the flyout is open --
    Timer {
        interval: 500; repeat: true
        running: root.anyActive || PopupBus.current === "timers"
        onTriggered: {
            root.tick++
            var t = root.now()
            var keep = [], chain = [], fired = false
            for (var i = 0; i < root.timers.length; i++) {
                var tm = root.timers[i]
                if (tm.endAt > t) { keep.push(tm); continue }
                fired = true
                // pomodoro: Focus and Break chain into each other until the
                // running one is cancelled (the 25|5 preset starts the cycle)
                if (tm.label === "Focus") {
                    root.fire("Focus done", "5 min break — step away", tm.important)
                    chain.push({ secs: 300, label: "Break", important: tm.important })
                } else if (tm.label === "Break") {
                    root.fire("Break over", "25 min focus — go", tm.important)
                    chain.push({ secs: 1500, label: "Focus", important: tm.important })
                } else {
                    root.fire(tm.label || "Timer",
                              root.fmtDur(tm.secs * 1000) + " is up", tm.important)
                }
            }
            if (fired) {
                root.timers = keep
                for (var c = 0; c < chain.length; c++)
                    root.addTimer(chain[c].secs, chain[c].label, chain[c].important)
                if (chain.length === 0) root.save()   // addTimer already saves
            }
        }
    }

    // --- alarms: cheap in-process date compare, 5s cadence while any enabled --
    Timer {
        interval: 5000; repeat: true
        running: root.alarms.some(a => a.enabled)
        onTriggered: {
            var d = new Date()
            function p(n) { return (n < 10 ? "0" : "") + n }
            var hm = p(d.getHours()) + ":" + p(d.getMinutes())
            var today = d.toISOString().slice(0, 10)
            var dow = (d.getDay() + 6) % 7   // Monday = 0, matches the UI letters
            var changed = false
            for (var i = 0; i < root.alarms.length; i++) {
                var a = root.alarms[i]
                // days: per-weekday schedule; missing (older alarms) = every day
                if (a.enabled && (!a.days || a.days[dow])
                        && a.time === hm && a.lastFired !== today) {
                    root.fire(a.label || "Alarm", a.time, a.important, true)
                    a.lastFired = today
                    changed = true
                }
            }
            if (changed) { root.alarmsChanged(); root.save() }
        }
    }

    function fire(title, body, important, snoozable) {
        if (snoozable) {
            // -A adds a Snooze button (rendered by our own notification
            // server); notify-send prints the chosen action key when clicked
            Quickshell.execDetached(["sh", "-c",
                'pw-play "$3" & a=$(notify-send -a "Timers" -u critical -A snooze="Snooze 5 min" "$1" "$2"); '
                + '[ "$a" = "snooze" ] && qs ipc call timers snooze ' + (important ? "1" : "0"),
                "sh", title, body, root.chime])
        } else {
            Quickshell.execDetached(["sh", "-c",
                'notify-send -a "Timers" -u critical "$1" "$2"; pw-play "$3" &',
                "sh", title, body, root.chime])
        }
        if (important) flashAnim.restart()
    }

    // --- persistence -------------------------------------------------------
    property bool saveDirty: false
    function save() {
        var json = JSON.stringify({
            timers: timers, alarms: alarms,
            swRunning: swRunning, swStart: swStart, swAccum: swAccum
        })
        if (saveProc.running) { saveDirty = true; return }
        saveProc.command = ["sh", "-c", 'printf %s "$1" > "$2"', "sh", json, stateFile]
        saveProc.running = true
    }
    Process {
        id: saveProc
        onExited: if (root.saveDirty) { root.saveDirty = false; root.save() }
    }
    Process {
        id: loadProc
        running: true
        command: ["cat", root.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var st = JSON.parse(text)
                    var t = root.now(), keep = []
                    for (var i = 0; i < (st.timers || []).length; i++) {
                        var tm = st.timers[i]
                        // fire timers that expired while the shell was down
                        // (recently), silently drop older leftovers
                        if (tm.endAt <= t) {
                            if (t - tm.endAt < 300000)
                                root.fire(tm.label || "Timer", "finished while the shell was restarting", tm.important)
                        } else keep.push(tm)
                    }
                    root.timers = keep
                    root.alarms = st.alarms || []
                    root.swRunning = !!st.swRunning
                    root.swStart = st.swStart || 0
                    root.swAccum = st.swAccum || 0
                } catch (e) { /* first run: no state yet */ }
            }
        }
    }

    // Parse a duration: "90s", "5m30s", "1h20m", "1:30" (m:ss) — and a bare
    // number stays MINUTES, matching the old input's habit.
    function parseDur(str) {
        var s = str.trim().toLowerCase()
        var m = s.match(/^(\d+):([0-5]?\d)$/)
        if (m) return parseInt(m[1]) * 60 + parseInt(m[2])
        m = s.match(/^(?:(\d+)h)?\s*(?:(\d+)m)?\s*(?:(\d+)s)?$/)
        if (m && (m[1] || m[2] || m[3]))
            return (parseInt(m[1]) || 0) * 3600 + (parseInt(m[2]) || 0) * 60
                 + (parseInt(m[3]) || 0)
        if (/^\d+$/.test(s)) return parseInt(s) * 60
        return 0
    }
    function fmtShort(secs) {
        var h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60), s = secs % 60
        var out = []
        if (h) out.push(h + "h")
        if (m) out.push(m + "m")
        if (s) out.push(s + "s")
        return out.join(" ") || "0s"
    }

    // --- actions -----------------------------------------------------------
    function addTimer(secs, label, important) {
        if (!(secs > 0)) return
        var t = timers.slice()
        t.push({ label: label || "Timer", endAt: now() + secs * 1000,
                 secs: secs, important: !!important })
        t.sort((a, b) => a.endAt - b.endAt)
        timers = t
        save()
    }
    function cancelTimer(idx) {
        var t = timers.slice(); t.splice(idx, 1); timers = t; save()
    }
    function toggleTimerImportant(idx) {
        var t = timers.slice(); t[idx].important = !t[idx].important; timers = t; save()
    }
    function swToggle() {
        if (swRunning) { swAccum += now() - swStart; swRunning = false }
        else { swStart = now(); swRunning = true }
        save()
    }
    function swReset() { swRunning = false; swAccum = 0; save() }
    function addAlarm(hm, important) {
        var m = /^([01]?\d|2[0-3]):?([0-5]\d)$/.exec(hm.trim())
        if (!m) return false
        var a = alarms.slice()
        a.push({ time: (m[1].length < 2 ? "0" : "") + m[1] + ":" + m[2],
                 label: "Alarm", enabled: true, important: !!important, lastFired: "",
                 days: [true, true, true, true, true, true, true] })
        a.sort((x, y) => x.time < y.time ? -1 : 1)
        alarms = a
        save()
        return true
    }
    function removeAlarm(idx) {
        var a = alarms.slice(); a.splice(idx, 1); alarms = a; save()
    }
    function patchAlarm(idx, key) {
        var a = alarms.slice(); a[idx][key] = !a[idx][key]; alarms = a; save()
    }
    function toggleAlarmDay(idx, day) {
        var a = alarms.slice()
        var days = (a[idx].days || [true, true, true, true, true, true, true]).slice()
        days[day] = !days[day]
        a[idx].days = days
        alarms = a
        save()
    }

    // CLI access: qs ipc call timers toggle | qs ipc call timers start 10
    //             qs ipc call timers addsecs 600 tea   (launcher quick-add)
    IpcHandler {
        target: "timers"
        function toggle(): void { PopupBus.toggle("timers") }
        function start(minutes: int): void { root.addTimer(minutes * 60, "Timer", false) }
        function addsecs(secs: int, label: string): void { root.addTimer(secs, label || "Timer", false) }
        function stopwatch(): void { root.swToggle() }
        // called by the Snooze notification action (fire() wires it up)
        function snooze(imp: int): void { root.addTimer(300, "Snoozed alarm", imp === 1) }
    }

    // --- pill state (rendered by shell.qml next to the workspaces) ----------
    // Nothing shows while idle; the flyout is reached via SUPER+T. Entry order:
    // stopwatch first (the thing you glance at most), then timers soonest-first.
    // No auto-cycling \u2014 scrolling on the pill switches entries; shell.qml draws
    // one dot per entry with the selected one highlighted.
    readonly property int pillCount: (swRunning ? 1 : 0) + timers.length
    property int pillIdx: 0
    onPillCountChanged: if (pillIdx >= pillCount) pillIdx = 0
    // clamped, not circular: scrolling past an end does nothing — the dot
    // strip only shows a mini dot on sides where entries remain
    function pillScroll(dir) {
        pillIdx = Math.max(0, Math.min(pillCount - 1, pillIdx + dir))
    }
    // true while any entry needs the h:mm:ss format — pins the pill width
    // (`timers || []` guards cover the moment of a config hot-reload, when
    // properties can briefly read as undefined)
    readonly property bool pillWide: {
        tick
        var ts = timers || []
        if (swRunning && swElapsed() >= 3600000) return true
        for (var i = 0; i < ts.length; i++)
            if (ts[i].endAt - now() >= 3600000) return true
        return false
    }
    readonly property bool pillIsSw: swRunning && pillIdx === 0
    readonly property int pillTimerIdx: swRunning ? pillIdx - 1 : pillIdx
    readonly property string pillGlyph: pillIsSw ? "\uf2f2" : "\uf252"
    readonly property string pillText: {
        tick
        var ts = timers || []
        if (pillCount === 0) return ""
        if (pillIsSw) return fmtDur(swElapsed())
        return (pillTimerIdx >= 0 && pillTimerIdx < ts.length)
               ? fmtDur(ts[pillTimerIdx].endAt - now()) : ""
    }
    readonly property bool pillUrgent: {
        tick
        var ts = timers || []
        return !pillIsSw && pillTimerIdx >= 0 && pillTimerIdx < ts.length
               && (ts[pillTimerIdx].endAt - now()) < 60000
    }

    // --- screen flash for important timers/alarms (click-through overlay) ---
    PanelWindow {
        id: flashWin
        visible: flashRect.opacity > 0
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}   // input passes straight through

        Rectangle {
            id: flashRect
            anchors.fill: parent
            // error red pulled slightly toward the wallpaper accent
            color: Qt.tint(Colors.error, Qt.alpha(Colors.primary, 0.3))
            opacity: 0
        }
    }
    // Gentle breathing pulse, NOT a strobe — the original 180ms blink at 30%
    // opacity was a jump scare (user: "nearly died from a heart attack").
    SequentialAnimation {
        id: flashAnim
        loops: 2
        NumberAnimation { target: flashRect; property: "opacity"; to: 0.16; duration: 550; easing.type: Easing.InOutSine }
        NumberAnimation { target: flashRect; property: "opacity"; to: 0;    duration: 950; easing.type: Easing.InOutSine }
    }

    // --- flyout --------------------------------------------------------------
    PanelWindow {
        id: flyout
        visible: PopupBus.current === "timers"
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        // exclusive while open: Esc closes instantly (no click-first needed)
        // and the minute/alarm inputs type without extra focus juggling
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }
        Item { focus: true; Keys.onEscapePressed: PopupBus.close() }

        Rectangle {
            // top-left, by the pill next to the workspaces
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: 6
            anchors.leftMargin: 12
            width: 330
            height: fcol.implicitHeight + 34
            radius: 18
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            transformOrigin: Item.TopLeft
            opacity: flyout.visible ? 1 : 0
            scale: flyout.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // swallow inside clicks

            ColumnLayout {
                id: fcol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 17 }
                spacing: 12

                // ===== stopwatch =====
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: "\uf2f2"   // stopwatch
                        color: root.swRunning ? Colors.primary : Colors.on_surface_variant
                        font { family: root.glyphFont; pixelSize: root.fontSize + 1 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.fmtDur(root.swElapsed())
                        color: Colors.on_surface
                        font { family: root.fontFamily; pixelSize: root.fontSize + 3; bold: root.swRunning }
                    }
                    Rectangle {
                        implicitWidth: 62; implicitHeight: 26; radius: 8
                        color: root.swRunning ? Colors.surface_container_high : Colors.primary
                        Text {
                            anchors.centerIn: parent
                            text: root.swRunning ? "Pause"
                                 : (root.swElapsed() > 0 ? "Resume" : "Start")
                            color: root.swRunning ? Colors.on_surface : Colors.on_primary
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.swToggle() }
                    }
                    Rectangle {
                        visible: root.swElapsed() > 0
                        implicitWidth: 52; implicitHeight: 26; radius: 8
                        color: Colors.surface_container_high
                        Text {
                            anchors.centerIn: parent
                            text: "Reset"
                            color: Colors.on_surface
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.swReset() }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                // ===== timers =====
                Text {
                    text: "Timer"
                    color: Colors.outline
                    font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [10, 25, 60]
                        Rectangle {
                            id: presetBtn
                            required property int modelData
                            implicitWidth: 46; implicitHeight: 28; radius: 9
                            color: presetArea.containsMouse ? Colors.primary : Colors.surface_container_high
                            Text {
                                anchors.centerIn: parent
                                text: presetBtn.modelData >= 60
                                      ? (presetBtn.modelData / 60) + "h" : presetBtn.modelData + "m"
                                color: presetArea.containsMouse ? Colors.on_primary : Colors.on_surface
                                font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                            }
                            MouseArea {
                                id: presetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addTimer(presetBtn.modelData * 60, presetBtn.modelData + " min", false)
                            }
                        }
                    }
                    // pomodoro: Focus/Break chain until the running one is cancelled
                    Rectangle {
                        implicitWidth: 46; implicitHeight: 28; radius: 9
                        color: pomoArea.containsMouse ? Colors.primary : Colors.surface_container_high
                        Text {
                            anchors.centerIn: parent
                            text: "25|5"
                            color: pomoArea.containsMouse ? Colors.on_primary : Colors.on_surface
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                        }
                        MouseArea {
                            id: pomoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addTimer(1500, "Focus", false)
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28; radius: 9
                        color: Colors.surface_container_high
                        border.width: 1
                        border.color: customMin.activeFocus ? Colors.primary : "transparent"
                        TextInput {
                            id: customMin
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            // "5" = minutes, "90s"/"5m30s"/"1h20m"/"1:30" also work
                            validator: RegularExpressionValidator {
                                regularExpression: /[\dhms: ]{0,12}/
                            }
                            color: Colors.on_surface
                            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                            onAccepted: {
                                var secs = root.parseDur(text)
                                if (secs > 0) { root.addTimer(secs, root.fmtShort(secs), false); text = "" }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: customMin.text.length === 0
                                text: "5m 30s ⏎"
                                color: Colors.outline
                                font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                            }
                        }
                    }
                }

                // active timers
                Repeater {
                    model: root.timers
                    RowLayout {
                        id: timerRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "\uf252"   // hourglass-half
                            color: Colors.primary
                            font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: {
                                root.tick
                                return root.fmtDur(timerRow.modelData.endAt - root.now())
                                       + "  ·  " + timerRow.modelData.label
                            }
                            color: Colors.on_surface
                            elide: Text.ElideRight
                            font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                        }
                        // star = important: fires with a red screen pulse
                        Text {
                            text: "\uf005"   // star
                            color: timerRow.modelData.important ? Colors.primary : Colors.outline
                            opacity: timerRow.modelData.important ? 1.0 : 0.45
                            font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleTimerImportant(timerRow.index)
                            }
                        }
                        Text {
                            text: "\uf00d"   // times
                            color: Colors.outline
                            font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelTimer(timerRow.index)
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                // ===== alarms =====
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "Alarms"
                        color: Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize - 3; bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        implicitWidth: 76; implicitHeight: 26; radius: 9
                        color: Colors.surface_container_high
                        border.width: 1
                        border.color: alarmTime.activeFocus ? Colors.primary : "transparent"
                        TextInput {
                            id: alarmTime
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            clip: true
                            maximumLength: 5
                            color: Colors.on_surface
                            font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                            onAccepted: if (root.addAlarm(text, false)) text = ""
                            Text {
                                anchors.centerIn: parent
                                visible: alarmTime.text.length === 0
                                text: "HH:MM"
                                color: Colors.outline
                                font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                            }
                        }
                    }
                    Rectangle {
                        implicitWidth: 44; implicitHeight: 26; radius: 9
                        color: Colors.primary
                        Text {
                            anchors.centerIn: parent
                            text: "Add"
                            color: Colors.on_primary
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.addAlarm(alarmTime.text, false)) alarmTime.text = ""
                        }
                    }
                }

                Text {
                    visible: root.alarms.length === 0
                    text: "No alarms"
                    color: Colors.outline
                    font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                }

                Repeater {
                    model: root.alarms
                    ColumnLayout {
                        id: alarmRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: alarmRow.modelData.time
                            color: alarmRow.modelData.enabled ? Colors.on_surface : Colors.outline
                            font { family: root.fontFamily; pixelSize: root.fontSize + 1
                                   bold: alarmRow.modelData.enabled }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "\uf005"   // star = important (red screen pulse)
                            color: alarmRow.modelData.important ? Colors.primary : Colors.outline
                            opacity: alarmRow.modelData.important ? 1.0 : 0.45
                            font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.patchAlarm(alarmRow.index, "important")
                            }
                        }
                        Rectangle {
                            implicitWidth: 38; implicitHeight: 20; radius: 10
                            color: alarmRow.modelData.enabled ? Colors.primary : Colors.surface_container_high
                            Rectangle {
                                width: 14; height: 14; radius: 7
                                anchors.verticalCenter: parent.verticalCenter
                                x: alarmRow.modelData.enabled ? parent.width - width - 3 : 3
                                color: alarmRow.modelData.enabled ? Colors.on_primary : Colors.outline
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.patchAlarm(alarmRow.index, "enabled")
                            }
                        }
                        Text {
                            text: "\uf00d"   // times
                            color: Colors.outline
                            font { family: root.glyphFont; pixelSize: root.fontSize - 2 }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeAlarm(alarmRow.index)
                            }
                        }
                        }

                        // per-weekday schedule: tap a letter to skip that day
                        RowLayout {
                            Layout.leftMargin: 2
                            spacing: 9
                            Repeater {
                                model: ["M", "T", "W", "T", "F", "S", "S"]
                                Text {
                                    id: dayLetter
                                    required property string modelData
                                    required property int index
                                    readonly property bool dayOn:
                                        !alarmRow.modelData.days || alarmRow.modelData.days[index]
                                    text: dayLetter.modelData
                                    color: dayLetter.dayOn ? Colors.primary : Colors.outline
                                    opacity: alarmRow.modelData.enabled
                                             ? (dayLetter.dayOn ? 1.0 : 0.4) : 0.3
                                    font { family: root.fontFamily; pixelSize: root.fontSize - 5
                                           bold: dayLetter.dayOn }
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -3
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleAlarmDay(alarmRow.index, dayLetter.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
