pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Caelestia's live palette. scheme.json is rewritten on every wallpaper /
// scheme change, so the overlay re-themes itself along with the shell.
Singleton {
    id: root

    property var c: ({})

    function col(name: string, fallback: string): color {
        return c[name] ? "#" + c[name] : fallback;
    }

    readonly property color primary: col("primary", "#b0c8ec")
    readonly property color textOnPrimary: col("onPrimary", "#29425f")
    readonly property color surface: col("surfaceContainer", "#161a1f")
    readonly property color surfaceHigh: col("surfaceContainerHigh", "#1c2026")
    readonly property color surfaceHighest: col("surfaceContainerHighest", "#21262d")
    readonly property color text: col("onSurface", "#e2e5ef")
    readonly property color textVariant: col("onSurfaceVariant", "#a7abb4")
    readonly property color outline: col("outlineVariant", "#444850")
    readonly property color scrim: col("scrim", "#000000")
    readonly property color error: col("error", "#ffb4ab")
    readonly property color tertiary: col("tertiary", "#e1d7ff")

    // Vivid accents for the glow, taken from the scheme's hues (the scheme's
    // own colours are pastel, which reads flat as light). Primary -> tertiary
    // -> one step further round the wheel, so it follows the wallpaper.
    function hue(c: color): real {
        return Math.max(0, c.hslHue);
    }
    readonly property color accent1: Qt.hsla(hue(primary), 0.9, 0.66, 1)
    readonly property color accent2: Qt.hsla(hue(tertiary), 0.9, 0.7, 1)
    readonly property color accent3: Qt.hsla((hue(tertiary) + 0.1) % 1, 0.85, 0.72, 1)

    // Caelestia's defaults (appearance.font.family.*)
    readonly property string sans: "Rubik"
    readonly property string mono: "CaskaydiaCove NF"
    readonly property string icons: "Material Symbols Rounded"

    // Material 3 "emphasized" — the curve Caelestia animates with
    readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
    readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/caelestia/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.c = JSON.parse(text()).colours ?? {};
            } catch (e) {
                console.warn("circle: could not parse scheme.json", e);
            }
        }
    }
}
