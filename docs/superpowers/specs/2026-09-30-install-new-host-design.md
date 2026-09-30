# Install-mode "new host" creation — design

Date: 2026-09-30

## Goal

`install.sh` in install mode can create a brand-new host instead of only installing one of the
existing `hosts/*` entries. Picking "+ new host" asks for a hostname, a login username, a git
identity, a hardware profile, and a keyboard layout; the script scaffolds `hosts/<name>/`,
registers sops placeholders, and then continues through the unchanged install flow (disko,
hardware config, PRIME patch, commit, `nixos-install`).

The login username stops being hardcoded as `krane`: it becomes a per-host option, defaulting
to `krane`, so the three existing hosts evaluate to byte-identical systems.

## Decisions

- **Install mode only.** Setup mode runs on a machine this flake already installed; the host
  must exist by then. Setup mode gains a guard that fails clearly when the machine's hostname
  is not in `hosts/`.
- **Hardware profile scaffolding** (not "clone an existing host", not a bare template).
- **Username is per host**: `krane.user.name`, default `"krane"`.
- **Git identity is per host**: `krane.user.gitName` (default: the username) and
  `krane.user.gitEmail` (default: `chris@krane.dev`), both prompted for new hosts.
- **Hosts are auto-discovered** from `hosts/` in `flake.nix`; templates are real Nix files with
  `@TOKEN@` placeholders rendered by `install.sh`.

## Out of scope

- AMD CPU + NVIDIA dGPU PRIME (`amdgpuBusId`). Not offered in the menu.
- Monitor detection. The live ISO runs no Hyprland; `display.nix` starts with one `preferred`
  monitor and is tuned after first boot.
- Pushing the new host anywhere. The commit exists only in the live-ISO checkout and the copy on
  the target disk.
- Renaming the `krane.*` option namespace or `krane-` store-name prefixes. Those are repo
  branding, not the user account.
- Creating a host from setup mode (adopting a machine this script did not install).

## Part 1: Nix side

### `modules/nixos/user.nix` (new, imported by `modules/nixos/default.nix`)

```nix
options.krane.user = {
  name     = mkOption { type = types.str; default = "krane"; };
  gitName  = mkOption { type = types.str; default = config.krane.user.name; defaultText = ...; };
  gitEmail = mkOption { type = types.str; default = "chris@krane.dev"; };
};
```

### Consumers switched to the option

| File | Change |
| --- | --- |
| `modules/nixos/users.nix` | `users.users.${cfg.name}`; comment names the option, not `krane` |
| `modules/nixos/desktop.nix` | autologin `user = config.krane.user.name` |
| `modules/nixos/nix-settings.nix` | `trusted-users = [ config.krane.user.name ]` |
| `modules/nixos/sops.nix` | rclone secret `owner = config.krane.user.name` |
| `lib/mk-host.nix` | `home-manager.users.${config.krane.user.name}`; passes `kraneUser = config.krane.user` via `home-manager.extraSpecialArgs` |
| `hosts/*/default.nix` | `home-manager.users.${config.krane.user.name}.imports = [ ./display.nix ];` |
| `hosts/tariognatha/vm-overrides.nix` | autologin user from the option |
| `modules/home/default.nix` | `home.username = kraneUser.name` |
| `modules/home/git.nix` | `user.name = kraneUser.gitName; user.email = kraneUser.gitEmail;` |

Any other `krane` occurrence that names the account (found with
`git grep -nw krane -- modules hosts lib`, ignoring `krane.` options and `krane-` prefixes) is
switched the same way.

### Host discovery in `flake.nix`

- `hosts` = directory names from `builtins.readDir ./hosts` (filter `type == "directory"`).
- Delete the hand-written list, `hostDirs`, and the `throwIf (hostDirs != hostsSorted)` guard in
  `checks.lua-syntax`.
- `tariognatha-vm` stays a manual extra `nixosConfigurations` entry.
- Update the "mirrors" comments in `install.sh` and `scripts/bootstrap-sops.sh`; both already
  glob `hosts/*/`, as does `scripts/docker-check.sh`.

### Invariant

For `tariognatha`, `tarmantria`, `taractias` and `tariognatha-vm`,
`nix eval --raw .#nixosConfigurations.<h>.config.system.build.toplevel.drvPath` is identical
before and after Part 1.

## Part 2: templates and hardware profiles

### `templates/host/`

- `default.nix.in`: header comment, `imports` (`./hardware-configuration.nix`, `./disko.nix`,
  profile imports), `@PROFILE@` body, `krane.user = { name = "@USERNAME@"; gitName = "@GIT_NAME@";
  gitEmail = "@GIT_EMAIL@"; };`, `system.stateVersion = "26.05";`, and the home-manager
  `display.nix` import.
- `disko.nix.in`: the shared GPT + ESP + btrfs subvolume layout with
  `device = "/dev/CHANGE-ME";` so the existing `patch_disko` fills it.
- `display.nix.in`: one monitor (`output = ""`, `mode = "preferred"`, `position = "auto"`,
  `scale = 1`), `kb_layout = "@KB_LAYOUT@"`, `kb_variant = "@KB_VARIANT@"`, `@TOUCHPAD@`
  (a `touchpad` block on laptops, empty on desktops), and the same `variables` block the
  existing hosts use.
- `profiles/<gpu>.nix.in`: text substituted into `default.nix` for `@PROFILE_IMPORTS@` and
  `@PROFILE@`.
- `form-factors/<ff>.nix.in`: extra nixos-hardware imports.

### GPU profiles

| Profile | Contents |
| --- | --- |
| `amd-igpu` | nixos-hardware `common-cpu-amd`, `common-gpu-amd`; `hardware.graphics.{enable,enable32Bit}`; `LIBVA_DRIVER_NAME = "radeonsi"`; `hardware.cpu.intel.updateMicrocode = false` |
| `intel-igpu` | nixos-hardware `common-cpu-intel`; `hardware.graphics.{enable,enable32Bit}`; `LIBVA_DRIVER_NAME = "iHD"` |
| `nvidia-desktop` | `../../modules/nixos/gpu/nvidia-desktop.nix` (keeps `host_uses_cuda` working) |
| `intel-nvidia-prime` | `../../modules/nixos/gpu/nvidia-prime.nix`; `krane.prime.intelBusId` / `nvidiaBusId` placeholder lines in the exact form `patch_prime` expects |

### Form factors

- `laptop`: `common-pc-laptop`, `common-pc-laptop-ssd`, touchpad block in `display.nix`.
- `desktop`: `common-pc-ssd`.

### Detection

`suggest_profile()` reuses the `lspci` / `dmidecode` checks already in `suggest_host()` and
prints `<gpu-profile> <form-factor>`. The `gum choose` menus pre-select both; the user can
override. Missing `lspci`/`dmidecode` means no pre-selection, not a failure.

## Part 3: `install.sh` flow

### Host selection

`choose_host` appends `+ new host` to the menu. `--new-host NAME` selects it directly and sets
the hostname.

### Order

All answers are collected first and no file is written until the wipe is confirmed, so an abort
before the wipe leaves the repo untouched.

1. `prompt_new_host`
   - hostname: `^[a-z][a-z0-9-]{0,62}$`, not an existing `hosts/` entry, not `tariognatha-vm`
   - username: `^[a-z_][a-z0-9_-]{0,31}$`, not `root` or another system account name
     (`nobody`, `daemon`, `nixbld*`, `sshd`, …), default `krane`
   - git name (default: username), git email (default: `chris@krane.dev`)
   - GPU profile, form factor (pre-selected from detection)
   - kb layout (default `at`), kb variant (default `nodeadkeys`)
2. `choose_disk`, `validate_disk_is_physical`, `confirm_wipe_target` (unchanged)
3. `scaffold_host`
   - render the templates into `hosts/<name>/` with `sed`, escaping `/`, `&` and `\` in values
   - `nix-instantiate --parse` each rendered file; die with the file name on failure
   - `.sops.yaml`: an `awk` step inserts
     `- &admin_<name> age1PLACEHOLDER_ADMIN_<NAME>_REPLACE_VIA_BOOTSTRAP_SOPS_SH` and
     `- &host_<name> age1PLACEHOLDER_HOST_<NAME>_REPLACE_VIA_BOOTSTRAP_SOPS_SH` as the last
     `keys:` entries (before `creation_rules:`), and appends a matching `creation_rules` block.
     A second run is a no-op when the anchors already exist.
   - no `secrets/<name>.yaml`; `modules/nixos/sops.nix`'s `pathExists` gate handles its absence
4. Existing flow, unchanged: `patch_disko`, `git add -A`, disko, swap, hardware config,
   `patch_prime`, `commit_hardware_config` (now also commits the new host and `.sops.yaml`),
   `nixos-install`, `finish_install`

### Username in the rest of install

- `INSTALL_USER` = `nix eval --raw "$REPO_ROOT#nixosConfigurations.$HOST.config.krane.user.name"`,
  evaluated after the host is known (existing or new). With `--dry-run` and a not-yet-scaffolded
  host, it uses the prompted username.
- Replaces hardcoded `krane` in `set_krane_password` (renamed `set_user_password`), the
  `/mnt/home/<user>/.dotfiles` copy, the `chown -R <user>:users`, the `flake.nix` presence check
  and all related messages.
- The throwaway git identity in `commit_hardware_config` uses `<user>@localhost`.
- `scripts/bootstrap-sops.sh`'s "Re-run as the admin user krane" becomes "Re-run as this host's
  admin user".

### End of run

For a new host, `finish_install` prints a warning: the host exists only as a local commit in
`~/.dotfiles` on the target and must be pushed from there after first boot.

### Non-interactive

`--yes --new-host NAME` requires `--user`, `--profile` and `--form-factor`; missing any of them
is a usage error. `--git-name`, `--git-email`, `--kb-layout` and `--kb-variant` are optional and
take the defaults above. These flags are rejected outside install mode and without
`--new-host`.

### Setup-mode guard

`preflight_setup` dies when `HOST` is not in `AVAILABLE_HOSTS`:
`host '<HOST>' not in hosts/ — install it via install mode, or pass --host`.

## Error handling

- Invalid hostname / username / email input re-prompts interactively and is a usage error under
  `--yes`.
- A template render or parse failure dies before disko runs. The partially rendered
  `hosts/<name>/` is removed and `.sops.yaml` is restored with `git checkout -- .sops.yaml`.
- Every later failure behaves exactly as for an existing host. The scaffolded host is by then
  in the working tree, so a rerun can select it from the menu like any other host.

## Testing

- **Invariant**: before/after `drvPath` comparison for all existing `nixosConfigurations`.
- **`install.sh --self-test-check-scaffold`**: renders every GPU profile × form factor into a
  temp dir, runs `nix-instantiate --parse` on each file, checks that the `.sops.yaml` insert is
  idempotent and that `sops_placeholder_present` detects the new host, and checks that the
  PRIME profile's lines match `patch_prime`'s regex.
- **`just check-new-host`**: in a throwaway `git worktree`, scaffolds `testhost` for each of the
  8 combinations with a stub `hardware-configuration.nix` and a fake disk, then evaluates
  `nixosConfigurations.testhost.config.system.build.toplevel.drvPath`.
- **Existing self-tests** keep passing: `--self-test`, `--self-test-check-disko-sed`,
  `--self-test-check-prime-sed`.
- **Docs**: new "Installing a new machine" section in `docs/INSTALL.md`; README host list
  wording updated if it implies a fixed set.
