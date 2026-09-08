# nixos-dotfiles

A declarative NixOS + Hyprland flake for three hosts. Each runs end-4's illogical-impulse (ii) Hyprland shell, home-manager as a NixOS module, and sops-nix for secrets.

ii ships its own installer logic, not a plain dotfiles checkout, so this repo pulls it in as the soymou module instead of reimplementing that logic. The soymou module's activation step overwrites most of `~/.config` on every switch, so the wrapper renders Hyprland config into place after it runs. Full mechanics are in [docs/II-INTEGRATION.md](docs/II-INTEGRATION.md). The fallback plan if the soymou module goes stale is [docs/FALLBACK-VENDORING.md](docs/FALLBACK-VENDORING.md).

## Hosts

| Host | Role | GPU |
| --- | --- | --- |
| `tariognatha` | Desktop | NVIDIA RTX-4070-Ti-class, open kernel module, single GPU |
| `tarmantria` | Laptop | Intel iGPU + NVIDIA dGPU, PRIME offload |
| `taractias` | Laptop | AMD Vega iGPU, no dGPU |

## Quickstart

```sh
git clone https://github.com/LeeKrane/nixos-dotfiles ~/.dotfiles
cd ~/.dotfiles
just check
```

`just check` evaluates the flake and dry-run-builds all three hosts' toplevel in a throwaway Docker sandbox, needing Docker but no local Nix. `just docker-build <host>` runs a real build. Both cache the Nix store in a persistent volume between runs.

To install onto real hardware, boot a NixOS unstable minimal ISO, clone this repo, then preview the installer before running it for real:

```sh
sudo ./install.sh --dry-run
```

**`sudo ./install.sh` without `--dry-run` erases the disk you select and takes 20-60+ minutes**, longer on the CUDA host (`tariognatha`), because `nixos-install` compiles quickshell from source. It asks for typed confirmation before touching anything. The live install must run as root; the script aborts if not.

```sh
sudo ./install.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for the full runbook.

## Layout

```
flake.nix  lib/mk-host.nix   flake entry point, shared host builder
install.sh                   live-ISO installer, post-boot setup script
hosts/<host>/                 hardware, disko layout, Hyprland monitor/input
modules/nixos/                system config: boot, gpu, desktop, sops, ...
modules/home/                 home-manager config: ii wrapper, neovim, ...
overlays/  pkgs/              ii-fixes overlay, plymouth-lone theme
config/nvim/  config/zsh/     vendored dotfiles
scripts/                      bootstrap-sops.sh, docker-check.sh, Proton Drive mount
secrets/                      nothing committed but README.md and .gitkeep
docs/                         INSTALL, VERIFY, MIGRATION-NOTES, II-INTEGRATION, FALLBACK-VENDORING
```

## Security: what is in this repo on purpose

Left in because it is either meaningless to anyone else or needed for the config to work as shown:

- `modules/home/git.nix` bakes in the git identity `krane <chris@krane.dev>`.
- `modules/nixos/locale.nix` sets the `Europe/Vienna` time zone and the `at-nodeadkeys` keyboard layout.
- The hostnames `tariognatha`, `tarmantria`, `taractias`.
- The username `krane`, hardcoded throughout.

No private keys, passwords, password hashes, API tokens, WireGuard/age/SSH key material, MAC addresses, or LAN/internal IP addresses appear in any tracked file or the published history.

sops-nix encrypts `secrets/*.yaml`, decryptable only by each host's SSH-host-key-derived age identity and the admin's personal key. sshd runs only so `sshd-keygen` generates that host key at boot, with `openFirewall = false` and no password or root login to attack.

If you fork this, change:

- The git identity, locale, keyboard, and hostnames above.
- Every `/dev/CHANGE-ME` disko placeholder, or run `./install.sh`, which does that for you.
- The username `krane` in `modules/nixos/users.nix`, `lib/mk-host.nix`, `modules/home/default.nix`, `modules/nixos/nix-settings.nix`, `modules/nixos/sops.nix`, and `install.sh`.
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
