# ii settings: what's changing

This branch adds a settings window to the ii (illogical-impulse) desktop, so
common Hyprland and desktop preferences can be changed from a GUI instead of
by hand-editing Nix files.

## What you get

- A settings window (opened the same way ii's other settings pages are
  opened) with pages for Hyprland look-and-feel (gaps, borders, blur,
  rounding, animations), idle/lock timeouts, display setup (resolution,
  scale, position, rotation, color management, HDR/SDR brightness), and
  autostart apps.
- Changes you make in the window take effect immediately and are saved per
  host, so they survive a `nixos-rebuild switch` the same way your other Nix
  config does.
- Nix still owns anything you've set in your host config directly — those
  fields show as locked in the GUI instead of silently being overwritten or
  fighting with Nix on the next switch.
- Display changes go through a confirm-or-revert step: apply a new display
  setting and you have 15 seconds to keep it before it automatically reverts,
  so a bad resolution or HDR setting can't lock you out of your session.
- A first-boot check re-asks about any display change you hadn't confirmed
  yet, but only for monitors that are actually connected.
- Animation, color, and profile pages ported from the upstream illogical-impulse
  settings UI are also available.

## What to expect right now

A handful of rough edges are still open and tracked for a fix before this
merges — see
[2026-10-02-ii-settings-premerge.md](2026-10-02-ii-settings-premerge.md) for
the list, and
[2026-10-02-ii-settings-manual-test.md](2026-10-02-ii-settings-manual-test.md)
for how to check them. The short version: a GUI change made between two
`nixos-rebuild switch` runs can be lost on a plain reboot until the boot-path
fix lands, and a few input fields need tighter validation before they're
fully hardened against bad input. None of this affects anything outside the
new settings window.

See [2026-10-02-ii-settings-user-steps.md](2026-10-02-ii-settings-user-steps.md)
for what's left for you to do before merging.
