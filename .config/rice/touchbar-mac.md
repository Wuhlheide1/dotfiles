# Intel MacBook + Touch Bar on Arch

For the planned dual-boot laptop. Two separate projects: get the Mac's
hardware working at all (Wi-Fi, keyboard, trackpad, audio, SSD — none of it
works out of the box), then decide what to do with the Touch Bar.

## Step 0: find out which chip it has

"Last Intel" Touch Bar MacBook Pros are one of two generations, and it
changes everything below:

- **T2 chip** (2018–2020, model identifiers `MacBookPro15,x` / `16,x`) — the
  T2 bridges *almost everything*: keyboard, trackpad, audio, the Touch Bar,
  even the SSD. Nothing works without a driver for it.
- **T1 chip** (2016–2017, `MacBookPro13,x` / `14,x`) — much simpler, T1 only
  handles Touch ID/security; the Touch Bar and everything else attach more
  directly and need less special-casing.

Check in macOS:  → About This Mac → model name/year, or in Terminal:
`system_profiler SPHardwareDataType | grep "Model Identifier"`.

Given "one of the last Intel ones," this is almost certainly a **T2 Mac**
(2019 or 2020) — the rest of this doc assumes that; if it turns out to be a
2016/2017 model, the t2linux wiki below still applies but several of the
T2-specific steps (apple-bce) won't be needed.

## Step 1: base hardware bring-up — follow t2linux, don't improvise

**<https://wiki.t2linux.org/>** is the actively-maintained community
resource for this — distro-agnostic install guide, and it covers Arch
directly. Do this whole guide first, before touching the Touch Bar
specifically:

- `apple-bce` (AUR, DKMS) — the T2 bridge driver. Without it: no internal
  keyboard/trackpad, no internal speakers/mic, no Touch Bar device at all.
- Broadcom Wi-Fi firmware/driver (Mac Wi-Fi chips need their own package).
- T2-aware audio routing (the internal speakers need a specific
  `alsa-ucm-conf` profile).
- A kernel new enough for all of the above — the t2linux guide will tell you
  whether Arch's stock `linux` package suffices or whether you need
  `linux-t2` from their repo (this shifts over time as patches land
  upstream; check the wiki's current recommendation when you actually do
  this, don't trust a fixed kernel version here).

Get to a normal working desktop on the laptop before step 2. This part is
the real work; the Touch Bar is a bonus on top of it.

## Step 2: Touch Bar, default option — tiny-dfr

Once `apple-bce` is loaded, the Touch Bar shows up as a HID device. The
default/recommended path (packaged in the AUR as `tiny-dfr`) is a small
daemon that draws a proper function-key + media-control strip — brightness,
volume, mute, media transport, an Esc key — configurable, actively
maintained, and this is what the T2 Linux community actually uses day to
day. Low effort, immediately useful (this laptop has no physical F-row or
Esc key otherwise). Install with `paru -S tiny-dfr`, enable its service per
the t2linux wiki page for your distro.

**Do this first and stop here** unless the itch to make it "yours" is
strong — it already solves the real problem (no physical function keys).

## Step 3 (experimental, stretch goal): the Touch Bar as a real Wayland output

The Touch Bar's kernel driver (`appletbdrm`) got a genuine **DRM mode**
upstreamed into mainline Linux (~6.15): instead of emulating function keys,
it exposes the strip as an honest-to-god second display — the same trick
macOS itself uses. There's at least one first-hand report of Hyprland
enumerating it as a real output (`appletbdrm` + `hid-multitouch` bound,
Hyprland picked it up as a monitor) — which would mean our *exact* existing
`screen: Quickshell.screens.find(s => s.name === "...")` bar-pinning pattern
(same one that pins the main bar to `DP-2`) could target the Touch Bar with
a small purpose-built strip: workspace indicator, media transport, maybe a
clock — real Quickshell QML, not tiny-dfr's fixed layout.

Be honest with yourself about the cost before chasing this:

- Function-key mode and DRM mode are two different personalities of the
  same driver — you likely can't have tiny-dfr's Esc/brightness keys **and**
  a custom Quickshell strip active at once. Losing Esc/brightness on a
  laptop with no physical F-row is a real tradeoff, not a free upgrade.
- This is genuinely bleeding-edge: the t2linux issue tracker has had actual
  regressions where `appletbdrm` stopped binding on specific kernel point
  releases (fixed later, but it shows this path isn't fully settled).
- The strip is very short and very wide (a few thousand pixels wide, maybe
  ~60px tall) — a QML layout for it is a real, fiddly design exercise, not a
  copy of the existing bar.
- **I can't build or test any of this from here** — there's no Touch Bar
  hardware on this desktop to iterate against. Once you're actually on the
  laptop with T2 support working, come back and we can try wiring a real
  Quickshell output for it together, live.

## tl;dr

1. Confirm T2 (almost certainly yes).
2. Follow wiki.t2linux.org top to bottom to get the laptop itself working.
3. Install `tiny-dfr` for the Touch Bar. Stop here unless you want to push further.
4. Only if step 3 feels like it's leaving something on the table: revisit
   `appletbdrm` DRM mode + a custom Quickshell output, together, once the
   hardware is in front of us.
