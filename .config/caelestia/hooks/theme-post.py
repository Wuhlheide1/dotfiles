#!/usr/bin/env python3
"""Caelestia theme engine - runs after every `caelestia scheme`/wallpaper apply.

Wired as theme.postHook in ~/.config/caelestia/cli.json. Caelestia exports
SCHEME_NAME/MODE/VARIANT/COLOURS and waits for this to exit while it still
holds its theme lock, so the foreground part has to stay fast; anything slow
goes to a detached `--background` run of this same file.

Why it exists (2026-10-13):
  * Caelestia's apply takes a NON-blocking lock and silently drops an apply
    that arrives while another is running. With the old 2.8 s hook, picking a
    second wallpaper quickly left the apps on the previous palette ("I need to
    load the wallpaper twice"). The background run now compares what was
    applied with scheme.json and re-applies if a change got dropped.
  * Caelestia harmonises the terminal colours 80% toward the accent, so in a
    teal scheme red was blue and yellow was purple. ansi_palette() keeps the
    hues honest and only tints them slightly toward the accent.
  * GTK is done here instead of by Caelestia (enableGtk: false): Caelestia
    hard-codes gtk-theme adw-gtk3-dark even in light mode, and its gtk.css only
    sets the old @define-color names that libadwaita >= 1.6 ignores.
  * Folder icons are recoloured to the exact accent in a user-level overlay
    theme (Caelestia-Dark/-Light, inheriting Papirus). papirus-folders needs
    root, so it had silently failed on every wallpaper change.

Templates: ~/.config/caelestia/theme-templates/<name> renders to
~/.local/state/caelestia/theme/<name>. Placeholders are {{ name.form }} (form =
hex, hexalpha, rgb, rgbalpha, hsl, red/green/blue, hue/saturation/lightness) and
{{ mode }}. On top of the scheme colours, templates get ansi0..ansi15 and
ansiRed/Green/Yellow/Blue/Magenta/Cyan/Orange (+ ...Bright).
NOT ~/.config/caelestia/templates: Caelestia would render that dir itself,
without the extra colours, before this hook runs.

Log: ~/.local/state/caelestia/theme-post.log
"""

import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

HOME = Path.home()
CFG = HOME / ".config/caelestia"
STATE = HOME / ".local/state/caelestia"
OUT = STATE / "theme"
TEMPLATES = CFG / "theme-templates"
LOG = STATE / "theme-post.log"
APPLIED = STATE / "theme-applied.json"
SCHEME = STATE / "scheme.json"
LOCK = STATE / "theme.lock"
ICONS = HOME / ".local/share/icons"
BRAVE = HOME / ".config/BraveSoftware/Brave-Browser"
# Brave extensions that theme one site each: dir -> the stylesheet they re-read
SITE_EXTS = {
    HOME / ".local/share/caelestia-youtube": "youtube.css",
    HOME / ".local/share/caelestia-gemini": "gemini.css",
}

# Rendered file -> where the app reads it. Re-created if something replaced it.
LINKS = {
    "gtk3.css": HOME / ".config/gtk-3.0/gtk.css",
    "gtk4.css": HOME / ".config/gtk-4.0/gtk.css",
    "starship.toml": HOME / ".config/starship.toml",
    "fastfetch.jsonc": HOME / ".config/fastfetch/config.jsonc",
    "claude-theme.json": HOME / ".claude/themes/caelestia.json",
    "fuzzel.ini": HOME / ".config/fuzzel/fuzzel.ini",
    "yazi-theme.toml": HOME / ".config/yazi/theme.toml",
}


def log(msg: str) -> None:
    try:
        if LOG.exists() and LOG.stat().st_size > 256_000:
            LOG.write_text(LOG.read_text()[-64_000:])
        with LOG.open("a") as f:
            f.write(f"{time.strftime('%F %T')} [{os.getpid()}] {msg}\n")
    except OSError:
        pass


def step(fn):
    def run(*a, **k):
        t = time.monotonic()
        try:
            fn(*a, **k)
        except Exception:
            log(f"{fn.__name__} FAILED\n{traceback.format_exc()}")
        else:
            log(f"{fn.__name__} {1000 * (time.monotonic() - t):.0f}ms")

    return run


def atomic_write(path: Path, data: str | bytes) -> bool:
    """Write only if the content changed; returns True if it did."""
    data_b = data.encode() if isinstance(data, str) else data
    try:
        if path.read_bytes() == data_b:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp{os.getpid()}")
    tmp.write_bytes(data_b)
    os.replace(tmp, path)
    return True


def colours_hash(colours: dict, mode: str) -> str:
    return hashlib.sha1(json.dumps([colours, mode], sort_keys=True).encode()).hexdigest()


# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------

def hct(hexs: str):
    from materialyoucolor.hct import Hct

    return Hct.from_int(0xFF000000 | int(hexs[:6], 16))


def hct_hex(h: float, c: float, t: float) -> str:
    from materialyoucolor.hct import Hct

    return f"{Hct.from_hct(h % 360, max(c, 0), max(min(t, 100), 0)).to_int() & 0xFFFFFF:06x}"


def toward(h: float, target: float, frac: float = 0.15, cap: float = 12) -> float:
    diff = ((target - h + 540) % 360) - 180
    return (h + max(-cap, min(cap, diff * frac))) % 360


# HCT hues of the semantic colours before tinting.
HUES = {"Red": 25, "Orange": 55, "Yellow": 88, "Green": 142, "Cyan": 195, "Blue": 258, "Magenta": 325}
ANSI_ORDER = ["Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"]


def ansi_palette(colours: dict, mode: str) -> dict:
    """Terminal palette that keeps red red, tinted ~12 deg toward the accent."""
    p = hct(colours["primary"])
    dark = mode == "dark"
    out = {}
    for name, h in HUES.items():
        h = toward(h, p.hue)
        boost = 8 if name == "Yellow" else 0  # yellow needs more light to read as yellow
        if dark:
            out[f"ansi{name}"] = hct_hex(h, 46, 72 + boost)
            out[f"ansi{name}Bright"] = hct_hex(h, 40, 82 + boost / 2)
        else:
            out[f"ansi{name}"] = hct_hex(h, 58, 40)
            out[f"ansi{name}Bright"] = hct_hex(h, 64, 46)
    # Neutrals carry a whisper of the accent so greys don't look foreign.
    # Light mode inverts black/white like Caelestia does: tools that print
    # "white" assume a dark background and would vanish on a light one.
    n = (p.hue, min(p.chroma, 6))
    tones = (22, 82, 50, 94) if dark else (72, 28, 52, 18)
    out["ansi0"], out["ansi7"], out["ansi8"], out["ansi15"] = (hct_hex(*n, t) for t in tones)
    for i, name in enumerate(ANSI_ORDER, 1):
        out[f"ansi{i}"] = out[f"ansi{name}"]
        out[f"ansi{i + 8}"] = out[f"ansi{name}Bright"]
    return out


# --------------------------------------------------------------------------
# Steps
# --------------------------------------------------------------------------

@step
def render_templates(colours: dict, mode: str) -> None:
    from caelestia.utils.theme import gen_replace_dynamic

    if not TEMPLATES.is_dir():
        return
    for tpl in sorted(TEMPLATES.iterdir()):
        if tpl.is_file() and not tpl.name.startswith("."):
            atomic_write(OUT / tpl.name, gen_replace_dynamic(colours, tpl, mode))
    for name, target in LINKS.items():
        src = OUT / name
        if not src.exists() or (target.is_symlink() and target.readlink() == src):
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and not target.is_symlink():
            target.rename(target.with_name(target.name + ".pre-engine-bak"))
        target.unlink(missing_ok=True)
        target.symlink_to(src)
        log(f"linked {target} -> {src}")


def gsettings(key: str, value: str) -> None:
    schema = "org.gnome.desktop.interface"
    cur = subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True).stdout.strip()
    if cur.strip("'") != value:
        subprocess.run(["gsettings", "set", schema, key, value])


# libadwaita/portal accent names, for apps that never read gtk.css (flatpaks).
ADW_ACCENTS = {"blue": 255, "teal": 200, "green": 145, "yellow": 90, "orange": 55, "red": 25, "pink": 350, "purple": 300}


def icon_theme(mode: str) -> str | None:
    """The icon pack picked in cli.json (iconThemeDark/Light, set by ~/.local/bin/icons-try),
    falling back to the Caelestia overlay. Caelestia itself writes the same key into the
    qtengine config, so GTK and Qt stay on one pack across wallpaper changes."""
    try:
        cfg = json.loads((HOME / ".config/caelestia/cli.json").read_text())["theme"]
        picked = cfg.get(f"iconTheme{mode.capitalize()}") or cfg.get("iconTheme")
    except (OSError, ValueError, KeyError):
        picked = None
    for name in (picked, f"Caelestia-{mode.capitalize()}"):
        if name and any((d / name / "index.theme").exists() for d in (ICONS, HOME / ".icons", Path("/usr/share/icons"))):
            return name
    return None


@step
def gtk(colours: dict, mode: str) -> None:
    gsettings("color-scheme", f"prefer-{mode}")
    gsettings("gtk-theme", "adw-gtk3-dark" if mode == "dark" else "adw-gtk3")
    if icons := icon_theme(mode):
        gsettings("icon-theme", icons)
    p = hct(colours["primary"])
    if p.chroma < 10:
        accent = "slate"
    else:
        accent = min(ADW_ACCENTS, key=lambda k: abs(((ADW_ACCENTS[k] - p.hue + 540) % 360) - 180))
    gsettings("accent-color", accent)


@step
def reload_apps() -> None:
    subprocess.run(["pkill", "-USR1", "-x", "kitty"], stderr=subprocess.DEVNULL)


@step
def fish_colours() -> None:
    # Universal variables: every running fish picks them up at its next prompt.
    # Background only: each `set -U` syncs fish_variables (~1 s for the lot).
    # Not --no-config: that also stops fish from saving universal variables.
    fish = OUT / "fish-colours.fish"
    if fish.exists():
        subprocess.run(["fish", "-c", f"source {fish}"], stderr=subprocess.DEVNULL)


# Papirus' blue folder: face, back, emblem.
PAPIRUS_BLUE = {"5294e2": "face", "4877b1": "back", "1d344f": "emblem"}
FOLDER_SIZES = ["22x22", "24x24", "32x32", "48x48", "64x64"]


@step
def folder_icons(colours: dict) -> None:
    src_root = Path("/usr/share/icons/Papirus")
    if not src_root.is_dir():
        return
    p = hct(colours["primary"])
    c = 0 if p.chroma < 8 else min(max(p.chroma, 30), 60)
    shade = {
        "face": hct_hex(p.hue, c, 62),
        "back": hct_hex(p.hue, c * 0.95, 50),
        "emblem": hct_hex(p.hue, c * 0.6, 22),
    }
    marker = ICONS / "Caelestia-Dark/.colours"
    key = json.dumps(shade, sort_keys=True)
    if marker.exists() and marker.read_text() == key:
        return
    pattern = re.compile("#(" + "|".join(PAPIRUS_BLUE) + ")", re.I)
    dark = ICONS / "Caelestia-Dark"
    for size in FOLDER_SIZES:
        files = [*(src_root / size / "places").glob("folder-blue*.svg"), *(src_root / size / "places").glob("user-blue*.svg")]
        for f in files:
            if f.is_symlink() or f.name.startswith(("folder-bluegrey", "user-bluegrey")):
                continue
            name = f.name.replace("-blue", "", 1)
            svg = pattern.sub(lambda m: "#" + shade[PAPIRUS_BLUE[m.group(1).lower()]], f.read_text())
            atomic_write(dark / size / "places" / name, svg)
        # Papirus' alias names (folder-videos -> folder-video, folder-home -> user-home, ...)
        # would otherwise fall through to Papirus and stay blue.
        places, out = src_root / size / "places", dark / size / "places"
        for link in places.glob("*.svg"):
            alias = out / link.name
            if not link.is_symlink() or alias.exists() or alias.is_symlink():
                continue
            target = link
            for _ in range(8):
                if not target.is_symlink() or (out / target.name).exists():
                    break
                target = places / os.readlink(target)
            if target.name != link.name and (out / target.name).exists():
                alias.symlink_to(target.name)
    dirs = ",".join(f"{s}/places" for s in FOLDER_SIZES)
    sections = "".join(
        f"\n[{s}/places]\nContext=Places\nSize={s.split('x')[0]}\nType=Fixed\n" for s in FOLDER_SIZES
    )
    for variant in ("Dark", "Light"):
        theme = ICONS / f"Caelestia-{variant}"
        theme.mkdir(parents=True, exist_ok=True)
        if variant == "Light":
            for size in FOLDER_SIZES:
                link = theme / size
                if not link.is_symlink():
                    link.symlink_to(f"../Caelestia-Dark/{size}")
        atomic_write(
            theme / "index.theme",
            f"[Icon Theme]\nName=Caelestia-{variant}\n"
            f"Comment=Papirus-{variant} with folders in the Caelestia accent (generated by theme-post.py)\n"
            f"Inherits=Papirus-{variant},breeze{'-dark' if variant == 'Dark' else ''},hicolor\n"
            f"Example=folder\nDirectories={dirs}\n{sections}",
        )
        os.utime(theme)
    marker.write_text(key)


@step
def site_themes() -> None:
    """YouTube and Gemini follow the scheme; with a wallpaper named *kazuha* they go full Kazuha.

    The Brave extensions in SITE_EXTS (built by ~/.config/rice/{youtube,gemini}/build.py,
    loaded via brave-flags.conf) re-read their stylesheet on every page load, so
    this only has to swap the file: no Brave restart.
    """
    path = STATE / "wallpaper/path.txt"
    wall = Path(path.read_text().strip()).name.lower() if path.exists() else ""
    for ext, css in SITE_EXTS.items():
        if not ext.is_dir():
            continue
        src = ext / "kazuha.css" if "kazuha" in wall else OUT / css
        if src.exists():
            atomic_write(ext / css, src.read_text())


@step
def brave_ntp() -> None:
    """Keep Brave's custom new-tab image in sync with the wallpaper.

    Brave only shows images it imported itself (Customize > Background >
    Upload). This overwrites that one imported file in place, so the NTP shows
    the current wallpaper without touching Brave's prefs.
    """
    prefs = BRAVE / "Default/Preferences"
    if not prefs.exists():
        return
    bg = json.loads(prefs.read_text()).get("brave", {}).get("new_tab_page", {}).get("background", {})
    if bg.get("type") != "custom_image" or not bg.get("selected_value"):
        return
    dest = BRAVE / "Default/sanitized_background_images" / bg["selected_value"]
    wall = Path((STATE / "wallpaper/path.txt").read_text().strip())
    marker = STATE / "brave-ntp.wall"
    stamp = f"{wall}:{wall.stat().st_mtime_ns}:{dest}"
    if dest.exists() and marker.exists() and marker.read_text() == stamp:
        return
    from io import BytesIO

    from PIL import Image

    src = wall
    if wall.suffix.lower() in (".mp4", ".mkv", ".webm", ".mov", ".avi"):
        # Video wallpaper (caelestia-shell-git): Brave gets the first frame.
        src = BytesIO(subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(wall), "-frames:v", "1", "-f", "image2pipe", "-c:v", "png", "-"],
            capture_output=True, check=True, timeout=30,
        ).stdout)
    with Image.open(src) as img:
        img = img.convert("RGB")
        img.thumbnail((2560, 2560), Image.Resampling.LANCZOS)
        buf = BytesIO()
        img.save(buf, "PNG", optimize=False, compress_level=3)
    atomic_write(dest, buf.getvalue())
    marker.write_text(stamp)


@step
def spotify() -> None:
    """Push the scheme into the running Spotify.

    Caelestia only rewrites Spicetify's Themes/caelestia/color.ini; Spotify reads
    the colours from the patched app (Apps/xpui/colors.css), which only
    `spicetify refresh` regenerates (the app had been stuck on a September
    scheme). -n: no restart; the caelestia-live.js extension (built by
    ~/.config/rice/spotify/build.py) swaps the new CSS into the running app.
    """
    theme = HOME / ".config/spicetify/Themes/caelestia"
    files = [theme / "color.ini", theme / "user.css"]
    if not shutil.which("spicetify") or not files[0].exists():
        return
    marker = STATE / "spotify.applied"
    stamp = "\n".join(f.read_text() for f in files if f.exists())
    if marker.exists() and marker.read_text() == stamp:
        return
    r = subprocess.run(["spicetify", "-n", "refresh"], capture_output=True, text=True, timeout=120)
    if r.returncode != 0 or "error" in r.stdout.lower():
        # e.g. after a Spotify update: needs `spicetify backup apply` once
        log(f"spotify: refresh failed: {(r.stdout + r.stderr).strip()[-300:]}")
        return
    marker.write_text(stamp)


@step
def steam(colours: dict, mode: str) -> None:
    """Steam follows the scheme through Millennium + kuska1's Material-Theme.

    With the theme's Color option on "Matugen", its matugen.js re-fetches
    css/main/colors/matugen.css every 1.5 s, so writing that file recolours the
    running Steam: no restart. The theme's roles are the M3 ones Caelestia
    already has (camelCase -> --md-sys-color-kebab-case). Its Appearance
    option is a fixed light/dark choice, so the mode-dependent variables from
    css/main/appearance/<mode>.css are repeated here; they come later in the
    page, so they win. A theme update resets the file until the next apply.
    """
    theme = HOME / ".steam/steam/millennium/themes/Material-Theme"
    if not (theme / "skin.json").exists():
        return
    roles = (
        "background error errorContainer inverseOnSurface inversePrimary inverseSurface onBackground onError "
        "onErrorContainer onPrimary onPrimaryContainer onPrimaryFixed onPrimaryFixedVariant onSecondary "
        "onSecondaryContainer onSecondaryFixed onSecondaryFixedVariant onSurface onSurfaceVariant onTertiary "
        "onTertiaryContainer onTertiaryFixed onTertiaryFixedVariant outline outlineVariant primary "
        "primaryContainer primaryFixed primaryFixedDim scrim secondary secondaryContainer secondaryFixed "
        "secondaryFixedDim shadow surface surfaceBright surfaceContainer surfaceContainerHigh "
        "surfaceContainerHighest surfaceContainerLow surfaceContainerLowest surfaceDim surfaceTint "
        "surfaceVariant tertiary tertiaryContainer tertiaryFixed tertiaryFixedDim"
    ).split()

    def rgb(h: str) -> str:
        return f"rgb({int(h[0:2], 16)}, {int(h[2:4], 16)}, {int(h[4:6], 16)})"

    def kebab(name: str) -> str:
        return re.sub(r"([A-Z])", r"-\1", name).lower()

    light = mode == "light"
    # The theme's presets rotate Steam's blue (hue ~215) onto the accent.
    hue = round(hct(colours["primary"]).hue - 215) % 360
    lines = [
        ":root {",
        '    --theme-color: "Matugen";',
        f"    --hue-rotate: {hue}deg;",
        f"    color-scheme: only {mode} !important;",
        f"    --scheme: {mode};",
        f"    --scheme-light: var(--{'ON' if light else 'OFF'});",
        f"    --scheme-dark: var(--{'OFF' if light else 'ON'});",
        f"    --scheme-color: {'white' if light else 'black'};",
        f"    --scheme-color-inverse: {'black' if light else 'white'};",
        f"    --md-sys-color-source-color: {rgb(colours.get('primaryPaletteKeyColor', colours['primary']))};",
    ]
    lines += [f"    --md-sys-color-{kebab(r)}: {rgb(colours[r])};" for r in roles if r in colours]
    lines.append("}")
    atomic_write(theme / "css/main/colors/matugen.css", "\n".join(lines) + "\n")


@step
def prism(colours: dict, mode: str) -> None:
    """Prism Launcher's "Caelestia" theme (themes/caelestia/theme.json + qss).

    Prism reads themes once at startup, so a running Prism keeps the old palette
    until it restarts. Its cfg (theme + matching icon set: white icons on dark)
    is only touched while Prism is closed, because Prism rewrites it on exit.
    """
    data = HOME / ".local/share/PrismLauncher"
    cfg = data / "prismlauncher.cfg"
    if not cfg.exists():
        return
    c = {k: f"#{v[:6]}" for k, v in colours.items() if isinstance(v, str) and re.fullmatch(r"[0-9a-fA-F]{6,8}", v)}
    theme = {
        "name": "Caelestia",
        "widgets": "Fusion",
        "qssFilePath": "themeStyle.css",
        "colors": {
            "Window": c["surface"],
            "WindowText": c["onSurface"],
            "Base": c["surfaceContainerLow"],
            "AlternateBase": c["surfaceContainer"],
            "ToolTipBase": c["surfaceContainerHighest"],
            "ToolTipText": c["onSurface"],
            "Text": c["onSurface"],
            "Button": c["surfaceContainerHigh"],
            "ButtonText": c["onSurface"],
            "BrightText": c["error"],
            "Link": c["primary"],
            "Highlight": c["primary"],
            "HighlightedText": c["onPrimary"],
            "fadeColor": c["surface"],
            "fadeAmount": 0.5,
        },
    }
    qss = (
        f"QToolTip {{ color: {c['onSurface']}; background-color: {c['surfaceContainerHighest']}; "
        f"border: 1px solid {c['outlineVariant']}; padding: 4px; }}\n"
    )
    out = data / "themes/caelestia"
    atomic_write(out / "theme.json", json.dumps(theme, indent=4) + "\n")
    atomic_write(out / "themeStyle.css", qss)
    (out / "resources").mkdir(exist_ok=True)

    if subprocess.run(["pgrep", "-x", "prismlauncher"], capture_output=True).returncode == 0:
        return
    want = {"ApplicationTheme": "caelestia", "IconTheme": "pe_dark" if mode == "light" else "pe_light"}
    lines = cfg.read_text().splitlines()
    for key, value in want.items():
        for i, line in enumerate(lines):
            if line.startswith(f"{key}="):
                lines[i] = f"{key}={value}"
                break
        else:  # keys live in [General]; later sections ([UI]) mustn't get them
            at = lines.index("[General]") + 1 if "[General]" in lines else 0
            lines.insert(at, f"{key}={value}")
    atomic_write(cfg, "\n".join(lines) + "\n")


@step
def claude_desktop(colours: dict, mode: str) -> None:
    """Claude Desktop follows the scheme (~/.config/rice/claude-desktop, 2026-10-29).

    theme.py there turns the scheme into overrides for claude.ai's CSS tokens;
    the loader that build.py adds to a private copy of the app re-inserts this
    file into every page of the running app when it changes: no restart.
    """
    gen = HOME / ".config/rice/claude-desktop/theme.py"
    if gen.exists():
        import runpy

        atomic_write(OUT / "claude-desktop.css", runpy.run_path(str(gen))["render"](colours, mode))


@step
def file_chooser() -> None:
    """Restart xdg-desktop-portal-gtk so file dialogs match the new palette.

    It is a long-lived GTK3 process that reads gtk.css and the gtk-theme once
    at startup, so Brave's "Open file" dialog stayed dark after a switch to
    light mode. Runs in the background (after gsettings changes have been
    signalled) and only when no portal dialog is open.
    """
    clients = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout
    if "xdg-desktop-portal-gtk" in clients:
        return
    subprocess.run(["systemctl", "--user", "--no-block", "try-restart", "xdg-desktop-portal-gtk.service"])


AIRLOCK = Path("/var/cache/astra-airlock")


@step
def airlock() -> None:
    """Login screen (astra-airlock) follows the desktop: colours + current wall.

    Writes what `sudo astra-airlock --sync` used to write, but as you. That sync
    ran python3 as root with your HOME, so it loaded your own Python files as
    root (passwordless root, removed 2026-11-10). The two cache entries belong
    to you since audit-fixes-20261110.sh. Same JSON in dark.json and light.json,
    exactly as airlock's syncScheme() wrote it; the wall is copied only when it
    changed (the wallpapers/ dir stays root's, so the copy is written in place).
    """
    user = HOME.name
    scheme_dir = AIRLOCK / "schemes/dynamic" / user
    wall_dst = AIRLOCK / "wallpapers" / user
    if not (os.access(scheme_dir, os.W_OK) and os.access(wall_dst, os.W_OK)):
        log("airlock: cache not writable yet, run ~/.config/rice/pending/audit-fixes-20261110.sh")
        return
    from caelestia.utils.scheme import get_scheme

    s = get_scheme()
    data = json.dumps({"name": s.name, "flavour": s.flavour, "mode": s.mode, "colours": s.colours}) + "\n"
    for name in ("dark.json", "light.json"):
        if atomic_write(scheme_dir / name, data):
            os.chmod(scheme_dir / name, 0o644)

    src = STATE / "wallpaper/current"
    if not src.is_file():
        return
    st = src.stat()
    key = f"{src.resolve()}\n{st.st_size}\n{st.st_mtime_ns}\n"
    stamp = STATE / "airlock-wall.stamp"
    if stamp.exists() and stamp.read_text() == key and wall_dst.stat().st_size == st.st_size:
        return
    shutil.copyfile(src, wall_dst)
    os.chmod(wall_dst, 0o644)
    stamp.write_text(key)


@step
def mouse_lighting(colours: dict) -> None:
    """Basilisk V4 Pro RGB (wheel, logo, underglow) in the scheme's accent.

    Material primaries are pastel tones that an RGB LED renders as near-white,
    so this keeps only the hue: the most saturated colour at that hue, scaled to
    full intensity (how bright it glows is `razer brightness`, set once by
    hand). A grey scheme gives white. The colour is stored on the mouse; if it
    is asleep or switched off right now, it keeps the previous one until the
    next wallpaper change.
    """
    razer = HOME / ".local/bin/razer"
    if not razer.exists():
        return
    p = hct(colours["primary"])
    rgb = [0xFF] * 3 if p.chroma < 8 else [int(hct_hex(p.hue, 200, 55)[i:i + 2], 16) for i in (0, 2, 4)]
    k = 255 / max(rgb)
    led = "".join(f"{round(v * k):02x}" for v in rgb)
    r = subprocess.run([str(razer), "--quiet", "light", "static", led], capture_output=True, text=True, timeout=10)
    if r.returncode == 2:
        log(f"mouse_lighting: mouse asleep, kept its old colour (wanted {led})")
    elif r.returncode:
        log(f"mouse_lighting: {r.stderr.strip()}")


def lock_busy() -> bool:
    try:
        with open(LOCK) as fd:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            fcntl.flock(fd, fcntl.LOCK_UN)
    except FileNotFoundError:
        pass
    return False


@step
def reconcile() -> None:
    """Re-apply if scheme.json moved on while our apply held the lock.

    A dropped apply leaves scheme.json (and so the shell) on the new palette
    and every app on the old one. If an apply is still running it will run
    this check itself when it finishes, so only act when the lock is free.
    """
    time.sleep(0.6)
    for _ in range(40):
        if lock_busy():
            return
        try:
            scheme = json.loads(SCHEME.read_text())
            applied = json.loads(APPLIED.read_text())
        except (OSError, json.JSONDecodeError):
            return
        if colours_hash(scheme["colours"], scheme["mode"]) == applied.get("hash"):
            return
        log("scheme.json changed during apply - re-applying the dropped change")
        from caelestia.utils.scheme import get_scheme
        from caelestia.utils.theme import apply_colours

        s = get_scheme()
        apply_colours(s.colours, s.mode)
        return


# --------------------------------------------------------------------------

def main() -> None:
    if "--background" in sys.argv:
        colours = json.loads(os.environ["SCHEME_COLOURS"])
        folder_icons(colours)
        fish_colours()
        file_chooser()
        brave_ntp()
        spotify()
        prism(colours, os.environ.get("SCHEME_MODE", "dark"))
        claude_desktop(colours, os.environ.get("SCHEME_MODE", "dark"))
        airlock()
        mouse_lighting(colours)
        reconcile()
        return

    try:
        colours = json.loads(os.environ["SCHEME_COLOURS"])
        mode = os.environ.get("SCHEME_MODE", "dark")
    except (KeyError, json.JSONDecodeError):
        scheme = json.loads(SCHEME.read_text())
        colours, mode = scheme["colours"], scheme["mode"]

    t = time.monotonic()
    # raised* = hover/selection fills in the templates. The `dynamic oled`
    # flavour (cli-overlay) sends its own, because there every container is black.
    raised = {"raisedLow": "surfaceContainerLow", "raised": "surfaceContainer",
              "raisedHigh": "surfaceContainerHigh", "raisedHighest": "surfaceContainerHighest"}
    extended = {**{k: colours[v] for k, v in raised.items() if v in colours}, **colours,
                **ansi_palette(colours, mode)}
    render_templates(extended, mode)
    site_themes()
    steam(colours, mode)
    gtk(colours, mode)
    reload_apps()
    APPLIED.write_text(json.dumps({"hash": colours_hash(colours, mode), "at": time.time()}))
    log(f"foreground done in {1000 * (time.monotonic() - t):.0f}ms ({mode}, primary {colours.get('primary')})")

    env = {**os.environ, "SCHEME_COLOURS": json.dumps(colours), "SCHEME_MODE": mode}
    with open(os.devnull, "rb") as devnull, LOG.open("a") as logf:
        subprocess.Popen(
            [sys.executable, __file__, "--background"],
            env=env, stdin=devnull, stdout=logf, stderr=logf, start_new_session=True,
        )


if __name__ == "__main__":
    main()
