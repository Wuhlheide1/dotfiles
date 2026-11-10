pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

// Spotify lyrics floating in the top left corner while a game is on screen.
// Its own quickshell config next to the shell (`qs -c lyrics -d`), click-through
// and only mapped while there is a line to show. README.md has the data flow.
//   qs -c lyrics ipc call lyrics toggle     (SUPER+Y)
ShellRoot {
    id: root

    // Tuning
    readonly property int marginLeft: 72        // clears the 52 px bar when a game is windowed
    readonly property int marginTop: 28
    readonly property int textWidth: 640
    readonly property int fontSize: 26
    readonly property real nextScale: 0.72
    readonly property real bgOpacity: 0.82
    readonly property int bgRadius: 16
    readonly property int padX: 18
    readonly property int padY: 12
    readonly property real lead: 0.15           // seconds a line lands ahead of the singer
    readonly property real nextHint: 5          // show the next line this long before it starts
    readonly property real maxHold: 12          // drop a line with nothing after it

    // Whole-class regexes. Same as the razer daemon's, plus Steam Remote Play;
    // ~/.config/razer/games adds to both.
    readonly property var gameClasses: ["steam_app_.*", "org\\.vinegarhq\\.Sober", "Minecraft.*", "gamescope", "streaming_client"]
    property var extraClasses: []

    property bool enabled: true
    property var colours: ({})
    property var lines: []          // [{t, text}], lines[0] is a blank before the first line
    property string source: ""      // spotify | lrclib
    property int current: 0
    property bool lineLive: false
    property bool nextClose: false

    readonly property MprisPlayer player: Mpris.players.values.find(p => p.dbusName === "org.mpris.MediaPlayer2.spotify") ?? null
    readonly property string trackId: {
        if (!player)
            return "";
        const url = player.metadata["xesam:url"] ?? "";
        return url.match(/open\.spotify\.com\/track\/(\w+)/)?.[1] ?? `${player.trackArtist}|${player.trackTitle}`;
    }

    readonly property var gameRegex: {
        const valid = gameClasses.concat(extraClasses).filter(p => {
            try {
                return new RegExp(p), true;
            } catch (e) {
                return false;
            }
        });
        return new RegExp(`^(?:${valid.join("|")})$`);
    }

    // The screen showing a game, focused or not: a look at Discord on the other
    // monitor shouldn't make the lyrics vanish.
    readonly property var gameScreen: {
        for (const monitor of Hyprland.monitors.values) {
            const windows = monitor.activeWorkspace?.toplevels.values ?? [];
            if (windows.some(w => gameRegex.test(w.wayland?.appId ?? "")))
                return Quickshell.screens.find(s => s.name === monitor.name) ?? null;
        }
        return null;
    }

    readonly property bool wanted: enabled && gameScreen !== null && player !== null
    readonly property bool live: wanted && player.isPlaying && lines.length > 1
    readonly property bool saying: live && (lineLive || nextClose)
    readonly property string request: wanted ? trackId : ""

    function colour(name: string, fallback: string): color {
        return colours[name] ? "#" + colours[name] : fallback;
    }

    // Spotify's MPRIS position is exact but nothing says when someone seeks,
    // so it's read back every couple of seconds and run on a local clock between.
    property real clockBase: 0
    property real clockAt: 0

    function position(): real {
        return clockBase + (player?.isPlaying ? (Date.now() - clockAt) / 1000 : 0);
    }

    function setLines(raw: var): void {
        const parsed = raw.map(([t, text]) => ({
                    t: t,
                    text: text.trim() === "♪" ? "" : text.trim()
                }));
        lines = [
            {
                t: 0,
                text: ""
            }
        ].concat(parsed);
        tick();
    }

    function tick(): void {
        const t = position() + lead;
        let i = 0;
        while (i + 1 < lines.length && lines[i + 1].t <= t)
            i++;
        const line = lines[i];
        const next = lines[i + 1];
        current = i;
        lineLive = !!line?.text && t - line.t < maxHold;
        nextClose = !!next?.text && next.t - t < nextHint;
    }

    onRequestChanged: {
        lines = [];
        source = "";
        if (request) {
            sync.running = true;
            bridge.ask();
        }
    }

    Connections {
        target: root.player

        function onIsPlayingChanged(): void {
            root.clockBase = root.player.isPlaying ? root.clockBase : root.position();
            root.clockAt = Date.now();
            sync.running = true;
        }
    }

    Process {
        id: bridge

        function ask(): void {
            if (!running || !root.request)
                return;
            write(JSON.stringify({
                id: root.request,
                title: root.player.trackTitle,
                artist: root.player.trackArtist,
                album: root.player.trackAlbum,
                length: root.player.length
            }) + "\n");
        }

        running: true
        stdinEnabled: true
        command: ["python3", Quickshell.shellDir + "/bridge.py"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    if (reply.id === root.request) {
                        root.source = reply.source;
                        root.setLines(reply.lines);
                    }
                } catch (e) {
                    console.warn("lyrics: bad reply from the bridge", e);
                }
            }
        }
        onRunningChanged: running ? ask() : restart.start()
    }

    Timer {
        id: restart

        interval: 5000
        onTriggered: bridge.running = true
    }

    Process {
        id: sync

        command: ["playerctl", "-p", "spotify", "position"]
        stdout: StdioCollector {
            onStreamFinished: {
                const measured = parseFloat(text);
                if (!isNaN(measured) && Math.abs(measured - root.position()) > 0.15) {
                    root.clockBase = measured;
                    root.clockAt = Date.now();
                }
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.live
        onTriggered: sync.running = true
    }

    Timer {
        interval: 100
        repeat: true
        running: root.live
        onTriggered: root.tick()
    }

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/caelestia/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.colours = JSON.parse(text()).colours ?? {};
            } catch (e) {
                console.warn("lyrics: could not parse scheme.json", e);
            }
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/razer/games"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.extraClasses = text().split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("#"))
    }

    IpcHandler {
        target: "lyrics"

        function toggle(): void {
            root.enabled = !root.enabled;
            Quickshell.execDetached(["notify-send", "-e", "-t", "1500", "-a", "caelestia-cli", "Game Lyrics", root.enabled ? "Enabled" : "Hidden"]);
        }

        function status(): string {
            return JSON.stringify({
                enabled: root.enabled,
                screen: root.gameScreen?.name ?? null,
                track: root.request,
                source: root.source,
                lines: root.lines.length,
                current: root.current,
                position: root.position(),
                saying: root.saying
            });
        }
    }

    LazyLoader {
        active: root.wanted

        PanelWindow {
            id: win

            readonly property int shadowPad: 24

            screen: root.gameScreen
            anchors.top: true
            anchors.left: true
            margins.top: Math.max(0, root.marginTop - shadowPad)
            margins.left: Math.max(0, root.marginLeft - shadowPad)
            implicitWidth: root.textWidth + root.padX * 2 + shadowPad * 2
            implicitHeight: root.fontSize * 8 + root.padY * 2 + shadowPad * 2
            color: "transparent"
            visible: root.saying || content.opacity > 0
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "caelestia-lyrics"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Text {
                id: curSizer

                visible: false
                width: root.textWidth
                text: root.lines[root.current]?.text ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: "Rubik"
                font.pixelSize: root.fontSize
                font.weight: 500
            }

            Text {
                id: nextSizer

                visible: false
                width: root.textWidth
                text: root.nextClose ? (root.lines[root.current + 1]?.text ?? "") : ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: "Rubik"
                font.pixelSize: root.fontSize
                font.weight: 500
            }

            Item {
                id: content

                readonly property real measuredW: Math.max(
                    curSizer.text ? Math.ceil(curSizer.contentWidth) : 0,
                    nextSizer.text ? Math.ceil(nextSizer.contentWidth * root.nextScale) : 0
                )
                readonly property real measuredH: (curSizer.text ? Math.ceil(curSizer.contentHeight) : 0)
                    + (nextSizer.text ? list.spacing + Math.ceil(nextSizer.contentHeight * root.nextScale) : 0)

                property real boxW: 0
                property real boxH: 0
                property bool sized: false

                function updateBox(): void {
                    if (measuredW <= 0 || measuredH <= 0)
                        return;
                    boxW = measuredW + root.padX * 2;
                    boxH = measuredH + root.padY * 2;
                    if (!sized)
                        Qt.callLater(() => { content.sized = true; });
                }

                onMeasuredWChanged: updateBox()
                onMeasuredHChanged: updateBox()
                Component.onCompleted: updateBox()
                onOpacityChanged: {
                    if (opacity === 0 && !root.saying)
                        sized = false;
                }

                anchors.fill: parent
                opacity: root.saying ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }

                RectangularShadow {
                    anchors.fill: bg
                    radius: bg.radius
                    blur: 20
                    spread: 0
                    offset: Qt.vector2d(0, 4)
                    color: Qt.alpha("#000000", 0.55)
                }

                Rectangle {
                    id: bg

                    x: win.shadowPad
                    y: win.shadowPad
                    width: content.boxW
                    height: content.boxH
                    radius: root.bgRadius
                    color: Qt.alpha(root.colour("surfaceContainer", "#161a1f"), root.bgOpacity)
                    border.width: 1
                    border.color: Qt.alpha(root.colour("outlineVariant", "#434850"), 0.4)
                    clip: true

                    Behavior on width {
                        enabled: content.sized
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on height {
                        enabled: content.sized
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }

                    ListView {
                        id: list

                        x: root.padX
                        y: root.padY
                        width: root.textWidth
                        height: root.fontSize * 8
                        interactive: false
                        spacing: 4
                        model: root.lines
                        currentIndex: root.current
                        highlight: Item {}
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: 0
                        highlightMoveDuration: 420
                        highlightMoveVelocity: -1
                        highlightResizeDuration: 0

                        delegate: Text {
                            id: line

                            required property int index
                            required property var modelData
                            readonly property bool isCurrent: index === root.current
                            readonly property bool isNext: index === root.current + 1

                            width: list.width
                            height: modelData.text ? implicitHeight : 0
                            text: modelData.text
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: "Rubik"
                            font.pixelSize: root.fontSize
                            font.weight: 500
                            color: root.colour("onSurface", "#e2e5ef")
                            style: Text.Outline
                            styleColor: "#80000000"
                            transformOrigin: Item.TopLeft
                            scale: isCurrent ? 1 : root.nextScale
                            opacity: isCurrent ? 1 : isNext && root.nextClose ? 0.65 : 0

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 420
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
