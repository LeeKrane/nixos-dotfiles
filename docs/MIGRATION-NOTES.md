# Migration notes

Behavioural changes worth knowing about going from the old Nobara and
KDE host to this repo. Not a changelog of every module, only the things
that will surprise you if you don't know they changed.

## Desktop: KDE Plasma to illogical-impulse

Hyprland and Quickshell (ii) replace the session entirely. KDE's
theming, settings and Plasma itself are gone, and KDE-specific config
was not carried over, since there is no equivalent to port it to. See
[docs/II-INTEGRATION.md](II-INTEGRATION.md) for how ii is wired in.

## Shell: zsh to fish

krane's login shell is now fish (`modules/nixos/users.nix`). Aliases
ported from `~/.krane-rc` live at the NixOS level (`/etc/fish/...`,
`modules/nixos/shells.nix`), not home-manager, because ii's dotfiles
copy step wipes `~/.config/fish` on every switch. See II-INTEGRATION.md.

zsh, oh-my-zsh and powerlevel10k stay as a fallback behind
`krane.zshFallback.enable` (default true, `modules/home/zsh-fallback.nix`).
`exec zsh` drops into it at any time.

## Terminal: Alacritty to kitty

ii's default terminal is kitty
(`programs.illogical-impulse.dotfiles.kitty.enable`). The old Alacritty
config is not ported, and stays in the previous dotfiles' git history
for reference.

## Bootloader: GRUB to systemd-boot

`modules/nixos/boot.nix`. There is no systemd-boot equivalent to GRUB's
theme. The Plymouth splash (`lone` theme, `pkgs/plymouth-lone`) carries
over, since it is independent of the bootloader. See docs/INSTALL.md's
Windows dual-boot section for how systemd-boot's auto-discovery compares
to the old GRUB setup.

## Proton Drive: subvolume to plain directory

The old mount point was a dedicated btrfs subvolume. This repo mounts to
a plain directory instead, `~/ProtonDrive`: `ensureProtonDriveMountpoint`
(`modules/home/proton-drive.nix`) runs `mkdir -p`, not `home.file`,
since `rclone mount` refuses a non-empty directory.

## Git: `aa` alias fixed

The old `.gitconfig` had `aa = "add all"`, not a valid alias body. Fixed
to `aa = "add -A"` in `modules/home/git.nix`. Every other alias is
unchanged.

## Neovim: `lazyvim.json` is read-only, mason disabled

`modules/home/neovim.nix` symlinks `config/nvim/lazyvim.json` from the
Nix store, so it is read only at runtime and `:LazyExtras` cannot save a
toggled extra. Edit `config/nvim/lazyvim.json` in this repo and
re-switch instead.

Mason (`:Mason`) is disabled in `config/nvim/lua/plugins/nix.lua`: every
LSP server, formatter and linter comes from nixpkgs through
`modules/home/neovim.nix`'s package list instead. Do not re-enable it,
since it would conflict with the Nix-provided binaries.

## `*.hm-bak` files are expected, clean them up periodically

`home-manager.backupFileExtension = "hm-bak"` (`lib/mk-host.nix`) is
mandatory. See II-INTEGRATION.md for why: fish and starship config
collide with ii's dotfiles copy step. Switches leave `*.hm-bak` files
under `$HOME`. Delete them once you confirm nothing important was in
them:

```sh
find ~ -name '*.hm-bak'
```

## rclone.conf is a live file, not declarative

`~/.config/rclone/rclone.conf` is seeded once, if absent, from the
`rclone/config-seed` sops secret (`seedRcloneConfig` in
`modules/home/proton-drive.nix`). After that it is a mutable file:
`scripts/proton-drive-rclone-mount.sh`'s `update_rclone_config` rewrites
its `2fa = ...` line whenever Proton's session expires. If it is lost,
the fix is re-authenticating with `rclone config`.

## UWSM

`programs.hyprland.withUWSM = true` (`modules/nixos/desktop.nix`). ii
starts things through its own `hl.exec_cmd`, not UWSM-scoped launches,
so some processes land outside a UWSM scope. This is expected. If it
matters, set `withUWSM = false` in `desktop.nix` and re-switch: the
plain Hyprland session is already on the tuigreet list.

## Monitor position and mouse device name, verify on target

Two values in `hosts/tariognatha/display.nix` are best guesses: DP-1's
`position` (`"2560x0"`, flip to `"-1152x0"` if it should sit left of
DP-2) and the Logitech G502's device name
(`"logitech-gaming-mouse-g502"`), which has to match `hyprctl devices`
exactly or the `devices` block applies to nothing. Check both with
`hyprctl monitors -j` and `hyprctl devices` after the first real switch
and fix `display.nix` if wrong. See [docs/VERIFY.md](VERIFY.md)'s
on-target checklist.

## Dropped: upstream ii's "Edit user keybinds" bind

Owning `custom/keybinds.lua` (see II-INTEGRATION.md's "Owned vs
appended") drops the one bind ii ships there by default,
`CTRL+SUPER+ALT+Slash` opening the file in an editor. Add it back
through `krane.hypr.binds` if it's missed.

## texlive packaging note

`modules/home/dev.nix` uses `texlive.combined.scheme-medium`, which
nixpkgs flags as deprecated and due for removal in 27.05, though it
still works today. Switch to `texliveSmall` or another top-level scheme
before a `nix flake update` lands that release.

## No standalone `python3` package

System `python3` on `PATH` is the soymou module's own
`python3.withPackages` environment, so `modules/home/dev.nix` cannot add
a plain `python3` too: it collides with `bin/idle`/`bin/python3` in
home-manager's `buildEnv`. Use `uv` for project interpreters instead.

## rust-analyzer via rustup, not a standalone package

`modules/home/dev.nix` installs `rustup`, not a pinned toolchain.
`rustup` ships its own `bin/rust-analyzer` proxy, which collides with
the standalone nixpkgs `rust-analyzer` in home-manager's `buildEnv`, so
`modules/home/neovim.nix` does not install that package. Run
`rustup default stable && rustup component add rust-analyzer rust-src`
once per user before Neovim's LSP works.

## `home.stateVersion` = "26.05"

Set once in `modules/home/default.nix`. This pins home-manager's
backward-compatibility behaviour. Do not bump it on an existing install
without reading home-manager's own release notes first.

## Default browser: zen

`hosts/*/display.nix` sets ii's `browser` variable to zen (the
[zen-browser flake](https://github.com/0xc000022070/zen-browser-flake),
`modules/home/apps.nix`). Firefox stays installed, not the ii default.

## Hostnames renamed

The old desktop's hostname is not carried over: the new desktop is
`tariognatha`. The laptop is a new machine, `tarmantria`. A third host,
`taractias` (a Lenovo IdeaPad 330S, AMD variant), was added later with
no old-system counterpart, see `hosts/taractias/default.nix`. The old
`rebos` machine names and SSH host entry for the desktop are dropped.
