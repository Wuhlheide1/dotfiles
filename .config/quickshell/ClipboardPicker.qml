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
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: picker

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:clipboard"

    signal closed()

    property string query: ""

    // Raw history rows: { cid: "<id>", preview: "<text>" }
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
                model.append({
                    cid: line.substring(0, tab).trim(),
                    preview: line.substring(tab + 1)
                })
            }
        }
    }

    function refresh() { model.clear(); listProc.running = true }

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

    Process { id: decodeProc }
    function pick(entry) {
        if (!entry) return
        // decode reads the id and re-copies the original bytes (text or image).
        decodeProc.command = ["sh", "-c", "cliphist decode " + entry.cid + " | wl-copy"]
        decodeProc.running = true
        picker.closed()
    }

    Component.onCompleted: { refresh(); input.forceActiveFocus() }

    // Dim + click-away.
    Rectangle {
        anchors.fill: parent
        color: Colors.shadow
        opacity: 0.35
        MouseArea { anchors.fill: parent; onClicked: picker.closed() }
    }

    Rectangle {
        id: card
        width: 520
        height: 460
        anchors.centerIn: parent
        radius: 16
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
                    radius: 10
                    color: Colors.surface_container_high

                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        focus: true
                        color: Colors.on_surface
                        font.pixelSize: 16
                        onTextChanged: picker.query = text

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search clipboard…"
                            color: Colors.outline
                            font.pixelSize: 16
                            visible: input.text.length === 0
                        }

                        Keys.onEscapePressed: picker.closed()
                        Keys.onDownPressed:  picker.setSelected(picker.selected + 1)
                        Keys.onUpPressed:    picker.setSelected(picker.selected - 1)
                        Keys.onReturnPressed: picker.pick(picker.results[picker.selected])
                        Keys.onEnterPressed:  picker.pick(picker.results[picker.selected])
                    }
                }

                // Wipe the whole history.
                Rectangle {
                    implicitWidth: 44; implicitHeight: 44
                    radius: 10
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
                        onClicked: { wipeProc.running = true; picker.refresh() }
                    }
                    Process { id: wipeProc; command: ["cliphist", "wipe"] }
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
                font.pixelSize: 14
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
                    required property var modelData
                    required property int index

                    width: list.width
                    height: 40
                    radius: 8
                    color: index === picker.selected ? Colors.primary : "transparent"

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.preview
                        elide: Text.ElideRight
                        color: index === picker.selected ? Colors.on_primary : Colors.on_surface
                        font.pixelSize: 14
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
