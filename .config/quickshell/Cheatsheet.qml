// Cheatsheet.qml — keybind reference overlay (SUPER+K).
//
// The bind list is parsed live from ~/.config/hypr/keybinds.lua by
// scripts/keybinds-list.sh, so this sheet can never go stale: annotate a bind
// with a trailing `-- description` there and it shows up here.
//
// Loaded on demand from shell.qml via a LazyLoader; Esc or any click closes.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: sheet

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:cheatsheet"

    signal dismissed()

    property string fontFamily: "Adwaita Sans"

    // Three balanced columns of category groups:
    // [ [ {name, binds:[{keys,desc},…]}, … ], … ]
    property var cols: [[], [], []]

    Process {
        id: loader
        command: ["bash", "/home/wuhlheide/.config/quickshell/scripts/keybinds-list.sh"]
        running: true
        property var lines: []
        stdout: SplitParser { onRead: data => loader.lines.push(data) }
        onExited: sheet.build(loader.lines)
    }

    function build(lines) {
        // TSV -> ordered category groups
        const order = [];
        const byCat = {};
        for (const line of lines) {
            const p = line.split("\t");
            if (p.length !== 3) continue;
            if (!byCat[p[0]]) { byCat[p[0]] = []; order.push(p[0]); }
            byCat[p[0]].push({ keys: p[1], desc: p[2] });
        }
        // Greedy-pack groups into the column with the fewest rows so the
        // three columns end up roughly the same height.
        const packed = [[], [], []];
        const rows = [0, 0, 0];
        for (const name of order) {
            let t = 0;
            for (let i = 1; i < 3; i++) if (rows[i] < rows[t]) t = i;
            packed[t].push({ name: name, binds: byCat[name] });
            rows[t] += byCat[name].length + 2;  // +2 ≈ header weight
        }
        cols = packed;
    }

    // Esc closes (the window holds exclusive keyboard focus).
    Item {
        focus: true
        Keys.onEscapePressed: sheet.dismissed()
        Component.onCompleted: forceActiveFocus()
    }

    // Dim layer; the whole sheet is read-only, so any click closes it.
    Rectangle {
        anchors.fill: parent
        color: Colors.shadow
        opacity: 0.35
    }
    MouseArea {
        anchors.fill: parent
        onClicked: sheet.dismissed()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: content.implicitWidth + 64
        height: content.implicitHeight + 56
        radius: 18
        color: Colors.surface_container
        border.color: Colors.outline_variant
        border.width: 1

        // Same enter animation as the bar menus.
        property bool ready: false
        Component.onCompleted: ready = true
        opacity: ready ? 1 : 0
        scale: ready ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale   { NumberAnimation { duration: 120 } }

        ColumnLayout {
            id: content
            anchors.centerIn: parent
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Keybinds"
                    color: Colors.on_surface
                    font { family: sheet.fontFamily; pixelSize: 18; bold: true }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Esc to close"
                    color: Colors.outline
                    font { family: sheet.fontFamily; pixelSize: 12 }
                }
            }

            RowLayout {
                spacing: 36
                Layout.alignment: Qt.AlignTop

                Repeater {
                    model: sheet.cols

                    ColumnLayout {
                        required property var modelData
                        spacing: 16
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 370

                        Repeater {
                            model: parent.modelData

                            ColumnLayout {
                                required property var modelData
                                spacing: 6

                                Text {
                                    text: modelData.name
                                    color: Colors.primary
                                    font { family: sheet.fontFamily; pixelSize: 13; bold: true }
                                }

                                Repeater {
                                    model: parent.modelData.binds

                                    RowLayout {
                                        required property var modelData
                                        spacing: 10

                                        Rectangle {
                                            implicitWidth: keyText.implicitWidth + 14
                                            implicitHeight: 22
                                            radius: 8
                                            color: Colors.surface_container_high
                                            Text {
                                                id: keyText
                                                anchors.centerIn: parent
                                                text: modelData.keys
                                                color: Colors.on_surface
                                                font { family: sheet.fontFamily; pixelSize: 11 }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.desc
                                            elide: Text.ElideRight
                                            color: Colors.on_surface_variant
                                            font { family: sheet.fontFamily; pixelSize: 12 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
