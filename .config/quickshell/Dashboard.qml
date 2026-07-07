import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Ambient dashboard (SUPER+D). A calm full-screen "glance" surface: giant
// clock + date + weather, now-playing, system vitals, and a LIVE window dock
// (ScreencopyView thumbnails of every open window — click one to jump to it).
// Loaded on demand from shell.qml via a LazyLoader; Esc or click-away closes.
PanelWindow {
    id: dash

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    screen: Quickshell.screens.find(s => s.name === "DP-2") ?? Quickshell.screens[0]

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "quickshell:dashboard"

    signal dismissed()

    // ---- live clock ----
    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: dash.now = new Date() }

    // ---- weather (open-meteo, no key; cached to a state file for instant show) ----
    property var wx: null
    readonly property string wxFile: "/home/wuhlheide/.local/state/quickshell/weather.json"
    FileView { id: wxCache; path: dash.wxFile; blockLoading: true; printErrors: false }
    Process {
        id: wxProc
        command: ["sh", "-c",
            "curl -sf --max-time 6 'https://api.open-meteo.com/v1/forecast?latitude=51.0&longitude=10.0"
            + "&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,"
            + "precipitation_probability_max&timezone=auto&forecast_days=1'"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    var d = JSON.parse(line)
                    dash.wx = { t: Math.round(d.current.temperature_2m), code: d.current.weather_code,
                                hi: Math.round(d.daily.temperature_2m_max[0]),
                                lo: Math.round(d.daily.temperature_2m_min[0]),
                                rain: d.daily.precipitation_probability_max[0], at: Date.now() }
                    wxCache.setText(JSON.stringify(dash.wx))
                } catch (e) { /* offline — keep cached */ }
            }
        }
    }
    function wxGlyph(c) {
        if (c === 0) return "\ue30d"
        if (c <= 2)  return "\ue302"
        if (c === 3) return "\ue312"
        if (c <= 48) return "\ue313"
        if (c <= 67 || (c >= 80 && c <= 82)) return "\ue318"
        if (c <= 77 || c === 85 || c === 86) return "\ue31a"
        if (c >= 95) return "\ue31d"
        return "\ue312"
    }

    // ---- system vitals (polled while open) ----
    property string vitals: ""
    Process {
        id: vitProc
        command: ["sh", "-c",
            "read up _ < /proc/uptime; la=$(cut -d' ' -f1 /proc/loadavg); "
            + "mem=$(free -m | awk '/^Mem:/{printf \"%d %d\", $3, $2}'); ct=''; gt=''; "
            + "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); "
            + "[ \"$n\" = k10temp ] && ct=$(cat $h/temp1_input 2>/dev/null); "
            + "[ \"$n\" = amdgpu ] && gt=$(cat $h/temp1_input 2>/dev/null); done; "
            + "printf '%s|%s|%s|%s|%s\\n' \"${up%.*}\" \"$la\" \"$mem\" \"$ct\" \"$gt\""]
        stdout: SplitParser { onRead: line => dash.vitals = line }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: vitProc.running = true }

    readonly property var v: {
        var p = (vitals || "").split("|")
        if (p.length < 3) return null
        var up = parseInt(p[0]) || 0
        var mem = (p[2] || "").split(" ")
        return {
            up: (up >= 86400 ? Math.floor(up / 86400) + "d " : "") + Math.floor((up % 86400) / 3600)
                + "h " + Math.floor((up % 3600) / 60) + "m",
            load: p[1] || "",
            memUsed: parseInt(mem[0]) || 0, memTot: parseInt(mem[1]) || 1,
            ct: p[3] ? Math.round(parseInt(p[3]) / 1000) : null,
            gt: p[4] ? Math.round(parseInt(p[4]) / 1000) : null
        }
    }

    readonly property var player: {
        var ps = Mpris.players ? Mpris.players.values : []
        return ps.find(p => p.isPlaying) ?? (ps.length ? ps[0] : null)
    }

    Component.onCompleted: {
        try {
            var c = JSON.parse(wxCache.text() || "")
            if (c && c.t !== undefined) dash.wx = c
        } catch (e) {}
        if (!dash.wx || Date.now() - (dash.wx.at || 0) > 30 * 60 * 1000) wxProc.running = true
        focusSink.forceActiveFocus()
    }

    // ---- backdrop: dim + click-away ----
    Rectangle {
        anchors.fill: parent
        color: Colors.background
        opacity: 0.94
        MouseArea { anchors.fill: parent; onClicked: dash.dismissed() }
    }
    Item { id: focusSink; focus: true; Keys.onEscapePressed: dash.dismissed() }

    // fade/scale in
    Item {
        id: stage
        anchors.fill: parent
        opacity: 0
        scale: 0.98
        Component.onCompleted: { opacity = 1; scale = 1 }
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 160, 1180)
            spacing: 34

            // ===== hero: clock + date + weather =====
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(dash.now, "HH:mm")
                    color: Colors.on_surface
                    font { family: dash.fontFamily; pixelSize: 148; weight: Font.Light }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(dash.now, "dddd, d MMMM")
                    color: Colors.on_surface_variant
                    font { family: dash.fontFamily; pixelSize: 26 }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    spacing: 10
                    visible: dash.wx !== null
                    Text {
                        text: dash.wx ? dash.wxGlyph(dash.wx.code) : ""
                        color: Colors.primary
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
                    }
                    Text {
                        text: dash.wx ? dash.wx.t + "°   ↑" + dash.wx.hi + "° ↓" + dash.wx.lo + "°"
                              + (dash.wx.rain >= 20 ? "    \ue318 " + dash.wx.rain + "%" : "") : ""
                        color: Colors.on_surface_variant
                        font { family: dash.fontFamily; pixelSize: 18 }
                    }
                }
            }

            // ===== info row: now-playing + vitals =====
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                spacing: 18

                // now playing
                Rectangle {
                    Layout.preferredWidth: 420
                    Layout.preferredHeight: 96
                    visible: dash.player !== null
                    radius: 18
                    color: Colors.surface_container
                    border.color: Colors.outline_variant
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14
                        ClippingRectangle {
                            Layout.preferredWidth: 68; Layout.preferredHeight: 68
                            radius: 12
                            color: Colors.surface_container_high
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                source: dash.player && dash.player.trackArtUrl ? dash.player.trackArtUrl : ""
                                sourceSize { width: 136; height: 136 }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !dash.player || !dash.player.trackArtUrl
                                text: "\uf001"
                                color: Colors.on_surface_variant
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 24 }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: dash.player ? (dash.player.trackTitle || "Unknown") : ""
                                color: Colors.on_surface
                                elide: Text.ElideRight
                                font { family: dash.fontFamily; pixelSize: 15; bold: true }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: dash.player ? (dash.player.trackArtist || "") : ""
                                color: Colors.on_surface_variant
                                elide: Text.ElideRight
                                font { family: dash.fontFamily; pixelSize: 13 }
                            }
                            RowLayout {
                                Layout.topMargin: 4
                                spacing: 18
                                Text {
                                    text: "\uf048"
                                    color: (dash.player && dash.player.canGoPrevious) ? Colors.on_surface : Colors.outline
                                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
                                    MouseArea { anchors.fill: parent; anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (dash.player) dash.player.previous() }
                                }
                                Text {
                                    text: (dash.player && dash.player.isPlaying) ? "\uf04c" : "\uf04b"
                                    color: Colors.primary
                                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
                                    MouseArea { anchors.fill: parent; anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (dash.player) dash.player.togglePlaying() }
                                }
                                Text {
                                    text: "\uf051"
                                    color: (dash.player && dash.player.canGoNext) ? Colors.on_surface : Colors.outline
                                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
                                    MouseArea { anchors.fill: parent; anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (dash.player) dash.player.next() }
                                }
                            }
                        }
                    }
                }

                // vitals
                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.preferredHeight: 96
                    visible: dash.v !== null
                    radius: 18
                    color: Colors.surface_container
                    border.color: Colors.outline_variant
                    border.width: 1
                    GridLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 14
                        VitalCell { glyph: "\uf017"; label: "uptime"; value: dash.v ? dash.v.up : "" }
                        VitalCell { glyph: "\uf0e4"; label: "load";   value: dash.v ? dash.v.load : "" }
                        VitalCell { glyph: "\uf2db"; label: "ram"
                            value: dash.v ? (dash.v.memUsed >= 1024
                                ? (dash.v.memUsed / 1024).toFixed(1) + "/" + (dash.v.memTot / 1024).toFixed(0) + "G"
                                : dash.v.memUsed + "/" + dash.v.memTot + "M") : "" }
                        VitalCell { glyph: "\uf2c9"; label: "temp"
                            value: dash.v && dash.v.ct !== null
                                ? dash.v.ct + "°" + (dash.v.gt !== null ? " · " + dash.v.gt + "°" : "") : "—" }
                    }
                }
            }

            // ===== live window dock =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 10
                visible: dash.windowCount > 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Open windows — click to jump"
                    color: Colors.outline
                    font { family: dash.fontFamily; pixelSize: 12 }
                }

                Flow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: Math.min(dash.width - 200, 1180)
                    spacing: 16

                    Repeater {
                        id: winRep
                        model: ToplevelManager.toplevels
                        delegate: Rectangle {
                            id: winCard
                            required property var modelData
                            readonly property real ar: (thumb.sourceSize.width > 0 && thumb.sourceSize.height > 0)
                                ? thumb.sourceSize.width / thumb.sourceSize.height : 1.6
                            height: 168
                            width: Math.max(150, Math.min(320, 132 * ar))
                            radius: 14
                            color: Colors.surface_container
                            border.width: hov.hovered ? 2 : 1
                            border.color: hov.hovered ? Colors.primary : Colors.outline_variant

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6
                                ClippingRectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: Colors.surface_container_high
                                    ScreencopyView {
                                        id: thumb
                                        anchors.fill: parent
                                        captureSource: winCard.modelData
                                        live: true
                                        visible: hasContent
                                    }
                                    // fallback icon when the window's buffer isn't
                                    // available (e.g. it's on another workspace)
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: !thumb.hasContent
                                        implicitSize: 44
                                        source: winCard.modelData && winCard.modelData.appId
                                            ? Quickshell.iconPath(winCard.modelData.appId.toLowerCase(), true) : ""
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (winCard.modelData ? (winCard.modelData.appId || winCard.modelData.title || "?") : "?")
                                    color: hov.hovered ? Colors.primary : Colors.on_surface_variant
                                    elide: Text.ElideRight
                                    font { family: dash.fontFamily; pixelSize: 11 }
                                }
                            }

                            HoverHandler { id: hov }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (winCard.modelData) winCard.modelData.activate()
                                    dash.dismissed()
                                }
                            }

                            scale: hov.hovered ? 1.03 : 1
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    readonly property int windowCount: ToplevelManager.toplevels ? ToplevelManager.toplevels.values.length : 0
    property string fontFamily: "Adwaita Sans"

    // small labelled vitals cell
    component VitalCell: RowLayout {
        id: cell
        property string glyph: ""
        property string label: ""
        property string value: ""
        spacing: 8
        Text {
            text: cell.glyph
            color: Colors.primary
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
        }
        ColumnLayout {
            spacing: -2
            Text { text: cell.value; color: Colors.on_surface
                   font { family: "Adwaita Sans"; pixelSize: 14; bold: true } }
            Text { text: cell.label; color: Colors.outline
                   font { family: "Adwaita Sans"; pixelSize: 10 } }
        }
    }
}
