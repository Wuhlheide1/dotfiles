import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: root
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 40
    color: Colors.background

    // --- Theme ---
    // All colors now live in the Colors singleton (Colors.qml), which matugen
    // regenerates from your wallpaper. Reference them as Colors.primary etc.
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14

    // --- Utilities & State ---
    NumberToKanji { id: kanji }

	
    LazyLoader {
        id: launcherLoader
        // built only when active; destroyed when inactive
        Launcher { onDismissed: launcherLoader.active = false }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcherLoader.active = !launcherLoader.active }
        function open():   void { launcherLoader.active = true }
    }

    LazyLoader {
        id: wallpaperLoader
        WallpaperPicker { onDismissed: wallpaperLoader.active = false }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { wallpaperLoader.active = !wallpaperLoader.active }
        function open():   void { wallpaperLoader.active = true }
    }

    LazyLoader {
        id: clipboardLoader
        ClipboardPicker { onDismissed: clipboardLoader.active = false }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { clipboardLoader.active = !clipboardLoader.active }
        function open():   void { clipboardLoader.active = true }
    }

    // Keybind cheatsheet (SUPER+K) — generated live from keybinds.lua.
    LazyLoader {
        id: cheatsheetLoader
        Cheatsheet { onDismissed: cheatsheetLoader.active = false }
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { cheatsheetLoader.active = !cheatsheetLoader.active }
        function open():   void { cheatsheetLoader.active = true }
    }

    // Brightness (software gamma via hyprsunset) — driven by the XF86MonBrightness keys.
    IpcHandler {
        target: "brightness"
        function up():   void { Brightness.up() }
        function down(): void { Brightness.down() }
        function set(v: int): void { Brightness.set(v) }
    }

    // Screenshots (grim/slurp) — driven by the Print / Shift+Print / Super+Print keys.
    Screenshot { id: screenshotTool }

    IpcHandler {
        target: "screenshot"
        function region(): void { screenshotTool.shoot("region") }
        function full():   void { screenshotTool.shoot("full") }
        function win():    void { screenshotTool.shoot("window") }
    }

    // Bottom-centre OSD for volume + brightness changes
    Osd {
        barWindow: root
        fontFamily: root.fontFamily
    }





    // Track the focused workspace
    property int focusedWsId: Hyprland.focusedWorkspace?.id ?? 0

    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 6

        Repeater {
            model: 6

            Rectangle {
                id: pill
                implicitWidth: 26
                implicitHeight: 26
                anchors.verticalCenter: parent.verticalCenter
                radius: 10

                property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                property bool isActive: root.focusedWsId === (index + 1)

                // Less busy: only the ACTIVE workspace gets a filled pill.
                // The rest are just numbers, separated by opacity, not boxes.
                color: isActive ? Colors.primary : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: kanji.numberToKanji(index + 1)
                    color: pill.isActive ? Colors.on_primary
                         : (pill.ws ? Colors.on_surface : Colors.outline)
                    // active = full, occupied = bright, empty = faded
                    opacity: pill.isActive ? 1.0 : (pill.ws ? 0.9 : 0.4)
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    font {
                        family: root.fontFamily
                        pixelSize: root.fontSize
                        bold: pill.isActive
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // Hyprland's Lua IPC evaluates the dispatch string as
                    // hl.dispatch(<arg>), and hl.dispatch wants a *dispatcher*
                    // object, not strings. Switching workspaces is the same
                    // dispatcher the SUPER+N keybinds use: hl.dsp.focus{workspace=N}.
                    onClicked: Hyprland.dispatch('hl.dsp.focus({ workspace = ' + (index + 1) + ' })')
                }
            }
        }



        // spacer pushes everything after it to the right edge
	Item { Layout.fillWidth: true }


        // --- Status cluster: [tray] | [vol] [bell] [gear] | [clock] ---
        // Tray leftmost, the interactive controls grouped in the middle, and the
        // clock framed on its own at the far right. Two dividers frame the group;
        // controls share even spacing. CPU/RAM live in the control-center menu.

        // Screen-recording indicator (invisible unless wf-recorder is running)
        Recorder {
            anchors.verticalCenter: parent.verticalCenter
            Layout.rightMargin: 12
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        // Chevron toggle for the system-tray flyout (leftmost)
        SystemTrayFlyout {
            anchors.verticalCenter: parent.verticalCenter
            barWindow: root
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        Rectangle {  // divider: tray | controls
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            implicitWidth: 1
            implicitHeight: 18
            radius: 1
            color: Colors.outline_variant
            opacity: 0.5
        }

        // Volume: scroll to adjust, click to mute
        Volume {
            anchors.verticalCenter: parent.verticalCenter
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        // Notification bell + center (replaces dunst as the notification daemon)
        NotificationCenter {
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 14
            barWindow: root
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        // Quick-settings menu: system usage / volume / wifi / bluetooth
        ControlCenter {
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 14
            barWindow: root
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        Rectangle {  // divider: controls | clock
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            implicitWidth: 1
            implicitHeight: 18
            radius: 1
            color: Colors.outline_variant
            opacity: 0.5
        }

        // Clock (HH:mm). Click to drop down a month calendar.
        Clock {
            anchors.verticalCenter: parent.verticalCenter
            Layout.rightMargin: 6
            barWindow: root
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }
    }
    // CPU/RAM monitoring now lives in the ControlCenter menu.
}
