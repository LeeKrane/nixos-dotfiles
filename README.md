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

| Desktop | Engineering |
| --- | --- |
| end-4's illogical-impulse (ii) shell on quickshell, wired in declaratively | `just check`: eval and dry-run-build every x86_64 host in a Docker sandbox, no local Nix needed |
| Agents tab in ii's sidebar listing live Claude Code sessions, plus desktop notifications | CI lint and eval on every push, weekly update pull requests in two lanes (servers, desktops), servers auto-upgrading from a `deploy` branch |
| Custom Plymouth boot theme (`plymouth-lone`) and a curated wallpaper set | sops-nix secrets, decryptable only by each host's own SSH-derived age key |
| NixVim editor config, also runnable standalone with `nix run .#nvim` | disko layouts and a guarded `install.sh` with `--dry-run` and typed confirmation |
| home-manager as a NixOS module, one switch for system and user | Three GPU profiles: NVIDIA desktop, Intel + NVIDIA PRIME offload, AMD iGPU |

## Hosts

| Host | Role | GPU / hardware |
| --- | --- | --- |
| `tariognatha` | Desktop | NVIDIA RTX-4070-Ti-class, open kernel module, single GPU |
| `tarmantria` | Laptop | Intel iGPU + NVIDIA dGPU, PRIME offload |
| `taractias` | Laptop | AMD Vega iGPU, no dGPU |
| `taragarmr` | Server | x86_64 mini PC (AZW SER, Ryzen 7 6800H): the server stack, WireGuard hub and public ingress |
| `taronychus` | Server | Raspberry Pi 5, aarch64 |
| `tarritator` | Server | Raspberry Pi 5, aarch64 |
| `tarronax` | Server | Raspberry Pi 4, aarch64 |

## How ii is wired in

ii ships its own installer logic, not a plain dotfiles checkout, so this repo pulls it in as the soymou module instead of reimplementing that logic. The soymou module's activation step overwrites most of `~/.config` on every switch, so the wrapper renders Hyprland config into place after it runs. Full mechanics are in [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md). The fallback plan if the soymou module goes stale is [docs/FALLBACK-VENDORING.md](docs/FALLBACK-VENDORING.md).

## Checks, CI and deploys

`just check` evaluates the flake and dry-run-builds every x86_64 host's toplevel in a throwaway Docker sandbox (the aarch64 Pis are evaluated only in CI), so the whole config can be checked on a machine with Docker but no Nix. `just docker-build <host>` does a real build in the same sandbox. Both keep the Nix store in a persistent volume between runs. A pre-push hook (`just hooks`) runs the same lint as CI, `scripts/lint.sh`.

CI runs the same eval and lint gate on every push to `main` and every pull request, except for documentation-only changes (`.github/workflows/check.yml`), and a weekly job (`.github/workflows/update.yml`) opens two pull requests, one per update lane: servers (stable channel, shared inputs, claude-code) and desktops (everything else). `.github/workflows/update-lane.yml` does each lane's work. Hosts are evaluated, not built; CI builds only the nvim checks, the Lua syntax check and the server-only packages (`server-upgrade`, `claude-code`). When a commit on `main` passes the check, `.github/workflows/promote.yml` moves the `deploy` branch to it, and the servers auto-upgrade from `deploy`.

## Installs

The desktops and laptops are installed from a NixOS unstable minimal ISO by `install.sh`. It previews every step with `--dry-run`, erases the selected disk only after typed confirmation, and can scaffold a new host from `templates/host/`. An install takes 20-60+ minutes, longer on the CUDA host (`tariognatha`), because `nixos-install` compiles quickshell from source. The full runbook is [docs/INSTALL.md](docs/INSTALL.md).

The servers are installed differently: `taragarmr` with nixos-anywhere, the Pis from flashable images (`packages.image-<host>`). Each host's `hosts/<host>/default.nix` header records how.

## Layout

```
flake.nix  lib/mk-host.nix   flake entry point, shared host builder
install.sh                   live-ISO installer, post-boot setup script
hosts/<host>/                 hardware, disko layout, Hyprland monitor/input; optional host.nix = { system, role, board, image } (default x86_64-linux, desktop; board and image are for the Pis)
templates/host/               new-host templates install.sh renders into hosts/<name>/
modules/nixos/{common,desktop,server}/  system config by role (hosts/<host>/host.nix), gpu/ per host
modules/home/{common,desktop,server}/    home-manager config by role: ii wrapper, neovim, ...
overlays/  pkgs/              ii-fixes overlay, plymouth-lone theme
modules/nixvim/               standalone NixVim editor config (packages.nvim)
config/zsh/                   vendored dotfiles
scripts/                      bootstrap-sops.sh, docker-check.sh, lint.sh, CI and update helpers, Proton Drive mount
secrets/                      one sops-encrypted <host>.yaml per host (per-host age recipients in .sops.yaml), plus README.md and .gitkeep
docs/                         INSTALL, VERIFY, MIGRATION-NOTES, II-INTEGRATION, FALLBACK-VENDORING
```

## Security: what is in this repo on purpose

Left in because it is either meaningless to anyone else or needed for the config to work as shown:

- `modules/nixos/common/user.nix` defaults the git identity to `krane <chris@krane.dev>`; each host can override it through `krane.user`.
- `modules/nixos/common/locale.nix` sets the `Europe/Vienna` time zone. The keyboard layout comes from `krane.keyboard.{layout,variant}` (`modules/nixos/common/keyboard.nix`), default `at` / `nodeadkeys`.
- The hostnames `tariognatha`, `tarmantria`, `taractias`, `taragarmr`, `taronychus`, `tarritator`, `tarronax`.
- The default username `krane` (`krane.user.name`, overridable per host).
- Private network addresses: the home LAN subnet and the servers' pinned DHCP leases (`lib/lan.nix`), and the WireGuard tunnel addresses (`lib/wireguard.nix`). They are RFC 1918 ranges, unreachable from outside, and the server and tunnel config is built from them.
- The SSH public keys the servers accept for login (`lib/ssh-keys.nix`), one per machine allowed in.

No private keys, passwords, password hashes, API tokens, WireGuard/age/SSH private key material, or MAC addresses appear in any tracked file or the published history.

sops-nix encrypts `secrets/*.yaml`, decryptable only by each host's SSH-host-key-derived age identity and the admins' personal keys. On the desktops, sshd runs only so `sshd-keygen` generates that host key at boot, with `openFirewall = false`. On the servers, sshd is also the admin access path, with port 22 open. On every host it accepts keys only, with no password or root login.

The identity, locale, keyboard, hostnames, disk layouts and age recipients are all specific to these machines. `install.sh`'s new-host flow generates the per-host parts (disk layout, username, git identity, sops recipients) for a new machine.

## History

The public history starts at a single initial commit (2026-09-06). The development before it stays on a local branch, unpublished. Everything since is developed in the open.

## Licence

[MIT](LICENSE), copyright krane, 2026, except the third-party material below.

The Plymouth boot theme under `pkgs/plymouth-lone/theme/` is a derivative of adi1090x's Plymouth themes and stays under its original GPLv3 licence: see `pkgs/plymouth-lone/theme/LICENSE`.

The ii patches under `patches/ii/` modify [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) and are GPL-3.0 like upstream: see `patches/ii/LICENSE`. The `01-fixes` backports and the `05-settings` settings pages come from [pctrade/end4-pC](https://github.com/pctrade/end4-pC). The `patches/illogical-flake-*.patch` files quote [soymou/illogical-flake](https://github.com/soymou/illogical-flake), which has no licence. [LICENSE](LICENSE) has the full breakdown, including the LazyVim and powerlevel10k material.

## Docs

- [docs/INSTALL.md](docs/INSTALL.md): full install runbook for the desktops and laptops.
- [docs/VERIFY.md](docs/VERIFY.md): what the checks prove, plus the on-target checklist.
- [docs/MIGRATION-NOTES.md](docs/MIGRATION-NOTES.md): behavioural changes worth knowing about.
- [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md): how the wrapper works, in detail.
- [docs/FALLBACK-VENDORING.md](docs/FALLBACK-VENDORING.md): the exit plan if the soymou module goes stale.
- [secrets/README.md](secrets/README.md): what each secrets file holds and how the keys are set up.
