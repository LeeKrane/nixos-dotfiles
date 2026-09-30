# Install guide

Full path from a blank machine to a working `tariognatha`, `tarmantria`, or `taractias`, or to a new host that `install.sh` scaffolds for you (see [Installing a new machine](#installing-a-new-machine)). Read [README.md](../README.md) and [docs/II-INTEGRATION.md](II-INTEGRATION.md) first if you haven't.

The normal path runs the repo's own `install.sh`. It drives disko, `nixos-install`, secrets bootstrap, the Rust toolchain, flathub, and the required second `nixos-rebuild switch`, and every destructive step has a `--dry-run` preview. Appendix A is the manual, `install.sh`-free path. Appendix B documents what `install.sh` does, step by step, for auditing or maintenance.

## 0. Before you start

- `tariognatha`: NVIDIA RTX-4070-Ti-class desktop GPU, single GPU, open kernel module.
- `tarmantria`: Intel iGPU plus NVIDIA dGPU laptop, PRIME offload.
- `taractias`: AMD Vega iGPU laptop, no dGPU.
- On `taractias`, press `e` in the ISO boot menu and append `iommu=pt` to the kernel line, or use a wired connection. The QCA9377 Wi-Fi stalls under the default IOMMU mode.
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

`install.sh` enables flakes itself by exporting `NIX_CONFIG`, so there is no need to edit `/etc/nix/nix.conf` before running it.

With no flags, `install.sh` detects a live ISO and walks through a live install:

1. Preflight checks root, UEFI boot, network, and required tools. Missing `dmidecode`/`lspci` only skips host suggestion and PRIME detection. It does not abort. Preflight also checks DNS for the caches the install needs and offers to pin public DNS through NetworkManager if a lookup fails or is slow.
2. Host: suggests one of the hosts under `hosts/` from the chassis, in a `gum choose` list you can override. The last entry, `+ new host`, creates a new host instead: see [Installing a new machine](#installing-a-new-machine).
3. Disk: lists real disks, excludes the ISO's own device, offers to swap in a stable `/dev/disk/by-id/...` path.
4. Confirmation: restates the disk and host, then asks you to type the kernel device name, such as `nvme0n1`, to confirm.
5. Partition and format: patches `hosts/<host>/disko.nix`'s `/dev/CHANGE-ME` placeholder with your disk, then runs disko. This erases the chosen disk. Layout: GPT, an ESP, and a btrfs root split into `@`, `@home`, `@nix`, `@snapshots` subvolumes, zstd-compressed, no swap partition, zram swap instead.

    Under 24 GiB RAM, `install.sh` creates a 16 GiB swapfile at `/mnt/swapfile` and removes it after `nixos-install`. The nix eval heap alone stays around 5 GB resident for the whole build phase and the live ISO has no swap. `nixos-install` itself is also capped to `max-jobs = 1` and half the machine's cores, to keep local compiles (e.g. quickshell) from piling onto that heap and triggering the OOM killer.

6. Hardware config: runs `nixos-generate-config --no-filesystems --root /mnt` and writes `hosts/<host>/hardware-configuration.nix`.
7. PRIME bus IDs, `tarmantria` only: reads `lspci -D` and patches `hosts/tarmantria/default.nix`'s `krane.prime.intelBusId`/`nvidiaBusId`. Left as `FILL AT INSTALL` placeholders otherwise.
8. Local commit: commits the hardware config and PRIME changes, since flakes only see git-tracked files.
9. `nixos-install`: builds and installs the flake. Slow: quickshell compiles from source. The CUDA cache is trusted only on `tariognatha`, the one host with CUDA packages. On a failure, `install.sh` retries up to three times, confirming each retry: nix resumes from the paths it already copied, so a retry costs a 10 second wait, not the whole download.
10. Copies this repo to `/mnt/home/<user>/.dotfiles`, where `<user>` is the host's `krane.user.name` (`krane` on the three original hosts).
11. Sets that user's password. This always runs, even under `--yes`.
12. Offers to reboot.

## 2. After first boot: setup mode

The greeter is tuigreet. "Hyprland (UWSM)" is the normal session, plain "Hyprland" a fallback. See [docs/II-INTEGRATION.md "Rollback and escape hatches"](II-INTEGRATION.md#rollback-and-escape-hatches) if you need it.

Every host autologins straight into the plain (non-UWSM) Hyprland session at boot and locks it immediately, so the ii lock screen, not tuigreet, is the first thing you see after a reboot. This is acceptable only because none of these hosts encrypt their disk: there is no disk-encryption password gate at boot to preserve, so trading the greeter's password gate for the lock screen's costs nothing. tuigreet still appears if you log out, or after `systemctl restart greetd`.

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
7. Prints a next-steps panel. Add the WireGuard and rclone values to `secrets/<host>.yaml` with `sops set` (see [secrets/README.md](../secrets/README.md)), rebuild, and the wg0 tunnel autostarts. Then run `just check`.

## Installing a new machine

For a machine that has no `hosts/<name>/` yet. This is install mode only: setup mode needs the host to exist already, and it stops with `host '<name>' not in hosts/` otherwise.

1. Boot the ISO and clone the repo as in section 0, then run `./install.sh`.
2. Pick `+ new host` at the bottom of the host list. `install.sh` asks for:
    - Hostname: a lowercase letter, then lowercase letters, digits and `-`, at most 63 characters. It must not end in `-`, and must not be an existing host or `tariognatha-vm`.
    - Login username, default `krane`. It must not be `root` or another system account name.
    - Git name (default: the username) and git email (default `chris@krane.dev`), written to the host's `krane.user`.
    - GPU profile and form factor, pre-selected from `lspci`/`dmidecode` when they are available:

        | Profile | For |
        | --- | --- |
        | `amd-igpu` | AMD CPU with integrated Radeon, no dGPU (like `taractias`) |
        | `intel-igpu` | Intel CPU with its integrated GPU, no dGPU |
        | `nvidia-desktop` | A single NVIDIA GPU (like `tariognatha`), gets the CUDA cache |
        | `intel-nvidia-prime` | Intel iGPU plus NVIDIA dGPU, PRIME offload (like `tarmantria`) |

        `laptop` adds nixos-hardware's laptop profiles and a touchpad block. `desktop` adds the SSD profile only. AMD CPU plus NVIDIA dGPU PRIME is not offered.
    - Keyboard layout and variant, default `at` / `nodeadkeys` (the variant default is empty for any other layout).
3. Disk selection and the typed wipe confirmation work as usual. Nothing is written to the repo before that confirmation, so aborting earlier leaves the checkout untouched.
4. `install.sh` renders `templates/host/` into `hosts/<name>/` (`default.nix`, `disko.nix`, `display.nix`, a placeholder `hardware-configuration.nix`, and `illogical-impulse/.gitignore` for the ii settings window's config directory) and parse-checks every `.nix` file. It then adds `age1PLACEHOLDER_*` recipients for the host to `.sops.yaml`. If rendering or parsing fails, it removes `hosts/<name>/` again and restores `.sops.yaml`. After that the normal flow runs: disko, hardware config, PRIME bus IDs (`intel-nvidia-prime` only), one local commit `Add <name> host`, and `nixos-install`.
5. The new host exists only as that local commit in `~/.dotfiles` on the new machine. After first boot, run setup mode as usual (it bootstraps the host's sops recipients), then push the branch from there.
6. `display.nix` starts with one catch-all `preferred` monitor rule, because the live ISO runs no Hyprland to detect outputs. After first login, check `hyprctl monitors -j` and name the real outputs.

Non-interactively:

```sh
./install.sh --new-host newbox --user alice --profile amd-igpu --form-factor laptop \
    --disk /dev/disk/by-id/<disk> --yes --confirm-wipe
```

`--yes --new-host` requires `--user`, `--profile` and `--form-factor`. `--git-name`, `--git-email`, `--kb-layout` and `--kb-variant` take the defaults above (`--kb-variant` defaults to empty unless `--kb-layout` is `at`). All of these flags are usage errors without `--new-host` or outside install mode.

To check the templates without a machine, commit your change and run `just check-new-host`. It needs local Nix. It scaffolds a throwaway `testhost` for each GPU profile × form factor in a temporary git worktree, and checks that each one is nixfmt-clean and evaluates.

## Flags

| Flag | What it does |
| --- | --- |
| `--mode install\|setup` | Force a mode instead of auto-detecting it. |
| `--host HOST` | One of the directories under `hosts/`. |
| `--new-host NAME` | Install mode only: create `hosts/NAME` from `templates/host/`. See "Installing a new machine". |
| `--user NAME` | New host's login user, default `krane`. |
| `--git-name NAME` | New host's git `user.name`, default: the login user. |
| `--git-email EMAIL` | New host's git `user.email`, default `chris@krane.dev`. |
| `--profile PROFILE` | New host's GPU profile: `amd-igpu`, `intel-igpu`, `nvidia-desktop`, `intel-nvidia-prime`. |
| `--form-factor FF` | New host's form factor: `laptop` or `desktop`. |
| `--kb-layout LAYOUT` | New host's keyboard layout, default `at`. |
| `--kb-variant VARIANT` | New host's keyboard variant, default `nodeadkeys` for `--kb-layout at`, otherwise empty. |
| `--disk DISK` | Target block device, install mode only. |
| `-y`, `--yes` | Auto-confirm every prompt. Never skips setting the login user's password. |
| `-n`, `--dry-run` | Print every mutating command instead of running it. Implies `--yes`. |
| `--confirm-wipe` | Required for a live, non-dry-run `--yes` install. |
| `--self-test` | Exercise `install.sh`'s own failure-handling logic in isolation. |
| `-h`, `--help` | Show usage and exit. |

`--host` (or `--new-host` with `--user`, `--profile` and `--form-factor`) and `--disk` are required alongside `--yes`/`--dry-run`: neither mode falls back to an interactive prompt once prompts are off. In install mode, `--yes` without `--dry-run` needs `--confirm-wipe` too.

On a non-NixOS system `install.sh` defaults to install mode. Pass `--dry-run` or `--mode setup` explicitly if you are experimenting from an ordinary Linux box rather than a live ISO.

### `--dry-run` and `--self-test`

`--dry-run` is safe to run anywhere, any time, as any user. Every destructive step (disk writes, `nixos-install`, `nixos-rebuild switch`, commits, `passwd`, `reboot`) prints `+ the command` instead of running it, while read-only probes still run for real. This is how `just install-lint` (`scripts/docker-check.sh shellcheck`) exercises it in CI, checking `git status --porcelain` and `git rev-parse HEAD` before and after to prove the tree stayed untouched.

`--self-test` is an undocumented maintainer and CI hook, not in `--help`, that exercises `install.sh`'s own failure handling: that `run_sh` honours `pipefail`, that the `ERR` trap fires inside a shell function, and that the disko and PRIME sed helpers produce the expected line when run for real against a throwaway fixture, that every new-host template combination renders and parses, and that a failed new-host scaffold rolls back.

### DNS timeouts ("Resolving timed out")

`install.sh`'s preflight offers to pin public DNS through NetworkManager when a lookup fails or is slow. To do it by hand, find the active connection name, then pin `1.1.1.1` and `9.9.9.9` on it:

```sh
nmcli -t -f NAME con show --active
nmcli con mod "<connection name>" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes
nmcli con up "<connection name>"
```

## NVIDIA black-screen ladder (`tariognatha`, or `tarmantria`'s dGPU path)

Out-of-tree modules (`v4l2loopback`, NVIDIA) build against `boot.kernelPackages`, `linuxPackages_latest` by default (`mkDefault` in `modules/nixos/boot.nix`). If one fails to build against a new kernel, pin an older `linuxPackages_6_x` there first.

If Hyprland fails to start with a black screen after switching, try these in order. Each is a one-line change in `modules/nixos/gpu/nvidia-desktop.nix` or `nvidia-prime.nix`. Re-switch after each.

1. `hardware.nvidia.open = false;`: falls back to the proprietary kernel module.
2. `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;`: a newer driver, for hardware the stable branch doesn't yet handle.
3. `boot.kernelParams = [ "nvidia_drm.fbdev=0" ];`, replacing the `=1` already there: disables the NVIDIA DRM framebuffer console.

## Windows dual-boot entry

`boot.loader.systemd-boot` auto-discovers a Windows install on the same ESP with no extra config. Check what's there after install:

```sh
sudo bootctl list
```

If Windows lives on a second, separate ESP, systemd-boot won't find it automatically. `modules/nixos/boot.nix` has a commented `extraEntries` template for that case. Uncomment it, then re-derive the correct values:

```sh
efibootmgr -v                 # confirm the Windows boot entry exists
sudo bootctl list                  # after adding the entry, confirm it shows up
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
rsync -avh --info=progress2 old:~/.config/teamclaude.json ~/.config/teamclaude.json  # seat tokens, else `teamclaude login` per seat
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

Under 24 GiB RAM, create a temporary swapfile first:

```sh
btrfs filesystem mkswapfile --size 16g /mnt/swapfile
swapon /mnt/swapfile
```

Run nixos-install with `NIX_CONFIG=$'max-jobs = 1\ncores = 4'` (or half the machine's cores) to avoid the OOM killer during local compiles.

5. Install. `flake.nix` carries no `nixConfig` (it made nix prompt to allow it on every invocation and hung direnv), so the CUDA cache is granted explicitly instead: pass `--option extra-substituters https://cache.nixos-cuda.org --option extra-trusted-public-keys cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=` only on `tariognatha`, the one host with CUDA packages; pass nothing extra on `tarmantria` and `taractias` since they never query that cache.

    ```sh
    nixos-install --flake "$PWD#<host>" --option extra-substituters https://cache.nixos-cuda.org --option extra-trusted-public-keys cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=   # tariognatha
    nixos-install --flake "$PWD#<host>"                                                                                                                                                             # tarmantria, taractias
    ```

    Remove the swapfile after, if you created one.

    ```sh
    swapoff /mnt/swapfile && rm -f /mnt/swapfile
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

10. Bring up WireGuard by adding the six `wireguard/*` keys to
    `secrets/<host>.yaml` with `sops set` (see
    [secrets/README.md](../secrets/README.md)), then rebuilding. The
    `wg0.conf` template renders from those secrets and
    `networking.wg-quick.interfaces.wg0` autostarts on the next switch, no
    manual `systemctl start` needed.

    ```sh
    sops set secrets/<host>.yaml '["wireguard"]["wg0-private-key"]' '"<real private key>"'
    sops set secrets/<host>.yaml '["wireguard"]["address"]' '"<this host tunnel address>/24"'
    sops set secrets/<host>.yaml '["wireguard"]["peer-public-key"]' '"<peer public key>"'
    sops set secrets/<host>.yaml '["wireguard"]["peer-endpoint"]' '"<peer host>:51820"'
    sops set secrets/<host>.yaml '["wireguard"]["peer-allowed-ips"]' '"<peer subnet>/24"'
    sops set secrets/<host>.yaml '["wireguard"]["listen-port"]' '"51820"'
    git add secrets/<host>.yaml && git commit -m "Add <host> WireGuard secrets"
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
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

- `preflight_live`: checks root, UEFI boot, network, and required tools. `check_dns` probes `cache.nixos.org`, plus `cache.nixos-cuda.org` on the CUDA host, and offers to pin public DNS on the active NetworkManager connection when a lookup fails or is slow.
- `choose_host` and `choose_disk`: `gum choose` over `suggest_host`'s guess plus `+ new host`, and `lsblk`'s disk list, excluding the ISO's own device and offering a stable `/dev/disk/by-id` path. `+ new host` (or `--new-host`) runs `prompt_new_host`, which collects every answer first, pre-selecting `suggest_profile`'s GPU profile and form factor.
- `validate_disk_is_physical` and `confirm_wipe_target`: a typed-confirmation gate before anything destructive.
- `scaffold_host`, new hosts only: renders `templates/host/` into a staging dir, runs `nix-instantiate --parse` on each file, copies it to `hosts/<name>/`, and adds the host's placeholders to `.sops.yaml` (`register_sops_host`). A failure before that finishes rolls both back from `on_exit`. Under `--dry-run` only the staging dir is written, and `patch_disko`/`patch_prime` patch that copy.
- `patch_disko` and `run_disko`: sed-patches `/dev/CHANGE-ME` in `hosts/$HOST/disko.nix`, verified with `grep -qF`, then builds and runs that host's disko script.
- `resolve_install_user`: after `git add -A`, reads the login user from `nix eval …#nixosConfigurations.$HOST.config.krane.user.name`, or from the prompt for a new host under `--dry-run`.
- `generate_hardware_config`: `nixos-generate-config`, checked for `availableKernelModules` and the absence of `fileSystems`.
- `patch_prime`: on `tarmantria` only, converts `lspci -D` addresses to `PCI:B:D:F` decimal and patches `krane.prime.intelBusId`/`nvidiaBusId`, once per bus ID.
- `commit_hardware_config`: commits (`Add <name> host` for a new host) with a throwaway `<user>@localhost` identity if none is already configured.
- `run_nixos_install`: `nixos-install --flake "$REPO_ROOT#$HOST" --no-root-passwd`, plus `flake_config_opt`'s `--option extra-substituters ... --option extra-trusted-public-keys ...` on the CUDA host, nothing on the others. Retries up to 3 times on failure, 10 seconds apart, confirmed each time.
- `finish_install`: copies the repo to `/mnt/home/<user>/.dotfiles`, chowns it, verifies `flake.nix` landed, sets the user's password, warns that a new host is only a local commit, and offers a reboot.

### Setup mode (`run_setup_mode`)

- `preflight_setup`: refuses to run as root, requires `git just sops age ssh-to-age`, and dies when the host (`--host` or `hostname`) is not under `hosts/`.
- `run_bootstrap_sops`: runs `scripts/bootstrap-sops.sh $HOST`, offers to commit `.sops.yaml`.
- `edit_host_secrets`: offers `sops secrets/$HOST.yaml`, skipped under `--yes`, then offers to commit it.
- `setup_rust` and `check_flathub`: offer the Rust toolchain and the flathub remote, each independently.
- `verify_checks`: each check independently reports OK, WARN, or SKIP.
- `second_switch`: `sudo nixos-rebuild switch --flake $REPO_ROOT#$HOST`, plus `flake_config_opt`'s CUDA substituter options, then `verify_checks` again.

### Dry-run invariants

- Every mutating call goes through `run`, `run_sh`, or `capture`, which print `+ the command` under `--dry-run` instead of running it.
- Read-only probes (`lsblk`, `lspci`, `hostname`, the post-sed `grep -qF` checks, the VERIFY checks) run for real in both modes.
- `gum choose`/`gum input` are never reached under `--yes`/`--dry-run`: every caller requires `--host`/`--disk` instead.
- Every run's output is duplicated into `/tmp/krane-install-<timestamp>-<pid>.log`, unless `/tmp` isn't writable, in which case it warns once and continues.
