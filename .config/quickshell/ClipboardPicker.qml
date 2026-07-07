// ClipboardPicker.qml — themed clipboard-history picker backed by cliphist.
//
// `cliphist list` gives "<id>\t<preview>" lines; selecting one runs
// `cliphist decode <id> | wl-copy` to put it back on the clipboard. Modeled
// on Launcher.qml (fullscreen dim + card + search + arrow/Enter nav) so it
// matches the rest of the shell instead of an unthemed wofi menu.
//
// Loaded on demand from shell.qml via a LazyLoader; toggled with SUPER+V.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: picker

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:clipboard"

    signal dismissed()

    property string query: ""

    // Image entries get real thumbnails: their bytes are decoded once into
    // this cache dir, keyed by cliphist id (stale thumbs GC'd on refresh).
    readonly property string thumbDir: "/home/wuhlheide/.cache/quickshell/cliphist-thumbs"
    property bool thumbsReady: false

    // Raw history rows: { cid: "<id>", preview: "<text>", isImage, meta }
    ListModel { id: model }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: line => {
                if (!line) return
                // cliphist rows are "<id>\t<preview>" (id may be left-padded).
                var tab = line.indexOf("\t")
                if (tab < 0) return
                var preview = line.substring(tab + 1)
                var img = /^\[\[ binary data .* (png|jpe?g|webp|bmp) \d+x\d+ \]\]$/.test(preview)
                model.append({
                    cid: line.substring(0, tab).trim(),
                    preview: preview,
                    isImage: img,
                    // "[[ binary data 72 KiB png 536x467 ]]" → "72 KiB png 536x467"
                    meta: img ? preview.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : ""
                })
            }
        }
        onExited: {
            var ids = []
            for (var i = 0; i < model.count; i++)
                if (model.get(i).isImage) ids.push(model.get(i).cid)
            if (ids.length === 0) { picker.thumbsReady = true; return }
            // decode missing thumbs; GC thumbs whose entry left the history
            thumbProc.command = ["sh", "-c",
                "d=" + picker.thumbDir + "; mkdir -p $d; ids=' " + ids.join(" ") + " '; " +
                "for f in $d/*.png; do [ -e \"$f\" ] || break; b=${f##*/}; " +
                "case $ids in *\" ${b%.png} \"*) ;; *) rm -f \"$f\";; esac; done; " +
                "for id in $ids; do [ -f $d/$id.png ] || cliphist decode $id > $d/$id.png; done"]
            thumbProc.running = true
        }
    }

    Process {
        id: thumbProc
        onExited: picker.thumbsReady = true
    }

    function refresh() { thumbsReady = false; model.clear(); listProc.running = true }

    // Filter (substring on the preview) → plain JS array, like Launcher.results.
    readonly property var results: {
        const q = query.toLowerCase().trim()
        const out = []
        for (var i = 0; i < model.count; i++) {
            const it = model.get(i)
            if (q.length === 0 || it.preview.toLowerCase().indexOf(q) >= 0)
                out.push(it)
        }
        return out
    }

    property int selected: 0
    onResultsChanged: setSelected(0)
    function setSelected(i) {
        selected = Math.max(0, Math.min(i, results.length - 1))
        list.positionViewAtIndex(selected, ListView.Contain)
    }

    function pick(entry) {
        if (!entry) return
        // MUST be execDetached: dismissed() deactivates the LazyLoader, which
        // destroys this component and kills any member Process mid-pipe — the
        // old Process-based version only copied when it won that race ("picking
        // does nothing most of the time").
        //
        // After copying, paste straight into whichever window gets focus back:
        // ctrl+v everywhere, ctrl+shift+v in kitty. send_shortcut must use the
        // Lua dispatcher form on this setup — the classic
        // `sendshortcut CTRL,V,` syntax is rejected by the non-legacy parser.
        // The sleep gives the picker time to unmap and focus to return.
        Quickshell.execDetached(["sh", "-c",
            "cliphist decode " + entry.cid + " | wl-copy; sleep 0.2; " +
            "cls=$(hyprctl activewindow -j | grep -o '\"class\": \"[^\"]*\"' | head -1 | cut -d'\"' -f4); " +
            "if [ \"$cls\" = kitty ]; then mods='CTRL SHIFT'; else mods='CTRL'; fi; " +
            "hyprctl dispatch \"hl.dsp.send_shortcut({ mods = '$mods', key = 'V' })\""])
        picker.dismissed()
    }

    Component.onCompleted: { refresh(); input.forceActiveFocus() }

    // Dim + click-away.
    Rectangle {
        anchors.fill: parent
        color: Colors.shadow
        opacity: 0.35
        MouseArea { anchors.fill: parent; onClicked: picker.dismissed() }
    }

    Rectangle {
        id: card
        width: 520
        height: 460
        anchors.centerIn: parent
        radius: 18
        color: Colors.surface_container
        border.color: Colors.outline_variant
        border.width: 1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

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
                        onTextChanged: picker.query = text

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search clipboard…"
                            color: Colors.outline
                            font { family: "Adwaita Sans"; pixelSize: 16 }
                            visible: input.text.length === 0
                        }

                        Keys.onEscapePressed: picker.dismissed()
                        Keys.onDownPressed:  picker.setSelected(picker.selected + 1)
                        Keys.onUpPressed:    picker.setSelected(picker.selected - 1)
                        Keys.onReturnPressed: picker.pick(picker.results[picker.selected])
                        Keys.onEnterPressed:  picker.pick(picker.results[picker.selected])
                    }
                }

                // Wipe the whole history.
                Rectangle {
                    implicitWidth: 44; implicitHeight: 44
                    radius: 12
                    color: wipeArea.containsMouse ? Colors.error : Colors.surface_container_high
                    Text {
                        anchors.centerIn: parent
                        text: "\uf1f8" // nf-fa-trash
                        color: wipeArea.containsMouse ? Colors.background : Colors.on_surface_variant
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
                    }
                    MouseArea {
                        id: wipeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wipeProc.running = true
                    }
                    // refresh only after the wipe finished, or the list re-reads stale entries
                    Process { id: wipeProc; command: ["cliphist", "wipe"]; onExited: picker.refresh() }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: picker.results.length === 0
                text: "Clipboard history is empty"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Colors.outline
                font { family: "Adwaita Sans"; pixelSize: 14 }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: picker.results.length > 0
                model: picker.results
                currentIndex: picker.selected
                spacing: 4

                delegate: Rectangle {
                    id: entryRow
                    required property var modelData
                    required property int index

                    readonly property bool thumbed: modelData.isImage && picker.thumbsReady

                    width: list.width
                    height: thumbed ? 68 : 40
                    radius: 10
                    color: index === picker.selected ? Colors.primary : "transparent"

                    Text {
                        visible: !entryRow.thumbed
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.preview
                        elide: Text.ElideRight
                        color: index === picker.selected ? Colors.on_primary : Colors.on_surface
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                    }

                    // image entry: thumbnail + size/format instead of the
                    // useless "[[ binary data ]]" text
                    RowLayout {
                        visible: entryRow.thumbed
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12
                        ClippingRectangle {
                            Layout.preferredWidth: 88
                            Layout.preferredHeight: 54
                            radius: 8
                            color: Colors.surface_container_high
                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize { width: 176; height: 108 }
                                // don't touch the file until the decode pass is done
                                source: entryRow.thumbed
                                    ? "file://" + picker.thumbDir + "/" + entryRow.modelData.cid + ".png" : ""
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.meta
                            elide: Text.ElideRight
                            color: index === picker.selected ? Colors.on_primary : Colors.on_surface_variant
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: picker.selected = index
                        onClicked: picker.pick(modelData)
                    }
                }
            }
        }
    }
}
