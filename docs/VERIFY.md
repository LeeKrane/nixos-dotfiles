# Verification

Two layers: the docker loop evaluates and builds on every change, and the on-target checklist proves what a booted machine does.

## 1. Docker loop

`scripts/docker-check.sh` runs a throwaway `nixos/nix` container against a persistent `nixstore` volume. It runs `git add -N` on untracked, non-ignored files first, because flakes only see tracked files. `test`, `ci` and `diff` use local Nix.

```sh
just check                 # nix flake check --no-build + every x86_64 host's toplevel, --dry-run
just eval-host tariognatha # single host, eval only
just docker-build tariognatha # real (slow) build of one host's toplevel
just fmt                   # nix fmt
just lint                  # scripts/lint.sh
just test                  # scripts/tests/*-test.sh, local Nix
just ci                    # lint + test, local Nix
just diff tariognatha      # closure diff vs /run/current-system, run on the target
```

Containers are capped at 6 CPUs and 14g memory. Override per run with `DOCKER_CPUS`, `DOCKER_CPU_SHARES`, `DOCKER_MEMORY`, `NIX_MAX_JOBS`, `NIX_CORES`.

What it proves:

- `nix flake check --no-build`: every module evaluates and every assertion passes. `checks.lua-syntax` runs `luac -p` over every host's rendered Hyprland Lua. `checks.ii-overlay` proves the `ii-fixes` `gnome-icon-theme` alias reaches the NixOS pkgs shared via `useGlobalPkgs`.
- `nix build ...toplevel --dry-run` for every x86_64 host: the closure's dependency graph is sound. The aarch64 Pis are only evaluated (`checks.pi-eval`, CI).
- `just docker-build <host>`: a real build succeeds. It is slow because quickshell compiles from source.

It cannot prove anything that needs a booted kernel: boot, systemd-boot, plymouth, the NVIDIA module, monitor layout, `home.activation` ordering (docker only evaluates the script text), Quickshell rendering, or greetd. Those are the on-target checklist.

## 2. On-target checklist

Run it on a real install after two consecutive `nixos-rebuild switch` runs: the first switch's ii dotfiles copy must run before the second switch's `kraneIiOverrides` entry has anything to check. See [docs/II-INTEGRATION.md](II-INTEGRATION.md).

### Autologin and lock-on-start

Every host autologins into Hyprland (`initial_session` in `modules/nixos/desktop/desktop.nix`) and locks at session start (`modules/home/desktop/lock-on-start.nix`). `loginctl`'s `LockedHint` is not proof: it only reflects the last `lock-session` call, not whether ii's lock surface is drawn. Check instead:

- After a fresh reboot, the ii lock panel is visible, not a bare desktop and not tuigreet.
- `journalctl --user -b | grep krane-lock-on-start` prints nothing. Any line means ii's lock IPC never appeared and the plain `hyprlock` fallback ran.
- After the first unlock, `~/.config/quickshell/ii/scripts/keyring/is_unlocked.sh` prints `Keyring is unlocked`. Autologin gives PAM no password, so ii's lock screen unlocks the keyring itself (`security.unlockKeyring` is `true`). If it is locked, expect a keyring prompt from NetworkManager or a browser.
- The lock screen's reboot/poweroff buttons skip the password prompt while `requirePasswordToPower` is `false` in `~/.config/illogical-impulse/config.json`, the current value. `launchOnStartup` is patched to `true` on fresh hosts (see [docs/II-INTEGRATION.md](II-INTEGRATION.md) "Patched files").

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
| Logitech G502 libinput name matches `display.nix`'s `devices[].name`, otherwise the block applies to nothing | `hyprctl devices \| grep -i logitech` | tariognatha |
| Built-in ELAN I2C touchpad shows up with no extra config | `hyprctl devices \| grep -i touchpad` | taractias |
| Single-panel scale guess in `display.nix` | `hyprctl monitors -j \| jq '.[] \| {name, scale}'` | taractias |
| Vega iGPU VA-API decode uses Mesa's radeonsi | `vainfo \| grep -i driver` | taractias |
| PRIME offload reaches the dGPU | `nvidia-offload glxinfo \| grep vendor` | tarmantria |
| Wi-Fi came up after the first reboot (`rtw88` on taractias) | `nmcli device status \| grep -i wifi` | tarmantria, taractias |
| Bluetooth came up after the first reboot | `bluetoothctl show \| grep -i powered` | tarmantria, taractias |
| Windows dual-boot entry present, if expected. See [docs/INSTALL.md](INSTALL.md) "Windows dual-boot entry" | `sudo bootctl list` | All, if dual-booting |
| Proton Drive mounted | `systemctl --user status proton-drive-mount` | All |
| teamclaude proxy running with at least one seat (none yet: `teamclaude login` once per seat) | `systemctl --user status teamclaude; teamclaude status` | All |
| wg0 up, peer has a recent handshake | `sudo wg show wg0` | Hosts with a `wireguard:` section in `secrets/<host>.yaml` |
| wg0 has this host's tunnel address | `ip -br addr show wg0` | Hosts with a `wireguard:` section in `secrets/<host>.yaml` |

The Wi-Fi and Bluetooth checks cover `hardware.enableRedistributableFirmware` (`modules/nixos/desktop/hardware.nix`), which `nixos-generate-config` never enables.

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
