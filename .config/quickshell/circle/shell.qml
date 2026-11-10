pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Circle to Search for Caelestia. Runs as its own quickshell config next to
// the shell (`qs -c circle -d`) and is opened over IPC:
//   qs -c circle ipc call circle toggle
// (Not a GlobalShortcut: quickshell's GlobalShortcut segfaults in its
// destructor on shutdown, which pops a crash dialog on every logout.)
ShellRoot {
    id: root

    // Settings (model, translate language, model list): ~/.config/circle/settings.json

    property ShellScreen target

    function open(): void {
        if (loader.active)
            return;
        const name = Hyprland.focusedMonitor?.name;
        target = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
        loader.active = true;
    }

    function close(): void {
        loader.active = false;
    }

    IpcHandler {
        target: "circle"

        function toggle(): void {
            if (loader.active)
                loader.item?.content.dismiss();
            else
                root.open();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        // Scripting / testing: select a region (screen-local px) and ask.
        function select(x: real, y: real, w: real, h: real): void {
            loader.item?.content.select(x, y, w, h);
        }

        // Switch model by id from ~/.config/circle/settings.json, e.g. "local".
        function model(id: string): void {
            Settings.choose(id);
        }

        function menu(): void {
            if (loader.item)
                loader.item.content.toggleMenu();
        }

        function ask(text: string): void {
            loader.item?.content.ask(text, text);
        }
    }

    LazyLoader {
        id: loader

        PanelWindow {
            property alias content: overlay

            screen: root.target
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "caelestia-circle"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Overlay {
                id: overlay

                anchors.fill: parent
                screen: root.target
                onClosed: root.close()
            }
        }
    }
}
