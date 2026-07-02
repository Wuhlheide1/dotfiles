import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// Bell button for the bar. Owns the DBus notification server (replaces dunst),
// shows a live unread badge, slides in toasts on arrival, and toggles a
// notification-history flyout when clicked.
Item {
    id: root

    // The bar PanelWindow, used to anchor the flyouts beneath the bar.
    property var barWindow
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14

    readonly property var notifs: server.trackedNotifications
    readonly property int count: notifs ? notifs.values.length : 0

    // Do Not Disturb: still collect notifications in the center, but suppress
    // the on-screen toasts while enabled.
    property bool dnd: false

    implicitWidth: bell.implicitWidth + 8
    implicitHeight: 26

    // --- DBus notification daemon ---
    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: (n) => {
            // Keep it in trackedNotifications so it shows in the center.
            n.tracked = true
            // Slide in a toast that auto-expires — unless Do Not Disturb is on.
            if (root.dnd) return
            toastModel.append({
                summary: n.summary,
                body: n.body,
                appName: n.appName,
                critical: n.urgency === NotificationUrgency.Critical,
                expireAt: Date.now() + (n.urgency === NotificationUrgency.Critical ? 10000 : 5000)
            })
        }
    }

    // --- Bell glyph + unread badge ---
    Text {
        id: bell
        anchors.centerIn: parent
        // bell-slash while DND; otherwise solid bell when unread, outline when not
        text: root.dnd ? "\uf1f6" : (root.count > 0 ? "\uf0f3" : "\uf0a2")
        color: root.dnd ? Colors.outline : (root.count > 0 ? Colors.primary : Colors.on_surface)
        opacity: root.dnd ? 0.8 : (root.count > 0 ? 1.0 : 0.7)
        font { family: root.fontFamily; pixelSize: root.fontSize + 1 }
    }

    Rectangle {
        visible: root.count > 0
        width: 14; height: 14; radius: 7
        color: Colors.error
        anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -2 }
        Text {
            anchors.centerIn: parent
            text: root.count > 9 ? "9+" : root.count
            color: Colors.background
            font { family: root.fontFamily; pixelSize: 9; bold: true }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
            if (m.button === Qt.RightButton) {
                // Right-click: clear all
                for (var i = root.notifs.values.length - 1; i >= 0; i--)
                    root.notifs.values[i].dismiss()
            } else {
                PopupBus.toggle("notif")
            }
        }
    }

    // ---------------------------------------------------------------
    // Toast stack (top-right, under the bar)
    // ---------------------------------------------------------------
    ListModel { id: toastModel }

    Timer {
        interval: 500; repeat: true
        running: toastModel.count > 0
        onTriggered: {
            var now = Date.now()
            for (var i = toastModel.count - 1; i >= 0; i--)
                if (toastModel.get(i).expireAt <= now) toastModel.remove(i)
        }
    }

    // Hide the on-screen toasts while the notification center is open — the
    // history list already shows everything, so stacked toasts are redundant.
    Connections {
        target: PopupBus
        function onCurrentChanged() {
            if (PopupBus.current === "notif") toastModel.clear()
        }
    }

    PopupWindow {
        id: toastPopup
        color: "transparent"
        visible: toastModel.count > 0 && PopupBus.current !== "notif"
        anchor.window: root.barWindow
        anchor.rect.x: root.barWindow ? root.barWindow.width - width - 12 : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + 6 : 46
        implicitWidth: 360
        implicitHeight: toastCol.implicitHeight

        Column {
            id: toastCol
            width: parent.width
            spacing: 8

            Repeater {
                model: toastModel
                Rectangle {
                    width: toastCol.width
                    implicitHeight: tcontent.implicitHeight + 20
                    radius: 12
                    color: Colors.surface_container_high
                    border.color: model.critical ? Colors.error : Colors.outline_variant
                    border.width: 1

                    ColumnLayout {
                        id: tcontent
                        anchors { fill: parent; margins: 10 }
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: (model.appName ? model.appName + " — " : "") + model.summary
                            color: Colors.on_surface
                            elide: Text.ElideRight
                            font { family: root.fontFamily; pixelSize: 13; bold: true }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: model.body.length > 0
                            text: model.body
                            color: Colors.on_surface_variant
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font { family: root.fontFamily; pixelSize: 12 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { toastModel.remove(index); PopupBus.open("notif") }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Notification center / history flyout (fullscreen overlay so clicking
    // outside the card reliably dismisses it).
    // ---------------------------------------------------------------
    PanelWindow {
        id: centerPopup
        visible: PopupBus.current === "notif"
        color: "transparent"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 12
            width: 380
            height: 440
            radius: 16
            color: Colors.surface_container
            border.color: Colors.outline_variant
            border.width: 1

            // subtle drop-in when the center opens
            transformOrigin: Item.TopRight
            opacity: centerPopup.visible ? 1 : 0
            scale: centerPopup.visible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            // swallow clicks inside the card
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: "Notifications"
                        color: Colors.on_surface
                        font { family: root.fontFamily; pixelSize: 15; bold: true }
                    }
                    Item { Layout.fillWidth: true }

                    // Do Not Disturb toggle (bell-slash; highlighted when active)
                    RowLayout {
                        spacing: 5
                        Text {
                            text: "\uf1f6" // nf-fa-bell-slash
                            color: root.dnd ? Colors.primary : Colors.outline
                            font { family: root.fontFamily; pixelSize: 13 }
                        }
                        Text {
                            text: "DND"
                            color: root.dnd ? Colors.primary : Colors.outline
                            font { family: root.fontFamily; pixelSize: 12; bold: root.dnd }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dnd = !root.dnd
                        }
                    }

                    Text {
                        visible: root.count > 0
                        text: "Clear all"
                        color: Colors.primary
                        font { family: root.fontFamily; pixelSize: 12 }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                for (var i = root.notifs.values.length - 1; i >= 0; i--)
                                    root.notifs.values[i].dismiss()
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.count === 0
                    text: "All caught up"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Colors.outline
                    font { family: root.fontFamily; pixelSize: 13 }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.count > 0
                    clip: true
                    spacing: 8
                    model: root.notifs

                    delegate: Rectangle {
                        width: ListView.view.width
                        implicitHeight: ncontent.implicitHeight + 20
                        radius: 12
                        color: Colors.surface_container_high
                        border.color: modelData.urgency === NotificationUrgency.Critical
                                      ? Colors.error : "transparent"
                        border.width: 1

                        ColumnLayout {
                            id: ncontent
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: (modelData.appName ? modelData.appName + " — " : "") + modelData.summary
                                    color: Colors.on_surface
                                    elide: Text.ElideRight
                                    font { family: root.fontFamily; pixelSize: 13; bold: true }
                                }
                                Text {
                                    text: "" // nf-fa-times
                                    color: Colors.outline
                                    font { family: root.fontFamily; pixelSize: 12 }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.dismiss()
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: modelData.body.length > 0
                                text: modelData.body
                                color: Colors.on_surface_variant
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                font { family: root.fontFamily; pixelSize: 12 }
                            }
                        }
                    }
                }
            }
        }
    }
}
