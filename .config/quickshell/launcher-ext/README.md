# Launcher extensions

Any **executable** file in this directory is run (no arguments) each time the
launcher opens. Every line it prints becomes a searchable launcher row:

```
name<TAB>glyph<TAB>command<TAB>keywords
```

- `name`     — what shows in the list (required)
- `glyph`    — a Nerd Font codepoint for the icon chip (may be empty)
- `command`  — run via `sh -c` when the row is picked (required)
- `keywords` — extra search terms (may be empty)

Keep scripts fast (<100 ms) — they run on every launcher open. Slow sources
should cache to a file and print the cache.

Non-executable files (like this README) are ignored. Disable an extension with
`chmod -x` or by renaming it to `*.off`.
