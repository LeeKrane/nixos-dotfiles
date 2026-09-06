# Install guide

Full path from a blank machine to a working `tariognatha`, `tarmantria`, or `taractias`. Read [README.md](../README.md) and [docs/II-INTEGRATION.md](II-INTEGRATION.md) first if you haven't.

The normal path runs the repo's own `install.sh`. It drives disko, `nixos-install`, secrets bootstrap, the Rust toolchain, flathub, and the required second `nixos-rebuild switch`, and every destructive step has a `--dry-run` preview. Appendix A is the manual, `install.sh`-free path. Appendix B documents what `install.sh` does, step by step, for auditing or maintenance.

## 0. Before you start

- `tariognatha`: NVIDIA RTX-4070-Ti-class desktop GPU, single GPU, open kernel module.
- `tarmantria`: Intel iGPU plus NVIDIA dGPU laptop, PRIME offload.
- `taractias`: AMD Vega iGPU laptop, no dGPU.
- UEFI boot, Secure Boot off. systemd-boot does not handle Secure Boot.
- A NixOS unstable minimal installer ISO, written to USB.
- A network connection once booted. `install.sh` re-execs itself through `nix shell` to pull in `gum` and other tools the minimal ISO does not ship.
- The minimal ISO ships NetworkManager. Connect with `nmtui`, or `nmcli device wifi connect SSID password PW` for Wi-Fi.
- Verify with `curl -fsS --max-time 5 -o /dev/null https://cache.nixos.org`, the probe `install.sh`'s own preflight check runs.
- This repo, cloned anywhere reachable from the booted installer:

```sh
git clone https://github.com/LeeKrane/nixos-dotfiles ~/.dotfiles
cd ~/.dotfiles
```

## 1. Run `./install.sh`

```sh
./install.sh
```

With no flags, `install.sh` detects a live ISO and walks through a live install:

1. Preflight checks root, UEFI boot, network, and required tools. Missing `dmidecode`/`lspci` only skips host suggestion and PRIME detection. It does not abort.
2. Host: suggests one of `tariognatha`, `tarmantria`, `taractias` from the chassis, in a `gum choose` list you can override.
3. Disk: lists real disks, excludes the ISO's own device, offers to swap in a stable `/dev/disk/by-id/...` path.
4. Confirmation: restates the disk and host, then asks you to type the disk path again.
5. Partition and format: patches `hosts/<host>/disko.nix`'s `/dev/CHANGE-ME` placeholder with your disk, then runs disko. This erases the chosen disk. Layout: GPT, an ESP, and a btrfs root split into `@`, `@home`, `@nix`, `@snapshots` subvolumes, zstd-compressed, no swap partition, zram swap instead.
6. Hardware config: runs `nixos-generate-config --no-filesystems --root /mnt` and writes `hosts/<host>/hardware-configuration.nix`.
7. PRIME bus IDs, `tarmantria` only: reads `lspci -D` and patches `hosts/tarmantria/default.nix`'s `krane.prime.intelBusId`/`nvidiaBusId`. Left as `FILL AT INSTALL` placeholders otherwise.
8. Local commit: commits the hardware config and PRIME changes, since flakes only see git-tracked files.
9. `nixos-install`: builds and installs the flake. Slow: quickshell compiles from source.
10. Copies this repo to `/mnt/home/krane/.dotfiles`.
11. Sets krane's password. This always runs, even under `--yes`.
12. Offers to reboot.

## 2. After first boot: setup mode

The greeter is tuigreet. "Hyprland (UWSM)" is the normal session, plain "Hyprland" a fallback. See [docs/II-INTEGRATION.md "Rollback and escape hatches"](II-INTEGRATION.md#rollback-and-escape-hatches) if you need it.

Log in, then from `~/.dotfiles`:

```sh
./install.sh
```

On an already-installed system this runs setup mode:

1. Bootstraps sops-nix (`scripts/bootstrap-sops.sh <host>`), deriving this host's age recipient and offering to commit `.sops.yaml`. Decline and commit later with Appendix A step 9's commands. sshd exists only so `sshd-keygen` generates this host's SSH key at boot. `openFirewall = false`.
2. Offers to edit `secrets/<host>.yaml` with `sops`, skipped under `--yes`/`--dry-run`. An uncommitted secrets file evaluates as absent to sops-nix, so commit it. See [secrets/README.md](../secrets/README.md) for what each key holds.
3. Offers the Rust toolchain, `rustup default stable` plus components.
4. Offers to add the flathub remote.
5. Runs the VERIFY checklist, see [docs/VERIFY.md](VERIFY.md#2-on-target-checklist), reporting each check OK, WARN, or SKIP.
6. Runs a second `nixos-rebuild switch`. The first switch already ran the ii (illogical-impulse) dotfiles copy and this repo's overrides once, so switching again proves the ordering holds on repeat.
7. Prints a next-steps panel. Fill in the WireGuard and rclone values in `secrets/<host>.yaml`, uncomment the WireGuard block in `modules/nixos/networking.nix`, then run `just check`.

## Flags

| Flag | What it does |
| --- | --- |
| `--mode install\|setup` | Force a mode instead of auto-detecting it. |
| `--host HOST` | One of `tariognatha`, `tarmantria`, `taractias`. |
| `--disk DISK` | Target block device, install mode only. |
| `-y`, `--yes` | Auto-confirm every prompt. Never skips setting krane's password. |
| `-n`, `--dry-run` | Print every mutating command instead of running it. Implies `--yes`. |
| `--confirm-wipe` | Required for a live, non-dry-run `--yes` install. |
| `--self-test` | Exercise `install.sh`'s own failure-handling logic in isolation. |
| `-h`, `--help` | Show usage and exit. |

`--host`/`--disk` are required alongside `--yes`/`--dry-run`: neither mode falls back to an interactive prompt once prompts are off. In install mode, `--yes` without `--dry-run` needs `--confirm-wipe` too.

On a non-NixOS system `install.sh` defaults to install mode. Pass `--dry-run` or `--mode setup` explicitly if you are experimenting from an ordinary Linux box rather than a live ISO.

### `--dry-run` and `--self-test`

`--dry-run` is safe to run anywhere, any time, as any user. Every destructive step (disk writes, `nixos-install`, `nixos-rebuild switch`, commits, `passwd`, `reboot`) prints `+ the command` instead of running it, while read-only probes still run for real. This is how `just install-lint` (`scripts/docker-check.sh shellcheck`) exercises it in CI, checking `git status --porcelain` and `git rev-parse HEAD` before and after to prove the tree stayed untouched.

`--self-test` is an undocumented maintainer and CI hook, not in `--help`, that exercises `install.sh`'s own failure handling: that `run_sh` honours `pipefail`, that the `ERR` trap fires inside a shell function, and that the disko and PRIME sed helpers produce the expected line when run for real against a throwaway fixture.

## NVIDIA black-screen ladder (`tariognatha`, or `tarmantria`'s dGPU path)

Out-of-tree modules (`v4l2loopback`, NVIDIA) build against `boot.kernelPackages`, `linuxPackages_latest` by default (`mkDefault` in `modules/nixos/boot.nix`). If one fails to build against a new kernel, pin an older `linuxPackages_6_x` there first.

If Hyprland fails to start with a black screen after switching, try these in order. Each is a one-line change in `modules/nixos/gpu/nvidia-desktop.nix` or `nvidia-prime.nix`. Re-switch after each.

1. `hardware.nvidia.open = false;`: falls back to the proprietary kernel module.
2. `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;`: a newer driver, for hardware the stable branch doesn't yet handle.
3. `boot.kernelParams = [ "nvidia_drm.fbdev=0" ];`, replacing the `=1` already there: disables the NVIDIA DRM framebuffer console.

## Windows dual-boot entry

`boot.loader.systemd-boot` auto-discovers a Windows install on the same ESP with no extra config. Check what's there after install:

```sh
bootctl list
```

If Windows lives on a second, separate ESP, systemd-boot won't find it automatically. `modules/nixos/boot.nix` has a commented `extraEntries` template for that case. Uncomment it, then re-derive the correct values:

```sh
efibootmgr -v                 # confirm the Windows boot entry exists
bootctl list                  # after adding the entry, confirm it shows up
```

The HD index in that template has to be re-derived per machine: it depends on the exact disk and partition layout at install time.

## Data migration

Nothing here is automated. Do it by hand once the new system is up, from whatever media or network path holds the old host's data.

`old:~/path` below is the old host's `krane` home directory, tilde-expanded by the remote shell, not a literal path:

```sh
rsync -avh --info=progress2 old:~/Documents             ~/Documents
rsync -avh --info=progress2 old:~/Pictures               ~/Pictures
rsync -avh --info=progress2 old:~/.ssh                   ~/.ssh
rsync -avh --info=progress2 old:~/.gnupg                 ~/.gnupg
rsync -avh --info=progress2 old:~/.mozilla               ~/.mozilla        # Firefox profile
rsync -avh --info=progress2 old:~/.config/BraveSoftware  ~/.config/BraveSoftware
rsync -avh --info=progress2 'old:~/.local/share/Steam/steamapps' ~/.local/share/Steam/steamapps
rsync -avh --info=progress2 old:~/.claude                ~/.claude
```

Fix permissions afterwards:

```sh
chmod 700 ~/.ssh ~/.gnupg
chmod 600 ~/.ssh/id_*
```

Bottles prefixes and Steam's `compatibilitytools.d` need care beyond a plain rsync: rsync `~/.local/share/bottles` after `bottles` (`modules/nixos/gaming.nix`) is installed, and rsync `compatibilitytools.d` for any Proton build besides GE-Proton, which `programs.steam.extraCompatPackages` already wires in.

## Appendix A: manual install (without `install.sh`)

Everything `install.sh` does, run by hand. Replace `<host>` with `tariognatha`, `tarmantria`, or `taractias`. Paths assume the repo is checked out at `~/.dotfiles`.

1. Enable flakes on the live ISO.

    ```sh
    mkdir -p /etc/nix
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
    ```

2. Edit `hosts/<host>/disko.nix`, replacing `/dev/CHANGE-ME` with the real disk. Prefer a `/dev/disk/by-id/...` path over `/dev/sdX`: it survives disk reordering. Then partition and format.

    ```sh
    nix run github:nix-community/disko -- --mode destroy,format,mount --flake .#<host>
    ```

3. Generate the hardware config, then copy it over the placeholder.

    ```sh
    nixos-generate-config --no-filesystems --root /mnt
    cp /mnt/etc/nixos/hardware-configuration.nix hosts/<host>/hardware-configuration.nix
    ```

4. On `tarmantria` only, find the GPU bus IDs and fill in `hosts/tarmantria/default.nix`'s `krane.prime.intelBusId`/`nvidiaBusId`.

    ```sh
    lspci | grep -E 'VGA|3D'
    ```

5. Install. `--accept-flake-config` trusts `flake.nix`'s two CUDA substituters, `cuda-maintainers.cachix.org` and `cache.nixos-cuda.org`, and their keys without prompting. Skip it and CUDA packages build from source instead.

    ```sh
    nixos-install --flake "$PWD#<host>" --accept-flake-config
    ```

6. Set krane's password before rebooting.

    ```sh
    nixos-enter --root /mnt -- passwd krane
    ```

7. Copy this repo onto the new install, before rebooting.

    ```sh
    cp -a ~/.dotfiles /mnt/home/krane/.dotfiles
    nixos-enter --root /mnt -- chown -R krane:users /home/krane/.dotfiles
    ```

8. Reboot, log in, then switch twice. The second switch is what proves the ii dotfiles-copy step and this repo's overrides stay idempotent on repeat.

    ```sh
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
    ```

9. Bootstrap sops-nix and fill in secrets. Commit both: flakes only see git-tracked files, so an uncommitted secrets file evaluates as absent.

    ```sh
    scripts/bootstrap-sops.sh <host>
    git add .sops.yaml && git commit -m "Add <host> sops recipient"
    sops secrets/<host>.yaml
    git add secrets/<host>.yaml && git commit -m "Add <host> secrets"
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
    ```

10. Bring up WireGuard once `modules/nixos/networking.nix`'s address and peer values are filled in.

    ```sh
    sudo systemctl start wg-quick-wg0.service
    ```

11. Set up Proton Drive, if you did not seed `rclone/config-seed` in the secrets file.

    ```sh
    rclone config
    systemctl --user restart proton-drive-mount
    ```

12. Add the flathub remote, then install what you want.

    ```sh
    flatpak install flathub <app-id>
    ```

13. Install the Rust toolchain. `modules/home/dev.nix` installs `rustup` itself, not a pinned toolchain.

    ```sh
    rustup default stable
    rustup component add rust-analyzer rust-src
    ```

14. Migrate data and add a Windows dual-boot entry: see "Data migration" and "Windows dual-boot entry" above. Run an AppImage with `appimage-run <file>.AppImage`. Custom C tools are installed by hand. The out-of-scope package list is in the `modules/home/apps.nix` comment.

## Appendix B: what `install.sh` does, step by step

Line numbers move. Function and variable names are the stable reference.

Mode detection (`detect_mode`) picks `install` if `/iso` exists, `/etc/NIXOS` is missing, or `/` is an `overlay` filesystem. That last check catches a live ISO's root. It picks `setup` otherwise. `--mode` overrides this.

### Live mode (`run_install_mode`)

- `preflight_live`: checks root, UEFI boot, network, and required tools.
- `choose_host` and `choose_disk`: `gum choose` over `suggest_host`'s guess and `lsblk`'s disk list, excluding the ISO's own device and offering a stable `/dev/disk/by-id` path.
- `validate_disk_is_physical` and `confirm_wipe_target`: a typed-confirmation gate before anything destructive.
- `patch_disko` and `run_disko`: sed-patches `/dev/CHANGE-ME` in `hosts/$HOST/disko.nix`, verified with `grep -qF`, then builds and runs that host's disko script.
- `generate_hardware_config`: `nixos-generate-config`, checked for `availableKernelModules` and the absence of `fileSystems`.
- `patch_prime`: on `tarmantria` only, converts `lspci -D` addresses to `PCI:B:D:F` decimal and patches `krane.prime.intelBusId`/`nvidiaBusId`, once per bus ID.
- `commit_hardware_config`: commits with a throwaway `krane@localhost` identity if none is already configured.
- `run_nixos_install`: `nixos-install --flake "$REPO_ROOT#$HOST" --no-root-passwd --accept-flake-config`.
- `finish_install`: copies the repo to `/mnt/home/krane/.dotfiles`, chowns it, verifies `flake.nix` landed, sets krane's password, offers a reboot.

### Setup mode (`run_setup_mode`)

- `preflight_setup`: refuses to run as root, requires `git just sops age ssh-to-age`.
- `run_bootstrap_sops`: runs `scripts/bootstrap-sops.sh $HOST`, offers to commit `.sops.yaml`.
- `edit_host_secrets`: offers `sops secrets/$HOST.yaml`, skipped under `--yes`, then offers to commit it.
- `setup_rust` and `check_flathub`: offer the Rust toolchain and the flathub remote, each independently.
- `verify_checks`: each check independently reports OK, WARN, or SKIP.
- `second_switch`: `sudo nixos-rebuild switch --flake $REPO_ROOT#$HOST`, then `verify_checks` again.

### Dry-run invariants

- Every mutating call goes through `run`, `run_sh`, or `capture`, which print `+ the command` under `--dry-run` instead of running it.
- Read-only probes (`lsblk`, `lspci`, `hostname`, the post-sed `grep -qF` checks, the VERIFY checks) run for real in both modes.
- `gum choose`/`gum input` are never reached under `--yes`/`--dry-run`: every caller requires `--host`/`--disk` instead.
- Every run's output is duplicated into `/tmp/krane-install-<timestamp>-<pid>.log`, unless `/tmp` isn't writable, in which case it warns once and continues.
