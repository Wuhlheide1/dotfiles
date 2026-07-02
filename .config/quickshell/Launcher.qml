// Launcher.qml — application launcher (search + arrow keys + Enter).
//
// Improvements over the basic version:
//   - smarter, scored search (matches name / generic name / keywords / exec),
//   - "frecency": apps you launch often float to the top (persisted to disk),
//   - the result list now actually SCROLLS to follow the selection,
//   - robust icons: entries with a missing/unresolvable icon get a clean
//     letter-avatar instead of the broken "missing texture" placeholder.
//
// Loaded on demand from shell.qml via a LazyLoader and toggled with a keybind.

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: launcher

    // Cover the whole screen so we can dim the background and catch click-away.
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Grab the keyboard so we can type into the search box.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:launcher"

    // Emitted when the user dismisses or picks something. The loader listens.
    signal dismissed()

    // --- data -------------------------------------------------------------
    property string query: ""

    // Persisted launch counts: { "<entry id>": count }. Drives "frecency"
    // ordering so your most-used apps come first.
    property var freqMap: ({})

    FileView {
        id: freqFile
        path: Quickshell.cachePath("launcher-frecency.json")
        blockLoading: true   // read synchronously on first access
        printErrors: false   // file won't exist on first run; that's fine
    }

    // Score a single entry against the (lowercased) query. -1 means "no match".
    // Higher tiers = stronger match, so exact/prefix beat buried substrings.
    function score(entry, q) {
        const name = (entry.name || "").toLowerCase();
        const generic = (entry.genericName || "").toLowerCase();
        const comment = (entry.comment || "").toLowerCase();
        const kw = (entry.keywords || []).join(" ").toLowerCase();
        const exec = (entry.execString || "").toLowerCase();

        if (name === q) return 1000;
        if (name.startsWith(q)) return 600;
        if (name.split(/\s+/).some(w => w.startsWith(q))) return 400;
        if (name.includes(q)) return 250;
        if (generic.includes(q) || kw.includes(q)) return 150;
        if (comment.includes(q) || exec.includes(q)) return 60;
        return -1;
    }

    // .values is a plain JS array (same as Hyprland.workspaces.values in the bar).
    readonly property var results: {
        const q = query.toLowerCase().trim();
        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);

        if (q.length === 0) {
            // No query: most-used first, then alphabetical.
            return all.slice().sort((a, b) => {
                const fb = (freqMap[b.id] || 0) - (freqMap[a.id] || 0);
                return fb !== 0 ? fb : a.name.localeCompare(b.name);
            });
        }

        // With a query: score, drop non-matches, then sort by score (+frecency).
        return all
            .map(a => ({ e: a, s: score(a, q) + (freqMap[a.id] || 0) * 5 }))
            .filter(x => x.s >= 0)
            .sort((a, b) => (b.s - a.s) || a.e.name.localeCompare(b.e.name))
            .map(x => x.e);
    }

    property int selected: 0
    onResultsChanged: setSelected(0)

    // Clamp the selection AND scroll the list so it stays visible.
    function setSelected(i) {
        selected = Math.max(0, Math.min(i, results.length - 1));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function run(entry) {
        if (!entry)
            return;
        // Bump frecency and persist before launching.
        freqMap[entry.id] = (freqMap[entry.id] || 0) + 1;
        freqFile.setText(JSON.stringify(freqMap));
        entry.execute();      // launches the .desktop entry
        launcher.dismissed();
    }

    Component.onCompleted: {
        input.forceActiveFocus();
        try { freqMap = JSON.parse(freqFile.text() || "{}"); }
        catch (e) { freqMap = ({}); }
    }

    // Dim layer; clicking it (outside the card) closes the launcher.
    Rectangle {
        anchors.fill: parent
        color: Colors.shadow
        opacity: 0.35
        MouseArea {
            anchors.fill: parent
            onClicked: launcher.dismissed()
        }
    }

    // The launcher card.
    Rectangle {
        id: card
        width: 480
        height: 440
        anchors.centerIn: parent
        radius: 16
        color: Colors.surface_container
        border.color: Colors.outline_variant
        border.width: 1

        // Swallow clicks so they don't fall through to the dim layer.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Search field
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
                    onTextChanged: launcher.query = text

                    // Placeholder
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps…"
                        color: Colors.outline
                        font.pixelSize: 16
                        visible: input.text.length === 0
                    }

                    // Keyboard navigation
                    Keys.onEscapePressed: launcher.dismissed()
                    Keys.onDownPressed:  launcher.setSelected(launcher.selected + 1)
                    Keys.onUpPressed:    launcher.setSelected(launcher.selected - 1)
                    Keys.onReturnPressed: launcher.run(launcher.results[launcher.selected])
                    Keys.onEnterPressed:  launcher.run(launcher.results[launcher.selected])
                }
            }

            // Results
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: launcher.results
                currentIndex: launcher.selected
                spacing: 4

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: list.width
                    height: 48
                    radius: 8
                    color: index === launcher.selected ? Colors.primary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        // Icon with a graceful fallback. iconPath(name, true)
                        // returns "" when the icon can't be resolved, so we draw
                        // a letter-avatar instead of a broken-image placeholder.
                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28

                            property string src: modelData.icon
                                ? Quickshell.iconPath(modelData.icon, true)
                                : ""

                            Image {
                                id: ico
                                anchors.fill: parent
                                asynchronous: true
                                sourceSize.width: 28
                                sourceSize.height: 28
                                source: parent.src
                                visible: parent.src !== "" && status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: !ico.visible
                                radius: 7
                                color: Colors.secondary_container
                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData.name || "?").charAt(0).toUpperCase()
                                    color: Colors.on_surface
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: index === launcher.selected ? Colors.on_primary : Colors.on_surface
                            font.pixelSize: 15
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.selected = index
                        onClicked: launcher.run(modelData)
                    }
                }
            }
        }
    }
}
