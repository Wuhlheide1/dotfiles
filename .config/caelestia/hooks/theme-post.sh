#!/usr/bin/env bash
# Runs after every `caelestia scheme` apply (wired via theme.postHook in
# cli.json). Caelestia exports SCHEME_NAME/FLAVOUR/MODE/VARIANT/COLOURS.
set -uo pipefail

# 1. Reload open kitty windows so they pick up the regenerated palette.
#    New windows get it from the `include` regardless.
pkill -USR1 -x kitty 2>/dev/null || true

# 2. Recolour Papirus folder icons to the nearest match for the new accent.
#    papirus-folders rewrites a lot of files, so only run it when the bucket
#    actually changes - a wallpaper shuffle usually lands on the same one.
command -v papirus-folders >/dev/null || exit 0

want=$(python3 - <<'PY'
import json, os, sys
try:
    cols = json.loads(os.environ["SCHEME_COLOURS"])
except Exception:
    sys.exit(0)
hexv = cols.get("primary")
if not hexv:
    sys.exit(0)
r, g, b = (int(hexv[i:i+2], 16) / 255 for i in (0, 2, 4))
mx, mn = max(r, g, b), min(r, g, b)
d = mx - mn
if d == 0:
    h = 0
elif mx == r:
    h = (60 * ((g - b) / d) + 360) % 360
elif mx == g:
    h = 60 * ((b - r) / d) + 120
else:
    h = 60 * ((r - g) / d) + 240
s = 0 if mx == 0 else d / mx
# A desaturated accent has no meaningful hue - use a neutral folder instead.
if s < 0.15:
    print("grey"); sys.exit(0)
for hi, name in [(15,"red"),(40,"orange"),(65,"yellow"),(160,"green"),
                 (195,"teal"),(205,"cyan"),(225,"blue"),(255,"indigo"),
                 (290,"violet"),(330,"magenta"),(345,"pink"),(361,"red")]:
    if h < hi:
        print(name); break
PY
)
[ -n "${want:-}" ] || exit 0

# `papirus-folders -l` marks the active colour with "> ".
current=$(papirus-folders -l 2>/dev/null | tr -d ' ' | grep '^>' | tr -d '>')
[ "$want" = "$current" ] && exit 0

papirus-folders -C "$want" --theme Papirus-Dark >/dev/null 2>&1 || true

# 3. Push the new scheme to the Airlock login screen, so the greeter matches the
#    desktop. Needs /etc/sudoers.d/astra-airlock-sync; `sudo -n` fails instantly
#    rather than hanging if that rule is absent, so this is safe either way.
command -v astra-airlock >/dev/null && sudo -n astra-airlock --sync >/dev/null 2>&1 || true

