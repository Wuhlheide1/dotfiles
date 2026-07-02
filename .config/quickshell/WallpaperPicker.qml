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

    // Build the shell command for a chosen wallpaper. Edit here to swap backend.
    // awww gives a nice animated transition; matugen re-themes everything.
    function setCmd(path) {
        // --prefer is required when matugen runs without a terminal (as it does
        // from here). 'lightness' picks the lightest dominant color, which varies
        // per wallpaper; 'saturation' tended to grab the same red/pink in every
        // image, making different wallpapers look identically themed.
        return "awww img '" + path + "' --transition-type grow --transition-fps 60 "
             + "&& matugen image '" + path + "' --prefer lightness";
    }

    // Run detached: a plain Process would be killed when the picker closes
    // (the LazyLoader destroys this component), aborting awww/matugen mid-run.
    function apply(path) {
        Quickshell.execDetached(["sh", "-c", setCmd(path)]);
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
        radius: 16
        color: Colors.surface_container
        border.color: Colors.outline_variant
        border.width: 1

        MouseArea { anchors.fill: parent }   // swallow clicks

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "Wallpaper  ·  " + wallModel.count + " images"
                color: Colors.on_surface
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 16; bold: true }
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
                        radius: 10
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
