import QtQuick
import Quickshell
import Quickshell.Io

// One conversation per overlay session, through backend.py (Claude, Gemini or
// the local model — see Settings). Turns are a ListModel so the streaming
// answer updates in place instead of rebuilding the card on every token.
Item {
    id: root

    required property var engine        // a Settings.models entry

    property bool busy
    readonly property alias turns: turns
    property var pending: []
    property string conversation    // agy conversation id (antigravity only)

    // agy takes a few seconds to start, so the overlay starts it as soon as
    // the user selects or types instead of on Enter.
    function warm(): void {
        if (engine.provider === "antigravity" && !proc.running)
            proc.running = true;
    }

    function ask(label: string, prompt: string, image: string): void {
        turns.append({ q: label, p: prompt, a: "", status: "Thinking", failed: false, by: engine.label });
        busy = true;
        const line = JSON.stringify({ text: prompt, image: image || null }) + "\n";
        if (proc.running && proc.processId)
            proc.write(line);
        else {
            pending.push(line);
            proc.running = true;
        }
    }

    // Switching model starts a fresh backend; the old answers stay on screen.
    onEngineChanged: {
        proc.running = false;
        busy = false;
        conversation = "";
    }

    function last(): int {
        return turns.count - 1;
    }

    function handle(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (ev.t === "conv") {
            conversation = ev.v;
            return;
        }
        const i = last();
        if (i < 0)
            return;

        switch (ev.t) {
        case "status":
            turns.setProperty(i, "status", ev.v);
            break;
        case "reset":
            turns.setProperty(i, "a", "");
            break;
        case "delta":
            turns.setProperty(i, "status", "");
            turns.setProperty(i, "a", turns.get(i).a + ev.v);
            break;
        case "error":
            turns.setProperty(i, "failed", true);
            turns.setProperty(i, "a", (turns.get(i).a ? turns.get(i).a + "\n\n" : "") + ev.v);
            break;
        case "done":
            turns.setProperty(i, "status", "");
            busy = false;
            break;
        }
    }

    ListModel {
        id: turns
    }

    Process {
        id: proc

        command: ["python3", "-I", Quickshell.shellPath("backend.py"), root.engine.provider, root.engine.model]
        workingDirectory: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/circle`
        stdinEnabled: true

        onStarted: {
            for (const line of root.pending)
                write(line);
            root.pending = [];
        }

        onExited: code => {
            const i = root.last();
            if (root.busy && i >= 0) {
                turns.setProperty(i, "failed", true);
                turns.setProperty(i, "status", "");
                turns.setProperty(i, "a", errors.last || `The ${root.engine.label} backend exited (${code}).`);
            }
            root.busy = false;
        }

        stdout: SplitParser {
            onRead: data => root.handle(data)
        }

        stderr: SplitParser {
            id: errors

            property string last

            onRead: data => {
                if (data.trim())
                    last = data.trim();
            }
        }
    }
}
