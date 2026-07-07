import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Bell button for the bar. Owns the DBus notification server (replaces dunst),
// shows a live unread badge, slides in toasts on arrival, and toggles a
// notification-history flyout when clicked.
Item {
    id: root

    // The bar PanelWindow, used to anchor the flyouts beneath the bar.
    property var barWindow
    property string fontFamily: "Adwaita Sans"
    property int fontSize: 14

    readonly property var notifs: server.trackedNotifications

    // Do Not Disturb: still collect notifications in the center, but suppress
    // the on-screen toasts while enabled. Manual toggle OR automatic while
    // screen-recording / a fullscreen window is up (games, videos).
    property bool dndManual: false
    property var recorder: null   // the bar's Recorder item (wf-recorder poll)
    readonly property bool autoRec: recorder ? recorder.recording : false
    property bool autoFs: false
    readonly property bool dnd: dndManual || autoRec || autoFs

    // Event-driven fullscreen tracking: relevant Hyprland socket2 events
    // trigger ONE hyprctl check (no constant polling).
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name === "fullscreen" || e.name === "closewindow"
                    || e.name === "workspacev2" || e.name === "focusedmon")
                fsCheck.running = true
        }
    }
    Process {
        id: fsCheck
        command: ["sh", "-c", "hyprctl activeworkspace -j | grep -q '\"hasfullscreen\": true'"]
        onExited: (code) => root.autoFs = (code === 0)
    }
    Component.onCompleted: {
        fsCheck.running = true
        try {
            var d = JSON.parse(histFile.text() || "{}")
            root.lastSeen = d.lastSeen || 0
            // image:// urls reference the previous process's image provider —
            // dead after a restart, so drop them (appIcon fallback still works)
            root.history = (d.entries || []).map(e => Object.assign({}, e, { image: "" }))
        } catch (e) { root.history = [] }
        root.histTick++
    }

    implicitWidth: bell.implicitWidth + 8
    implicitHeight: 26

    // --- DBus notification daemon ---
    NotificationServer {
        id: server
        // survive config hot-reloads — losing the whole history on every
        // theme tweak made the center look like it "forgot" notifications
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: (n) => {
            // Keep it in trackedNotifications so its actions stay invokable.
            n.tracked = true
            // Log it to the persistent history (newest first, capped).
            root.history = [{
                hid: (++root.hidSeq) + "-" + Date.now(),
                nid: n.id,
                summary: n.summary,
                body: n.body,
                appName: n.appName,
                appIcon: n.appIcon ?? "",
                image: n.image ?? "",
                critical: n.urgency === NotificationUrgency.Critical,
                time: Date.now()
            }].concat(root.history).slice(0, 100)
            root.histChanged()
            // Slide in a toast that auto-expires — unless Do Not Disturb is on.
            // Critical urgency (timers, alarms, genuinely important things)
            // always punches through DND: fullscreen video shouldn't eat a
            // ringing timer (user request, 2026-07-07).
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) return
            // honour the sender's requested timeout when it gives one (ms);
            // fall back to 5s (10s for critical)
            var ttl = n.expireTimeout > 0 ? n.expireTimeout
                    : (n.urgency === NotificationUrgency.Critical ? 10000 : 5000)
            toastModel.append({
                nid: n.id,
                summary: n.summary,
                body: n.body,
                appName: n.appName,
                appIcon: n.appIcon ?? "",
                image: n.image ?? "",
                critical: n.urgency === NotificationUrgency.Critical,
                expireAt: Date.now() + ttl
            })
        }
    }

    // ---------------------------------------------------------------
    // Persistent history: a JSON log that survives shell restarts is the
    // single source of truth for the center. Live Notification objects are
    // only consulted for their action buttons (nid lookups).
    // File shape: { lastSeen: <ms>, entries: [{hid,nid,summary,body,appName,
    //               appIcon,image,critical,time}] } — newest first, cap 100.
    // ---------------------------------------------------------------
    property var history: []
    property double lastSeen: 0
    property int histTick: 0     // bumped after every history mutation
    property int hidSeq: 0

    FileView {
        id: histFile
        path: "/home/wuhlheide/.local/state/quickshell/notifications.json"
        blockLoading: true
        printErrors: false
    }

    Timer {
        id: saveTimer
        interval: 400   // debounce bursts of notifications into one write
        onTriggered: histFile.setText(JSON.stringify(
            { lastSeen: root.lastSeen, entries: root.history }))
    }
    function histChanged() { root.histTick++; saveTimer.restart() }

    readonly property int count: { root.histTick; return root.history.length }
    readonly property int unread: {
        root.histTick
        return root.history.filter(e => e.time > root.lastSeen).length
    }

    property int ageTick: 0
    Timer {
        interval: 30000; repeat: true; triggeredOnStart: true
        running: PopupBus.current === "notif"
        onTriggered: root.ageTick++
    }
    function notifById(id) {
        return root.notifs ? (root.notifs.values.find(n => n.id === id) ?? null) : null
    }
    function fmtAge(t) {
        root.ageTick   // re-evaluate while the center is open
        if (!t) return ""
        var s = (Date.now() - t) / 1000
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    function removeEntry(hid) {
        var e = root.history.find(x => x.hid === hid)
        if (!e) return
        var n = root.notifById(e.nid)
        if (n) n.dismiss()
        root.history = root.history.filter(x => x.hid !== hid)
        root.histChanged()
    }
    function clearApp(app) {
        root.history.filter(x => (x.appName || "?") === app).forEach(x => {
            var n = root.notifById(x.nid)
            if (n) n.dismiss()
        })
        root.history = root.history.filter(x => (x.appName || "?") !== app)
        root.histChanged()
    }
    function clearAll() {
        for (var i = root.notifs.values.length - 1; i >= 0; i--)
            root.notifs.values[i].dismiss()
        root.history = []
        root.histChanged()
    }
    // history-entry click: default action if the notification is still live
    // this daemon session, else just focus the app; either way retire it
    function activateEntry(e) {
        var n = root.notifById(e.nid)
        if (n) root.activate(n)
        else root.focusApp(e.appName)
        root.history = root.history.filter(x => x.hid !== e.hid)
        root.histChanged()
    }

    // --- grouping: one sender stacking up collapses under an app header ---
    property var expandedApps: ({})
    function toggleExpand(app) {
        expandedApps[app] = !expandedApps[app]
        root.histTick++
    }
    // free-text filter over the history (search field in the center)
    property string histQuery: ""

    // rows[] mixes { kind:"entry", e, grouped } / { kind:"header", app, count }
    // / { kind:"more", app, count }; groups sit at their newest entry's spot
    readonly property var rows: {
        root.histTick
        const h = root.history
        // while searching: flat, ungrouped matches
        if (root.histQuery !== "") {
            const f = root.histQuery
            return h.filter(e => (e.summary || "").toLowerCase().includes(f)
                    || (e.body || "").toLowerCase().includes(f)
                    || (e.appName || "").toLowerCase().includes(f))
                .map(e => ({ kind: "entry", e: e, grouped: false }))
        }
        const out = []
        const seen = {}
        for (const e of h) {
            const app = e.appName || "?"
            if (seen[app]) continue
            seen[app] = true
            const group = h.filter(x => (x.appName || "?") === app)
            if (group.length === 1) {
                out.push({ kind: "entry", e: group[0], grouped: false })
                continue
            }
            out.push({ kind: "header", app: app, count: group.length })
            const lim = root.expandedApps[app] ? group.length : 3
            group.slice(0, lim).forEach(x => out.push({ kind: "entry", e: x, grouped: true }))
            if (group.length > lim)
                out.push({ kind: "more", app: app, count: group.length - lim })
        }
        return out
    }

    // The "default" action is what the sender wants a plain click to do (e.g.
    // Vesktop focuses the chat the message came from). Some apps offer exactly
    // one unnamed action instead — treat that as the default too.
    function defaultAction(n) {
        var acts = n?.actions ?? []
        var d = acts.find(a => a.identifier === "default")
        return d ?? (acts.length === 1 ? acts[0] : null)
    }

    // Wayland focus-stealing prevention means most apps can't raise their own
    // window from a notification action, so focus it ourselves. App names that
    // don't match their window class get mapped; the rest try lowercased.
    readonly property var classMap: ({ "discord": "vesktop", "brave": "brave-browser" })
    function focusApp(appName) {
        if (!appName) return
        var k = appName.toLowerCase().replace(/\s+/g, "-")
        var cls = root.classMap[k] ?? k
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "class:^" + cls + "$"])
    }

    // Plain click on a toast or history entry: run the sender's default
    // action, bring its window forward, and retire the notification.
    function activate(n) {
        if (!n) return
        var act = root.defaultAction(n)
        if (act) act.invoke()
        root.focusApp(n.appName)
        n.dismiss()
    }

    // App icon / sender avatar with a letter-avatar fallback. Used by both the
    // toasts and the history list.
    component NotifIcon: ClippingRectangle {
        id: nIcon
        property string image: ""
        property string icon: ""
        property string appName: ""
        // icon may be a theme name OR a file path (screenshot.sh sends -i <png>)
        readonly property string src: image !== "" ? image
            : icon.startsWith("file://") ? icon
            : icon.startsWith("/") ? "file://" + icon
            : (icon !== "" ? Quickshell.iconPath(icon, true) : "")
        implicitWidth: 30
        implicitHeight: 30
        radius: 9
        color: nImg.visible ? "transparent" : Colors.secondary_container
        Image {
            id: nImg
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize { width: 60; height: 60 }
            source: nIcon.src
            visible: nIcon.src !== "" && status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !nImg.visible
            text: (nIcon.appName || "?").charAt(0).toUpperCase()
            color: Colors.on_surface
            font { family: root.fontFamily; pixelSize: 14; bold: true }
        }
    }

    // --- Bell glyph + unread badge ---
    // CLI access: qs ipc call notif toggle
    IpcHandler {
        target: "notif"
        function toggle(): void { PopupBus.toggle("notif") }
    }

    Text {
        id: bell
        anchors.centerIn: parent
        // bell-slash while DND; otherwise solid bell when unread, outline when not
        text: root.dnd ? "\uf1f6" : (root.unread > 0 ? "\uf0f3" : "\uf0a2")
        color: root.dnd ? Colors.outline : (root.unread > 0 ? Colors.primary : Colors.on_surface)
        opacity: root.dnd ? 0.8 : (root.unread > 0 ? 1.0 : 0.7)
        font { family: "JetBrainsMono Nerd Font"; pixelSize: root.fontSize + 1 }
    }

    Rectangle {
        visible: root.unread > 0
        width: 14; height: 14; radius: 7
        color: Colors.error
        anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -2 }
        Text {
            anchors.centerIn: parent
            text: root.unread > 9 ? "9+" : root.unread
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
                root.clearAll()   // right-click: clear history + live
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

    // Opening the center clears the toasts (the history shows everything)
    // and marks everything read — the bell badge only counts what arrived
    // since the center was last opened.
    Connections {
        target: PopupBus
        function onCurrentChanged() {
            if (PopupBus.current === "notif") {
                toastModel.clear()
                root.lastSeen = Date.now()
                root.histChanged()
            } else {
                histSearch.text = ""   // fresh search on next open
            }
        }
    }

    // Own Overlay-layer surface (NOT a PopupWindow parented to the bar): popups
    // inherit the bar's Top layer, which fullscreen windows cover. Overlay
    // renders above fullscreen, so toasts stay visible while gaming.
    PanelWindow {
        id: toastPopup
        color: "transparent"
        visible: toastModel.count > 0 && PopupBus.current !== "notif"
        exclusiveZone: 0
        screen: root.barWindow ? root.barWindow.screen : null
        anchors { top: true; right: true }
        margins { top: 6; right: 12 }
        implicitWidth: 360
        implicitHeight: Math.max(1, toastCol.implicitHeight)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Column {
            id: toastCol
            width: parent.width
            spacing: 8

            Repeater {
                model: toastModel
                Rectangle {
                    width: toastCol.width
                    implicitHeight: tcontent.implicitHeight + 20
                    radius: 16
                    color: Colors.surface_container_high
                    border.color: model.critical ? Colors.error : Colors.outline_variant
                    border.width: 1

                    // hovering pauses the expiry so a long body can be read;
                    // on leave the toast gets a short grace period instead
                    HoverHandler {
                        onHoveredChanged: toastModel.setProperty(index, "expireAt",
                            hovered ? Number.MAX_SAFE_INTEGER : Date.now() + 2500)
                    }

                    RowLayout {
                        id: tcontent
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        NotifIcon {
                            Layout.alignment: Qt.AlignTop
                            image: model.image
                            icon: model.appIcon
                            appName: model.appName
                        }

                        ColumnLayout {
                        Layout.fillWidth: true
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
                        // action buttons the app offered (Reply / Open / Undo…)
                        RowLayout {
                            id: toastActions
                            readonly property var acts: root.notifById(model.nid)?.actions ?? []
                            visible: acts.length > 0
                            Layout.topMargin: 4
                            spacing: 6
                            Repeater {
                                model: toastActions.acts
                                Rectangle {
                                    id: toastActBtn
                                    required property var modelData
                                    required property int index
                                    implicitWidth: taText.implicitWidth + 18
                                    implicitHeight: 24
                                    radius: 9
                                    color: taArea.containsMouse ? Colors.primary : Colors.surface_container
                                    border.color: Colors.outline_variant
                                    border.width: taArea.containsMouse ? 0 : 1
                                    Text {
                                        id: taText
                                        anchors.centerIn: parent
                                        text: toastActBtn.modelData.text || "Open"
                                        color: taArea.containsMouse ? Colors.on_primary : Colors.on_surface
                                        font { family: root.fontFamily; pixelSize: 11 }
                                    }
                                    MouseArea {
                                        id: taArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: toastActBtn.modelData.invoke()
                                    }
                                }
                            }
                        }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        // sit under the content so the action buttons win clicks
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        // left: act on it (default action + focus the app);
                        // middle: dismiss without acting
                        onClicked: (m) => {
                            var n = root.notifById(model.nid)
                            if (m.button === Qt.LeftButton) root.activate(n)
                            else if (n) n.dismiss()
                            toastModel.remove(index)
                        }
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
        // OnDemand (not None): lets Esc close the center once it has focus,
        // without the hard grab an Exclusive layer would put on the keyboard
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        MouseArea { anchors.fill: parent; onClicked: PopupBus.close() }
        Item { focus: true; Keys.onEscapePressed: PopupBus.close() }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 12
            width: 380
            height: 440
            radius: 18
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
                anchors { fill: parent; margins: 17 }
                spacing: 12

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
                    Item {
                        implicitWidth: dndRow.implicitWidth
                        implicitHeight: dndRow.implicitHeight
                        Row {
                            id: dndRow
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf1f6" // nf-fa-bell-slash
                                color: root.dnd ? Colors.primary : Colors.outline
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                // show why it's on when it wasn't turned on by hand
                                text: root.dnd && !root.dndManual
                                    ? "DND · " + (root.autoRec ? "recording" : "fullscreen")
                                    : "DND"
                                color: root.dnd ? Colors.primary : Colors.outline
                                font { family: root.fontFamily; pixelSize: 12; bold: root.dnd }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dndManual = !root.dndManual
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
                            onClicked: root.clearAll()
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Colors.outline_variant; opacity: 0.35 }

                // search — only worth screen space once the history piles up
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.count >= 8
                    implicitHeight: 30
                    radius: 10
                    color: Colors.surface_container_high
                    TextInput {
                        id: histSearch
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Colors.on_surface
                        font { family: root.fontFamily; pixelSize: 12 }
                        onTextChanged: root.histQuery = text.toLowerCase().trim()
                        Keys.onEscapePressed: PopupBus.close()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: histSearch.text.length === 0
                            text: "Search notifications…"
                            color: Colors.outline
                            font { family: root.fontFamily; pixelSize: 12 }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.count === 0 || root.rows.length === 0
                    text: root.count === 0 ? "All caught up" : "No matches"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Colors.outline
                    font { family: root.fontFamily; pixelSize: 13 }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.rows.length > 0
                    clip: true
                    spacing: 8
                    model: root.rows

                    delegate: Loader {
                        id: rowLoader
                        required property var modelData
                        readonly property var row: modelData
                        width: ListView.view.width
                        sourceComponent: row.kind === "header" ? headerComp
                                       : row.kind === "more" ? moreComp : entryComp

                        // --- group header: app name + count; click collapses/expands ---
                        Component {
                            id: headerComp
                            Item {
                                implicitHeight: 22
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleExpand(rowLoader.row.app)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8
                                    Text {
                                        text: rowLoader.row.app
                                        color: Colors.on_surface
                                        font { family: root.fontFamily; pixelSize: 12; bold: true }
                                    }
                                    Rectangle {
                                        implicitWidth: cntText.implicitWidth + 12
                                        implicitHeight: 16
                                        radius: 8
                                        color: Colors.surface_container_high
                                        Text {
                                            id: cntText
                                            anchors.centerIn: parent
                                            text: rowLoader.row.count
                                            color: Colors.on_surface_variant
                                            font { family: root.fontFamily; pixelSize: 10 }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "clear"
                                        color: Colors.outline
                                        font { family: root.fontFamily; pixelSize: 11 }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.clearApp(rowLoader.row.app)
                                        }
                                    }
                                }
                            }
                        }

                        // --- "N more…" expander under a collapsed group ---
                        Component {
                            id: moreComp
                            Item {
                                implicitHeight: 20
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleExpand(rowLoader.row.app)
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowLoader.row.count + " more\u2026"
                                    color: Colors.primary
                                    font { family: root.fontFamily; pixelSize: 11 }
                                }
                            }
                        }

                        // --- one notification card (live or restored) ---
                        Component {
                            id: entryComp
                            Rectangle {
                                implicitHeight: ncontent.implicitHeight + 20
                                radius: 14
                                color: Colors.surface_container_high
                                border.color: rowLoader.row.e.critical ? Colors.error : "transparent"
                                border.width: 1

                                // body click acts on it (default action / focus);
                                // sits under the content so \u2715/actions win clicks
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.activateEntry(rowLoader.row.e); PopupBus.close() }
                                }

                                RowLayout {
                                    id: ncontent
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                                    spacing: 10

                                    NotifIcon {
                                        Layout.alignment: Qt.AlignTop
                                        // the header already identifies the app
                                        visible: !rowLoader.row.grouped
                                        image: rowLoader.row.e.image || ""
                                        icon: rowLoader.row.e.appIcon || ""
                                        appName: rowLoader.row.e.appName || ""
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                Layout.fillWidth: true
                                                text: rowLoader.row.grouped
                                                    ? rowLoader.row.e.summary
                                                    : ((rowLoader.row.e.appName ? rowLoader.row.e.appName + " \u2014 " : "") + rowLoader.row.e.summary)
                                                color: Colors.on_surface
                                                elide: Text.ElideRight
                                                font { family: root.fontFamily; pixelSize: 13; bold: true }
                                            }
                                            Text {
                                                text: root.fmtAge(rowLoader.row.e.time)
                                                color: Colors.outline
                                                font { family: root.fontFamily; pixelSize: 10 }
                                            }
                                            Text {
                                                text: "\uf00d" // nf-fa-times
                                                color: Colors.outline
                                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -6
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.removeEntry(rowLoader.row.e.hid)
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: (rowLoader.row.e.body || "").length > 0
                                            text: rowLoader.row.e.body || ""
                                            color: Colors.on_surface_variant
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 4
                                            elide: Text.ElideRight
                                            font { family: root.fontFamily; pixelSize: 12 }
                                        }
                                        // action buttons, only while the sender's
                                        // notification is still live this session
                                        RowLayout {
                                            id: histActions
                                            readonly property var acts: root.notifById(rowLoader.row.e.nid)?.actions ?? []
                                            visible: acts.length > 0
                                            Layout.topMargin: 4
                                            spacing: 6
                                            Repeater {
                                                model: histActions.acts
                                                Rectangle {
                                                    id: histActBtn
                                                    required property var modelData
                                                    implicitWidth: haText.implicitWidth + 18
                                                    implicitHeight: 24
                                                    radius: 9
                                                    color: haArea.containsMouse ? Colors.primary : Colors.surface_container
                                                    border.color: Colors.outline_variant
                                                    border.width: haArea.containsMouse ? 0 : 1
                                                    Text {
                                                        id: haText
                                                        anchors.centerIn: parent
                                                        text: histActBtn.modelData.text || "Open"
                                                        color: haArea.containsMouse ? Colors.on_primary : Colors.on_surface
                                                        font { family: root.fontFamily; pixelSize: 11 }
                                                    }
                                                    MouseArea {
                                                        id: haArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: histActBtn.modelData.invoke()
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
        }
    }
}
