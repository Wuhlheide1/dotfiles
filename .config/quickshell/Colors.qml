pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// HAND-WRITTEN — no longer a matugen output. matugen writes the wallpaper-
// derived accent roles to ~/.local/state/quickshell/colors.json (template:
// ~/.config/matugen/templates/colors.json); this singleton watches that file
// and GLIDES every accent to its new value in step with the awww wallpaper
// transition instead of snapping. Because no .qml file changes on a re-theme,
// the shell also no longer hard-reloads on every wallpaper change.
//
// Surfaces, text and lines are FIXED neutral greys — the wallpaper only
// drives the accent roles below. (User preference: matugen for highlights
// only, so the desktop chrome stays calm across wallpapers.)
Singleton {
    id: root

    // Base surfaces (fixed neutral)
    readonly property color background:             "#131315"
    readonly property color on_background:          "#e7e5e8"
    readonly property color surface:                "#131315"
    readonly property color on_surface:             "#e7e5e8"
    readonly property color on_surface_variant:     "#b6b4b9"
    readonly property color surface_container:      "#1c1c1f"
    readonly property color surface_container_high: "#27272b"

    // Accent (wallpaper-derived, animated). The literals are only the
    // pre-first-load fallback — colors.json overrides them immediately.
    property color primary:                "#abcaea"
    property color on_primary:             "#12334c"
    property color primary_container:      "#8eaccb"
    property color on_primary_container:   "#002037"

    property color secondary:              "#bcc8d6"
    property color on_secondary:           "#27313c"
    property color secondary_container:    "#3f4a56"

    property color tertiary:               "#debbe4"

    // Lines / muted (fixed neutral)
    readonly property color outline:                "#8b8991"
    readonly property color outline_variant:        "#3b3a40"

    // State
    property color error:                           "#ffb4ab"
    readonly property color shadow:                 "#000000"

    // The cross-fade. Disabled until after the first load so a shell restart
    // doesn't fade in from the stale fallback literals above.
    property bool ready: false
    Behavior on primary              { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on on_primary           { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on primary_container    { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on on_primary_container { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on secondary            { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on on_secondary         { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on secondary_container  { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on tertiary             { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
    Behavior on error                { enabled: root.ready; ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }

    function apply() {
        var c
        try { c = JSON.parse(accentFile.text() || "") }
        catch (e) { return }   // mid-write / missing — the next change retries
        if (!c || !c.primary) return
        root.primary              = c.primary
        root.on_primary           = c.on_primary
        root.primary_container    = c.primary_container
        root.on_primary_container = c.on_primary_container
        root.secondary            = c.secondary
        root.on_secondary         = c.on_secondary
        root.secondary_container  = c.secondary_container
        root.tertiary             = c.tertiary
        root.error                = c.error
        if (!root.ready) Qt.callLater(() => root.ready = true)
    }

    FileView {
        id: accentFile
        path: "/home/wuhlheide/.local/state/quickshell/colors.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.apply()
    }

    Component.onCompleted: apply()
}
