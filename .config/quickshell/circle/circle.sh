#!/usr/bin/env bash
# Helpers for the circle-to-search overlay. Everything that leaves the machine
# goes through here, so it is easy to audit.
#   circle.sh lens <png>        upload to Google Lens, open results in the browser
#   circle.sh gemini <png> [q]  new chat in the Gemini app with the image (asks q if given)
#   circle.sh antigravity <conversation> <model>   resume an agy conversation in a terminal
#   circle.sh ocr <png>         print the text in the image (tesseract, local)
#   circle.sh search <text>     plain web search
#   circle.sh copy-image <png>  image to clipboard
#   circle.sh copy-text         stdin to clipboard
set -uo pipefail

notify() { notify-send -a caelestia-cli -i image-x-generic "Circle to Search" "$1"; }

case "${1:-}" in
lens)
    # The browser has to do the upload itself: a results URL obtained by curl
    # belongs to curl's Google session and comes up empty in the browser. So
    # write a one-shot page that puts the image in a form and posts it to Lens.
    dir=${XDG_RUNTIME_DIR:-/tmp}/circle
    mkdir -p "$dir"
    data=$(magick "$2" -resize '2000x2000>' png:- | base64 -w0)
    cat >"$dir/lens.html" <<HTML
<!doctype html><meta charset=utf-8><title>Google Lens…</title>
<style>html{background:#0c0e12}</style>
<form id=f method=post enctype=multipart/form-data
      action="https://lens.google.com/v3/upload?hl=${LANG%%_*}&st=$(date +%s%3N)">
<input type=file name=encoded_image id=i hidden></form>
<script>
const b = atob("$data"), u = new Uint8Array(b.length);
for (let k = 0; k < b.length; k++) u[k] = b.charCodeAt(k);
const t = new DataTransfer();
t.items.add(new File([u], "circle.png", { type: "image/png" }));
i.files = t.files;
f.submit();
</script>
HTML
    xdg-open "$dir/lens.html" >/dev/null 2>&1 &
    ;;
gemini)
    # The Gemini app is gemini.google.com in a Brave --app window
    # (~/.local/share/applications/gemini.desktop). The Circle to Gemini
    # extension (~/.local/share/circle-gemini) reads this inbox whenever a Gemini
    # page loads or gains focus, and takes each handoff once, within 2 minutes.
    inbox=${XDG_DATA_HOME:-$HOME/.local/share}/circle-gemini/inbox
    mkdir -p "$inbox"
    find "$inbox" -maxdepth 1 -type f -name '*.png' -mmin +10 -delete
    id=$(date +%s%N)
    img=
    if [ -f "$2" ] && magick "$2" -resize '3000x3000>' "$inbox/$id.png"; then
        img=$id.png
        setsid -f sh -c 'sleep 300; rm -f -- "$1"' _ "$inbox/$img"
    fi
    jq -n --arg id "$id" --arg img "$img" --arg text "${3:-}" \
        '{id: $id, ts: (now * 1000 | floor), image: (if $img == "" then null else $img end),
          text: $text, send: ($text != "")}' >"$inbox/handoff.tmp" &&
        mv "$inbox/handoff.tmp" "$inbox/handoff.json"
    win=$(hyprctl -j clients | jq -r 'first(.[] | select(.class | startswith("brave-gemini.google.com__"))) | .address')
    if [ -n "$win" ]; then
        hyprctl dispatch focuswindow "address:$win" >/dev/null
    else
        setsid -f gtk-launch gemini >/dev/null 2>&1
    fi
    ;;
antigravity)
    setsid -f kitty --directory "$HOME" agy --conversation "$2" --model "$3" >/dev/null 2>&1
    ;;
ocr)
    command -v tesseract >/dev/null || exit 127
    # Use every language that is both wanted and installed. Screen text is
    # small, so upscale 2x in greyscale first — tesseract is far better at it.
    langs=$(tesseract --list-langs 2>/dev/null | grep -xE 'eng|deu|jpn' | paste -sd+)
    magick "$2" -colorspace Gray -resize 200% png:- 2>/dev/null |
        tesseract stdin stdout -l "${langs:-eng}" --psm 3 2>/dev/null |
        sed -e 's/[[:space:]]*$//' | cat -s | sed -e '/./,$!d'
    ;;
search)
    shift
    q=$(jq -rn --arg q "$*" '$q|@uri')
    xdg-open "https://www.google.com/search?q=$q" >/dev/null 2>&1 &
    ;;
clients)
    # Windows visible on monitor $2, in screen-local coords, topmost first, so a
    # tap can select the window under the cursor.
    m=$(hyprctl -j monitors | jq -c --arg n "$2" '.[] | select(.name == $n)')
    hyprctl -j clients | jq -c --argjson m "$m" '[.[]
        | select(.mapped and (.hidden | not))
        | select(.workspace.id == $m.activeWorkspace.id or .workspace.id == $m.specialWorkspace.id)
        | {x: (.at[0] - $m.x), y: (.at[1] - $m.y), w: .size[0], h: .size[1],
           z: ((if .workspace.id == $m.specialWorkspace.id then 8 else 0 end)
             + (if .pinned then 4 else 0 end) + (if .fullscreen > 0 then 2 else 0 end)
             + (if .floating then 1 else 0 end))}]
        | sort_by(-.z)'
    ;;
copy-image)
    wl-copy --type image/png <"$2"
    ;;
copy-text)
    wl-copy
    ;;
*)
    echo "usage: circle.sh lens|gemini|antigravity|ocr|search|copy-image|copy-text" >&2
    exit 2
    ;;
esac
