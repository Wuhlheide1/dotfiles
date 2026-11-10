"""Overlay on the packaged caelestia-cli: adds the `dynamic oled` flavour.

Every surface pure black (OLED pixels off), only text, icons, outlines and
highlights lit, in the wallpaper's accents. Pick it with `>scheme dynamic
oled` in the launcher or `caelestia scheme set -n dynamic -f oled`; `-f default`
goes back. `>variant` still applies (monochrome = no accent at all). It has no
light mode: a light wallpaper with smartScheme on only changes the variant.

Why it is built like this: the CLI has no user scheme directory and hard-codes
dynamic's flavours. Symlinked to ~/.local/lib/python3.14/site-packages/caelestia,
this package shadows the system one for every caller (the shell and the Hyprland
binds don't have ~/.local/bin on their PATH, so a wrapper script would miss them),
hands everything through to the real package and patches the scheme code before
the subcommands import it. A new Python minor needs the symlink redone; until
then the flavour renders as plain dynamic default, nothing breaks.

`caelestia shell -d` starts the desktop, so a failed patch may only ever cost the
flavour, never the CLI. Drop this once the C++ scheme module (shell #2244) lands.
"""

import sys
from pathlib import Path
from site import getsitepackages

FLAVOUR = "oled"

# Every surface role is true black: panels, cards, bars, fields, popups. What
# stays lit is text, icons, outlines and the highlight roles (primary,
# secondary/tertiary containers, state layers), which the flavour leaves alone.
SURFACES = (
    "background surface surfaceDim surfaceBright surfaceVariant "
    "surfaceContainerLowest surfaceContainerLow surfaceContainer surfaceContainerHigh surfaceContainerHighest "
    "base mantle crust surface0 surface1 surface2"
).split()

# Apps also use the containers for hover and selection rows (fish pager, kitty's
# active tab, nvim's cursor line, ...). Those templates read raised* instead,
# which keep a faint ladder here. theme-post.py makes raised* = the container
# in every other flavour, so nothing changes there.
RAISED = {
    "raisedLow": ("surfaceContainerLow", 0.6),
    "raised": ("surfaceContainer", 0.65),
    "raisedHigh": ("surfaceContainerHigh", 0.75),
    "raisedHighest": ("surfaceContainerHighest", 0.85),
}


def dim(colour: str, share: float) -> str:
    return bytes(round(c * share) for c in bytes.fromhex(colour)).hex()


def add_flavour() -> None:
    from caelestia.utils import material, scheme as schemes
    from caelestia.utils.paths import wallpaper_thumbnail_path

    stock_flavours = schemes.get_scheme_flavours
    stock_colours = material.get_colours_for_image

    def get_scheme_flavours(name: str | None = None) -> list[str]:
        flavours = stock_flavours(name)
        return [*flavours, FLAVOUR] if (name or schemes.get_scheme().name) == "dynamic" else flavours

    def get_colours_for_image(image=wallpaper_thumbnail_path, scheme=None) -> dict[str, str]:
        colours = stock_colours(image, scheme)
        if (scheme or schemes.get_scheme()).flavour != FLAVOUR:
            return colours
        raised = {k: dim(colours[src], share) for k, (src, share) in RAISED.items() if src in colours}
        return colours | {k: "000000" for k in SURFACES if k in colours} | raised

    schemes.get_scheme_flavours = get_scheme_flavours
    material.get_colours_for_image = get_colours_for_image
    # The setter still runs, so leaving the flavour keeps what smartScheme asked for
    schemes.Scheme.mode = property(lambda s: "dark" if s.flavour == FLAVOUR else s._mode, schemes.Scheme.mode.fset)


real = Path(getsitepackages()[0]) / __name__
__path__.append(str(real))

try:
    add_flavour()
except Exception as e:
    print(f"caelestia overlay: {FLAVOUR} flavour unavailable: {e!r}", file=sys.stderr)

exec(compile((real / "__init__.py").read_text(), str(real / "__init__.py"), "exec"))
