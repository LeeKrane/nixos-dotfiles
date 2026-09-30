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

**end-4's illogical-impulse Hyprland shell, made fully declarative on NixOS, across three machines.**

[![check](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/check.yml?query=branch%3Amain)
[![update](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/update.yml/badge.svg)](https://github.com/LeeKrane/nixos-dotfiles/actions/workflows/update.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-illogical--impulse-58E1FF?logo=hyprland&logoColor=white)](https://github.com/end-4/dots-hyprland)
[![Nix flake](https://img.shields.io/badge/Nix-flake-7EBAE4)](flake.nix)
[![home-manager](https://img.shields.io/badge/home--manager-NixOS%20module-41439A)](https://github.com/nix-community/home-manager)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

## What's inside

| Desktop | Engineering |
| --- | --- |
| end-4's illogical-impulse (ii) shell on quickshell, wired in declaratively | `just check`: eval and dry-run-build every host in a Docker sandbox, no local Nix needed |
| Agents tab in ii's sidebar listing live Claude Code sessions, plus desktop notifications | CI lint and eval on every push, weekly pull request bumping flake inputs and claude-code |
| Custom Plymouth boot theme (`plymouth-lone`) and a curated wallpaper set | sops-nix secrets, decryptable only by each host's own SSH-derived age key |
| NixVim editor config, also runnable standalone with `nix run .#nvim` | disko layouts and a guarded `install.sh` with `--dry-run` and typed confirmation |
| home-manager as a NixOS module, one switch for system and user | Three GPU profiles: NVIDIA desktop, Intel + NVIDIA PRIME offload, AMD iGPU |

## Hosts

| Host | Role | GPU |
| --- | --- | --- |
| `tariognatha` | Desktop | NVIDIA RTX-4070-Ti-class, open kernel module, single GPU |
| `tarmantria` | Laptop | Intel iGPU + NVIDIA dGPU, PRIME offload |
| `taractias` | Laptop | AMD Vega iGPU, no dGPU |

## How ii is wired in

ii ships its own installer logic, not a plain dotfiles checkout, so this repo pulls it in as the soymou module instead of reimplementing that logic. The soymou module's activation step overwrites most of `~/.config` on every switch, so the wrapper renders Hyprland config into place after it runs. Full mechanics are in [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md). The fallback plan if the soymou module goes stale is [docs/FALLBACK-VENDORING.md](docs/FALLBACK-VENDORING.md).

## Quickstart

```sh
git clone https://github.com/LeeKrane/nixos-dotfiles ~/.dotfiles
cd ~/.dotfiles
just check
```

`just check` evaluates the flake and dry-run-builds every host's toplevel in a throwaway Docker sandbox, needing Docker but no local Nix. `just docker-build <host>` runs a real build. Both cache the Nix store in a persistent volume between runs.

CI runs the same eval and lint gate on every push to `main` and every pull request (`.github/workflows/check.yml`), and a weekly job opens a pull request with updated flake inputs and claude-code (`.github/workflows/update.yml`). Both are eval-only, not builds.

To install onto real hardware, boot a NixOS unstable minimal ISO, clone this repo, then preview the installer before running it for real:

```sh
./install.sh --dry-run
```

**`./install.sh` without `--dry-run` erases the disk you select and takes 20-60+ minutes**, longer on the CUDA host (`tariognatha`), because `nixos-install` compiles quickshell from source. It asks for typed confirmation before touching anything.

```sh
./install.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for the full runbook.

## Layout

```
flake.nix  lib/mk-host.nix   flake entry point, shared host builder
install.sh                   live-ISO installer, post-boot setup script
hosts/<host>/                 hardware, disko layout, Hyprland monitor/input
templates/host/               new-host templates install.sh renders into hosts/<name>/
modules/nixos/                system config: boot, gpu, desktop, sops, ...
modules/home/                 home-manager config: ii wrapper, neovim, ...
overlays/  pkgs/              ii-fixes overlay, plymouth-lone theme
modules/nixvim/               standalone NixVim editor config (packages.nvim)
config/zsh/                   vendored dotfiles
scripts/                      bootstrap-sops.sh, docker-check.sh, Proton Drive mount
secrets/                      nothing committed but README.md and .gitkeep
docs/                         INSTALL, VERIFY, MIGRATION-NOTES, II-INTEGRATION, FALLBACK-VENDORING
```

## Security: what is in this repo on purpose

Left in because it is either meaningless to anyone else or needed for the config to work as shown:

- `modules/nixos/user.nix` defaults the git identity to `krane <chris@krane.dev>`; each host can override it through `krane.user`.
- `modules/nixos/locale.nix` sets the `Europe/Vienna` time zone. The keyboard layout comes from `krane.keyboard.{layout,variant}` (`modules/nixos/keyboard.nix`), default `at` / `nodeadkeys`.
- The hostnames `tariognatha`, `tarmantria`, `taractias`.
- The default username `krane` (`krane.user.name`, overridable per host).

No private keys, passwords, password hashes, API tokens, WireGuard/age/SSH key material, MAC addresses, or LAN/internal IP addresses appear in any tracked file or the published history.

sops-nix encrypts `secrets/*.yaml`, decryptable only by each host's SSH-host-key-derived age identity and the admin's personal key. sshd runs only so `sshd-keygen` generates that host key at boot, with `openFirewall = false` and no password or root login to attack.

If you fork this, change:

- The git identity, locale, keyboard, and hostnames above.
- Every `/dev/CHANGE-ME` disko placeholder, or run `./install.sh`, which does that for you.
- The default username and git identity in `modules/nixos/user.nix`, or set `krane.user` per host. `./install.sh`'s new-host flow asks for both.
- Run your own `scripts/bootstrap-sops.sh` and fill in your own `secrets/*.yaml`. The committed `age1PLACEHOLDER_*` recipients decrypt nothing without the matching private keys, never published.

## History

This repo is published as a single initial commit. The development history that produced it predates the public release and stays on a local branch, unpublished.

## Licence

[MIT](LICENSE), copyright krane, 2026.

The Plymouth boot theme under `pkgs/plymouth-lone/theme/` is a derivative of adi1090x's Plymouth themes and stays under its original GPLv3 licence: see `pkgs/plymouth-lone/theme/LICENSE`.

## Docs

- [docs/INSTALL.md](docs/INSTALL.md): full install runbook, all hosts.
- [docs/VERIFY.md](docs/VERIFY.md): what the checks prove, plus the on-target checklist.
- [docs/MIGRATION-NOTES.md](docs/MIGRATION-NOTES.md): behavioural changes worth knowing about.
- [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md): how the wrapper works, in detail.
- [docs/FALLBACK-VENDORING.md](docs/FALLBACK-VENDORING.md): the exit plan if the soymou module goes stale.
- [secrets/README.md](secrets/README.md): what each secrets file holds and how to create one.
