# Verification

Two layers: the docker loop evaluates and builds on every change, and the on-target checklist proves what a booted machine does.

## 1. Docker loop

`scripts/docker-check.sh` runs a throwaway `nixos/nix` container against a persistent `nixstore` volume. It runs `git add -N` on untracked, non-ignored files first, because flakes only see tracked files. `test`, `ci` and `diff` use local Nix.

```sh
just check                    # nix flake check --no-build + every x86_64 host's toplevel, --dry-run
just docker-build tariognatha # real (slow) build of one host
just diff tariognatha         # closure diff vs /run/current-system, on the target
```

The other recipes and the container resource overrides are in the `justfile`.

`just check` proves every module evaluates, every assertion and `checks.*` (including `lua-syntax` over each host's rendered Hyprland Lua) pass, and every x86_64 host's closure resolves. The aarch64 Pis are only evaluated (`checks.pi-eval`, CI). Anything that needs a booted kernel (boot, NVIDIA, monitors, activation ordering, Quickshell, greetd) is the on-target checklist.

## 2. On-target checklist

Run it on a real install after two consecutive `nixos-rebuild switch` runs: the first switch's ii dotfiles copy must run before the second switch's `kraneIiOverrides` entry has anything to check. See [docs/II-INTEGRATION.md](II-INTEGRATION.md).

### Autologin and lock-on-start

Every host autologins into Hyprland (`initial_session` in `modules/nixos/desktop/desktop.nix`) and locks at session start (`modules/home/desktop/lock-on-start.nix`). Check:

- After a fresh reboot, the ii lock panel is visible, not a bare desktop and not tuigreet.
- `journalctl --user -b | grep krane-lock-on-start` prints nothing. Any line means ii's lock IPC never appeared and the plain `hyprlock` fallback ran.
- After the first unlock, `~/.config/quickshell/ii/scripts/keyring/is_unlocked.sh` prints `Keyring is unlocked`. Autologin gives PAM no password, so ii's lock screen unlocks the keyring itself (`security.unlockKeyring` is `true`). If it is locked, expect a keyring prompt from NetworkManager or a browser.
- The lock screen's reboot/poweroff buttons skip the password prompt unless `requirePasswordToPower` is `true` in `~/.config/illogical-impulse/config.json`. `launchOnStartup` is patched to `true` on fresh hosts (see [docs/II-INTEGRATION.md](II-INTEGRATION.md) "Patched files").

### Checks

| Check | Command | Host |
| --- | --- | --- |
| Owned Hyprland files carry the generated header (`header` in `modules/home/desktop/hypr-config.nix`) | `head -4 ~/.config/hypr/custom/keybinds.lua` | All |
| Override block appears once in `env.lua`, want `1` | `grep -c -- '-- >>> krane overrides >>>' ~/.config/hypr/custom/env.lua` | All |
| Override block appears once in `general.lua`, want `1` | `grep -c -- '-- >>> krane overrides >>>' ~/.config/hypr/custom/general.lua` | All |
| Hyprland accepted the whole config: empty output | `hyprctl configerrors` | All |
| Keybinds survived the switch (no latched emergency mode) | `hyprctl binds \| head -5` | All |
| Cursor theme from `modules/home/desktop/cursor.nix` installed and set for GTK, want `Bibata-Modern-Classic` twice | `ls /etc/profiles/per-user/$USER/share/icons \| grep Bibata-Modern-Classic$; grep gtk-cursor-theme-name ~/.config/gtk-3.0/settings.ini` | All |
| Monitor layout matches `hosts/<host>/display.nix` and the GUI-owned positions in `ii-settings.json` | `hyprctl monitors -j \| jq '.[] \| {name, width, height, refreshRate, scale, transform}'` | All |
| PRIME offload reaches the dGPU | `nvidia-offload glxinfo \| grep vendor` | tarmantria |
| Wi-Fi came up after the first reboot (needs `hardware.enableRedistributableFirmware`) | `nmcli device status \| grep -i wifi` | tarmantria, taractias |
| Bluetooth came up after the first reboot | `bluetoothctl show \| grep -i powered` | tarmantria, taractias |
| Windows dual-boot entry present, if expected. See [docs/INSTALL.md](INSTALL.md) "Windows dual-boot entry" | `sudo bootctl list` | All, if dual-booting |
| Proton Drive mounted | `systemctl --user status proton-drive-mount` | All |
| teamclaude proxy running with at least one seat (none yet: `teamclaude login` once per seat) | `systemctl --user status teamclaude; teamclaude status` | All |
| wg0 up, peer has a recent handshake | `sudo wg show wg0` | Hosts with a `wireguard:` section in `secrets/<host>.yaml` |
| wg0 has this host's tunnel address | `ip -br addr show wg0` | Hosts with a `wireguard:` section in `secrets/<host>.yaml` |

### Settings window

- `readlink -f ~/.config/illogical-impulse` is `~/.dotfiles/hosts/<host>/illogical-impulse`.
- `krane-ii-settings render --json ~/.dotfiles/hosts/<host>/ii-settings.json | diff - ~/.config/hypr/custom/krane_gui.lua` prints nothing.
- `hyprctl configerrors` is empty; `qs log -c ii` has no `[KraneSettings]` warning.
- `SUPER + I` opens every page; closing it leaves the bar running.
- One control per config.json page changes exactly one key in `git diff hosts/<host>/illogical-impulse/config.json`.
- Hyprland page: gaps set to 12 shows in `hyprctl getoption general:gaps_in` within a second and in `git diff hosts/<host>/ii-settings.json`; reset removes the key and restores the value without a switch.
- Keyboard layout (and on tariognatha idle) is disabled with "Set in Nix".
- Displays: a change reverts after 15 s unless kept; a kept change asks again after the next reboot.
- `systemctl --user is-active krane-ii-settings-revert.timer` is `inactive` when no change is pending.
- After a reboot with no switch, `krane_gui.lua` still matches a `set`/`reset` made before it.

### Bar icon popouts

- Each of the network, Bluetooth, speaker and mic icons opens its popout next to the icon, on your real bar layout.
- Typing a Wi-Fi password in the Wi-Fi popout works.
- The Wi-Fi and Bluetooth power switches work.
- Lock the screen with a popout open; after unlock it stays closed.
- Click outside, Esc, a second click on the icon and Details each close a popout.
- Mute buttons and sliders work; scrolling over the bar moves the speaker slider.
- The notification icon and empty indicator space still toggle the right sidebar.
- With Settings > Bar > Icon popouts off, speaker and mic icons appear only when muted and every click opens the sidebar.
- The sidebar volume dialogs and the overlay mixer show the new mute button and slider, nothing else changed.
- The look (card size, spacing, shadow, corners) fits the rest of the shell.

### End4-pC fixes

- Dismiss a notification before its 7 s timeout; `qs log -c ii` has no new `TypeError`.
- The About page shows the discrete GPU (tariognatha). The `lspci` fallback only runs when the `glxinfo` Intel match is empty; otherwise read `getGpu` in `services/SystemInfo.qml`.
- `sed '/^esac/q' ~/.config/quickshell/ii/scripts/ai/gemini-categorize-wallpaper.sh | bash -s -- <video>` ends in seconds and leaves a 200 px `/tmp/quickshell/ai/wallpaper.jpg` (no network call).
- `rm -rf ~/.cache/thumbnails/<size>`, then open the wallpaper selector: thumbnails appear.
- After a screenshot copy, `wl-paste --list-types` lists `image/png`.
- Dragging a window preview in the overview does not close it.
- Play something with data-URI or raw-path art (for example Telegram): the art shows. Plain http art still shows.

### Left sidebar icon picker

- Settings > Bar > "Left sidebar button" lists the built-in icons and highlights the current one.
- The grid includes the Claude Code icon (`claude-code`).
- Picking an icon and a color changes the bar button at once and survives a shell restart.
- A folder of `.svg` or `.png` files in "Custom icons folder" replaces the grid; picking one shows it on the button in its own colors. A folder name with spaces or `#` works. Emptying the field, or removing the picked file, shows `spark`.
- With AI, translator and anime off and Agents on, the button is visible; with Agents off too it is hidden.

### Lock screen

Run on a host with two monitors (tariognatha). Lock with `qs -c ii ipc call lock activate`.

- With the pointer on each monitor in turn, lock and unlock: the pointer position and the focused monitor (`hyprctl monitors -j | jq -r '.[] | select(.focused).name'`) are back where they were.
- In Settings > Hyprland > Displays, select each monitor and press "Make main monitor" (the selected main monitor shows "This is the main monitor" instead of the button): the password prompt, clock and weather appear only there, the other monitor shows the wallpaper, typing works with the pointer on either monitor, and the password unlocks.
- Click the wallpaper-only monitor while locked: nothing happens (no suspend, reboot or power-off).
- With "Automatic (first monitor)" selected, and with a saved name whose monitor is unplugged: the prompt appears on the first monitor, whichever one has the pointer.
- Unplug the prompt monitor while locked: the prompt moves to the remaining monitor.
- Boot with `launchOnStartup` on, with "Main monitor" set and then empty: a prompt appears either way.
- Turn "Enable blur" off: the monitor without the prompt shows the unblurred wallpaper.
- Lock with windows open on both monitors: `hyprctl monitors -j | jq -c '[.[] | .activeWorkspace.id]'` shows empty workspaces that no window and no workspace rule uses; the original workspaces return after unlock.
- Waffle lock, on a host that enables it: unchanged.
