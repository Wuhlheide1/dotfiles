//@ pragma UseQApplication
// ^ required so tray right-click (platform) menus can render

import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: root
    // Pin the bar to the main monitor — without this it lands on whichever
    // screen the compositor favours at launch (varied between restarts).
    screen: Quickshell.screens.find(s => s.name === "DP-2") ?? Quickshell.screens[0]
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 40
    // Neutral surface with a barely-there wallpaper tint and a whisper of
    // transparency (matugen is accents-only now; this keeps the bar alive
    // without letting the wallpaper take over the chrome).
    color: Qt.alpha(Qt.tint(Colors.background, Qt.alpha(Colors.primary, 0.05)), 0.93)

    // --- Theme ---
    // All colors now live in the Colors singleton (Colors.qml), which matugen
    // regenerates from your wallpaper. Reference them as Colors.primary etc.
    // UI text is Adwaita Sans (Inter-based, closest installed match to
    // SamsungOne); icon glyphs stay pinned to the Nerd Font inside each widget.
    property string fontFamily: "Adwaita Sans"
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

    // Brightness (DDC backlight when available, else hyprsunset gamma) —
    // driven by SUPER+F1/F2 and the XF86MonBrightness keys.
    IpcHandler {
        target: "brightness"
        function up():   void { Brightness.up() }
        function down(): void { Brightness.down() }
        function set(v: int): void { Brightness.set(v) }
        // re-probe DDC once (e.g. right after installing ddcutil)
        function redetect(): void { Brightness.redetect() }
    }

    // Screenshots (grim/slurp) — driven by the Print / Shift+Print / Super+Print keys.
    Screenshot { id: screenshotTool }

    IpcHandler {
        target: "screenshot"
        function region(): void { screenshotTool.shoot("region") }
        function full():   void { screenshotTool.shoot("full") }
        function win():    void { screenshotTool.shoot("window") }
        function annotate(): void { screenshotTool.shoot("edit") }
        function ocr(): void { screenshotTool.shoot("ocr") }
    }

    // Bottom-centre OSD for volume + brightness changes
    Osd {
        barWindow: root
        fontFamily: root.fontFamily
    }

    // Timers / alarms / stopwatch: state, SUPER+T flyout and IPC only —
    // the visible part is the pill next to the workspaces below
    Timers {
        id: timersWidget
        barWindow: root
        fontFamily: root.fontFamily
        fontSize: root.fontSize
    }





    // Track the focused workspace
    property int focusedWsId: Hyprland.focusedWorkspace?.id ?? 0

    // Clicking any empty spot on the bar closes whichever flyout is open —
    // sits beneath the widget row, so widget clicks still win.
    MouseArea {
        anchors.fill: parent
        visible: PopupBus.current !== ""
        onPressed: PopupBus.close()
    }

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

        // --- running timer / stopwatch pill (hidden while idle; SUPER+T flyout) ---
        Rectangle {  // divider: workspaces | timer pill
            visible: timersWidget.pillCount > 0
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            implicitWidth: 1
            implicitHeight: 18
            radius: 1
            color: Colors.outline_variant
            opacity: 0.5
        }
        Rectangle {
            id: timerPill
            visible: timersWidget.pillCount > 0
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: pillContent.implicitWidth + 20
            implicitHeight: 26
            radius: 10
            color: Colors.surface_container_high

            // width pin: widest time string of the current format, so the pill
            // never resizes while ticking or when scrolling between entries
            Text {
                id: pillMetric
                visible: false
                text: timersWidget.pillWide ? "8:88:88" : "88:88"
                font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
            }

            RowLayout {
                id: pillContent
                anchors.centerIn: parent
                spacing: 6
                Text {
                    Layout.preferredWidth: 15
                    horizontalAlignment: Text.AlignHCenter
                    text: timersWidget.pillGlyph
                    color: timersWidget.pillUrgent ? Colors.error : Colors.primary
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: root.fontSize - 2 }
                }
                Text {
                    Layout.preferredWidth: pillMetric.implicitWidth
                    horizontalAlignment: Text.AlignRight
                    text: timersWidget.pillText
                    color: timersWidget.pillUrgent ? Colors.error : Colors.on_surface
                    font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                }
                // paging dots: a window of at most 3 full dots. A mini 2px dot
                // past an edge means you can still scroll that way; no mini =
                // you're at that end. Size/position changes animate on scroll.
                Column {
                    visible: timersWidget.pillCount > 1
                    Layout.preferredWidth: 5
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Repeater {
                        model: timersWidget.pillCount
                        Rectangle {
                            required property int index
                            readonly property int winStart:
                                Math.max(0, Math.min(timersWidget.pillIdx - 1,
                                                     timersWidget.pillCount - 3))
                            readonly property bool inWin:
                                index >= winStart && index < winStart + 3
                            visible: inWin || index === winStart - 1 || index === winStart + 3
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: inWin ? 4 : 2
                            height: inWin ? 4 : 2
                            radius: width / 2
                            color: index === timersWidget.pillIdx ? Colors.primary : Colors.outline
                            opacity: index === timersWidget.pillIdx ? 1.0 : (inWin ? 0.5 : 0.3)
                            Behavior on width   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on height  { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on color   { ColorAnimation  { duration: 150 } }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: PopupBus.toggle("timers")
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => timersWidget.pillScroll(ev.angleDelta.y > 0 ? -1 : 1)
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
            id: recorderWidget
            anchors.verticalCenter: parent.verticalCenter
            Layout.rightMargin: 12
            barWindow: root
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

        // Laptop battery (self-hides on desktops with no battery device)
        Battery {
            anchors.verticalCenter: parent.verticalCenter
            Layout.rightMargin: 10
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        // Volume: scroll to adjust, click to mute
        Volume {
            anchors.verticalCenter: parent.verticalCenter
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        // Notification bell + center (replaces dunst as the notification daemon)
        NotificationCenter {
            id: notifWidget
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 14
            barWindow: root
            recorder: recorderWidget   // auto-DND while recording
            fontFamily: root.fontFamily
            fontSize: root.fontSize
        }

        // Quick-settings menu: system usage / volume / wifi / bluetooth
        ControlCenter {
            anchors.verticalCenter: parent.verticalCenter
            Layout.leftMargin: 14
            barWindow: root
            notifCenter: notifWidget   // DND tile flips its dndManual
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
    // Drag a file from anywhere onto the bar to send it to the phone (Valent).
    // DropArea only reacts to drags, so normal clicks pass through untouched.
    DropArea {
        id: phoneDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            if (!drop.hasUrls) return
            // execDetached, URIs as argv piped via printf: the old shared
            // Process no-op'd on every drop after the first (same command =
            // no re-run, the documented Process-reuse gotcha)
            var cmd = ["sh", "-c",
                'printf "%s\n" "$@" | bash /home/wuhlheide/.config/quickshell/scripts/phone.sh share-uris',
                "dnd"]
            for (var i = 0; i < drop.urls.length; i++) cmd.push(String(drop.urls[i]))
            Quickshell.execDetached(cmd)
        }
        Rectangle {
            anchors.fill: parent
            visible: phoneDrop.containsDrag
            color: Qt.alpha(Colors.primary, 0.18)
            Text {
                anchors.centerIn: parent
                text: "Drop to send to phone"
                color: Colors.on_surface
                font { family: root.fontFamily; pixelSize: root.fontSize - 1; bold: true }
            }
        }
    }

    // CPU/RAM monitoring now lives in the ControlCenter menu.
}
