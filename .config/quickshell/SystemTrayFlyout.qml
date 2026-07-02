import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

// Chevron button for the bar. Toggles a flyout containing the StatusNotifier
// (system tray) icons. Left-click an icon = activate, right-click = its menu.
Item {
    id: root

    property var barWindow
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14
    // Driven by the shared coordinator so only one bar menu is open at a time.
    readonly property bool open: PopupBus.current === "tray"

    readonly property int count: SystemTray.items ? SystemTray.items.values.length : 0

    implicitWidth: chevron.implicitWidth + 8
    implicitHeight: 26

    Text {
        id: chevron
        anchors.centerIn: parent
        // nf-fa-chevron-up when open, chevron-down when closed
        text: root.open ? "" : ""
        color: root.open ? Colors.primary : Colors.on_surface
        opacity: 0.8
        font { family: root.fontFamily; pixelSize: root.fontSize - 1 }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: PopupBus.toggle("tray")
    }

    // Fullscreen overlay so clicking outside the flyout reliably dismisses it.
    PanelWindow {
        id: trayPopup
        visible: root.open
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }

        Rectangle {
            id: trayBg
            anchors.top: parent.top
            anchors.topMargin: 6
            // Centre the flyout under the tray button (clamped on-screen) rather
            // than pinning it to the screen's right edge. root lives in the bar
            // window, which shares the overlay's left origin, so window-relative
            // x lines up between the two surfaces.
            x: {
                var c = root.mapToItem(null, root.width / 2, 0).x
                return Math.max(8, Math.min(c - width / 2, trayPopup.width - width - 8))
            }
            width: implicitWidth
            height: implicitHeight
            implicitWidth: Math.max(140, trayRow.implicitWidth + 20)
            implicitHeight: 52
            radius: 14
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            // subtle drop-in when the flyout opens
            transformOrigin: Item.Top
            opacity: trayPopup.visible ? 1 : 0
            scale: trayPopup.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            // swallow clicks inside the flyout
            MouseArea { anchors.fill: parent }

            Text {
                anchors.centerIn: parent
                visible: root.count === 0
                text: "No tray items"
                color: Colors.outline
                font { family: root.fontFamily; pixelSize: 12 }
            }

            RowLayout {
                id: trayRow
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: SystemTray.items

                    // hover-highlight pill around each icon
                    Rectangle {
                        id: cell
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 10
                        color: cellArea.containsMouse ? Colors.surface_container_high : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Image {
                            anchors.centerIn: parent
                            width: 22; height: 22
                            source: modelData.icon
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            sourceSize.width: 22
                            sourceSize.height: 22
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => {
                                if (m.button === Qt.RightButton && modelData.hasMenu) {
                                    // coords relative to the (now fullscreen) window
                                    var p = mapToItem(null, m.x, m.y)
                                    modelData.display(trayPopup, p.x, p.y)
                                } else {
                                    modelData.activate()
                                    PopupBus.close()
                                }
                            }
                        }

                        // tooltip with the item's title on hover
                        Rectangle {
                            visible: cellArea.containsMouse && tipText.text.length > 0
                            anchors.top: parent.bottom
                            anchors.topMargin: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: tipText.implicitWidth + 14
                            height: tipText.implicitHeight + 8
                            radius: 6
                            color: Colors.surface_container_high
                            border.color: Colors.outline_variant
                            border.width: 1
                            Text {
                                id: tipText
                                anchors.centerIn: parent
                                text: modelData.tooltipTitle || modelData.title || modelData.id || ""
                                color: Colors.on_surface
                                font { family: root.fontFamily; pixelSize: 11 }
                            }
                        }
                    }
                }
            }
        }
    }
}
