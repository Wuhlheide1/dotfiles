import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Bar clock (HH:mm). Click to drop down a month calendar. Event sync from
// Google Calendar (read-only ICS) gets wired into eventModel once the user
// provides their private iCal URL.
Item {
    id: root

    property var barWindow
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14

    // month currently shown in the popup; reset to today each time it opens
    property var viewDate: new Date()
    property var today: new Date()

    implicitWidth: clockText.implicitWidth + 8
    implicitHeight: 26

    Text {
        id: clockText
        anchors.centerIn: parent
        text: Qt.formatDateTime(new Date(), "HH:mm")
        color: PopupBus.current === "calendar" ? Colors.primary : Colors.on_surface
        font { family: root.fontFamily; pixelSize: root.fontSize }

        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
                clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
                root.today = new Date()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.viewDate = new Date(); PopupBus.toggle("calendar") }
    }

    // ---------------------------------------------------------------
    // Calendar flyout (fullscreen overlay; click-outside dismisses)
    PanelWindow {
        id: calPopup
        visible: PopupBus.current === "calendar"
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }

        Rectangle {
            id: card
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 12
            width: 300
            height: implicitHeight
            implicitHeight: ccol.implicitHeight + 28
            radius: 16
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            transformOrigin: Item.TopRight
            opacity: calPopup.visible ? 1 : 0
            scale: calPopup.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // swallow inside clicks

            ColumnLayout {
                id: ccol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // --- month navigation header ---
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: ""   // nf-fa-chevron-left
                        color: Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: 13 }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() - 1, 1)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Qt.formatDateTime(root.viewDate, "MMMM yyyy")
                        color: Colors.on_surface
                        font { family: root.fontFamily; pixelSize: 14; bold: true }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewDate = new Date()   // jump back to current month
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: ""   // nf-fa-chevron-right
                        color: Colors.on_surface_variant
                        font { family: root.fontFamily; pixelSize: 13 }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() + 1, 1)
                        }
                    }
                }

                // --- weekday row + day grid (Monday-first) ---
                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    rowSpacing: 3
                    columnSpacing: 0

                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Colors.outline
                            font { family: root.fontFamily; pixelSize: 10; bold: true }
                        }
                    }

                    Repeater {
                        model: 42   // 6 weeks
                        Item {
                            id: cell
                            Layout.fillWidth: true
                            implicitHeight: 30

                            property var cellDate: {
                                var first = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth(), 1)
                                var dow = (first.getDay() + 6) % 7   // Monday=0
                                return new Date(first.getFullYear(), first.getMonth(), 1 - dow + index)
                            }
                            property bool inMonth: cellDate.getMonth() === root.viewDate.getMonth()
                            property bool isToday: cellDate.toDateString() === root.today.toDateString()

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26; radius: 13
                                color: cell.isToday ? Colors.primary : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: cell.cellDate.getDate()
                                color: cell.isToday ? Colors.on_primary
                                     : (cell.inMonth ? Colors.on_surface : Colors.outline)
                                opacity: cell.inMonth ? 1 : 0.35
                                font { family: root.fontFamily; pixelSize: 12; bold: cell.isToday }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.4 }

                // --- upcoming events (populated once Google ICS is wired) ---
                Text {
                    Layout.fillWidth: true
                    visible: eventModel.count === 0
                    text: "No events synced yet"
                    color: Colors.outline
                    horizontalAlignment: Text.AlignHCenter
                    font { family: root.fontFamily; pixelSize: 11 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Repeater {
                        model: ListModel { id: eventModel }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3; height: 14; radius: 2; color: Colors.primary }
                            Text {
                                text: model.time
                                color: Colors.on_surface_variant
                                font { family: root.fontFamily; pixelSize: 11 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: model.title
                                color: Colors.on_surface
                                elide: Text.ElideRight
                                font { family: root.fontFamily; pixelSize: 11 }
                            }
                        }
                    }
                }
            }
        }
    }
}
