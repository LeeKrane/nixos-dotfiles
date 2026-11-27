```text
 __  __               _____   ____            __          __       ___      ___
/\ \/\ \  __         /\  __`\/\  _`\         /\ \        /\ \__  /'___\ __ /\_ \
\ \ `\\ \/\_\   __  _\ \ \/\ \ \,\L\_\       \_\ \    ___\ \ ,_\/\ \__//\_\\//\ \      __    ____
 \ \ , ` \/\ \ /\ \/'\\ \ \ \ \/_\__ \       /'_` \  / __`\ \ \/\ \ ,__\/\ \ \ \ \   /'__`\ /',__\
  \ \ \`\ \ \ \\/>  </ \ \ \_\ \/\ \L\ \    /\ \L\ \/\ \L\ \ \ \_\ \ \_/\ \ \ \_\ \_/\  __//\__, `\
   \ \_\ \_\ \_\/\_/\_\ \ \_____\ `\____\   \ \___,_\ \____/\ \__\\ \_\  \ \_\/\____\ \____\/\____/
    \/_/\/_/\/_/\//\/_/  \/_____/\/_____/    \/__,_ /\/___/  \/__/ \/_/   \/_/\/____/\/____/\/___/
```

<div align="center">

**end-4's illogical-impulse Hyprland shell, made fully declarative on NixOS, across seven machines: three desktops and four servers.**

<sub>Built on [end-4's dots-hyprland](https://github.com/end-4/dots-hyprland), wrapped by [soymou's illogical-flake](https://github.com/soymou/illogical-flake), with fixes from [pctrade's end4-pC](https://github.com/pctrade/end4-pC).</sub>

[![check](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/check.yml?query=branch%3Amain)
[![update](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/update.yml/badge.svg)](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/update.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-illogical--impulse-58E1FF?logo=hyprland&logoColor=white)](https://github.com/end-4/dots-hyprland)
[![Nix flake](https://img.shields.io/badge/Nix-flake-7EBAE4)](flake.nix)
[![home-manager](https://img.shields.io/badge/home--manager-NixOS%20module-41439A)](https://github.com/nix-community/home-manager)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

## What's inside

- end-4's illogical-impulse (ii) shell on quickshell, wired in declaratively, with an Agents tab in its sidebar listing live Claude Code sessions.
- Custom Plymouth boot theme (`plymouth-lone`) and a curated wallpaper set.
- NixVim editor config, also runnable standalone with `nix run .#nvim`.
- Checks, CI, weekly update PRs and server auto-upgrades (below), sops-nix secrets, disko layouts and a guarded `install.sh`.

## Hosts

| Host | Role | GPU / hardware |
| --- | --- | --- |
| `tariognatha` | Desktop | NVIDIA, open kernel module, single GPU |
| `tarmantria` | Laptop | Intel iGPU + NVIDIA dGPU, PRIME offload |
| `taractias` | Laptop | AMD iGPU, no dGPU |
| `taragarmr` | Server | x86_64 mini PC (AZW SER, Ryzen 7 6800H): the server stack, WireGuard hub and public ingress |
| `taronychus` | Server | Raspberry Pi 5, aarch64 |
| `tarritator` | Server | Raspberry Pi 5, aarch64 |
| `tarronax` | Server | Raspberry Pi 4, aarch64 |

## How ii is wired in

This repo pulls ii in as the soymou module instead of reimplementing ii's installer logic. The module's activation step overwrites most of `~/.config` on every switch, so the wrapper renders Hyprland config into place after it runs. Mechanics, patches and the exit plan if the module goes stale: [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md), [If the soymou module breaks](docs/II-INTEGRATION.md#if-the-soymou-module-breaks).

## Checks, CI and deploys

`just check` and CI eval-check every host and dry-run-build the x86_64 ones (the aarch64 Pis are evaluated only in CI); `just hooks` installs a pre-push hook running `scripts/lint.sh`, the same lint as CI. Details: [docs/VERIFY.md](docs/VERIFY.md). Weekly update pull requests come in two lanes, servers and desktops. When a commit on `main` passes the check, `.github/workflows/promote.yml` moves the `deploy` branch to it, and the servers auto-upgrade from `deploy`.

Things that are easy to break here:

- The update pull requests are opened with `GITHUB_TOKEN`, so GitHub does not run `check.yml` on them. `update-lane.yml` calls it itself and reports the result in the PR body; `check.yml` runs again on `main` after the merge.- Every gated `main` commit reaches the servers, including desktop-only ones, because `system.configurationRevision` (`lib/mk-host.nix`) is the commit. Such a commit causes a revision-only activation, and the upgrade hooks compare that revision with `deploy`, so do not remove it. A desktop-lane `nixpkgs` bump also changes the server closures: `modules/home/server/default.nix` takes `codegraph` from `nixpkgs-unstable`. The PR body's "Merging deploys to" line lists the servers a PR reaches.
- A server upgrade that fails its health check rolls back, including after the reboot a kernel change triggers (`scripts/server-upgrade-hooks.sh`, `boot-health`). A kernel that does not boot never reaches that check.
- The desktop notifier (`modules/home/desktop/flake-update-notify.nix`) parses the PR body's `### Package versions`, `### Inputs` and `### Security` headings from `scripts/update-summary.sh` and `scripts/security-summary.sh`. Rename them only together with `scripts/flake-update-notify.sh`.

## Installs

The desktops and laptops are installed from a NixOS unstable minimal ISO by `install.sh`: runbook in [docs/INSTALL.md](docs/INSTALL.md). The servers are installed differently: `taragarmr` with nixos-anywhere, the Pis from flashable images (`packages.image-<host>`); each host's `hosts/<host>/default.nix` header records how.

## Gotchas

- Login shell is fish; its config lives at the NixOS level because ii wipes `~/.config/fish` on every switch. zsh stays as a fallback behind `krane.zshFallback.enable` (default true, `modules/home/common/zsh-fallback.nix`): `exec zsh`.
- Neovim is the standalone NixVim build (`modules/nixvim/`), installed by `modules/home/common/neovim.nix`; `~/.config/nvim` is unused. `just nvim <file>` tries changes without switching. Colors follow the wallpaper: `modules/nixvim/lua/dynamic-theme.lua` reads ii's `material_colors.scss` and falls back to a built-in palette without it.
- ii's default browser is zen (`browser` in `hosts/*/display.nix`, package from the zen-browser flake in `modules/home/desktop/apps.nix`).
- `home.stateVersion` is "26.05" (`modules/home/common/default.nix`). Do not bump it on an existing install without reading home-manager's release notes.

## Layout

```
flake.nix  lib/mk-host.nix   flake entry point, shared host builder
install.sh                   live-ISO installer, post-boot setup script
hosts/<host>/                hardware, disko layout, Hyprland monitor/input; optional host.nix = { system, role, board, image } (default x86_64-linux, desktop; board and image are for the Pis)
templates/host/              new-host templates install.sh renders into hosts/<name>/
modules/nixos/{common,desktop,server}/  system config by role, gpu/ per host
modules/home/{common,desktop,server}/   home-manager config by role: ii wrapper, neovim, ...
modules/nixvim/              standalone NixVim editor config (packages.nvim)
overlays/  pkgs/  patches/   overlays, own packages (plymouth-lone, ...), patches for ii and ii-flake
config/zsh/                  vendored dotfiles
assets/wallpapers/           curated wallpaper set
android/                     ani-cli launcher app
scripts/                     bootstrap-sops.sh, docker-check.sh, lint.sh, CI and update helpers, Proton Drive mount
secrets/                     sops-encrypted <host>.yaml per host, README.md
tests/server-host/           server-role config evaluated by CI, not a real host
docs/                        INSTALL, VERIFY, II-INTEGRATION
```

## Security: what is in this repo on purpose

Left in because it is meaningless to anyone else or needed for the config to work as shown: the git identity `krane <chris@krane.dev>` (`modules/nixos/common/user.nix`), username and hostnames, the `Europe/Vienna` time zone and `at` / `nodeadkeys` keyboard defaults, the RFC 1918 LAN and WireGuard addresses (`lib/lan.nix`, `lib/wireguard.nix`) and the SSH public keys the servers accept (`lib/ssh-keys.nix`).

No private keys, passwords, password hashes, API tokens, WireGuard/age/SSH private key material, or MAC addresses appear in any tracked file or the published history. Secrets: [secrets/README.md](secrets/README.md).

## Licence

[MIT](LICENSE), copyright krane, 2026. Third-party material (the Plymouth theme, the ii patches, vendored LazyVim and powerlevel10k files) keeps its own licence: see [LICENSE](LICENSE).

## Docs

- [docs/INSTALL.md](docs/INSTALL.md): install runbook for the desktops and laptops.
- [docs/VERIFY.md](docs/VERIFY.md): what the checks prove, plus the on-target checklist.
- [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md): how the ii wrapper works, and the exit plan if the soymou module goes stale.
- [secrets/README.md](secrets/README.md): what each secrets file holds and how the keys are set up.