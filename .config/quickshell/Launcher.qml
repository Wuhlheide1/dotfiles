// Launcher.qml — application launcher (search + arrow keys + Enter).
//
// Improvements over the basic version:
//   - smarter, scored search (matches name / generic name / keywords / exec),
//   - "frecency": apps you launch often float to the top (persisted to disk),
//   - the result list now actually SCROLLS to follow the selection,
//   - robust icons: entries with a missing/unresolvable icon get a clean
//     letter-avatar instead of the broken "missing texture" placeholder,
//   - Raycast-style extras: system ACTIONS (lock, screenshot, reboot…) rank
//     alongside apps, and typing math shows an inline CALCULATOR row whose
//     result Enter copies to the clipboard.
//
// Loaded on demand from shell.qml via a LazyLoader and toggled with a keybind.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: launcher

    // Cover the whole screen so we can dim the background and catch click-away.
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Grab the keyboard so we can type into the search box.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:launcher"

    // Emitted when the user dismisses or picks something. The loader listens.
    signal dismissed()

    // --- data -------------------------------------------------------------
    property string query: ""

    // Persisted launch counts: { "<entry id>": count }. Drives "frecency"
    // ordering so your most-used apps come first.
    property var freqMap: ({})

    FileView {
        id: freqFile
        path: Quickshell.cachePath("launcher-frecency.json")
        blockLoading: true   // read synchronously on first access
        printErrors: false   // file won't exist on first run; that's fine
    }

    // --- system actions (Raycast-style commands) ---------------------------
    // Only surface while typing; matched by name + keywords like apps are.
    readonly property var actions: [
        { name: "Lock Screen",        glyph: "\uf023", keywords: "lock security afk",            cmd: "hyprlock" },
        { name: "Suspend",            glyph: "\uf186", keywords: "sleep zzz",                    cmd: "systemctl suspend" },
        { name: "Reboot",             glyph: "\uf021", keywords: "restart",                      cmd: "systemctl reboot" },
        { name: "Shut Down",          glyph: "\uf011", keywords: "power off poweroff halt",      cmd: "systemctl poweroff" },
        { name: "Log Out",            glyph: "\uf08b", keywords: "exit quit session",            cmd: "hyprctl dispatch exit" },
        { name: "Control Center",     glyph: "\uf013", keywords: "settings quick wifi bluetooth volume", cmd: "qs ipc call control toggle" },
        { name: "Wallpaper Picker",   glyph: "\uf03e", keywords: "background image",             cmd: "qs ipc call wallpaper open" },
        { name: "Shuffle Wallpaper",  glyph: "\uf074", keywords: "random background image next", cmd: "bash /home/wuhlheide/.config/quickshell/scripts/wallpaper.sh random" },
        { name: "Clipboard History",  glyph: "\uf0ea", keywords: "paste cliphist copy",          cmd: "qs ipc call clipboard open" },
        { name: "Keybind Cheatsheet", glyph: "\uf11c", keywords: "shortcuts help keys",          cmd: "qs ipc call cheatsheet open" },
        { name: "Screenshot Region",  glyph: "\uf125", keywords: "capture area grim slurp",      cmd: "qs ipc call screenshot region" },
        { name: "Screenshot Screen",  glyph: "\uf108", keywords: "capture full monitor",         cmd: "qs ipc call screenshot full" },
        { name: "Screenshot Window",  glyph: "\uf2d0", keywords: "capture active",               cmd: "qs ipc call screenshot win" },
        { name: "Screenshot & Annotate", glyph: "\uf040", keywords: "satty edit draw markup arrow", cmd: "qs ipc call screenshot annotate" },
        { name: "Screenshot OCR",     glyph: "", keywords: "text grab copy read tesseract",  cmd: "qs ipc call screenshot ocr" },
        { name: "Record Screen",      glyph: "\uf03d", keywords: "video wf-recorder toggle stop", cmd: "/home/wuhlheide/.config/quickshell/scripts/record.sh toggle" },
        { name: "Color Picker",       glyph: "\uf1fb", keywords: "hex eyedropper pick",          cmd: "hyprpicker -a -f hex" },
        { name: "Bluetooth Manager",  glyph: "\uf293", keywords: "overskride pair devices",      cmd: "overskride" }
    ]

    // --- emoji picker (":fire" → matching emoji, Enter copies) --------------
    // Cache is a mutated object member, NOT a reassigned property — assigning
    // a property inside emojiHits() (called from the results binding) would
    // create a results binding loop.
    property var emojiCache: ({})

    FileView {
        id: emojiFile
        path: "/home/wuhlheide/.config/quickshell/emoji.json"
        printErrors: false
    }

    function emojiHits(term) {
        if (emojiCache.list === undefined) {
            try { emojiCache.list = JSON.parse(emojiFile.text() || "[]"); }
            catch (e) { emojiCache.list = []; }
        }
        const emojiList = emojiCache.list;
        const words = term.split(/\s+/).filter(w => w.length > 0);
        if (words.length === 0) return [];
        const hits = [];
        for (const e of emojiList) {
            if (!words.every(w => e.n.includes(w))) continue;
            hits.push({ kind: "emoji", name: e.n, char: e.c,
                        s: e.n.startsWith(words[0]) ? 1 : 0 });
            if (hits.length >= 60) break;
        }
        hits.sort((a, b) => (b.s - a.s) || (a.name.length - b.name.length));
        return hits.slice(0, 20);
    }

    // --- file search ("~photo" → files under $HOME, Enter opens) ------------
    property var fileHits: []
    readonly property bool fileMode: query.trim().startsWith("~")
    readonly property string fileTerm: fileMode ? query.trim().slice(1).trim() : ""

    onFileTermChanged: {
        findProc.running = false
        if (fileTerm.length >= 2) fileDebounce.restart()
        else { fileDebounce.stop(); fileHits = [] }
    }

    Timer {
        id: fileDebounce
        interval: 300
        onTriggered: { findProc.acc = []; findProc.running = true }
    }

    Process {
        id: findProc
        property var acc: []
        // term is passed as $0, so no shell-quoting games; noisy trees pruned
        command: ["sh", "-c",
            'find "$HOME" \\( -name .cache -o -name .git -o -name node_modules ' +
            '-o -name .steam -o -name steamapps -o -name .dotfiles \\) -prune ' +
            '-o -iname "*$0*" -print 2>/dev/null | head -12', launcher.fileTerm]
        stdout: SplitParser { onRead: line => { if (line.trim() !== "") findProc.acc.push(line.trim()) } }
        onExited: launcher.fileHits = acc
    }

    // --- unit conversion ("10km to mi", "72f in c", "1.5gb to mb") ----------
    readonly property var unitDefs: ({
        km: [1000, "len"], m: [1, "len"], cm: [0.01, "len"], mm: [0.001, "len"],
        mi: [1609.344, "len"], yd: [0.9144, "len"], ft: [0.3048, "len"], "in": [0.0254, "len"],
        kg: [1, "mass"], g: [0.001, "mass"], t: [1000, "mass"],
        lb: [0.45359237, "mass"], oz: [0.028349523125, "mass"],
        l: [1, "vol"], ml: [0.001, "vol"], gal: [3.785411784, "vol"],
        b: [1, "data"], kb: [1e3, "data"], mb: [1e6, "data"], gb: [1e9, "data"], tb: [1e12, "data"],
        kib: [1024, "data"], mib: [1048576, "data"], gib: [1073741824, "data"],
        kmh: [0.2777778, "spd"], mph: [0.44704, "spd"], kn: [0.5144444, "spd"]
    })

    readonly property var convResult: {
        const m = query.trim().toLowerCase()
            .replace(/km\/h/g, "kmh").replace(/°/g, "")
            .match(/^([\d.,]+)\s*([a-z]+)\s+(?:to|in|=)\s+([a-z]+)$/);
        if (!m) return null;
        const v = parseFloat(m[1].replace(",", "."));
        if (!isFinite(v)) return null;
        const from = m[2], to = m[3];
        let out = null;
        const temps = ["c", "f", "k"];
        if (temps.includes(from) && temps.includes(to)) {
            const c = from === "c" ? v : from === "f" ? (v - 32) / 1.8 : v - 273.15;
            out = to === "c" ? c : to === "f" ? c * 1.8 + 32 : c + 273.15;
        } else {
            const f = unitDefs[from], t = unitDefs[to];
            if (!f || !t || f[1] !== t[1]) return null;
            out = v * f[0] / t[0];
        }
        const pretty = parseFloat(out.toPrecision(7));
        return { expr: m[1] + " " + m[2] + "  =  " + pretty + " " + m[3], value: String(pretty) };
    }

    // --- quicklinks (user bookmarks: quicklinks.json — url or cmd rows) -----
    // Same lazy-parse-into-a-mutated-member pattern as the emoji cache: never
    // ASSIGN a property from inside the results binding (binding loop).
    property var qlCache: ({})
    FileView {
        id: quicklinksFile
        path: "/home/wuhlheide/.config/quickshell/quicklinks.json"
        printErrors: false
    }
    function quicklinks() {
        if (qlCache.list === undefined) {
            try { qlCache.list = JSON.parse(quicklinksFile.text() || "[]"); }
            catch (e) { qlCache.list = []; }
        }
        return qlCache.list;
    }

    // --- script extensions (launcher-ext/*: executables emitting TSV rows) --
    // Run fresh on every launcher open (this component is lazy-loaded), so
    // extensions can surface live data. Contract in launcher-ext/README.md.
    property var extRows: []
    Process {
        id: extProc
        command: ["sh", "-c",
            "for f in /home/wuhlheide/.config/quickshell/launcher-ext/*; do " +
            "[ -x \"$f\" ] && \"$f\"; done 2>/dev/null"]
        property var acc: []
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t");
                if (p.length >= 3 && p[0] !== "" && p[2] !== "")
                    extProc.acc.push({ name: p[0], glyph: p[1] || "", cmd: p[2], keywords: p[3] || "" });
            }
        }
        onExited: { launcher.extRows = acc; acc = [] }
    }

    // --- web search ---------------------------------------------------------
    // "g rust traits" → Brave Search, "yt lofi" → YouTube, etc. Any other
    // query also gets a catch-all "Search web" row at the bottom of the list.
    readonly property var webPrefixes: ({
        "g":  ["Brave Search", "https://search.brave.com/search?q="],
        "yt": ["YouTube",      "https://www.youtube.com/results?search_query="],
        "aw": ["Arch Wiki",    "https://wiki.archlinux.org/index.php?search="],
        "gh": ["GitHub",       "https://github.com/search?q="]
    })

    // --- timer quick-add ("10m tea", "1h30m", "90s pasta") -------------------
    readonly property var timerResult: {
        const m = query.trim().match(
            /^(?:(\d+)h\s*)?(?:(\d+)m\s*)?(?:(\d+)s\s*)?(?:\s*(\S.*))?$/);
        if (!m) return null;
        const secs = (parseInt(m[1]) || 0) * 3600 + (parseInt(m[2]) || 0) * 60
                   + (parseInt(m[3]) || 0);
        if (secs <= 0) return null;
        const label = (m[4] || "").trim();
        // "10m to mi" is a unit conversion, not a timer
        if (/^(to|in|=)\s/.test(label)) return null;
        const dur = (m[1] ? m[1] + "h " : "") + (m[2] ? m[2] + "m " : "")
                  + (m[3] ? m[3] + "s" : "");
        return { secs: secs, label: label || "Timer",
                 name: "Start timer · " + dur.trim() + (label ? " — " + label : "") };
    }

    // --- inline calculator --------------------------------------------------
    // Query that looks like math ("22*38", "(4+3)/2", "2^10") → result row.
    // Charset is locked down hard so Function() can't reach anything scary.
    readonly property var calcResult: {
        const q = query.trim();
        if (q.length < 3) return null;
        if (!/^[0-9+\-*/(). eE]+$/.test(q)) return null;
        if (!/[0-9]/.test(q) || !/[+\-*/]/.test(q.slice(1))) return null;
        try {
            const v = Function('"use strict"; return (' + q + ')')();
            if (typeof v !== "number" || !isFinite(v)) return null;
            return { expr: q, value: String(Math.round(v * 1e10) / 1e10) };
        } catch (e) { return null; }
    }

    // fzf-style subsequence fallback: every query char appears in order in the
    // haystack ("frfx" → firefox, "sptfy" → spotify). Lowest tier by design —
    // it only rescues queries nothing else matched. Tighter, earlier matches
    // score higher (max 50, so always below the substring tiers). Queries
    // under 3 chars are excluded or single letters would match everything.
    function fuzzy(hay, q) {
        if (q.length < 3) return -1;
        let i = 0, start = -1, last = -1;
        for (let j = 0; j < hay.length && i < q.length; j++) {
            if (hay[j] === q[i]) { if (i === 0) start = j; last = j; i++; }
        }
        if (i < q.length) return -1;
        return Math.max(20, 50 - (last - start + 1 - q.length) * 4 - start * 2);
    }

    // Score a single entry against the (lowercased) query. -1 means "no match".
    // Higher tiers = stronger match, so exact/prefix beat buried substrings.
    function score(entry, q) {
        const name = (entry.name || "").toLowerCase();
        const generic = (entry.genericName || "").toLowerCase();
        const comment = (entry.comment || "").toLowerCase();
        const kw = (entry.keywords || []).join(" ").toLowerCase();
        const exec = (entry.execString || "").toLowerCase();

        if (name === q) return 1000;
        if (name.startsWith(q)) return 600;
        if (name.split(/\s+/).some(w => w.startsWith(q))) return 400;
        if (name.includes(q)) return 250;
        if (generic.includes(q) || kw.includes(q)) return 150;
        if (comment.includes(q) || exec.includes(q)) return 60;
        return fuzzy(name, q);
    }

    // Unified result list: every row is { kind: "app"|"action"|"calc", … }.
    // .values is a plain JS array (same as Hyprland.workspaces.values in the bar).
    readonly property var results: {
        const q = query.toLowerCase().trim();

        // dedicated modes take over the whole list
        if (fileMode)
            return fileHits.map(p => ({
                kind: "file", path: p, glyph: "\uf016",
                name: p.split("/").pop(),
                dir: p.slice(0, p.length - p.split("/").pop().length - 1)
                      .replace(/^\/home\/wuhlheide/, "~")
            }));
        if (q.startsWith(":"))
            return emojiHits(q.slice(1));

        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
        const items = [];

        // conversions/math win the top slot when the query parses
        if (convResult)
            items.push({ kind: "calc", name: convResult.expr,
                         glyph: "\uf1ec", value: convResult.value });
        else if (calcResult)
            items.push({ kind: "calc", name: calcResult.expr + "  =  " + calcResult.value,
                         glyph: "\uf1ec", value: calcResult.value });

        // timer quick-add ranks right under conversions/math
        if (!convResult && timerResult)
            items.push({ kind: "timer", name: timerResult.name, glyph: "",
                         secs: timerResult.secs, label: timerResult.label });

        // explicit search prefix ("g …", "yt …") pins its row to the top
        const qWords = q.split(/\s+/);
        const wp = webPrefixes[qWords[0]];
        const webTerm = wp && qWords.length > 1 ? qWords.slice(1).join(" ") : "";
        if (wp && webTerm !== "")
            items.push({ kind: "web", name: wp[0] + ": “" + webTerm + "”",
                         glyph: "", url: wp[1] + encodeURIComponent(webTerm) });

        if (q.length === 0) {
            // No query: most-used apps first, then alphabetical. (No actions —
            // they'd clutter the frecency list.)
            all.slice().sort((a, b) => {
                const fb = (freqMap[b.id] || 0) - (freqMap[a.id] || 0);
                return fb !== 0 ? fb : a.name.localeCompare(b.name);
            }).forEach(a => items.push({ kind: "app", entry: a, name: a.name }));
            return items;
        }

        // With a query: score apps and actions together (+frecency for apps).
        const scored = [];
        all.forEach(a => {
            // frecency only boosts MATCHES — added before the >=0 check it
            // would resurrect non-matching apps you merely launch often
            const base = score(a, q);
            if (base >= 0) scored.push({ kind: "app", entry: a, name: a.name,
                                         s: base + (freqMap[a.id] || 0) * 5 });
        });
        actions.forEach(a => {
            const n = a.name.toLowerCase();
            let s = -1;
            if (n === q) s = 700;
            else if (n.startsWith(q)) s = 450;
            else if (n.split(/\s+/).some(w => w.startsWith(q))) s = 320;
            else if (n.includes(q)) s = 180;
            else if (a.keywords.split(/\s+/).some(w => w.startsWith(q))) s = 120;
            else s = fuzzy(n, q);
            if (s >= 0) scored.push({ kind: "action", name: a.name, glyph: a.glyph, cmd: a.cmd, s: s });
        });
        // quicklinks + script-extension rows score like actions, nudged just
        // below them so built-ins win exact-name ties
        const nameScore = (name, keywords) => {
            const n = name.toLowerCase();
            if (n === q) return 700;
            if (n.startsWith(q)) return 450;
            if (n.split(/\s+/).some(w => w.startsWith(q))) return 320;
            if (n.includes(q)) return 180;
            if ((keywords || "").split(/\s+/).some(w => w.startsWith(q))) return 120;
            return fuzzy(n, q);
        };
        quicklinks().forEach(l => {
            const s = nameScore(l.name, l.keywords);
            if (s >= 0) scored.push({ kind: "link", name: l.name, glyph: l.glyph || "",
                                      url: l.url ?? "", cmd: l.cmd ?? "", s: s - 20 });
        });
        extRows.forEach(x => {
            const s = nameScore(x.name, x.keywords);
            if (s >= 0) scored.push({ kind: "ext", name: x.name, glyph: x.glyph || "",
                                      cmd: x.cmd, s: s - 10 });
        });
        // open windows rank alongside apps; Enter focuses instead of launching
        ToplevelManager.toplevels.values.forEach(w => {
            const t = (w.title || "").toLowerCase(), a = (w.appId || "").toLowerCase();
            let s = -1;
            if (a.startsWith(q) || t.startsWith(q)) s = 500;
            else if (a.includes(q)) s = 260;
            else if (t.includes(q)) s = 200;
            else s = Math.max(fuzzy(a, q), fuzzy(t, q));
            if (s >= 0) scored.push({ kind: "window", name: w.title || w.appId,
                                      appId: w.appId, win: w, glyph: "", s: s });
        });
        scored.sort((a, b) => (b.s - a.s) || a.name.localeCompare(b.name));

        const out = items.concat(scored);
        // catch-all web search at the bottom (unless a prefix already made one)
        if (!wp && q.length >= 3)
            out.push({ kind: "web", name: "Search web for “" + query.trim() + "”",
                       glyph: "", url: webPrefixes["g"][1] + encodeURIComponent(query.trim()) });
        return out;
    }

    property int selected: 0
    onResultsChanged: setSelected(0)

    // Clamp the selection AND scroll the list so it stays visible.
    function setSelected(i) {
        selected = Math.max(0, Math.min(i, results.length - 1));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function run(item) {
        if (!item)
            return;
        if (item.kind === "calc") {
            // value is digits/./-/e only, so plain single-quoting is safe
            Quickshell.execDetached(["sh", "-c", "printf %s '" + item.value + "' | wl-copy"]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "action" || item.kind === "ext") {
            Quickshell.execDetached(["sh", "-c", item.cmd]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "link") {
            if (item.url !== "") Quickshell.execDetached(["xdg-open", item.url]);
            else Quickshell.execDetached(["sh", "-c", item.cmd]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "emoji") {
            Quickshell.execDetached(["sh", "-c", 'printf %s "$0" | wl-copy', item.char]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "file") {
            Quickshell.execDetached(["xdg-open", item.path]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "web") {
            Quickshell.execDetached(["xdg-open", item.url]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "timer") {
            Quickshell.execDetached(["qs", "ipc", "call", "timers", "addsecs",
                                     String(item.secs), item.label]);
            launcher.dismissed();
            return;
        }
        if (item.kind === "window") {
            item.win.activate();
            launcher.dismissed();
            return;
        }
        // Bump frecency and persist before launching.
        freqMap[item.entry.id] = (freqMap[item.entry.id] || 0) + 1;
        freqFile.setText(JSON.stringify(freqMap));
        item.entry.execute();      // launches the .desktop entry
        launcher.dismissed();
    }

    Component.onCompleted: {
        input.forceActiveFocus();
        try { freqMap = JSON.parse(freqFile.text() || "{}"); }
        catch (e) { freqMap = ({}); }
        extProc.acc = [];
        extProc.running = true;   // gather extension rows for this open
    }

    // Dim layer; clicking it (outside the card) closes the launcher.
    Rectangle {
        anchors.fill: parent
        color: Colors.shadow
        opacity: 0.35
        MouseArea {
            anchors.fill: parent
            onClicked: launcher.dismissed()
        }
    }

    // The launcher card.
    Rectangle {
        id: card
        width: 480
        height: 440
        anchors.centerIn: parent
        radius: 18
        color: Colors.surface_container
        border.color: Colors.outline_variant
        border.width: 1

        // Swallow clicks so they don't fall through to the dim layer.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Search field
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 12
                color: Colors.surface_container_high

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.margins: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    color: Colors.on_surface
                    font { family: "Adwaita Sans"; pixelSize: 16 }
                    onTextChanged: launcher.query = text

                    // Placeholder
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search\u2026  (: emoji, ~ files, g/yt web, 22*38)"
                        color: Colors.outline
                        font { family: "Adwaita Sans"; pixelSize: 16 }
                        visible: input.text.length === 0
                    }

                    // Keyboard navigation
                    Keys.onEscapePressed: launcher.dismissed()
                    Keys.onDownPressed:  launcher.setSelected(launcher.selected + 1)
                    Keys.onUpPressed:    launcher.setSelected(launcher.selected - 1)
                    Keys.onReturnPressed: launcher.run(launcher.results[launcher.selected])
                    Keys.onEnterPressed:  launcher.run(launcher.results[launcher.selected])
                }
            }

            // Results
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: launcher.results
                currentIndex: launcher.selected
                spacing: 4

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: list.width
                    height: 48
                    radius: 10
                    color: index === launcher.selected ? Colors.primary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        // Icon with a graceful fallback. iconPath(name, true)
                        // returns "" when the icon can't be resolved, so we draw
                        // a letter-avatar instead of a broken-image placeholder.
                        // Actions/calc rows get a glyph chip instead of an icon.
                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28

                            property string src: modelData.kind === "app" && modelData.entry.icon
                                ? Quickshell.iconPath(modelData.entry.icon, true)
                                : modelData.kind === "window" && modelData.appId
                                ? Quickshell.iconPath(modelData.appId.toLowerCase(), true)
                                : ""

                            Image {
                                id: ico
                                anchors.fill: parent
                                asynchronous: true
                                sourceSize.width: 28
                                sourceSize.height: 28
                                source: parent.src
                                visible: parent.src !== "" && status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: !ico.visible
                                radius: 7
                                color: Colors.secondary_container
                                Text {
                                    visible: modelData.kind === "app"
                                    anchors.centerIn: parent
                                    text: (modelData.name || "?").charAt(0).toUpperCase()
                                    color: Colors.on_surface
                                    font { family: "Adwaita Sans"; pixelSize: 15; bold: true }
                                }
                                Text {
                                    visible: modelData.kind !== "app" && modelData.kind !== "emoji"
                                    anchors.centerIn: parent
                                    text: modelData.glyph || ""
                                    color: Colors.on_surface
                                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                                }
                                Text {
                                    visible: modelData.kind === "emoji"
                                    anchors.centerIn: parent
                                    text: modelData.char || ""
                                    font.pixelSize: 16
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: index === launcher.selected ? Colors.on_primary : Colors.on_surface
                            font { family: "Adwaita Sans"; pixelSize: 15 }
                        }

                        // faint kind hint on the right for non-app rows
                        Text {
                            visible: modelData.kind !== "app"
                            text: modelData.kind === "action" ? "action"
                                : modelData.kind === "file" ? modelData.dir
                                : modelData.kind === "window" ? "window · " + (modelData.appId || "")
                                : modelData.kind === "web" ? "web"
                                : modelData.kind === "link" ? "link"
                                : modelData.kind === "ext" ? "ext"
                                : modelData.kind === "timer" ? "timer"
                                : "copy"
                            elide: Text.ElideLeft
                            Layout.maximumWidth: 170
                            color: index === launcher.selected ? Colors.on_primary : Colors.outline
                            opacity: 0.8
                            font { family: "Adwaita Sans"; pixelSize: 11 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.selected = index
                        onClicked: launcher.run(modelData)
                    }
                }
            }
        }
    }
}

