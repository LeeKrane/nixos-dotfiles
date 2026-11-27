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
| `tariognatha` | Desktop | NVIDIA RTX-4070-Ti-class, open kernel module, single GPU |
| `tarmantria` | Laptop | Intel iGPU + NVIDIA dGPU, PRIME offload |
| `taractias` | Laptop | AMD Vega iGPU, no dGPU |
| `taragarmr` | Server | x86_64 mini PC (AZW SER, Ryzen 7 6800H): the server stack, WireGuard hub and public ingress |
| `taronychus` | Server | Raspberry Pi 5, aarch64 |
| `tarritator` | Server | Raspberry Pi 5, aarch64 |
| `tarronax` | Server | Raspberry Pi 4, aarch64 |

## How ii is wired in

This repo pulls ii in as the soymou module instead of reimplementing ii's installer logic. The module's activation step overwrites most of `~/.config` on every switch, so the wrapper renders Hyprland config into place after it runs. Mechanics, patches and the exit plan if the module goes stale: [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md), [If the soymou module breaks](docs/II-INTEGRATION.md#if-the-soymou-module-breaks).

## Checks, CI and deploys

`just check` evaluates the flake and dry-run-builds every x86_64 host's toplevel in a throwaway Docker sandbox (the aarch64 Pis are evaluated only in CI), so a machine with Docker but no Nix can check the whole config. `just docker-build <host>` does a real build there. A pre-push hook (`just hooks`) runs `scripts/lint.sh`, the same lint as CI.

CI runs the same eval and lint gate on every push to `main` and every pull request, except documentation-only changes (`.github/workflows/check.yml`). A weekly job (`.github/workflows/update.yml`) opens two pull requests, one per update lane: servers (stable channel, shared inputs, claude-code) and desktops (everything else); `.github/workflows/update-lane.yml` does each lane's work. CI builds only the nvim checks, the Lua syntax check and the server-only packages (`server-upgrade`, `claude-code`). When a commit on `main` passes the check, `.github/workflows/promote.yml` moves the `deploy` branch to it, and the servers auto-upgrade from `deploy`.

Things that are easy to break here:

- The update pull requests are opened with `GITHUB_TOKEN`, so GitHub does not run `check.yml` on them. `update-lane.yml` calls it itself and reports the result in the PR body; `check.yml` runs again on `main` after the merge. Opening them needs "Allow GitHub Actions to create and approve pull requests" under the repository's Settings, Actions, General.
- Every gated `main` commit reaches the servers, including desktop-only ones, because `system.configurationRevision` (`lib/mk-host.nix`) is the commit. Such a commit causes a revision-only activation, and the upgrade hooks compare that revision with `deploy`, so do not remove it. A desktop-lane `nixpkgs` bump also changes the server closures: `modules/home/server/default.nix` takes `codegraph` from `nixpkgs-unstable`. The PR body's "Merging deploys to" line lists the servers a PR reaches.
- A server upgrade that fails its health check rolls back, including after the reboot a kernel change triggers (`scripts/server-upgrade-hooks.sh`, `boot-health`). A kernel that does not boot never reaches that check.
- The desktop notifier (`modules/home/desktop/flake-update-notify.nix`) parses the PR body's `### Package versions`, `### Inputs` and `### Security: what is in this repo on purpose

Left in because it is meaningless to anyone else or needed for the config to work as shown: the git identity `krane <chris@krane.dev>` (`modules/nixos/common/user.nix`), username and hostnames, the `Europe/Vienna` time zone and `at` / `nodeadkeys` keyboard defaults, the RFC 1918 LAN and WireGuard addresses (`lib/lan.nix`, `lib/wireguard.nix`) and the SSH public keys the servers accept (`lib/ssh-keys.nix`).

No private keys, passwords, password hashes, API tokens, WireGuard/age/SSH private key material, or MAC addresses appear in any tracked file or the published history. Secrets are sops-nix encrypted: [secrets/README.md](secrets/README.md). sshd accepts keys only, with no password or root login. On the desktops it runs only so `sshd-keygen` creates the age identity's host key, with `openFirewall = false`; on the servers it is also the admin path, port 22 open.

## Licence

[MIT](LICENSE), copyright krane, 2026, except the third-party material below.

The Plymouth boot theme under `pkgs/plymouth-lone/theme/` is a derivative of adi1090x's Plymouth themes and stays under its original GPLv3 licence: see `pkgs/plymouth-lone/theme/LICENSE`.

The ii patches under `patches/ii/` modify [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) and are GPL-3.0 like upstream: see `patches/ii/LICENSE`. The `01-fixes` backports and the `05-settings` settings pages come from [pctrade/end4-pC](https://github.com/pctrade/end4-pC). The `patches/illogical-flake-*.patch` files quote [soymou/illogical-flake](https://github.com/soymou/illogical-flake), which has no licence. [LICENSE](LICENSE) has the full breakdown, including the LazyVim and powerlevel10k material.

## Docs

- [docs/INSTALL.md](docs/INSTALL.md): install runbook for the desktops and laptops.
- [docs/VERIFY.md](docs/VERIFY.md): what the checks prove, plus the on-target checklist.
- [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md): how the ii wrapper works, and the exit plan if the soymou module goes stale.
- [secrets/README.md](secrets/README.md): what each secrets file holds and how the keys are set up.