# circle — Circle to Search for Caelestia

SUPER+G freezes the focused monitor. Then:

- **drag a box** around anything (drag again to replace it)
- **click** a window → selects that window; click empty desktop → back to whole screen
- **type + Enter** → ask about the selection (or the whole screen) in the card; follow-ups stay in the same conversation
- **type + Shift+Enter** → ask it in the full Gemini app instead (new chat, selection attached); empty Shift+Enter just opens it with the image
- **Enter on empty** → Google Lens (the browser does the upload via a one-shot local page, so results land in your own Google session)
- pill buttons: Lens · Text (OCR, copies it) · Translate · Copy image
- card buttons: **Continue in Gemini** (open_in_new: same image + last question in the Gemini app) · **Continue in Antigravity** (terminal: resumes the conversation in `agy`, where it may run commands and edit files, asking first; only for the Gemini models below) · Copy · Close
- **Esc** / SUPER+G again → close

Files: `shell.qml` (IPC + settings: model, translate language), `Overlay.qml`
(UI), `Ai.qml` (streaming Claude session), `Theme.qml` (reads Caelestia's
scheme.json live), `circle.sh` (everything that touches the network/clipboard),
`system-prompt.md` (how Claude answers), `Tint.qml` + `shaders/` (the glow).

Shaders: `aura.frag` (edge bloom, selection ring, scan shimmer) and
`tint.frag` (gradient recolour for sparkle, busy ring, "Thinking…"). Keep every animation speed constant — multiplying the clock by a changing factor jumps the phase and flashes.
After editing one, recompile:
`/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/X.frag.qsb shaders/X.frag`
Accent colours are vivid versions of the scheme's primary/tertiary hues (Theme.qml).

## Models

Pick one from the chip in the search pill (it's remembered). The list lives in
`~/.config/circle/settings.json` — edit it to add models or change
`translateTo`. Or switch from a keybind: `qs -c circle ipc call circle model local`.
All of them go through `backend.py` (standard library only):

- **Gemini 3.8 Flash / Gemini 4 Argon** (default) — Google AI Pro through the
  Antigravity CLI (`agy`, AUR antigravity-cli; sign in once by running `agy`).
  Web search included. agy is a coding agent: in print mode everything that needs
  permission (commands, files outside its folder) is auto-denied, so here it only
  sees the selection (dropped as a file into `$XDG_RUNTIME_DIR/circle/agy`, whose
  GEMINI.md = system-prompt.md + rules) and the web. The process starts as soon as
  you select or type, so the ~3 s start-up is hidden; first answer ~5 s (Argon
  ~10 s), follow-ups ~2 s. Its conversations are kept 3 days (for Continue in
  Antigravity), then `prune_agy()` deletes them.
- **Gemma 4 12B, local** (Ollama on the RX 7800 XT, Vulkan). Free and private;
  web search via DuckDuckGo (keyless). ~76 tokens/s; unloads from VRAM after
  10 idle minutes and is pre-loaded when the overlay opens. Models live on the
  990 PRO NVMe (/var/lib/ollama = subvol @ollama); cold load ~6 s.
  Setup: `sudo pacman -S ollama ollama-vulkan`, `sudo systemctl enable --now ollama`,
  `ollama pull gemma4:12b`.
- **Gemini Flash-Lite** — Gemini API, free key from
  https://aistudio.google.com/apikey in `~/.config/circle/gemini-key` (chmod 600).
  Google AI Pro does *not* cover the API, and the Gemini CLI login no longer
  works for personal accounts. Free tier: Flash-Lite 15 requests/min, Flash
  (pinned to 3.5 — `-latest` is a slow 3.8) 5/min, Pro none. Google Search
  grounding has no free quota, so web search uses the DuckDuckGo tools too; a
  question with search costs 2–3 requests. Short rate limits are waited out
  automatically. Free-tier data may be used by Google to improve its products.
- **Claude Haiku / Sonnet** — Claude Code CLI login (`claude -p`), only
  WebSearch/WebFetch tools, no session persistence. Counts against Claude Pro usage.
OCR is local tesseract; without it the Text button asks Claude instead.

Gemini app handoff: `circle.sh gemini` writes `handoff.json` + the image into
the inbox of the **Circle to Gemini** Brave extension
(`~/.local/share/circle-gemini`, in the `--load-extension` list of
`~/.config/brave-flags.conf`), then focuses the Gemini app window or opens it
(`gtk-launch gemini`). Unpacked extensions read their files straight from disk,
so the extension sees the inbox without a native host. The next Gemini page that
loads or gains focus takes the handoff once (within 2 min), starts a new chat,
pastes the image (Gemini reads `clipboardData.files`; a drop on
`.xap-uploader-dropzone` is the fallback) and sends the question once the upload
is done. If the image doesn't attach, it doesn't send.

Hyprland wiring: keybinds.lua (SUPER+G), autostart.lua (`qs -c circle -d`),
windowsAndWorkspaces.lua (`caelestia-circle` in the no-anim layer rule).
Restart: `qs -c circle kill; qs -c circle -d`. Logs: `qs -c circle log`.

Plugin-ready: when Caelestia ships plugins, Overlay/Ai/IconButton port over
nearly as-is (swap Theme.* for Colours.palette.m3*, the IPC for a CustomShortcut).
