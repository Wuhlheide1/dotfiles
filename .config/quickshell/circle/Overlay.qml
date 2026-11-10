pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia

// The frozen screen, the lasso, the search pill and the answer card.
Item {
    id: root

    required property ShellScreen screen
    signal closed

    // Selection, in screen-local pixels. hasSel false = the whole screen.
    property bool hasSel
    property real selX
    property real selY
    property real selW
    property real selH
    property bool animateSel

    property bool shown                // drives the enter/exit animations
    property string panel              // "", "text" or "ai"

    property string image              // saved crop of the current selection
    property bool saving
    property int serial
    property var waiting: []
    property string sentImage          // last image Claude has seen

    property bool hasTesseract
    property string ocrText
    property bool ocrDone
    property bool showTextWhenDone
    property var clients: []
    property var avail: ({})           // backend.py check: what's set up

    function availability(m: var): string {
        const a = avail[m.provider];
        if (!a)
            return "";
        if (m.provider === "local") {
            if (!a.ok)
                return "Ollama isn't running";
            if (!a.models.some(n => n === m.model || n === m.model + ":latest"))
                return `Not downloaded — ollama pull ${m.model}`;
            return "";
        }
        if (!a.ok)
            return {
                antigravity: "agy not found — install antigravity-cli",
                gemini: "Needs an API key (see README)"
            }[m.provider] ?? "claude CLI not found";
        return "";
    }

    readonly property string script: Quickshell.shellPath("circle.sh")

    // Animation clock for the shaders, in seconds. Only ticks while open.
    property real clock
    property real bloom        // edge glow: flares on open, settles to a hint

    NumberAnimation on clock {
        from: 0
        to: 100000
        duration: 100000000
        loops: Animation.Infinite
    }

    SequentialAnimation {
        id: bloomAnim

        NumberAnimation { target: root; property: "bloom"; to: 0.55; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "bloom"; to: 0.14; duration: 1600; easing.type: Easing.InOutSine }
    }

    function run(args: list<string>): void {
        Quickshell.execDetached([script, ...args]);
    }

    // ---- selection & capture -------------------------------------------

    // Set the box without capturing (used live while dragging).
    function setBox(x: real, y: real, w: real, h: real): void {
        const x0 = Math.max(0, Math.floor(x));
        const y0 = Math.max(0, Math.floor(y));
        selX = x0;
        selY = y0;
        selW = Math.min(width, Math.ceil(x + w)) - x0;
        selH = Math.min(height, Math.ceil(y + h)) - y0;
        hasSel = true;
    }

    // Final selection: capture it (and OCR it) in the background.
    function commit(): void {
        scanAnim.restart();
        resetCapture();
        ensureImage();
        ai.warm();
    }

    function select(x: real, y: real, w: real, h: real): void {
        animateSel = hasSel;
        setBox(x, y, w, h);
        commit();
    }

    function clearSelection(): void {
        if (!hasSel)
            return;
        hasSel = false;
        resetCapture();
    }

    function resetCapture(): void {
        serial++;
        image = "";
        saving = false;
        ocrText = "";
        ocrDone = false;
        if (panel === "text")
            panel = "";
    }

    function ensureImage(): void {
        if (image || saving)
            return;
        saving = true;
        const mine = serial;
        const rect = hasSel ? Qt.rect(selX, selY, selW, selH) : Qt.rect(0, 0, width, height);
        const file = `/tmp/circle-${Quickshell.processId}-${Date.now()}.png`;
        CUtils.saveItem(shot, Qt.resolvedUrl(file), rect, path => {
            if (mine !== root.serial)
                return;
            root.saving = false;
            root.image = path;
            if (root.hasTesseract) {
                ocr.command = [root.script, "ocr", path];
                ocr.running = true;
            }
            const cbs = root.waiting;
            root.waiting = [];
            for (const cb of cbs)
                cb(path);
        });
    }

    function withImage(cb: var): void {
        if (image)
            return cb(image);
        waiting.push(cb);
        ensureImage();
    }

    function clientAt(x: real, y: real): var {
        return clients.find(c => x >= c.x && y >= c.y && x <= c.x + c.w && y <= c.y + c.h);
    }

    // ---- actions --------------------------------------------------------

    function ask(label: string, prompt: string): void {
        panel = "ai";
        withImage(path => {
            ai.ask(label, prompt, path !== root.sentImage ? path : "");
            root.sentImage = path;
        });
    }

    function submit(): void {
        const q = input.text.trim();
        input.text = "";
        if (q)
            ask(q, q);
        else
            lens();
    }

    function lens(): void {
        withImage(path => {
            root.run(["lens", path]);
            root.dismiss();
        });
    }

    // The full Gemini app (gemini.desktop) gets the selection as a new chat and
    // asks `text` there; with no text it just waits with the image attached.
    function toGemini(text: string): void {
        withImage(path => {
            root.run(["gemini", path, text]);
            root.dismiss();
        });
    }

    // Shift+Enter: ask in the Gemini app instead of the card.
    function handoff(): void {
        const q = input.text.trim();
        input.text = "";
        toGemini(q);
    }

    function continueInGemini(): void {
        toGemini(ai.turns.count ? ai.turns.get(ai.turns.count - 1).p : "");
    }

    // Resume this conversation in the Antigravity CLI in a terminal, where it
    // may run commands and edit files (asking first) instead of only answering.
    function continueInAntigravity(): void {
        root.run(["antigravity", ai.conversation, Settings.current.model]);
        root.dismiss();
    }

    function showText(): void {
        if (panel === "text") {
            panel = "";
            return;
        }
        if (!hasTesseract) {
            ask("Text", "Transcribe all text in the image exactly as written, keeping line breaks. Output only the text — no code fence, no commentary.");
            return;
        }
        showTextWhenDone = true;
        withImage(() => {
            if (root.ocrDone)
                root.openText();
        });
    }

    function openText(): void {
        showTextWhenDone = false;
        panel = "text";
        if (ocrText)
            copyText(ocrText);
    }

    function translate(): void {
        ask("Translate", `Translate the text in this image into ${Settings.translateTo}. Output only the translation. If it is already ${Settings.translateTo}, say so in one short line.`);
    }

    function copyImage(): void {
        withImage(path => {
            root.run(["copy-image", path]);
            Quickshell.execDetached(["notify-send", "-a", "caelestia-cli", "-i", path, "Circle to Search", "Selection copied to clipboard"]);
            root.dismiss();
        });
    }

    function copyText(text: string): void {
        copier.text = text;
        copier.running = true;
        card.flash();
    }

    // Claude's Markdown -> Qt StyledText. Qt's own Markdown path ignores
    // color/linkColor under quickshell, which left answers dark grey.
    function styled(md: string): string {
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const inline = t => esc(t)
            .replace(/`([^`]+)`/g, `<font face="${Theme.mono}">$1</font>`)
            .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
            .replace(/(^|[^*\w])[*_]([^*_\s][^*_]*)[*_](?![\w*])/g, "$1<i>$2</i>")
            .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, `<a href="$2" style="color:${Theme.primary}; text-decoration:none">$1</a>`);
        const out = [];
        let code = false;
        for (const line of md.split("\n")) {
            if (/^\s*```/.test(line)) {
                code = !code;
                continue;
            }
            let m;
            if (code)
                out.push(`<font face="${Theme.mono}">${esc(line).replace(/ /g, "&nbsp;")}</font>`);
            else if ((m = line.match(/^#{1,6}\s+(.*)/)))
                out.push(`<b>${inline(m[1])}</b>`);
            else if ((m = line.match(/^(\s*)[-*+]\s+(.*)/)))
                out.push(`${"&nbsp;".repeat(2 + m[1].length)}•&nbsp;&nbsp;${inline(m[2])}`);
            else if ((m = line.match(/^(\s*)(\d+)[.)]\s+(.*)/)))
                out.push(`${"&nbsp;".repeat(2 + m[1].length)}${m[2]}.&nbsp;&nbsp;${inline(m[3])}`);
            else
                out.push(inline(line));
        }
        return out.join("<br>").replace(/(<br>){3,}/g, "<br><br>");
    }

    function toggleMenu(): void {
        menu.open = !menu.open;
    }

    function dismiss(): void {
        if (!closeAnim.running)
            closeAnim.start();
    }

    opacity: 0
    focus: true
    Keys.onEscapePressed: dismiss()

    Component.onCompleted: {
        Quickshell.execDetached(["sh", "-c", "find /tmp -maxdepth 1 -name 'circle-*.png' -mmin +30 -delete; mkdir -p \"${XDG_RUNTIME_DIR:-/tmp}/circle\""]);
        input.forceActiveFocus();
        warm();
    }

    SequentialAnimation {
        id: closeAnim

        PropertyAction { target: root; property: "shown"; value: false }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 120 }
        ScriptAction { script: root.closed() }
    }

    // ---- processes ------------------------------------------------------

    Ai {
        id: ai

        engine: Settings.current
        onEngineChanged: {
            root.sentImage = "";    // a new backend hasn't seen it
            root.warm();
        }
    }

    // Local models unload after 10 idle minutes; start loading on open so the
    // first answer doesn't pay the load time.
    function warm(): void {
        if (Settings.current.provider === "local")
            Quickshell.execDetached(["python3", "-I", Quickshell.shellPath("backend.py"), "warm", Settings.current.model]);
    }

    Process {
        running: true
        command: ["python3", "-I", Quickshell.shellPath("backend.py"), "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.avail = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v tesseract"]
        onExited: code => root.hasTesseract = code === 0
    }

    Process {
        running: true
        command: [root.script, "clients", root.screen.name]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.clients = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: ocr

        stdout: StdioCollector {
            onStreamFinished: {
                root.ocrText = text.trim();
                root.ocrDone = true;
                if (root.showTextWhenDone)
                    root.openText();
            }
        }
    }

    Process {
        id: copier

        property string text

        command: [root.script, "copy-text"]
        stdinEnabled: true
        onStarted: {
            write(text);
            stdinEnabled = false;
        }
        onExited: stdinEnabled = true
    }

    // ---- the frozen screen ----------------------------------------------

    ScreencopyView {
        id: shot

        anchors.fill: parent
        captureSource: root.screen
        live: false

        onHasContentChanged: {
            if (hasContent) {
                root.opacity = 1;   // identical to the real screen, so no fade
                root.shown = true;
                bloomAnim.start();
            }
        }
    }

    // Dim everything outside the selection: an even-odd path with a hole.
    Item {
        id: hole

        x: root.selX
        y: root.selY
        width: root.hasSel ? root.selW : 0
        height: root.hasSel ? root.selH : 0

        Behavior on x { enabled: root.animateSel; Anim {} }
        Behavior on y { enabled: root.animateSel; Anim {} }
        Behavior on width { enabled: root.animateSel; Anim {} }
        Behavior on height { enabled: root.animateSel; Anim {} }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.shown ? 1 : 0

        Behavior on opacity { Anim {} }

        ShapePath {
            fillColor: Qt.alpha(Theme.scrim, root.hasSel ? 0.55 : 0.22)
            fillRule: ShapePath.OddEvenFill
            strokeColor: "transparent"
            strokeWidth: -1

            Behavior on fillColor { ColorAnimation { duration: 300 } }

            PathRectangle {
                width: root.width
                height: root.height
            }
            PathRectangle {
                x: hole.x
                y: hole.y
                width: hole.width
                height: hole.height
                radius: Math.min(20, hole.width / 2, hole.height / 2)
            }
        }
    }

    // Edge bloom, selection glow ring and scan shimmer — one shader pass.
    ShaderEffect {
        id: aura

        property real time: root.clock
        property real edge: root.shown ? Math.max(root.bloom, busy * 0.4) : 0
        property vector2d res: Qt.vector2d(width, height)
        property vector4d sel: Qt.vector4d(hole.x - 2, hole.y - 2, hole.width + 4, hole.height + 4)
        property real selOn: root.hasSel && root.shown ? 1 : 0
        property real radius: 22
        property real scan
        property real busy: ai.busy ? 1 : 0
        property color c1: Theme.accent1
        property color c2: Theme.accent2
        property color c3: Theme.accent3

        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/aura.frag.qsb")

        Behavior on selOn { NumberAnimation { duration: 350 } }
        Behavior on busy { NumberAnimation { duration: 1200; easing.type: Easing.InOutSine } }

        NumberAnimation on scan {
            id: scanAnim

            running: false
            from: 0
            to: 1
            duration: 1100
            easing.type: Easing.InOutQuad
        }
    }

    // ---- the lasso ------------------------------------------------------

    MouseArea {
        id: canvas

        property real ox
        property real oy
        property bool dragging

        anchors.fill: parent
        cursorShape: Qt.CrossCursor

        onPressed: event => {
            ox = event.x;
            oy = event.y;
            dragging = false;
        }

        onPositionChanged: event => {
            if (!dragging) {
                if (Math.abs(event.x - ox) < 6 && Math.abs(event.y - oy) < 6)
                    return;
                dragging = true;
                root.animateSel = false;    // the box follows the cursor 1:1
            }
            root.setBox(Math.min(ox, event.x), Math.min(oy, event.y), Math.abs(event.x - ox), Math.abs(event.y - oy));
        }

        onReleased: event => {
            if (dragging) {
                dragging = false;
                if (root.selW < 8 || root.selH < 8)
                    root.clearSelection();
                else
                    root.commit();
            } else {
                // A click: take the window under it, or go back to the whole screen.
                const c = root.clientAt(event.x, event.y);
                if (c)
                    root.select(c.x, c.y, c.w, c.h);
                else
                    root.clearSelection();
            }
            input.forceActiveFocus();
        }
    }

    // ---- answer card ----------------------------------------------------

    Rectangle {
        id: card

        property bool copied

        function flash(): void {
            copied = true;
            copiedTimer.restart();
        }

        anchors.horizontalCenter: bar.horizontalCenter
        anchors.bottom: bar.top
        anchors.bottomMargin: 12
        width: bar.width
        height: Math.min(header.height + body.contentHeight + 36, root.height - bar.height - 160)
        radius: 24
        color: Theme.surface
        clip: true

        visible: opacity > 0
        opacity: root.shown && root.panel ? 1 : 0
        scale: root.shown && root.panel ? 1 : 0.96
        transformOrigin: Item.Bottom

        Behavior on opacity { Anim {} }
        Behavior on scale { Anim {} }
        Behavior on height { Anim { duration: 250 } }

        Timer {
            id: copiedTimer

            interval: 1400
            onTriggered: card.copied = false
        }

        // swallow clicks so they don't start a new lasso
        MouseArea {
            anchors.fill: parent
        }

        RowLayout {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.leftMargin: 20
            anchors.rightMargin: 10

            Text {
                Layout.fillWidth: true
                text: card.copied ? "Copied" : root.panel === "text" ? "Text" : Settings.current.label
                color: card.copied ? Theme.primary : Theme.textVariant
                font.family: Theme.sans
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            // continue in the Gemini app
            IconButton {
                visible: root.panel === "ai" && ai.turns.count > 0
                icon: "open_in_new"
                implicitWidth: 34
                implicitHeight: 34
                onClicked: root.continueInGemini()
            }

            // continue in Antigravity (only when the answer came through agy)
            IconButton {
                visible: root.panel === "ai" && ai.conversation !== "" && !ai.busy
                icon: "terminal"
                implicitWidth: 34
                implicitHeight: 34
                onClicked: root.continueInAntigravity()
            }

            IconButton {
                icon: "content_copy"
                implicitWidth: 34
                implicitHeight: 34
                onClicked: {
                    if (root.panel === "text")
                        root.copyText(root.ocrText);
                    else if (ai.turns.count)
                        root.copyText(ai.turns.get(ai.turns.count - 1).a);
                }
            }

            IconButton {
                icon: "close"
                implicitWidth: 34
                implicitHeight: 34
                onClicked: root.panel = ""
            }
        }

        Flickable {
            id: body

            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            anchors.topMargin: 4
            contentHeight: root.panel === "text" ? textView.implicitHeight : turnsView.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // follow the stream while Claude is writing
            onContentHeightChanged: {
                if (ai.busy && contentHeight > height)
                    contentY = contentHeight - height;
            }

            TextEdit {
                id: textView

                visible: root.panel === "text"
                width: body.width
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                text: root.ocrText || "No text found in the selection."
                color: root.ocrText ? Theme.text : Theme.textVariant
                selectionColor: Theme.primary
                selectedTextColor: Theme.textOnPrimary
                font.family: Theme.sans
                font.pixelSize: 15
            }

            Column {
                id: turnsView

                visible: root.panel === "ai"
                width: body.width
                spacing: 20

                Repeater {
                    model: ai.turns

                    Column {
                        id: turn

                        required property string q
                        required property string a
                        required property string status
                        required property bool failed

                        width: turnsView.width
                        spacing: 6

                        Text {
                            width: parent.width
                            text: turn.q
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            color: Theme.primary
                            font.family: Theme.sans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        Text {
                            visible: turn.status !== ""
                            text: turn.status + "…"
                            color: "white"
                            font.family: Theme.sans
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            layer.enabled: visible
                            layer.effect: Tint {
                                time: root.clock
                                period: 320
                            }
                        }

                        // selectable: drag to select, Ctrl+C to copy part of it
                        TextEdit {
                            visible: turn.a !== ""
                            width: parent.width
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.RichText
                            text: root.styled(turn.a)
                            color: turn.failed ? Theme.error : Theme.text
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.textOnPrimary
                            font.family: Theme.sans
                            font.pixelSize: 15
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            Keys.onEscapePressed: root.dismiss()

                            HoverHandler {
                                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- search pill ----------------------------------------------------

    // closes the model menu on any click outside it
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onPressed: menu.open = false
    }

    Rectangle {
        id: bar

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.shown ? 48 : 8
        width: Math.min(720, root.width - 64)
        height: 56
        radius: height / 2
        color: Theme.surface
        opacity: root.shown ? 1 : 0

        Behavior on anchors.bottomMargin { Anim {} }
        Behavior on opacity { Anim {} }

        // model menu, opens upward from the chip
        Rectangle {
            id: menu

            property bool open

            anchors.bottom: parent.top
            anchors.bottomMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 4
            width: 290
            height: menuCol.implicitHeight + 12
            radius: 20
            color: Theme.surface
            z: 10

            visible: opacity > 0
            opacity: open ? 1 : 0
            scale: open ? 1 : 0.95
            transformOrigin: Item.BottomRight

            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { Anim { duration: 250 } }

            Column {
                id: menuCol

                anchors.fill: parent
                anchors.margins: 6

                Repeater {
                    model: Settings.models

                    Item {
                        id: row

                        required property var modelData
                        readonly property bool selected: modelData.id === Settings.current.id
                        readonly property string problem: root.availability(modelData)

                        width: menuCol.width
                        height: 50

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: row.selected ? Theme.primary : Theme.text
                            opacity: row.selected ? 0.14 : rowArea.containsMouse ? 0.06 : 0
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.right: check.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: row.modelData.label
                                color: row.selected ? Theme.primary : Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.problem || row.modelData.note
                                color: row.problem ? Theme.error : Theme.textVariant
                                opacity: row.problem ? 0.85 : 1
                                font.family: Theme.sans
                                font.pixelSize: 12
                            }
                        }

                        Text {
                            id: check

                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "check"
                            visible: row.selected
                            color: Theme.primary
                            font.family: Theme.icons
                            font.pixelSize: 20
                        }

                        MouseArea {
                            id: rowArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Settings.choose(row.modelData.id);
                                menu.open = false;
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // flowing gradient ring while Claude is working
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            z: -1
            radius: parent.radius + 2
            color: "white"
            opacity: ai.busy ? 0.75 : 0
            visible: opacity > 0
            layer.enabled: visible
            layer.effect: Tint {
                time: root.clock * 0.5
                period: 700
            }

            Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutSine } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 8
            spacing: 2

            Text {
                id: sparkle

                text: "auto_awesome"
                color: "white"
                font.family: Theme.icons
                font.pixelSize: 22
                font.variableAxes: ({ FILL: 1 })
                layer.enabled: true
                layer.effect: Tint {
                    time: root.clock * 0.5
                    period: 40
                }

                SequentialAnimation on scale {
                    running: ai.busy
                    loops: Animation.Infinite
                    onStopped: sparkle.scale = 1
                    NumberAnimation { to: 1.08; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 10

                TextInput {
                    id: input

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.textOnPrimary
                    selectByMouse: true
                    clip: true
                    font.family: Theme.sans
                    font.pixelSize: 16

                    // Enter: answer here. Shift+Enter: ask in the Gemini app.
                    Keys.onReturnPressed: event => event.modifiers & Qt.ShiftModifier ? root.handoff() : root.submit()
                    Keys.onEnterPressed: event => event.modifiers & Qt.ShiftModifier ? root.handoff() : root.submit()
                    Keys.onEscapePressed: menu.open ? menu.open = false : root.dismiss()
                    onTextChanged: {
                        if (text)
                            ai.warm();
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text && !input.preeditText
                    text: root.hasSel ? (ai.turns.count ? "Ask a follow-up" : "Ask about your selection") : "Drag a box, click a window, or ask about the screen"
                    color: Theme.textVariant
                    elide: Text.ElideRight
                    width: parent.width
                    font.family: Theme.sans
                    font.pixelSize: 16
                }
            }

            // model picker chip
            Item {
                id: chip

                implicitWidth: chipRow.implicitWidth + 20
                implicitHeight: 32
                Layout.rightMargin: 4

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.text
                    opacity: menu.open ? 0.12 : chipArea.containsMouse ? 0.08 : 0.04

                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                Row {
                    id: chipRow

                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Settings.current.label
                        color: root.availability(Settings.current) ? Theme.error : Theme.textVariant
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "expand_more"
                        color: Theme.textVariant
                        font.family: Theme.icons
                        font.pixelSize: 18
                        rotation: menu.open ? 180 : 0

                        Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    id: chipArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.open = !menu.open
                }
            }

            IconButton {
                icon: "image_search"
                onClicked: root.lens()
            }

            IconButton {
                icon: "text_fields"
                active: root.panel === "text"
                onClicked: root.showText()
            }

            IconButton {
                icon: "translate"
                onClicked: root.translate()
            }

            IconButton {
                icon: "content_copy"
                onClicked: root.copyImage()
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 400
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.emphasized
    }
}
