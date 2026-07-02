import Quickshell
import QtQuick

// Screenshot tool: thin QML wrapper that fires the grim/slurp capture script.
// Driven through shell.qml's `screenshot` IpcHandler (Print / Shift+Print /
// Super+Print keybinds). The script handles save + clipboard + notify; the
// notification lands in our own NotificationServer, so it shows in the center.
//
// Uses Quickshell.execDetached (fire-and-forget) rather than a reused Process:
// a shared Process only re-runs when its `command` actually changes, so firing
// the same mode (e.g. "full") twice would silently no-op the second time.
Item {
    id: root

    // Single-user box: hard path, same convention as the rest of this config.
    readonly property string script: "/home/wuhlheide/.config/quickshell/scripts/screenshot.sh"

    // mode: "region" | "full" | "window"
    function shoot(mode: string): void {
        Quickshell.execDetached(["bash", root.script, mode]);
    }
}
