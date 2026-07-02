# Quickshell, by example — your config

A practical guide to working with **Quickshell** (you're on 0.3.0), written around
*your* setup: `~/.config/quickshell/` with `shell.qml`, `NumberToKanji.qml`,
`Colors.qml`, and `Launcher.qml`, driven by Hyprland (configured in Lua).

## Contents
1. [Mental model](#1-mental-model)
2. [Running & debugging](#2-running--debugging) — the single most useful skill
3. [Anatomy of your `shell.qml`](#3-anatomy-of-your-shellqml)
4. [Reactive data: bindings, `Timer`, `Process`](#4-reactive-data-bindings-timer-process)
5. [Theming with matugen](#5-theming-with-matugen)
6. [Adding a bar module](#6-adding-a-bar-module)
7. [Reusable components & singletons](#7-reusable-components--singletons)
8. [Popups (`PopupWindow`)](#8-popups-popupwindow)
9. [The app launcher](#9-the-app-launcher)
10. [Multi-monitor](#10-multi-monitor)
11. [Gotchas you already hit (and will hit)](#11-gotchas)
12. [Reference](#12-reference)

---

## 1. Mental model

Quickshell is **QML driving Wayland surfaces**. You don't write a "bar program";
you declare *windows* and what's inside them, and Quickshell renders them as
`wlr-layer-shell` surfaces (bars, popups, launchers, lock screens…).

Three ideas do 90% of the work:

- **Declarative tree.** Everything is a nested tree of *items* (`Rectangle`,
  `Text`, `RowLayout`…). You describe *what* things are, not *how* to paint them.
- **Property bindings.** `text: kanji.numberToKanji(index + 1)` isn't a one-time
  assignment — it's a *binding*. When anything on the right changes, the left
  updates automatically. This is the heart of QML. Your whole workspace-color
  logic is just bindings reacting to `Hyprland.focusedWorkspace`.
- **Files are types.** Any `PascalCase.qml` file in the directory is automatically
  usable as a type by its name. `NumberToKanji.qml` → `NumberToKanji { }`.
  `Colors.qml` (a singleton) → `Colors.primary`. No imports needed for siblings.

**Entry point:** `~/.config/quickshell/shell.qml` is the "default" config. Run with
`qs`. (Other configs live in subdirs: `~/.config/quickshell/foo/shell.qml` → `qs -c foo`.)

**Hot reload:** Quickshell watches your files. Save → it reloads instantly. You
almost never restart it.

---

## 2. Running & debugging

This is the skill that makes everything else easy. The CLI is `qs`:

```sh
qs                 # run the default config (foreground)
qs -d              # run detached (daemonized)
qs log             # *** print logs of the running instance ***
qs list            # list running instances
qs kill            # kill instances
qs ipc ...         # talk to a running instance (see §9)
```

**`qs log` is your best friend.** When the bar "breaks" (disappears, wrong colors,
nothing happens), read it. Quickshell prints exactly where:

```
ERROR: caused by @Colors.qml[34:29]: Cannot assign a value to a signal ...
WARN  scene: @shell.qml[58:21]: Unable to assign [undefined] to QColor
```

- `@file[line:col]` points at the offending spot.
- `ERROR` = config failed to load (bar gone). Fix and save; it reloads.
- `WARN scene: ... [undefined] to QColor` *at load only* is usually a benign
  transient: a binding referencing the `Colors` singleton evaluated a tick before
  the singleton finished initializing. If it doesn't recur when you interact, ignore it.

Tip: keep a terminal open with logs streaming while you edit. Run `qs log` after each
change, or run `qs` in the foreground in a spare terminal.

---

## 3. Anatomy of your `shell.qml`

```qml
PanelWindow {                       // a layer-shell window…
    anchors { top: true; left: true; right: true }   // …pinned across the top
    implicitHeight: 40
    color: Colors.background

    NumberToKanji { id: kanji }     // instantiate your helper (call kanji.numberToKanji)

    RowLayout {                     // lay children left→right
        anchors.fill: parent
        Repeater { model: 6; Rectangle { /* one workspace pill */ } }
        Item { Layout.fillWidth: true }   // spring: shoves the rest to the right
        Text { id: clock }                // clock, on the right
    }
}
```

Key pieces:
- **`PanelWindow`** = a bar. `anchors.top/left/right` + `implicitHeight` pin it.
- **`RowLayout`** arranges children in a row. A `Item { Layout.fillWidth: true }`
  is the classic "spacer" trick to push following items to the right edge.
- **`Repeater { model: 6; <delegate> }`** stamps out the delegate 6 times, exposing
  `index` (0..5) to each copy. That's how you get 6 workspace pills from one block.
- Inside a layout, position items with `Layout.*` (e.g. `Layout.alignment`),
  **not** `anchors` (see §11).

---

## 4. Reactive data: bindings, `Timer`, `Process`

Your bar already shows all three patterns. Here's the why.

**Binding** — recomputes automatically:
```qml
property bool isActive: root.focusedWsId === (index + 1)
color: isActive ? Colors.primary : "transparent"   // re-runs when isActive changes
```

**`Timer`** — do something on an interval:
```qml
Timer {
    interval: 1000; running: true; repeat: true
    onTriggered: clock.text = Qt.formatDateTime(new Date(), "HH:mm")
}
```

**`Process` + `SplitParser`** — run a command and react to its output
(`import Quickshell.Io`). Your CPU reader:
```qml
Process {
    id: cpuProc
    command: ["sh", "-c", "head -1 /proc/stat"]
    stdout: SplitParser {            // fires onRead per line
        onRead: line => { /* parse, set root.cpuUsage */ }
    }
}
Timer { interval: 2000; running: true; repeat: true; onTriggered: cpuProc.running = true }
```
Setting `running = true` re-runs the command. You store the result in a `property`
(`root.cpuUsage`), and anything bound to that property updates. Right now nothing
displays it — §6 fixes that.

> For long-lived streams (e.g. `playerctl --follow`), leave the Process running and
> just keep parsing lines, instead of re-running on a timer.

---

## 5. Theming with matugen

[matugen](https://github.com/InioX/matugen) generates a **Material You** palette
from your wallpaper and writes it into files via templates. It's already wired up
here — you just need to install it and run it.

**Install (Arch, from the AUR):**
```sh
paru -S matugen      # or: yay -S matugen   (package: matugen / matugen-bin)
```

**What's set up for you:**
- `~/.config/quickshell/Colors.qml` — a **singleton** holding the palette, with
  Tokyo-Night-ish defaults so the bar works *now*. Everything in the bar reads from
  it (`Colors.primary`, `Colors.on_surface`, …).
- `~/.config/matugen/templates/Colors.qml` — the matugen **template** (same file,
  but with `{{ colors.primary.default.hex }}` placeholders; spaces optional).
- `~/.config/matugen/config.toml` — wires template → output.

> **Template gotcha:** matugen evaluates `{{ … }}` *everywhere in the file, including
> inside comments*. Don't write placeholder examples in comments — matugen will try
> to parse them and fail. Worse, its error points at the first *real* placeholder, not
> the comment, so it's a confusing one to debug.

**Use it:**
```sh
matugen image ~/images/wallpapers/Tropic.jpg --prefer saturation   # what we used
matugen image ~/Pictures/wallpaper.png -m dark                      # force dark mode
matugen color hex "#7dcfff"                                         # from a single color
```
matugen rewrites `~/.config/quickshell/Colors.qml`, Quickshell hot-reloads, and the
bar recolors **live**. (Try it and watch with `qs log`.)

**The "it shows colors and waits for me to pick" prompt.** matugen 4.x sometimes
finds *several* candidate source colors in an image and asks you to choose one in
the terminal. To pick automatically, pass `--prefer`:
```sh
matugen image <img> --prefer saturation   # most vivid (good default)
# other choices: darkness | lightness | value | less-saturation | closest-to-fallback
```
Without a terminal (e.g. from a script) it *errors* unless `--prefer` is given.

**Auto-recolor on wallpaper change.** matugen can set the wallpaper itself with
`swww`/`hyprpaper`. e.g. with swww:
```sh
matugen image ~/Pictures/wall.png   # this also runs your `set_wallpaper` hook if configured
```
Or just call matugen from whatever script/keybind you already use to change wallpaper.

**Property naming gotcha (important):** the color properties are `snake_case`
(`on_primary`, not `onPrimary`). In QML a property whose name starts with `on` + a
capital letter is parsed as a *signal handler* — `property color onPrimary` is a
hard error. snake_case sidesteps that *and* matches matugen's role names 1:1, so
adding a new role is copy-the-name-across.

**Add another app to matugen** — drop a template and register it in `config.toml`:
```toml
[templates.kitty]
input_path  = '~/.config/matugen/templates/kitty.conf'
output_path = '~/.config/kitty/colors-matugen.conf'
```

---

## 6. Adding a bar module

Goal: show CPU% on the right, next to the clock. Your `Process` already computes
`root.cpuUsage`; we just render it. Put this in the `RowLayout`, before/after the clock:

```qml
Text {
    Layout.alignment: Qt.AlignVCenter
    text: "  " + root.cpuUsage + "%"
    color: Colors.on_surface
    font { family: root.fontFamily; pixelSize: root.fontSize }
}
```
That's it — because `text` is bound to `root.cpuUsage`, it updates every time the
Process refreshes. The icon `` is a Nerd Font glyph (you're using JetBrainsMono
Nerd Font, so glyphs work).

**Make it a reusable pill.** Hardcoding a `Text` per stat gets repetitive. Extract
a component (see §7) so each stat is one line:
```qml
StatPill { icon: ""; value: root.cpuUsage + "%" }
StatPill { icon: ""; value: root.memUsage + "%" }
```

**Common module ideas & where the data comes from:**
| Module        | Source |
|---------------|--------|
| Clock/date    | `Qt.formatDateTime(new Date(), …)` + a `Timer` (you have this) |
| CPU / mem     | `Process` reading `/proc/stat`, `/proc/meminfo` (you have CPU) |
| Volume        | `Process` on `wpctl get-volume @DEFAULT_AUDIO_SINK@`, or the Pipewire/Mpris services |
| Battery       | read `/sys/class/power_supply/BAT0/capacity`, or `UPower` service |
| Network       | `Process` on `nmcli`, or read `/sys/class/net/...` |
| Tray          | `Quickshell.Services.SystemTray` → `SystemTray.items` |
| Media         | `Quickshell.Services.Mpris` → current player metadata |

Quickshell ships service singletons (SystemTray, Mpris, Pipewire, UPower, Notifications)
so you often don't even need a `Process`. Browse them in the docs (§12).

---

## 7. Reusable components & singletons

**Component = a `PascalCase.qml` file.** Its root item's properties become the
component's API. Example — `StatPill.qml`:

```qml
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: pill
    property string icon: ""
    property string value: ""
    spacing: 4
    Layout.alignment: Qt.AlignVCenter

    Text { text: pill.icon;  color: Colors.on_surface_variant; font.pixelSize: 14 }
    Text { text: pill.value; color: Colors.on_surface;          font.pixelSize: 14 }
}
```
Use anywhere: `StatPill { icon: ""; value: "42%" }`. No import needed (sibling file).

**Singleton = shared, single instance.** First line `pragma Singleton`, root type
`Singleton` (from Quickshell), referenced by filename. `Colors.qml` is one:
```qml
pragma Singleton
import Quickshell
import QtQuick
Singleton {
    readonly property color primary: "#7dcfff"
}
```
Use globals from a singleton when many files need the same data (palette, config,
shared state). Use a plain component when you want many *instances*.

> Rule of thumb: **`Colors`** = singleton (one palette, everyone reads it).
> **`StatPill`** / **`NumberToKanji`** = components (you make as many as you want;
> note `NumberToKanji` you instantiate once with `id: kanji` purely to call its function).

---

## 8. Popups (`PopupWindow`)

A `PopupWindow` is a separate surface **anchored to another window** — perfect for a
calendar under the clock, a volume slider, a right-click menu.

```qml
// inside your bar (PanelWindow id: root), e.g. wrap the clock in a MouseArea:
PopupWindow {
    id: calPopup
    anchor.window: root                       // anchor to the bar
    anchor.rect.x: clock.x                     // x of the clock within the bar
    anchor.rect.y: root.height                 // just below the bar
    implicitWidth: 260
    implicitHeight: 260
    visible: false                             // start hidden

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container
        radius: 12
        border.color: Colors.outline_variant
        // …put a calendar / anything here…
        Text {
            anchors.centerIn: parent
            color: Colors.on_surface
            text: Qt.formatDateTime(new Date(), "dddd\nMMMM d, yyyy")
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
```
Toggle it from the clock:
```qml
Text {
    id: clock
    /* … */
    MouseArea { anchors.fill: parent; onClicked: calPopup.visible = !calPopup.visible }
}
```
Notes:
- `anchor.rect.x/y` are relative to `anchor.window`. If your item is nested deep,
  compute its bar-relative position with `clock.mapToItem(root, 0, 0).x`.
- A popup is its own surface, so it can extend *outside* the bar's height.
- For click-outside-to-close, give the popup `visible` logic or use the full-screen
  dim-layer trick the launcher uses (§9).

---

## 9. The app launcher

`Launcher.qml` is a complete, working launcher (search + ↑/↓ + Enter, click-away to
close). It's **not wired in yet** so your bar stays stable. Here's how it works and
how to turn it on.

**How it works:**
- It's a full-screen `PanelWindow` with a dim background and a centered card.
- `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` makes it grab the
  keyboard so you can type (needs `import Quickshell.Wayland`).
- App list comes from `DesktopEntries.applications.values` (a JS array of
  `DesktopEntry`). Each has `.name`, `.icon`, `.comment`, and `.execute()`.
- Icons: `Quickshell.iconPath(entry.icon, "application-x-executable")` → `Image.source`.
- It emits `signal closed()` when you pick something or dismiss; the loader listens.

**Turn it on — load it lazily and toggle via IPC** (fits your Lua `exec_cmd` style).

Add to `shell.qml` (inside the `PanelWindow`):
```qml
import Quickshell.Io   // already imported in your shell.qml

LazyLoader {
    id: launcherLoader
    // built only when active; destroyed when inactive
    Launcher { onClosed: launcherLoader.active = false }
}

IpcHandler {
    target: "launcher"
    function toggle(): void { launcherLoader.active = !launcherLoader.active }
    function open():   void { launcherLoader.active = true }
}
```
Test it from a terminal (no keybind needed yet):
```sh
qs ipc call launcher toggle
qs ipc show           # lists all IPC targets/functions you've defined
```
Then bind it in Hyprland. Your `keybinds.lua` currently has:
```lua
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(myPrograms.menu))
```
Swap it for:
```lua
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
```

**Alternative — native Hyprland global shortcut** (no shelling out). Quickshell can
register a shortcut Hyprland triggers directly:
```qml
import Quickshell.Hyprland
GlobalShortcut {
    appid: "quickshell"
    name: "launcherToggle"
    onPressed: launcherLoader.active = !launcherLoader.active
}
```
and bind (raw Hyprland syntax — the dispatcher is `global`, target is `appid:name`):
```
bind = SUPER, space, global, quickshell:launcherToggle
```
Use whichever your Lua wrapper makes easier; IPC is the safer bet since it's just a
normal `exec_cmd`.

---

## 10. Multi-monitor

A bare `PanelWindow` appears on one screen. To put a bar on **every** monitor, wrap
it in `Variants` over `Quickshell.screens`:
```qml
Variants {
    model: Quickshell.screens
    PanelWindow {
        required property var modelData
        screen: modelData          // bind this window to one screen
        anchors { top: true; left: true; right: true }
        // … your bar …
    }
}
```
`Variants` stamps one copy per item in `model` (here, per screen), like a `Repeater`
but for windows.

---

## 11. Gotchas

Things this config already ran into — worth internalizing:

- **Tabs vs spaces.** Your files mix both. QML doesn't care, but *you* will when
  copy-pasting. Pick one; if an editor "can't find" a line, it's whitespace.
- **`PascalCase` filenames.** A file usable as a type must start uppercase.
  `numberToKanji.qml` was invisible until renamed `NumberToKanji.qml`.
- **`on` + Uppercase property names are illegal.** `property color onPrimary`
  is parsed as a signal handler → error. Use `on_primary` (snake_case). (§5)
- **No `anchors` inside a Layout.** Items in `RowLayout`/`ColumnLayout` must use
  `Layout.alignment`, `Layout.fillWidth`, etc. Mixing in `anchors.verticalCenter`
  warns and can misposition.
- **`[undefined] to QColor` at load.** Benign transient if it only appears during
  load and doesn't recur on interaction (a `Colors.*` binding evaluated a tick early).
- **`.values` on Quickshell models.** Models like `Hyprland.workspaces` and
  `DesktopEntries.applications` expose `.values` as a plain JS array you can
  `.find`/`.filter`/`.sort` — that's how both the bar and launcher read them.
- **`?.` and `??` are your friends.** `Hyprland.focusedWorkspace?.id ?? 0` avoids
  crashes when something isn't ready yet (very common during reload).

---

## 12. Reference

- Quickshell docs (types/guides): https://quickshell.org/docs/
- Useful type pages: `PanelWindow`, `PopupWindow`, `LazyLoader`, `Variants`,
  `DesktopEntries`/`DesktopEntry`, `Quickshell.Hyprland/GlobalShortcut`,
  `Quickshell.Io` (`Process`, `IpcHandler`), `Quickshell.Services.*`
  (SystemTray, Mpris, Pipewire, UPower, Notifications).
- Examples repo: https://git.outfoxxed.me/quickshell/quickshell-examples
- matugen: https://github.com/InioX/matugen (+ its wiki for templates/filters)
- Qt QML basics (Item, anchors, Layouts, Text): https://doc.qt.io/qt-6/qmlapplications.html

**Workflow recap:** edit a `.qml` → save → Quickshell hot-reloads → `qs log` if it
broke. Add UI by nesting items; add data with bindings/`Process`/services; factor
repetition into `PascalCase.qml` components; share globals via singletons.
