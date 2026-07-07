// WallpaperPicker.qml — a grid of wallpapers; click one to set it.
//
// On selection it runs `awww img <path>` (the wallpaper) AND `matugen image
// <path>` (which regenerates ~/.config/quickshell/Colors.qml + hypr colors),
// so the whole shell live-recolors from the new wallpaper.
//
// Backend is awww (the running awww-daemon). To swap backends, edit `setCmd`.
//
// Loaded on demand from shell.qml via a LazyLoader and toggled over IPC.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel

PanelWindow {
    id: picker

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:wallpaper"

    signal dismissed()

    // --- config -----------------------------------------------------------
    property string wallDir: "/home/wuhlheide/images/wallpapers"

    // awww + matugen + hyprctl reload all live in wallpaper.sh so the picker,
    // the shuffle keybind, login and the timer apply wallpapers identically.
    property string wallScript: "/home/wuhlheide/.config/quickshell/scripts/wallpaper.sh"

    // the wallpaper currently driving the theme (wallpaper.sh state file)
    FileView {
        id: curFile
        path: "/home/wuhlheide/.local/state/quickshell/wallpaper"
        blockLoading: true
        printErrors: false
    }
    readonly property string current: (curFile.text() || "").trim()

    // Run detached: a plain Process would be killed when the picker closes
    // (the LazyLoader destroys this component), aborting awww/matugen mid-run.
    function apply(path) {
        Quickshell.execDetached(["bash", wallScript, "set", path]);
        picker.dismissed();
    }

    function shuffle() {
        Quickshell.execDetached(["bash", wallScript, "random"]);
        picker.dismissed();
    }

    Component.onCompleted: grid.forceActiveFocus()

    FolderListModel {
        id: wallModel
        folder: "file://" + picker.wallDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    // Dim layer; click outside the card to close.
    Rectangle {
        anchors.fill: parent
        color: Colors.shadow
        opacity: 0.35
        MouseArea { anchors.fill: parent; onClicked: picker.dismissed() }
    }

    Rectangle {
        id: card
        width: 860
        height: 560
        anchors.centerIn: parent
        radius: 18
        color: Colors.surface_container
        border.color: Colors.outline_variant
        border.width: 1

        MouseArea { anchors.fill: parent }   // swallow clicks

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Wallpaper  ·  " + wallModel.count + " images"
                    color: Colors.on_surface
                    font { family: "Adwaita Sans"; pixelSize: 16; bold: true }
                }
                Item { Layout.fillWidth: true }
                Item {
                    implicitWidth: shuffleRow.implicitWidth
                    implicitHeight: shuffleRow.implicitHeight
                    Row {
                        id: shuffleRow
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "" // nf-fa-random
                            color: Colors.primary
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Shuffle"
                            color: Colors.primary
                            font { family: "Adwaita Sans"; pixelSize: 13 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.shuffle()
                    }
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                focus: true
                model: wallModel
                cellWidth: width / 3
                cellHeight: cellWidth * 0.6

                Keys.onEscapePressed: picker.dismissed()
                Keys.onReturnPressed: if (currentItem) picker.apply(currentItem.filePath)
                Keys.onEnterPressed:  if (currentItem) picker.apply(currentItem.filePath)

                delegate: Item {
                    required property int index
                    required property string fileName
                    required property string filePath   // model role: absolute path
                    required property url fileUrl        // model role: for Image

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 12
                        clip: true
                        color: Colors.surface_container_high
                        border.width: index === grid.currentIndex ? 3 : 0
                        border.color: Colors.primary

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 320   // downscale; thumbnails only
                            source: fileUrl
                        }

                        // "current" badge on the wallpaper driving the theme
                        Rectangle {
                            visible: filePath === picker.current
                            anchors { top: parent.top; left: parent.left; margins: 8 }
                            width: curLabel.implicitWidth + 14
                            height: 20
                            radius: 10
                            color: Colors.primary
                            Text {
                                id: curLabel
                                anchors.centerIn: parent
                                text: "current"
                                color: Colors.on_primary
                                font { family: "Adwaita Sans"; pixelSize: 10; bold: true }
                            }
                        }

                        Rectangle {   // filename caption strip
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 24
                            color: Colors.shadow
                            opacity: 0.55
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                text: fileName
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: "white"
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: grid.currentIndex = index
                            onClicked: picker.apply(filePath)
                        }
                    }
                }
            }
        }
    }
}
