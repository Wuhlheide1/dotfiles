import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Quick-settings flyout: volume slider, Wi-Fi toggle, Bluetooth toggle + devices.
// (Wi-Fi network picker / password entry is intentionally left for later.)
Item {
    id: root

    property var barWindow
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14

    implicitWidth: gear.implicitWidth + 8
    implicitHeight: 26

    // Default sink, tracked so its audio props are live & writable.
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.ready && sink.audio !== null
    readonly property real vol: sinkReady ? sink.audio.volume : 0
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    readonly property var btAdapter: Bluetooth.defaultAdapter

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

    // --- active network readout (wired for now; polled only while menu open) ---
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

    // --- system usage (polled only while the menu is open) ---
    property int cpu: 0
    property int mem: 0
    property int lastTotal: 0
    property int lastIdle: 0

    Process {
        id: sysProc
        command: ["sh", "-c",
            "awk 'NR==1{print \"cpu\", $2, $3, $4, $5, $6, $7, $8}' /proc/stat; " +
            "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"mem %d\\n\", (t-a)*100/t}' /proc/meminfo"]
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
                }
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: centerPopup.visible            // only poll while the menu is open
        onTriggered: sysProc.running = true
    }

    // --- reusable pill toggle ---
    component Toggle: Rectangle {
        property bool on: false
        signal toggled()
        implicitWidth: 42; implicitHeight: 22; radius: 11
        color: on ? Colors.primary : Colors.surface_container_high
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 18; height: 18; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: parent.on ? parent.width - width - 2 : 2
            color: parent.on ? Colors.on_primary : Colors.outline
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled() }
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
            Layout.preferredWidth: 36
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

    // --- power button (icon over small label) ---
    component PowerBtn: Rectangle {
        property string glyph: ""
        property string label: ""
        property bool danger: false
        signal activated()
        Layout.fillWidth: true
        implicitHeight: 42
        radius: 10
        color: pbArea.containsMouse ? (danger ? Colors.error : Colors.surface_container_high)
                                    : Colors.surface_container_high
        opacity: pbArea.containsMouse ? 1 : 0.85
        Behavior on color { ColorAnimation { duration: 100 } }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: glyph
                color: (pbArea.containsMouse && danger) ? Colors.background
                      : (danger ? Colors.error : Colors.on_surface)
                font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: label
                color: (pbArea.containsMouse && danger) ? Colors.background : Colors.on_surface_variant
                font { family: root.fontFamily; pixelSize: 9 }
            }
        }
        MouseArea {
            id: pbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    // --- bar button (sliders glyph) ---
    Text {
        id: gear
        anchors.centerIn: parent
        text: "\uf1de" // nf-fa-sliders
        color: PopupBus.current === "control" ? Colors.primary : Colors.on_surface
        opacity: 0.85
        font { family: root.fontFamily; pixelSize: root.fontSize }
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
        onVisibleChanged: if (!visible) root.clearPower()  // never reopen mid-confirm
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // click anywhere outside the card → close
        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }

        Rectangle {
            id: card
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6   // overlay already starts below the bar's reserved zone
            anchors.rightMargin: 12
            width: 320
            height: implicitHeight
            implicitHeight: col.implicitHeight + 28

            // subtle drop-in when the menu opens
            transformOrigin: Item.TopRight
            opacity: centerPopup.visible ? 1 : 0
            scale: centerPopup.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            // swallow clicks inside the card so they don't reach the dismiss area
            MouseArea { anchors.fill: parent }
            radius: 16
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 14

                // --- System usage ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatBar { label: "CPU"; value: root.cpu; barColor: Colors.primary }
                    StatBar { label: "RAM"; value: root.mem; barColor: Colors.secondary }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.4 }

                // --- Volume ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: root.sinkReady && root.sink.audio.muted ? "\uf026" : "\uf028"
                        color: Colors.on_surface
                        font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
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
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 6; radius: 3
                            color: Colors.surface_container_high
                            Rectangle {
                                width: parent.width * root.vol
                                height: parent.height; radius: 3
                                color: Colors.primary
                            }
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

                // --- Brightness (software GPU gamma via hyprsunset; never touches the monitor) ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: "\uf185"   // nf-fa-sun-o
                        color: Colors.on_surface
                        font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 22
                        Rectangle {
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

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.4 }

                // --- Media (MPRIS: whatever is playing — Spotify, mpv, browser…) ---
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.mprisPlayer !== null
                    spacing: 10

                    // album art, or a music-note fallback
                    Rectangle {
                        Layout.preferredWidth: 40; Layout.preferredHeight: 40
                        radius: 8; clip: true
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
                            font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
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
                        font { family: root.fontFamily; pixelSize: root.fontSize }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.mprisPlayer) root.mprisPlayer.previous()
                        }
                    }
                    Text {
                        text: (root.mprisPlayer && root.mprisPlayer.isPlaying) ? "\uf04c" : "\uf04b" // pause / play
                        color: Colors.primary
                        font { family: root.fontFamily; pixelSize: root.fontSize + 3 }
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
                        font { family: root.fontFamily; pixelSize: root.fontSize }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.mprisPlayer) root.mprisPlayer.next()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 1
                    color: Colors.outline_variant; opacity: 0.4
                    visible: root.mprisPlayer !== null
                }

                // --- Network (wired; Wi-Fi picker arrives with the laptop migration) ---
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        // wifi glyph if on a wl* iface, otherwise a wired plug
                        text: root.netIface.indexOf("wl") === 0 ? "\uf1eb" : "\uf1e6"
                        color: root.netUp ? Colors.primary : Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize }
                    }
                    ColumnLayout {
                        Layout.leftMargin: 6
                        spacing: 0
                        Text {
                            text: root.netUp ? "Connected" : "Disconnected"
                            color: Colors.on_surface
                            font { family: root.fontFamily; pixelSize: root.fontSize }
                        }
                        Text {
                            visible: root.netUp
                            text: root.netIface + "  \u2022  " + root.netIp
                            color: Colors.on_surface_variant
                            font { family: root.fontFamily; pixelSize: root.fontSize - 3 }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.4 }

                // --- Bluetooth ---
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "\uf294" // nf-fa-bluetooth-b
                        color: (root.btAdapter && root.btAdapter.enabled) ? Colors.primary : Colors.outline
                        font { family: root.fontFamily; pixelSize: root.fontSize }
                    }
                    Text {
                        text: "Bluetooth"
                        color: Colors.on_surface
                        Layout.leftMargin: 6
                        font { family: root.fontFamily; pixelSize: root.fontSize }
                    }
                    Item { Layout.fillWidth: true }
                    Toggle {
                        on: root.btAdapter ? root.btAdapter.enabled : false
                        onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                    }
                }

                // paired/connected devices
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24
                    spacing: 6
                    visible: root.btAdapter && root.btAdapter.enabled

                    Repeater {
                        model: Bluetooth.devices
                        RowLayout {
                            Layout.fillWidth: true
                            visible: modelData.bonded || modelData.connected
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                     + (modelData.batteryAvailable ? "  " + Math.round(modelData.battery * 100) + "%" : "")
                                color: modelData.connected ? Colors.on_surface : Colors.on_surface_variant
                                elide: Text.ElideRight
                                font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                            }
                            Text {
                                text: modelData.connected ? "Disconnect" : "Connect"
                                color: modelData.connected ? Colors.error : Colors.primary
                                font { family: root.fontFamily; pixelSize: root.fontSize - 2 }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.4 }

                // --- Power ---
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 42

                    // default: four power actions
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8
                        visible: root.pendingCmd === ""
                        PowerBtn {
                            glyph: ""; label: "Shutdown"; danger: true
                            onActivated: root.askPower("systemctl poweroff", "Shut down")
                        }
                        PowerBtn {
                            glyph: ""; label: "Reboot"
                            onActivated: root.askPower("systemctl reboot", "Reboot")
                        }
                        PowerBtn {
                            glyph: ""; label: "Suspend"
                            onActivated: root.askPower("systemctl suspend", "Suspend")
                        }
                        PowerBtn {
                            glyph: ""; label: "Log out"
                            onActivated: root.askPower("hyprctl dispatch exit", "Log out")
                        }
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
                            implicitWidth: 84; implicitHeight: 34; radius: 9
                            color: Colors.error
                            Text {
                                anchors.centerIn: parent; text: "Confirm"; color: Colors.background
                                font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.runPower() }
                        }
                        Rectangle {
                            implicitWidth: 74; implicitHeight: 34; radius: 9
                            color: Colors.surface_container_high
                            Text {
                                anchors.centerIn: parent; text: "Cancel"; color: Colors.on_surface
                                font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clearPower() }
                        }
                    }
                }
            }
        }
    }
}
