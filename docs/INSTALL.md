# Install guide

Path from a blank machine to a working `tariognatha`, `tarmantria`, or `taractias`, or to a new host that `install.sh` scaffolds (see [Installing a new machine](#installing-a-new-machine)). Read [README.md](../README.md) and [II-INTEGRATION.md](II-INTEGRATION.md) first.

Desktops and laptops only. The servers (`taragarmr`, `taronychus`, `tarritator`, `tarronax`) are not installed with `install.sh`: see their `hosts/<name>/default.nix` header comments and the Servers section of [secrets/README.md](../secrets/README.md).

`install.sh` drives disko, `nixos-install`, secrets bootstrap, the Rust toolchain, flathub and the required second `nixos-rebuild switch`. Every destructive step has a `--dry-run` preview. Appendix A is the manual path, Appendix B documents `install.sh` step by step.

## 0. Before you start

- `tariognatha`: NVIDIA RTX-4070-Ti-class desktop GPU, single GPU, open kernel module.
- `tarmantria`: Intel iGPU plus NVIDIA dGPU laptop, PRIME offload.
- `taractias`: AMD Vega iGPU laptop, no dGPU.
- On `taractias`, press `e` in the ISO boot menu and append `iommu=pt` to the kernel line, or use a wired connection. The QCA9377 Wi-Fi stalls under the default IOMMU mode. The installed system sets `iommu=pt` itself (`hosts/taractias/default.nix`).
- UEFI boot, Secure Boot off. systemd-boot does not handle Secure Boot.
- A NixOS unstable minimal installer ISO, written to USB.
- Network once booted. `install.sh` re-execs itself through `nix shell` for `gum` and other tools the minimal ISO lacks, and enables flakes itself, so `/etc/nix/nix.conf` needs no edit. The ISO ships NetworkManager: `nmtui`, or `nmcli device wifi connect SSID password PW`.
- Check with `curl -fsS --max-time 5 -o /dev/null https://cache.nixos.org`, the probe `install.sh`'s preflight runs.
- This repo, cloned anywhere reachable from the installer:

```sh
git clone https://github.com/LeeKrane/nixos-dotfiles ~/.dotfiles
cd ~/.dotfiles
```

## 1. Run `./install.sh`

```sh
./install.sh
```

On a live ISO this runs install mode:

1. Preflight: root, UEFI boot, network, required tools. Missing `dmidecode`/`lspci` only skips host suggestion and PRIME detection.
2. Host: a `gum choose` list of the hosts under `hosts/`, pre-selected from the chassis. The last entry, `+ new host`, scaffolds a new one: see [Installing a new machine](#installing-a-new-machine).
3. DNS check for the caches the install needs. If a lookup fails or takes over 3 s, it offers to pin public DNS through NetworkManager.
4. Disk: lists real disks, excludes the ISO's own device, offers a stable `/dev/disk/by-id/...` path.
5. Confirmation: you type the kernel device name, such as `nvme0n1`.
6. Partition and format: patches `hosts/<host>/disko.nix`'s `/dev/CHANGE-ME` with your disk and runs disko. This erases the disk. Layout: GPT, an ESP, btrfs root with zstd-compressed `@`, `@home`, `@nix`, `@snapshots` subvolumes, zram swap.
7. Install swapfile: under 24 GiB RAM, a 16 GiB swapfile at `/mnt/swapfile`, removed after `nixos-install`. The nix eval heap alone stays around 5 GB and the live ISO has no swap. `nixos-install` also runs with `max-jobs = 1` and half the cores, so local compiles (quickshell) do not trigger the OOM killer.
8. Hardware config: `nixos-generate-config --no-filesystems --root /mnt`, written to `hosts/<host>/hardware-configuration.nix`.
9. PRIME bus IDs, `tarmantria` only: patches `krane.prime.intelBusId`/`nvidiaBusId` in `hosts/tarmantria/default.nix` from `lspci -D`.
10. Local commit of the hardware config and PRIME changes: flakes only see git-tracked files.
11. `nixos-install`. Slow: quickshell compiles from source. The CUDA cache is passed only for hosts that import `gpu/nvidia-desktop` (`tariognatha`). On failure it asks to retry, up to three attempts: nix resumes from the paths already copied.
12. Copies this repo to `/mnt/home/<user>/.dotfiles`, where `<user>` is the host's `krane.user.name` (`krane` on the original hosts).
13. Sets that user's password. Runs even under `--yes`.
14. Offers to reboot.

## 2. After first boot: setup mode

Every host autologins into the plain (non-UWSM) Hyprland session and locks it at once, so the ii lock screen is the first thing you see (`modules/nixos/desktop/desktop.nix`). This is acceptable because no host encrypts its disk: there is no boot password gate to preserve. tuigreet appears after logout or `systemctl restart greetd`; "Hyprland (UWSM)" is its normal session, plain "Hyprland" the fallback ([II-INTEGRATION.md "Rollback and escape hatches"](II-INTEGRATION.md#rollback-and-escape-hatches)).

Log in, then from `~/.dotfiles`:

```sh
./install.sh
```

On an installed system this runs setup mode:

1. Bootstraps sops-nix (`scripts/bootstrap-sops.sh <host>`): derives this host's age recipient and offers to commit `.sops.yaml`. If you decline, commit later with Appendix A step 9. sshd runs only so `sshd-keygen` creates the host key at boot; `openFirewall = false`.
2. Offers to edit `secrets/<host>.yaml` with `sops` (skipped under `--yes`/`--dry-run`) and to commit it. An uncommitted secrets file evaluates as absent to sops-nix. Keys: [secrets/README.md](../secrets/README.md).
3. Offers the Rust toolchain (`rustup default stable` plus components).
4. Offers the flathub remote.
5. Runs the [VERIFY checklist](VERIFY.md#2-on-target-checklist), reporting each check OK, WARN or SKIP.
6. Runs a second `nixos-rebuild switch`. The first already ran the ii dotfiles copy and this repo's overrides once, so the second proves they hold on repeat.
7. Prints next steps: add the WireGuard and rclone values to `secrets/<host>.yaml` with `sops set` ([secrets/README.md](../secrets/README.md)), rebuild (wg0 then autostarts), run `just check`.

Afterwards:

- Switches leave `*.hm-bak` files under `$HOME`. They are expected; see [II-INTEGRATION.md](II-INTEGRATION.md).
- `~/.config/rclone/rclone.conf` is seeded once, if absent, from the `rclone/config-seed` secret (`modules/home/desktop/proton-drive.nix`), then mutated by `scripts/proton-drive-rclone-mount.sh` when Proton's session expires. If it is lost, run `rclone config`.

## Installing a new machine

For a machine with no `hosts/<name>/` yet. Install mode only: setup mode stops with `host '<name>' not in hosts/`.

1. Boot the ISO, clone the repo as in section 0, run `./install.sh`.
2. Pick `+ new host`. It asks for:
    - Hostname: lowercase letter first, then lowercase letters, digits and `-`; at most 63 characters; not ending in `-`; not an existing host or `tariognatha-vm`.
    - Login username, default `krane`; not `root` or another system account.
    - Git name (default: the username) and git email (default `chris@krane.dev`), written to `krane.user`.
    - GPU profile and form factor, pre-selected from `lspci`/`dmidecode`:

        | Profile | For |
        | --- | --- |
        | `amd-igpu` | AMD CPU with integrated Radeon, no dGPU (like `taractias`) |
        | `intel-igpu` | Intel CPU with its integrated GPU, no dGPU |
        | `nvidia-desktop` | A single NVIDIA GPU (like `tariognatha`), gets the CUDA cache |
        | `intel-nvidia-prime` | Intel iGPU plus NVIDIA dGPU, PRIME offload (like `tarmantria`) |

        `laptop` adds nixos-hardware's laptop profiles and a touchpad block; `desktop` adds the SSD profile only. AMD CPU plus NVIDIA dGPU PRIME is not offered.
    - Keyboard layout and variant, default `at` / `nodeadkeys` (empty variant for any other layout).
3. Disk selection and the typed wipe confirmation work as usual. Nothing is written to the repo before that confirmation.
4. `install.sh` renders `templates/host/` into `hosts/<name>/` (`default.nix`, `disko.nix`, `display.nix`, a placeholder `hardware-configuration.nix`, `illogical-impulse/.gitignore`, `ii-settings.json` as `{}`), parse-checks every `.nix` file, and adds `age1PLACEHOLDER_*` recipients to `.sops.yaml`. If rendering or parsing fails it removes `hosts/<name>/` and restores `.sops.yaml`. Then the normal flow runs, with one local commit `Add <name> host`. The template sets `system.stateVersion = "26.05"`; do not bump it on an installed host.
5. The new host exists only as that commit in `~/.dotfiles` on the new machine. After first boot, run setup mode (it bootstraps the host's sops recipients), then push from there.
6. `display.nix` starts with one catch-all `preferred` monitor rule, because the ISO runs no Hyprland to detect outputs. After first login, check `hyprctl monitors -j` and name the real outputs.

Non-interactively:

```sh
./install.sh --new-host newbox --user alice --profile amd-igpu --form-factor laptop \
    --disk /dev/disk/by-id/<disk> --yes --confirm-wipe
```

`--yes --new-host` requires `--user`, `--profile` and `--form-factor`. `--git-name`, `--git-email`, `--kb-layout` and `--kb-variant` take the defaults above. All of these flags are usage errors without `--new-host` or outside install mode.

To check the templates without a machine, commit your change and run `just check-new-host` (needs local Nix). It scaffolds a throwaway `testhost` for each GPU profile and form factor in a temporary git worktree and checks each is nixfmt-clean and evaluates.

## Flags

| Flag | What it does |
| --- | --- |
| `--mode install\|setup` | Force a mode instead of auto-detecting it. |
| `--host HOST` | One of the directories under `hosts/`. |
| `--new-host NAME` | Install mode only: create `hosts/NAME` from `templates/host/`. |
| `--user NAME` | New host's login user, default `krane`. |
| `--git-name NAME` | New host's git `user.name`, default: the login user. |
| `--git-email EMAIL` | New host's git `user.email`, default `chris@krane.dev`. |
| `--profile PROFILE` | New host's GPU profile: `amd-igpu`, `intel-igpu`, `nvidia-desktop`, `intel-nvidia-prime`. |
| `--form-factor FF` | New host's form factor: `laptop` or `desktop`. |
| `--kb-layout LAYOUT` | New host's keyboard layout, default `at`. |
| `--kb-variant VARIANT` | New host's keyboard variant, default `nodeadkeys` for `at`, otherwise empty. |
| `--disk DISK` | Target block device, install mode only. |
| `-y`, `--yes` | Auto-confirm every prompt. Never skips setting the login user's password. |
| `-n`, `--dry-run` | Print every mutating command instead of running it. Implies `--yes`. |
| `--confirm-wipe` | Required for a live, non-dry-run `--yes` install. |
| `--self-test` | Exercise `install.sh`'s own failure handling in isolation (maintainer and CI hook, not in `--help`). |
| `-h`, `--help` | Show usage and exit. |

`--yes`/`--dry-run` turn prompts off, so they need `--host` (or `--new-host` with its three required flags) and, in install mode, `--disk`. A live `--yes` install also needs `--confirm-wipe`.

On a non-NixOS system `install.sh` defaults to install mode. Pass `--dry-run` or `--mode setup` when experimenting on an ordinary Linux box.

`--dry-run` is safe anywhere, as any user. Mutating steps print `+ the command`; read-only probes still run. `just install-test` (`scripts/docker-check.sh install-test`) runs it and checks `git status --porcelain` and `git rev-parse HEAD` before and after.

### DNS timeouts ("Resolving timed out")

Preflight offers to pin public DNS. By hand:

```sh
nmcli -t -f NAME con show --active
nmcli con mod "<connection name>" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes
nmcli con up "<connection name>"
```

## NVIDIA black-screen ladder (`tariognatha`, or `tarmantria`'s dGPU path)

Out-of-tree modules (`v4l2loopback`, NVIDIA) build against `boot.kernelPackages`, `linuxPackages_latest` by default (`mkDefault` in `modules/nixos/desktop/boot.nix`). If one fails to build on a new kernel, pin an older `linuxPackages_6_x` there.

If Hyprland shows a black screen after switching, try these in order, re-switching after each. Each is a one-line change in `modules/nixos/gpu/nvidia-desktop.nix` or `nvidia-prime.nix`.

1. `hardware.nvidia.open = false;`: the proprietary kernel module.
2. `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;`: a newer driver.
3. `boot.kernelParams = [ "nvidia_drm.fbdev=0" ];`, replacing the `=1` in `nvidia-desktop.nix`: disables the NVIDIA DRM framebuffer console.

## Windows dual-boot entry

systemd-boot lists a Windows install on the same ESP automatically. Check with:

```sh
sudo bootctl list
```

Windows on a separate disk's ESP needs an explicit entry. `modules/nixos/desktop/t7-win11.nix` is the working example (`tariognatha`, `tarmantria`): `boot.loader.systemd-boot.extraEntries` plus an EDK2 shell `startup.nsh` that boots the filesystem carrying a marker file, because systemd-boot cannot chainload from another disk and `fsN` handles shift with attached drives. Copy it for another disk, then confirm with `efibootmgr -v` and `sudo bootctl list`.

## Data migration

Manual, once the new system is up, from whatever media or network path holds the old host's data. `old:~/path` is the old host's home directory, expanded by the remote shell:

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

Fix permissions:

```sh
chmod 700 ~/.ssh ~/.gnupg
chmod 600 ~/.ssh/id_*
```

Bottles prefixes and Steam's `compatibilitytools.d` need more than a plain rsync: rsync `~/.local/share/bottles` after `bottles` (`modules/nixos/desktop/gaming.nix`) is installed, and rsync `compatibilitytools.d` for any Proton build besides GE-Proton, which `programs.steam.extraCompatPackages` already provides.

## Appendix A: manual install (without `install.sh`)

Replace `<host>` with `tariognatha`, `tarmantria`, or `taractias`. Paths assume the repo at `~/.dotfiles`.

1. Enable flakes on the live ISO.

    ```sh
    mkdir -p /etc/nix
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
    ```

2. Edit `hosts/<host>/disko.nix`, replacing `/dev/CHANGE-ME` with the disk, preferably a `/dev/disk/by-id/...` path. Then partition and format.

    ```sh
    nix run github:nix-community/disko -- --mode destroy,format,mount --flake .#<host>
    ```

3. Generate the hardware config and copy it over the placeholder.

    ```sh
    nixos-generate-config --no-filesystems --root /mnt
    cp /mnt/etc/nixos/hardware-configuration.nix hosts/<host>/hardware-configuration.nix
    ```

4. On `tarmantria` only, find the GPU bus IDs and fill in `krane.prime.intelBusId`/`nvidiaBusId` in `hosts/tarmantria/default.nix`.

    ```sh
    lspci | grep -E 'VGA|3D'
    ```

    Under 24 GiB RAM, create a temporary swapfile first, and run `nixos-install` with `NIX_CONFIG=$'max-jobs = 1\ncores = 4'` (or half the cores) to avoid the OOM killer:

    ```sh
    btrfs filesystem mkswapfile --size 16g /mnt/swapfile
    swapon /mnt/swapfile
    ```

5. Install. `flake.nix` has no `nixConfig`, so pass the CUDA cache explicitly, only on `tariognatha`, the one host with CUDA packages.

    ```sh
    nixos-install --flake "$PWD#<host>" --option extra-substituters https://cache.nixos-cuda.org --option extra-trusted-public-keys cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=   # tariognatha
    nixos-install --flake "$PWD#<host>"                                                                                                                                                             # tarmantria, taractias
    ```

    Remove the swapfile after, if you made one.

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

8. Reboot, log in, switch twice. The second switch proves the ii dotfiles-copy step and this repo's overrides are idempotent.

    ```sh
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
    ```

9. Bootstrap sops-nix and fill in secrets. Commit both: an uncommitted secrets file evaluates as absent.

    ```sh
    scripts/bootstrap-sops.sh <host>
    git add .sops.yaml && git commit -m "Add <host> sops recipient"
    sops secrets/<host>.yaml
    git add secrets/<host>.yaml && git commit -m "Add <host> secrets"
    sudo nixos-rebuild switch --flake ~/.dotfiles#<host>
    ```

10. Add the six `wireguard/*` keys to `secrets/<host>.yaml` with `sops set` ([secrets/README.md](../secrets/README.md)) and rebuild. The `wg0.conf` template renders from them and `networking.wg-quick.interfaces.wg0` autostarts on the next switch.

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

11. Set up Proton Drive, if you did not seed `rclone/config-seed`.

    ```sh
    rclone config
    systemctl --user restart proton-drive-mount
    ```

12. Add the flathub remote, then install what you want.

    ```sh
    flatpak install flathub <app-id>
    ```

13. Install the Rust toolchain. `modules/home/desktop/dev.nix` installs `rustup`, not a pinned toolchain.

    ```sh
    rustup default stable
    rustup component add rust-analyzer rust-src
    ```

14. Migrate data and add a Windows entry: see "Data migration" and "Windows dual-boot entry".

## Appendix B: what `install.sh` does, step by step

Function and variable names are the stable reference; line numbers move.

Mode detection (`detect_mode`): `install` if `/iso` exists, `/etc/NIXOS` is missing, or `/` is an `overlay` filesystem (a live ISO's root); `setup` otherwise. `--mode` overrides.

### Install mode (`run_install_mode`)

- `preflight_live`: root, UEFI, network, required tools.
- `choose_host`: `gum choose` over `suggest_host`'s guess plus `+ new host`. `+ new host` (or `--new-host`) runs `prompt_new_host`, which collects every answer first, pre-selecting `suggest_profile`'s GPU profile and form factor.
- `check_dns`: probes `cache.nixos.org` (plus `cache.nixos-cuda.org` on the CUDA host); offers to pin public DNS on the active NetworkManager connection when a lookup fails or exceeds 3 s.
- `choose_disk`, `validate_disk_is_physical`, `confirm_wipe_target`: disk list from `lsblk` minus the ISO's device, a stable `/dev/disk/by-id` path, and a typed-confirmation gate before anything destructive.
- `scaffold_host`, new hosts only: renders `templates/host/` into a staging dir, runs `nix-instantiate --parse` on each file, copies it to `hosts/<name>/`, adds the host's placeholders to `.sops.yaml` (`register_sops_host`). A failure before it finishes rolls both back from `on_exit`. Under `--dry-run` only the staging dir is written.
- `patch_disko`, `run_disko`: sed-patches `/dev/CHANGE-ME` in `hosts/$HOST/disko.nix`, verified with `grep -qF`, then builds and runs that host's disko script.
- `resolve_install_user`: after `git add -A`, reads the login user from `nix eval …#nixosConfigurations.$HOST.config.krane.user.name` (the prompt answer for a new host under `--dry-run`).
- `setup_install_swap` / `teardown_install_swap`: the 16 GiB swapfile when RAM is under 24 GiB. Best effort: a failure warns and continues.
- `generate_hardware_config`: `nixos-generate-config`, checked for `availableKernelModules` and no `fileSystems`.
- `patch_prime`: `tarmantria` only; converts `lspci -D` addresses to `PCI:B:D:F` decimal.
- `commit_hardware_config`: commits (`Add <name> host` for a new host), with a throwaway `<user>@localhost` identity if none is configured.
- `run_nixos_install`: `nixos-install --flake "$REPO_ROOT#$HOST" --no-root-passwd`, plus `flake_config_opt`'s CUDA substituter options on the CUDA host. Up to 3 attempts, 10 s apart, each confirmed.
- `finish_install`: copies the repo to `/mnt/home/<user>/.dotfiles`, chowns it, verifies `flake.nix` landed, sets the password, warns that a new host is only a local commit, offers a reboot.

### Setup mode (`run_setup_mode`)

- `preflight_setup`: refuses to run as root, requires `git just sops age ssh-to-age`, dies when the host (`--host` or `hostname`) is not under `hosts/`.
- `run_bootstrap_sops`: runs `scripts/bootstrap-sops.sh $HOST`, offers to commit `.sops.yaml`.
- `edit_host_secrets`: offers `sops secrets/$HOST.yaml` (skipped under `--yes`), then offers to commit it.
- `setup_rust`, `check_flathub`: each offered independently.
- `verify_checks`: each check reports OK, WARN or SKIP independently.
- `second_switch`: `sudo nixos-rebuild switch --flake $REPO_ROOT#$HOST` plus the CUDA options, then `verify_checks` again.

### Dry-run invariants

- Every mutating call goes through `run`, `run_sh` or `capture`, which print `+ the command` under `--dry-run`.
- Read-only probes (`lsblk`, `lspci`, `hostname`, the post-sed `grep -qF` checks, the VERIFY checks) run for real.
- `gum choose`/`gum input` are never reached under `--yes`/`--dry-run`: callers require `--host`/`--disk` instead.
- Output is duplicated to `/tmp/krane-install-<timestamp>-<pid>.log`; if `/tmp` is not writable it warns once and continues.
