# ii settings: manual test checklist

Grouped by area, ordered to need the fewest switches, reboots, and monitor
hotplugs: A-D and G are pure GUI/session checks on an already-switched host
(no reboot, no unplugging anything); E and F both need a reboot and are
combined into one reboot cycle at the end, with a monitor unplugged before
that reboot and replugged after.

Each item notes whether it already passes today or needs one of the three
fix specs first:
[2026-10-02-ii-settings-boot-path-design.md](../specs/2026-10-02-ii-settings-boot-path-design.md) (Spec 1),
[2026-10-02-ii-settings-gui-write-paths-design.md](../specs/2026-10-02-ii-settings-gui-write-paths-design.md) (Spec 2),
[2026-10-02-ii-settings-input-hardening-design.md](../specs/2026-10-02-ii-settings-input-hardening-design.md) (Spec 3).
Background on each issue is in
[2026-10-02-ii-settings-premerge.md](2026-10-02-ii-settings-premerge.md).

Open the settings window with SUPER+I throughout.

## A. Hyprland page — Layout & Input

- [ ] (works today) Change a gap/border/rounding/blur value; confirm
      `hyprctl getoption <key>` reflects it and `hosts/<host>/ii-settings.json`
      gains exactly that key.
      ```
      krane-ii-settings set hyprland general:gaps_in 12 && sleep 1 && hyprctl getoption general:gaps_in -j | jq -r .css
      git -C ~/.dotfiles diff hosts/<host>/ii-settings.json
      ```
- [ ] (works today) Reset the same value; confirm the key leaves the repo
      file:
      ```
      krane-ii-settings reset hyprland general:gaps_in && sleep 1 && hyprctl getoption general:gaps_in -j | jq -r .css
      git -C ~/.dotfiles diff --stat hosts/<host>/ii-settings.json
      ```
- [ ] (works today) Open the page twice without changing anything:
      `git -C ~/.dotfiles diff hosts/*/ii-settings.json` must print nothing
      (no write-on-load).
- [ ] (needs Spec 2, M4) Drag a spin box (repeat delay/rate, touchpad scroll
      factor, blur passes/size) slowly; confirm exactly one write lands per
      committed edit, not one per intermediate tick during the drag.

## B. Idle page

- [ ] (works today) On tariognatha, idle rows show the "set in Nix" locked
      notice and cannot be edited. On tarmantria, they're editable and a
      change updates `hypridle.conf` and restarts `hypridle` only when the
      rendered config actually changed.
- [ ] (needs Spec 2, M3) Start a monitor `try` (Displays page), then try to
      change an idle timeout while the revert countdown is still showing;
      confirm the Idle page is disabled for that duration rather than
      accepting the write.

## C. Visual & Aesthetics, Autostart Apps, Animations

- [ ] (works today) Pick each animation preset in turn (Stock, Elastic,
      Normal, Niri Like); after each, `hyprctl configerrors` must be empty.
- [ ] (needs Spec 2, M4) Same drag-vs-commit check as Area A for any spin
      box in Visual & Aesthetics.
- [ ] (needs Spec 3) Ask the AI assistant to change a shell config value
      (anything reachable via `set_shell_config`, e.g. a theme or accent
      color); confirm a confirmation prompt appears before the value
      changes, and that rejecting it leaves the value unchanged. Today this
      applies with no prompt at all.

## D. Displays

- [ ] (works today) Drag a monitor on the canvas; confirm only the dragged
      monitor's position is written, others are untouched.
- [ ] (works today) Change scale, transform, bit depth, or color management
      on an output Nix does not own for that field; confirm a 15-second
      keep-or-revert banner appears, and that letting it time out reverts to
      the previous live value.
- [ ] (works today) Same change, but click Keep before the timer runs out;
      confirm the value stays and the repo file records it.
- [ ] (needs Spec 2, SDR/luminance/VRR gating) On an output where Nix owns
      `sdrbrightness`/`sdrsaturation`/the luminance fields, confirm those
      controls are disabled (locked), not just `scale`/`transform`/`mode`.
- [ ] (needs Spec 2, countdown fix) Start a `try`, close and reopen the
      settings window partway through the 15 seconds; confirm the countdown
      shown picks up from the real remaining time, not a fresh 15.
- [ ] (works today) HDR: raise SDR/HDR luminance values within schema range;
      confirm `hyprctl configerrors` stays empty and the canvas preview
      updates.
- [ ] (works today, tarmantria only) Reload at scale 1.6 with the external
      HDMI output attached; confirm the GUI's eDP-1 transform/color
      management survive the reload instead of resetting.

## E. Boot-time persistence (reboot without switch)

- [ ] (needs Spec 1, D1) Set a Hyprland value through the GUI (e.g.
      `general:gaps_in`), do **not** run `nixos-rebuild switch`, reboot, and
      confirm `hyprctl getoption general:gaps_in` still reflects the GUI
      value after the reboot. This currently fails: the value reverts to
      whatever was live at the last switch.
- [ ] (needs Spec 1, D1) Make an unconfirmed display change (a `try` that
      you let time out so it's recorded as `bootConfirmed: false`), reboot
      without switching, and confirm the keep/revert dialog shown at login
      reflects a setting that is actually live at that point, not one that
      was silently dropped on the way up.

## F. Boot-check with a monitor unplugged/replugged

Combine with Area E's reboot — unplug one external monitor before the
reboot, leave it unplugged through login, then replug it afterward.

- [ ] (works today) With an unconfirmed display change recorded for the
      unplugged monitor, confirm the boot-check dialog does **not** ask
      about that monitor while it's disconnected, and does not delete its
      recorded settings either.
- [ ] (works today) Replug the monitor later (same session, no reboot
      needed); confirm it is asked about then, using the settings recorded
      before the reboot.
- [ ] (needs Spec 1, M2) If ii's own Quickshell instance is slow to start at
      this boot (simulate by delaying `qs -c ii`, or just note whether this
      happens on your hardware), confirm the settings dialog waits for the
      fallback `hyprlock` to clear before opening, instead of appearing on
      top of it.

## G. Presets

- [ ] (works today) Save a preset with a normal name, apply it, remove it.
- [ ] (needs Spec 3) Attempt to save or export a preset with a name
      containing `/`, `..`, or a leading dot; confirm it's rejected before
      any file is written, both from the settings window and from
      `presets.sh` run directly.
- [ ] (needs Spec 3) Hand-edit `hosts/<host>/illogical-impulse/config.json`'s
      autostart list to include one malformed entry (not an object, or a
      non-string `cmd`) alongside valid ones; confirm the valid entries
      still start and a warning is logged for the bad one, instead of every
      entry after it failing to start.
