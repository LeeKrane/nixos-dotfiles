# Verification

Two layers prove different, non-overlapping slices of correctness. The
docker eval and build loop runs fast, on every change. The on-target
checklist is the only real proof of what the docker loop cannot touch at
all.

## 1. Docker loop

Everything here runs via `scripts/docker-check.sh`, wrapping a throwaway
`nixos/nix` container against a persistent `nixstore` docker volume. See
its own header comment for what each invocation does.

```sh
just docker-check          # nix flake check --no-build --show-trace
                            # + tariognatha, tarmantria and taractias
                            # toplevel, --dry-run
just eval-host tariognatha  # fast: single host, eval only, no build
just docker-build tariognatha   # real (slow) build of one host's toplevel
just fmt                    # nix fmt
just lint                   # statix check + deadnix, report-only
```

`scripts/docker-check.sh` runs `git add -A` before every one of these.
Flakes only ever see git-tracked or staged files.

Every `docker run` this script does is capped by default at 6 CPUs and
14g memory, so a real build doesn't peg the host it runs on. Override per
invocation on a bigger or smaller machine: `DOCKER_CPUS`,
`DOCKER_CPU_SHARES`, `DOCKER_MEMORY`, `NIX_MAX_JOBS`, `NIX_CORES`.

### What it proves

- `nix flake check --no-build`: every module evaluates. `checks.lua-syntax`
  runs `luac -p` over every rendered Hyprland Lua file for all three
  hosts. Option types and assertions all pass.
- `nix eval …pkgs.gnome-icon-theme.pname`: the `ii-fixes` overlay reaches
  home-manager's package set, not just the NixOS-level one.
- `nix build …toplevel --dry-run` for all three hosts: every derivation in
  the closure would build. The dependency graph is sound, with no missing
  or renamed nixpkgs attrs and no `throw`s hit.
- `just docker-build <host>`: a real build succeeds. It runs slow, because
  quickshell compiles from source with no binary cache.

### What it cannot prove

Anything that exists only once a kernel boots on real or virtualised
hardware:

- Boot process, systemd-boot, plymouth. On-target only.
- The NVIDIA kernel module loading. On-target only.
- Monitor layout, transforms and scale, checked with `hyprctl monitors -j`.
  On-target only.
- `home.activation` ordering between `kraneIiOverrides` and
  `copyIllogicalImpulseConfigs`. On-target only: docker only evaluates the
  activation script text, never runs it.
- Quickshell rendering a working shell. On-target only.
- greetd/tuigreet presenting a session picker. On-target only.

## 2. On-target checklist

Run these on a real install, after two consecutive `nixos-rebuild switch`
runs. The first switch's illogical-impulse (ii) dotfiles-copy step has to
run once before the second switch's `kraneIiOverrides` activation entry
means anything to check. See [docs/II-INTEGRATION.md](II-INTEGRATION.md).

| Check | Command | Host |
| --- | --- | --- |
| Owned Hyprland files carry the generated header (`modules/home/hypr-config.nix`'s `header` function) | `head -4 ~/.config/hypr/custom/keybinds.lua` | All |
| Override block appears exactly once in `env.lua`, want `1` | `grep -c -- '-- >>> krane overrides >>>' ~/.config/hypr/custom/env.lua` | All |
| Override block appears exactly once in `general.lua`, want `1` | `grep -c -- '-- >>> krane overrides >>>' ~/.config/hypr/custom/general.lua` | All |
| Hyprland accepted the whole config, no unknown-key errors | `hyprctl configerrors` | All |
| Monitor layout matches `hosts/<host>/display.nix` | `hyprctl monitors -j \| jq '.[] \| {name, width, height, refreshRate, scale, transform}'` | All |
| Logitech G502 libinput device name matches `display.nix`'s `devices[].name` | `hyprctl devices \| grep -i logitech` | tariognatha |
| Built-in ELAN I2C touchpad shows up with no extra config | `hyprctl devices \| grep -i touchpad` | taractias |
| Single-panel scale guess in `display.nix` | `hyprctl monitors -j \| jq '.[] \| {name, scale}'` | taractias |
| Vega iGPU VA-API decode goes through Mesa's radeonsi driver | `vainfo \| grep -i driver` | taractias |
| PRIME offload reaches the dGPU | `nvidia-offload glxinfo \| grep vendor` | tarmantria |
| Wi-Fi came up after the first reboot | `nmcli device status \| grep -i wifi` | tarmantria, taractias |
| Bluetooth came up after the first reboot | `bluetoothctl show \| grep -i powered` | tarmantria, taractias |
| Windows dual-boot entry present, if expected. See [docs/INSTALL.md](INSTALL.md) "Windows dual-boot entry" | `bootctl list` | All, if dual-booting |
| Proton Drive mounted | `systemctl --user status proton-drive-mount` | All |

`modules/nixos/hardware.nix`'s `hardware.enableRedistributableFirmware`
makes the iwlwifi, rtw88 and Bluetooth adapters work on the laptop hosts.
`nixos-generate-config` never turns it on by itself, so these two checks
are the one thing docker verification cannot prove. On taractias,
`rtw88` should show the in-kernel RTL8821CE adapter.
