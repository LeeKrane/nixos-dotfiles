# Install-Mode New Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `install.sh` in install mode can create a brand-new host (hostname, login user, git identity, GPU profile, form factor, keyboard) by scaffolding `hosts/<name>/` from `templates/host/` and registering sops placeholders, then continue through the unchanged install flow. The login username becomes the per-host option `krane.user.name` (default `krane`), so the existing hosts evaluate to byte-identical systems.

**Architecture:** A new NixOS module `modules/nixos/user.nix` declares `krane.user.{name,gitName,gitEmail}`; every account-name consumer reads it, and `lib/mk-host.nix` hands it to home-manager as the `kraneUser` extraSpecialArg. `flake.nix` discovers hosts from the directories under `hosts/`. `install.sh` gains a "+ new host" menu entry and `--new-host` flags: it collects every answer first, then after the wipe confirmation renders `templates/host/*.nix.in` into a staging dir (sed for scalars, awk for multi-line blocks), parse-checks it with `nix-instantiate --parse`, copies it to `hosts/<name>/`, and inserts `.sops.yaml` placeholders with awk. A failure before that finishes rolls back from `on_exit`. The rest of install mode reads the login user from `nix eval …config.krane.user.name` instead of hardcoding `krane`.

**Tech Stack:** Nix flakes, NixOS modules, home-manager, bash + gum, sops-nix, disko

**Spec:** docs/superpowers/specs/2026-09-30-install-new-host-design.md

## Global Constraints

- Work only in `/home/krane/.dotfiles/.claude/worktrees/install-new-host`, branch `worktree-install-new-host`. Never `cd` elsewhere.
- Run git as `/etc/profiles/per-user/krane/bin/git`; a hook blocks plain `git`. Use `command cat`, never bare `cat`.
- One commit per task, subject line only: no body, no `Co-Authored-By`, no Claude/Anthropic attribution. Never push.
- Flakes see only tracked files: `git add` every new file before any `nix` command that has to see it.
- `nix eval` may be refused by this session's command guard (it was during planning). Get drvPaths with `nix path-info --derivation <installable>`, which prints the same `.drv` path as `nix eval --raw <installable>.drvPath`. Check values through `nix build --no-link .#checks.x86_64-linux.user-option` (Task 2) and `just check-new-host` (Task 10). Repo scripts may call `nix eval` themselves.
- Invariant: the toplevel drvPaths of `tariognatha`, `tarmantria`, `taractias` and `tariognatha-vm` must match Task 1's `/tmp/install-new-host-baseline.txt`, checked in Tasks 2, 3 and 11. Do not reorder any list or attrset whose value reaches a derivation. `kraneUser` only carries strings that were already hardcoded.
- Default user `"krane"`. Default git name: the username. Default git email `"chris@krane.dev"`. `system.stateVersion = "26.05"`. Default keyboard layout `at`, default variant `nodeadkeys`.
- Hostname: `^[a-z][a-z0-9-]{0,62}$`, must not end in `-`, must not be an existing `hosts/` entry, must not be `tariognatha-vm`.
- Username: `^[a-z_][a-z0-9_-]{0,31}$`, must not be `root`, a name in `SYSTEM_ACCOUNT_NAMES`, `nixbld*` or `systemd-*`.
- sops placeholders: `age1PLACEHOLDER_ADMIN_<NAME>_REPLACE_VIA_BOOTSTRAP_SOPS_SH` and `age1PLACEHOLDER_HOST_<NAME>_REPLACE_VIA_BOOTSTRAP_SOPS_SH`. `<NAME>` is the hostname after `tr '[:lower:]' '[:upper:]'`, dashes kept, which is what `sops_placeholder_present` (install.sh:1001) and `scripts/bootstrap-sops.sh:52-54` compute. Anchors stay lowercase: `&admin_<name>`, `&host_<name>`.
- GPU profiles: `amd-igpu intel-igpu nvidia-desktop intel-nvidia-prime`. Form factors: `laptop desktop`.
- Option paths: `krane.user.name`, `krane.user.gitName`, `krane.user.gitEmail`. The home-manager extraSpecialArg is `kraneUser` (`= config.krane.user`). The `krane.*` namespace and `krane-` store-name prefixes stay as they are.
- install.sh style: 4-space indent. Use the existing helpers (`run`, `run_soft`, `run_sh`, `capture`, `die`, `soft_fail`, `usage_die`, `log_step`, `log_info`, `log_ok`, `log_warn`, `confirm`, `choose_one`, `gum_tty`). Every mutating step goes through `run*`; read-only probes run for real under `--dry-run`. Comments say why, one short block per function.
- Nix style: run `nix fmt -- <files>` after editing Nix files, since CI runs `nix fmt -- --ci`. CI also runs `statix check .`, `deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .` and `shellcheck -x -S style install.sh scripts/*.sh`, and all of them must stay clean.
- Line numbers refer to commit `4c96cbf`. Earlier tasks shift them, so find each edit by the quoted anchor text.
- The command guard can refuse shell loops over variables and runtime globs. Every command in this plan is written as one plain command for that reason. If a glob such as `hosts/*/hardware-configuration.nix` is refused, spell the paths out.

## Review Focus

- A hostname ending in `-` (`box-`) passes the spec regex, but NixOS's `networking.hostName` rejects it, so it would fail inside `nixos-install` after the wipe. The validator must refuse it. Test: Task 6 (`check_new_hostname` table).
- A new hostname that is a prefix of an existing host (`tar` versus `&admin_taractias`) must not look already registered to the `.sops.yaml` idempotence check. Test: Task 5 (`register_sops_host … tar`).
- A git name or email that contains `/`, `&`, `\`, `"` or `${` must render as valid Nix holding the same string, not break sed or the Nix string. Test: Task 4 (escaping render in `--self-test-check-scaffold`).
- `suggest_profile` with one probe unknown (no GPU match but a known chassis, or both probes empty) must not slide the form factor into the profile slot. Test: Task 6 (`suggest_profile` stubs).
- A failure after `hosts/<name>/` is written but before scaffolding finishes (for example a `.sops.yaml` with no `creation_rules:`) must remove only the new host dir and restore `.sops.yaml`. A refused repeat must never delete an existing host. Test: Task 7 (sandbox rollback self-test).

---

## File Structure

- Create `modules/nixos/user.nix`: declares `krane.user.{name,gitName,gitEmail}` with defaults.
- Modify `modules/nixos/default.nix`: imports `./user.nix`.
- Modify `modules/nixos/users.nix`, `desktop.nix`, `nix-settings.nix`, `sops.nix`, `peripherals.nix` (comment only): read the account name from `config.krane.user.name`.
- Modify `lib/mk-host.nix`: the home-manager block becomes a module function; `users.${config.krane.user.name}` and `extraSpecialArgs.kraneUser`.
- Modify `hosts/{tariognatha,tarmantria,taractias}/default.nix`, `hosts/tariognatha/vm-overrides.nix`: `home-manager.users.${config.krane.user.name}` and the VM's autologin.
- Modify `modules/home/default.nix`, `modules/home/git.nix`: `home.username` and the git identity from `kraneUser`.
- Modify `modules/nixos/gpu/nvidia-desktop.nix`, `nvidia-prime.nix`: header comments name the template profiles as importers too.
- Modify `flake.nix`: `checks.user-option`; host auto-discovery; `lua-syntax` without the list guard; description and comments.
- Create `templates/host/default.nix.in`, `disko.nix.in`, `display.nix.in`, `hardware-configuration.nix.in`: the per-host files with `@TOKEN@` placeholders.
- Create `templates/host/profiles/{amd-igpu,intel-igpu,nvidia-desktop,intel-nvidia-prime}.nix.in`: `#== imports` and `#== body` sections spliced into `default.nix`.
- Create `templates/host/form-factors/{laptop,desktop}.nix.in`: `#== imports` (nixos-hardware) and `#== touchpad` (spliced into `display.nix`).
- Modify `install.sh`: template rendering, sops registration, validators, `suggest_profile`, new flags and usage, the new-host flow with rollback, `INSTALL_USER` plumbing, the setup-mode guard, and self-test hooks (`--self-test-check-scaffold`, `--self-test-scaffold`).
- Modify `scripts/bootstrap-sops.sh`: host-discovery comment; the root-refusal message no longer names `krane`.
- Modify `scripts/docker-check.sh`: host-discovery comment; a fourth `--dry-run` run covering a new host.
- Create `scripts/check-new-host.sh`: scaffolds `testhost` for all 8 combinations in a throwaway worktree and evaluates each.
- Modify `justfile`: `check-new-host` recipe; `install-lint` comment.
- Modify `docs/INSTALL.md`: "Installing a new machine" section, flags table, steps, Appendix B.
- Modify `README.md`: host count wording, security notes, fork list, layout.

---

### Task 1: Record the drvPath baseline

**Files:**
- Create (outside the repo): `/tmp/install-new-host-baseline.txt`. Executors cannot see `$CLAUDE_JOB_DIR/tmp`, so the baseline goes under `/tmp`. It must survive until Task 11. If `/tmp` is wiped in between, rebuild it from commit `4c96cbf` in a scratch worktree.

**Interfaces:**
- Produces: `/tmp/install-new-host-baseline.txt`, four sorted `.drv` paths, one per line, for `taractias`, `tariognatha`, `tariognatha-vm` and `tarmantria`. Tasks 2, 3 and 11 compare against it.

- [ ] **Step 1: Confirm the tree is clean and at the spec commit**

Run: `/etc/profiles/per-user/krane/bin/git status --porcelain` and `/etc/profiles/per-user/krane/bin/git log -1 --format=%h`
Expected: no status output. HEAD is the commit that added this plan, whose parent is `4c96cbf`.

- [ ] **Step 2: Record the baseline**

Run (one command, no loop, so the command guard accepts it):

```bash
nix path-info --derivation .#nixosConfigurations.tariognatha.config.system.build.toplevel .#nixosConfigurations.tarmantria.config.system.build.toplevel .#nixosConfigurations.taractias.config.system.build.toplevel .#nixosConfigurations.tariognatha-vm.config.system.build.toplevel > /tmp/install-new-host-baseline.txt
```

Expected: exit 0 after about a minute. stderr shows only `evaluation warning: 'swww' has been renamed to 'awww'`. The file holds four lines ending in `nixos-system-taractias-….drv`, `nixos-system-tariognatha-….drv`, `nixos-system-tariognatha-vm-….drv` and `nixos-system-tarmantria-….drv`. During planning they were:

```
/nix/store/276dhlhsvcvxfxmjxapjk80bnz32zcim-nixos-system-taractias-26.11.20260904.801bef6.drv
/nix/store/gqkzl5bxsiwhfhh0qg1wbyzd0fwq4j04-nixos-system-tariognatha-26.11.20260904.801bef6.drv
/nix/store/hia5dhqi3c93j9wn3335zdpwkdzb2hvb-nixos-system-tariognatha-vm-26.11.20260904.801bef6.drv
/nix/store/qlvr6s1bfmfi9sgiqnim84physn69w9g-nixos-system-tarmantria-26.11.20260904.801bef6.drv
```

Equivalent forms, per host: `nix eval --raw .#nixosConfigurations.<h>.config.system.build.toplevel.drvPath`, or without local Nix, `just eval-host <h>` (docker, `scripts/docker-check.sh eval`). Use whichever works, but use the same one in every later comparison.

- [ ] **Step 3: Confirm the baseline is deterministic**

Run the Step 2 command again with `> /tmp/install-new-host-baseline-2.txt`, then `diff /tmp/install-new-host-baseline.txt /tmp/install-new-host-baseline-2.txt`.
Expected: no output, exit 0.

- [ ] **Step 4: No commit**

The baseline lives outside the repo. Nothing to commit.

---

### Task 2: `krane.user` option and every account-name consumer

**Files:**
- Create: `modules/nixos/user.nix`
- Modify: `modules/nixos/default.nix:9`, `modules/nixos/users.nix:1-2,8,40-41`, `modules/nixos/desktop.nix:25,33`, `modules/nixos/nix-settings.nix:2,11`, `modules/nixos/sops.nix:74-78`, `modules/nixos/peripherals.nix:34`, `lib/mk-host.nix:28-38,111`, `hosts/tariognatha/default.nix:1,13`, `hosts/tarmantria/default.nix:1,13`, `hosts/taractias/default.nix:4-7,29`, `hosts/tariognatha/vm-overrides.nix:5,43,47`, `modules/home/default.nix:1-4,28-33`, `modules/home/git.nix:1,7-9`, `flake.nix:124-130` (lua-syntax `renderedFiles`), `flake.nix:157` (new check after `lua-syntax`)
- Test: `nix build --no-link .#checks.x86_64-linux.user-option`, plus the drvPath diff against the baseline

**Interfaces:**
- Produces: the NixOS options `krane.user.name` (type `strMatching "[a-z_][a-z0-9_-]{0,31}"`, default `"krane"`), `krane.user.gitName` (str, default `config.krane.user.name`) and `krane.user.gitEmail` (str, default `"chris@krane.dev"`). Every host's home-manager modules get the specialArg `kraneUser` (the attrset `config.krane.user`). The flake gains the output `checks.x86_64-linux.user-option`.
- Consumes: nothing new.

- [ ] **Step 1: Write the failing check**

In `flake.nix`, inside `checks.${system} = { … }`, directly after the closing `);` of `lua-syntax` (line 157) and before the `# NixVim's own startup test` comment, insert:

```nix
        # krane.user wiring (modules/nixos/user.nix): the stock hosts keep "krane", and
        # overriding it moves the account, the home-manager user, the git identity,
        # nix trusted-users and greetd autologin with it. Eval-only: the derivation is
        # trivial, the assertions run while evaluating it.
        user-option =
          let
            base = self.nixosConfigurations.taractias.config;
            moved =
              (self.nixosConfigurations.taractias.extendModules {
                modules = [
                  {
                    krane.user = {
                      name = "tester";
                      gitName = "Test Er";
                      gitEmail = "tester@example.invalid";
                    };
                  }
                ];
              }).config;
            nameOnly =
              (self.nixosConfigurations.taractias.extendModules {
                modules = [ { krane.user.name = "solo"; } ];
              }).config;
            hm = moved.home-manager.users.tester;
            expectations = [
              {
                ok = base.krane.user.name == "krane";
                what = "default krane.user.name is not krane";
              }
              {
                ok = base.krane.user.gitName == "krane" && base.krane.user.gitEmail == "chris@krane.dev";
                what = "default git identity is not krane <chris@krane.dev>";
              }
              {
                ok = base.users.users ? krane && base.home-manager.users ? krane;
                what = "default account krane is missing from users.users or home-manager.users";
              }
              {
                ok = nameOnly.krane.user.gitName == "solo";
                what = "krane.user.gitName does not default to krane.user.name";
              }
              {
                ok = moved.users.users ? tester && !(moved.users.users ? krane);
                what = "users.users does not follow krane.user.name";
              }
              {
                ok = moved.users.users.tester.home == "/home/tester" && hm.home.homeDirectory == "/home/tester";
                what = "home directory does not follow krane.user.name";
              }
              {
                ok = hm.home.username == "tester";
                what = "home.username does not follow krane.user.name";
              }
              {
                ok =
                  hm.programs.git.settings.user.name == "Test Er"
                  && hm.programs.git.settings.user.email == "tester@example.invalid";
                what = "git identity does not follow krane.user.gitName/gitEmail";
              }
              {
                ok =
                  builtins.elem "tester" moved.nix.settings.trusted-users
                  && !(builtins.elem "krane" moved.nix.settings.trusted-users);
                what = "nix trusted-users does not follow krane.user.name";
              }
              {
                ok = moved.services.greetd.settings.initial_session.user == "tester";
                what = "greetd autologin does not follow krane.user.name";
              }
            ];
            failed = map (e: e.what) (builtins.filter (e: !e.ok) expectations);
          in
          nixpkgs.lib.throwIf (failed != [ ])
            "checks.user-option: ${nixpkgs.lib.concatStringsSep "; " failed}"
            (pkgs.runCommand "krane-user-option" { } "touch $out");
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nix build --no-link .#checks.x86_64-linux.user-option`
Expected: FAIL, with an evaluation error that names the missing option, e.g. ``The option `krane.user' does not exist`` or `attribute 'user' missing`.

- [ ] **Step 3: Add the option module**

Create `modules/nixos/user.nix`:

```nix
# The login account's name and git identity, per host. Every module that names the
# account reads it from here (users.nix, desktop.nix, nix-settings.nix, sops.nix,
# lib/mk-host.nix, hosts/*/default.nix), and home-manager gets it as the `kraneUser`
# specialArg (lib/mk-host.nix). The defaults are the three original hosts' values;
# install.sh's new-host flow writes a `krane.user` block into hosts/<name>/default.nix.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.krane.user = {
    name = mkOption {
      # Same rule as install.sh's check_new_username.
      type = types.strMatching "[a-z_][a-z0-9_-]{0,31}";
      default = "krane";
      description = "Login account: users.users.<name>, home-manager.users.<name>, greetd autologin and nix trusted-users.";
    };
    gitName = mkOption {
      type = types.str;
      default = config.krane.user.name;
      defaultText = lib.literalExpression "config.krane.user.name";
      description = "git user.name for this host's account.";
    };
    gitEmail = mkOption {
      type = types.str;
      default = "chris@krane.dev";
      description = "git user.email for this host's account.";
    };
  };
}
```

Run: `/etc/profiles/per-user/krane/bin/git add modules/nixos/user.nix`

In `modules/nixos/default.nix`, replace `    ./users.nix` with:

```nix
    ./users.nix
    ./user.nix
```

(Adding it to the imports list only declares options, so no derivation changes.)

- [ ] **Step 4: Switch the NixOS consumers**

`modules/nixos/users.nix`: replace lines 1-2

```nix
# The one human user account.
{ pkgs, ... }:
```

with

```nix
# The one human user account, named by krane.user.name (modules/nixos/user.nix).
{ config, pkgs, ... }:
```

Replace line 8, `  users.users.krane = {`, with `  users.users.${config.krane.user.name} = {`. Replace lines 40-41:

```nix
  # No password hash is ever committed. krane's login password is set
  # once at install with `nixos-enter -- passwd krane`.
```

with

```nix
  # No password hash is ever committed. The account's login password is set
  # once at install with `nixos-enter -- passwd <krane.user.name>`.
```

`modules/nixos/desktop.nix`: replace line 25's `      # Boot straight into krane's plain (non-UWSM) Hyprland session; the session locks` with `      # Boot straight into krane.user.name's plain (non-UWSM) Hyprland session; the session locks`. Replace line 33, `        user = "krane";`, with `        user = config.krane.user.name;`. The file already takes `config`.

`modules/nixos/nix-settings.nix`: replace line 2, `{ inputs, ... }:`, with `{ config, inputs, ... }:`. Replace line 11, `      trusted-users = [ "krane" ];`, with `      trusted-users = [ config.krane.user.name ];`.

`modules/nixos/sops.nix`: replace lines 74-78

```nix
      # Owned by krane, not root: copied verbatim into krane's own rclone.conf.
      // lib.optionalAttrs (hasSection "rclone") {
        "rclone/config-seed" = {
          owner = "krane";
```

with

```nix
      # Owned by the login account (krane.user.name), not root: copied verbatim into
      # that account's own rclone.conf.
      // lib.optionalAttrs (hasSection "rclone") {
        "rclone/config-seed" = {
          owner = config.krane.user.name;
```

`modules/nixos/peripherals.nix`: replace line 34, `  # users.users.krane.extraGroups = [ "uinput" ];`, with `  # users.users.${config.krane.user.name}.extraGroups = [ "uinput" ];`. It is a comment only, kept consistent for whoever uncomments it.

- [ ] **Step 5: Switch `lib/mk-host.nix`**

Turn the home-manager block into a module function so it can read `config`. Replace line 28, `    {`, the line right after `    ../hosts/${hostName}`, with:

```nix
    (
      { config, ... }:
      {
```

Replace lines 35-38

```nix
        extraSpecialArgs = {
          inherit inputs hostName;
        };
        users.krane.imports = [
```

with

```nix
        extraSpecialArgs = {
          inherit inputs hostName;
          # modules/nixos/user.nix's krane.user, so home-manager modules read the
          # account name and git identity from the same per-host place.
          kraneUser = config.krane.user;
        };
        users.${config.krane.user.name}.imports = [
```

Replace line 111, `    }` (the one closing the block, directly above `  ]` and `  ++ extraModules;`), with:

```nix
      }
    )
```

Run `nix fmt -- lib/mk-host.nix`. Apart from nixfmt re-indenting lines 29-110 by two spaces, nothing between those anchors changes. The inner `{ config, lib, pkgs, ... }:` home-manager module shadowing the outer `config` is intended: it wants home-manager's `config`.

- [ ] **Step 6: Switch the hosts**

`hosts/tariognatha/default.nix` and `hosts/tarmantria/default.nix`: replace line 1, `{ ... }:`, with `{ config, ... }:`. Replace line 13, `  home-manager.users.krane.imports = [ ./display.nix ];`, with:

```nix
  home-manager.users.${config.krane.user.name}.imports = [ ./display.nix ];
```

`hosts/taractias/default.nix`: replace lines 4-7

```nix
{
  inputs,
  ...
}:
```

with

```nix
{
  config,
  inputs,
  ...
}:
```

and replace line 29 the same way as above.

`hosts/tariognatha/vm-overrides.nix`: replace line 5, `{ lib, ... }:`, with `{ config, lib, ... }:`. Replace line 43, `      user = "krane";`, with `      user = config.krane.user.name;`. Replace line 47, `    users.users.krane.initialPassword = "krane";`, with:

```nix
    users.users.${config.krane.user.name}.initialPassword = "krane";
```

(The password string is a throwaway VM password, not the account name, so it stays.)

- [ ] **Step 7: Switch the home-manager consumers**

`modules/home/default.nix`: replace lines 1-4

```nix
{
  config,
  ...
}:
```

with

```nix
{
  config,
  kraneUser,
  ...
}:
```

and lines 28-33

```nix
  home.username = "krane";
  # The one absolute /home path this repo constructs, derived from the username option, not
  # hardcoded. No mkForce/mkDefault needed: NixOS already sets users.users.krane.home =
  # mkDefault "/home/krane" (users.nix), which HM copies into this option, the same value, so
  # they agree.
  home.homeDirectory = "/home/${config.home.username}";
```

with

```nix
  # krane.user.name from the NixOS side (modules/nixos/user.nix), handed in by
  # lib/mk-host.nix as the kraneUser specialArg.
  home.username = kraneUser.name;
  # The one absolute /home path this repo constructs, derived from the username option, not
  # hardcoded. No mkForce/mkDefault needed: NixOS already sets users.users.<name>.home =
  # mkDefault "/home/<name>" for users.nix's normal user, which HM copies into this option,
  # the same value, so they agree.
  home.homeDirectory = "/home/${config.home.username}";
```

`modules/home/git.nix`: replace line 1, `{ pkgs, ... }:`, with `{ kraneUser, pkgs, ... }:`. Replace lines 7-9

```nix
      # programs.git.userName/.userEmail are renamed to settings.user.{name,email} on this revision.
      user.name = "krane";
      user.email = "chris@krane.dev";
```

with

```nix
      # programs.git.userName/.userEmail are renamed to settings.user.{name,email} on this revision.
      # Per host, from krane.user.gitName/gitEmail (modules/nixos/user.nix).
      user.name = kraneUser.gitName;
      user.email = kraneUser.gitEmail;
```

- [ ] **Step 8: Switch `flake.nix`'s lua-syntax lookup**

Replace lines 126-130

```nix
            renderedFiles = nixpkgs.lib.concatMap (
              host:
              nixpkgs.lib.attrValues
                self.nixosConfigurations.${host}.config.home-manager.users.krane.krane.hypr._rendered
            ) hosts;
```

with

```nix
            renderedFiles = nixpkgs.lib.concatMap (
              host:
              let
                cfg = self.nixosConfigurations.${host}.config;
              in
              nixpkgs.lib.attrValues cfg.home-manager.users.${cfg.krane.user.name}.krane.hypr._rendered
            ) hosts;
```

- [ ] **Step 9: Format and confirm nothing names the account any more**

Run: `nix fmt -- flake.nix lib/mk-host.nix modules/nixos/user.nix modules/nixos/default.nix modules/nixos/users.nix modules/nixos/desktop.nix modules/nixos/nix-settings.nix modules/nixos/sops.nix modules/nixos/peripherals.nix modules/home/default.nix modules/home/git.nix hosts/tariognatha/default.nix hosts/tarmantria/default.nix hosts/taractias/default.nix hosts/tariognatha/vm-overrides.nix`

Run: `/etc/profiles/per-user/krane/bin/git grep -nE 'users\.krane|/home/krane|"krane"' -- modules hosts lib flake.nix`
Expected: only three kinds of match remain. One is `modules/nixos/user.nix` (`default = "krane";`). One is `hosts/tariognatha/vm-overrides.nix` (`initialPassword = "krane";`, the throwaway VM password). The rest are `flake.nix` lines inside `checks.user-option` that compare against `"krane"`, which are assertions rather than consumers. Any other match is a consumer you missed.

- [ ] **Step 10: Run the check, watch it pass**

Run: `nix build --no-link .#checks.x86_64-linux.user-option`
Expected: exit 0, no `checks.user-option:` error.

- [ ] **Step 11: drvPath invariant**

Run the Task 1 Step 2 command with `> /tmp/install-new-host-after.txt`, then `diff /tmp/install-new-host-baseline.txt /tmp/install-new-host-after.txt`.
Expected: no output. On any difference, stop and find which consumer changed a value. Typical causes are a list reordered in `modules/nixos/default.nix` or a string that is not byte-identical.

- [ ] **Step 12: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add flake.nix lib/mk-host.nix modules/nixos/user.nix modules/nixos/default.nix modules/nixos/users.nix modules/nixos/desktop.nix modules/nixos/nix-settings.nix modules/nixos/sops.nix modules/nixos/peripherals.nix modules/home/default.nix modules/home/git.nix hosts/tariognatha/default.nix hosts/tarmantria/default.nix hosts/taractias/default.nix hosts/tariognatha/vm-overrides.nix
/etc/profiles/per-user/krane/bin/git commit -m "Make the login user and git identity a per-host krane.user option"
```

---

### Task 3: Discover hosts from `hosts/` in `flake.nix`

**Files:**
- Modify: `flake.nix:2` (description), `flake.nix:35-36` (nixos-hardware comment), `flake.nix:64-78` (`hosts`, `hostDirs`, `hostsSorted`), `flake.nix:124-157` (`lua-syntax` guard), `install.sh:58-59`, `scripts/bootstrap-sops.sh:16-17`, `scripts/docker-check.sh:25-26`
- Test: a temporary `hosts/probehost/` (a copy of taractias) is discovered and a non-directory `hosts/NOTAHOST` is ignored, both staged so the flake sees them; then the drvPath diff

**Interfaces:**
- Produces: `hosts` in `flake.nix` = `attrNames (filterAttrs (_: type: type == "directory") (readDir ./hosts))`, so `nixosConfigurations.<dir>` exists for every staged `hosts/<dir>/`. Task 10's `check-new-host` relies on this.
- Consumes: Task 2's lua-syntax `renderedFiles`.

- [ ] **Step 1: Write the failing probe**

```bash
cp -r hosts/taractias hosts/probehost
printf 'not a host\n' > hosts/NOTAHOST
/etc/profiles/per-user/krane/bin/git add hosts/probehost hosts/NOTAHOST
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nix path-info --derivation .#nixosConfigurations.probehost.config.system.build.toplevel`
Expected: FAIL, `attribute 'probehost' missing` (the hand-written list does not include it).

Run: `nix path-info --derivation .#checks.x86_64-linux.lua-syntax`
Expected: FAIL with `checks.lua-syntax: flake.nix's `hosts` list [...] does not match hosts/ directory contents [...]`.

- [ ] **Step 3: Replace the host list**

Replace `flake.nix` lines 64-78

```nix
      # Single source of truth for this flake's host list, checked
      # against hosts/ by checks.lua-syntax below.
      hosts = [
        "tariognatha"
        "tarmantria"
        "taractias"
      ];

      # Sorted the same way as `hosts` for comparison below.
      hostDirs = nixpkgs.lib.sort (a: b: a < b) (
        nixpkgs.lib.attrNames (
          nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
        )
      );
      hostsSorted = nixpkgs.lib.sort (a: b: a < b) hosts;
```

with

```nix
      # Every directory under hosts/ is a host. install.sh's new-host flow adds one by
      # scaffolding hosts/<name>/ from templates/host/. install.sh, bootstrap-sops.sh's
      # known_hosts() and docker-check.sh's HOSTS glob the same directories. Plain files
      # under hosts/ are ignored.
      hosts = nixpkgs.lib.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );
```

Replace the whole `lua-syntax = … ;` binding (lines 124-157, from `        lua-syntax =` through the `            );` directly above the blank line before `# NixVim's own startup test`) with:

```nix
        lua-syntax =
          let
            renderedFiles = nixpkgs.lib.concatMap (
              host:
              let
                cfg = self.nixosConfigurations.${host}.config;
              in
              nixpkgs.lib.attrValues cfg.home-manager.users.${cfg.krane.user.name}.krane.hypr._rendered
            ) hosts;
          in
          # Refuse an empty `_rendered` list here, at eval time, and
          # again in the builder, so this check can't pass vacuously.
          nixpkgs.lib.throwIf (renderedFiles == [ ])
            "checks.lua-syntax: krane.hypr._rendered is empty for all hosts; the check would pass vacuously"
            (
              pkgs.runCommand "krane-hypr-lua-syntax" { } ''
                count=0
                for f in ${nixpkgs.lib.escapeShellArgs renderedFiles}; do
                  echo "luac -p $f"
                  ${pkgs.lua5_4}/bin/luac -p "$f"
                  count=$((count + 1))
                done
                if [ "$count" -eq 0 ]; then
                  echo "no rendered Lua files were checked" >&2
                  exit 1
                fi
                echo "checked $count rendered Lua files"
                touch "$out"
              ''
            );
```

(The `checks.lua-syntax` drvPath changes, because `readDir` order is alphabetical and the hand list was not. That check is not part of the invariant. The `nixosConfigurations` are.)

Replace line 2, `  description = "NixOS + Hyprland (illogical-impulse) dotfiles flake for tariognatha, tarmantria and taractias";`, with:

```nix
  description = "NixOS + Hyprland (illogical-impulse) dotfiles flake, one nixosConfiguration per hosts/ directory";
```

Replace lines 35-36

```nix
    # No `nixpkgs.follows`: nixos-hardware's modules aren't pinned to a
    # nixpkgs revision. Applied only to taractias.
```

with

```nix
    # No `nixpkgs.follows`: nixos-hardware's modules aren't pinned to a
    # nixpkgs revision. Imported by taractias and by hosts scaffolded from
    # templates/host/ (GPU profile and form-factor imports).
```

- [ ] **Step 4: Update the "mirrors" comments**

`install.sh` lines 58-59:

```bash
# hosts/ is the single source of truth here, same as flake.nix's hosts,
# known_hosts() and docker-check.sh's HOSTS.
```

becomes

```bash
# hosts/ is the single source of truth: flake.nix discovers its hosts from
# the same directories, as do bootstrap-sops.sh's known_hosts() and
# docker-check.sh's HOSTS.
```

`scripts/bootstrap-sops.sh` lines 16-17:

```bash
# hosts/ is the single source of truth here, same as flake.nix's hosts
# list and docker-check.sh's HOSTS.
```

becomes

```bash
# hosts/ is the single source of truth: flake.nix discovers its hosts from
# the same directories, as do install.sh and docker-check.sh's HOSTS.
```

`scripts/docker-check.sh` lines 25-26:

```bash
# hosts/ is the single source of truth here, same as flake.nix's hosts
# and bootstrap-sops.sh's known_hosts().
```

becomes

```bash
# hosts/ is the single source of truth: flake.nix discovers its hosts from
# the same directories, as do install.sh and bootstrap-sops.sh's known_hosts().
```

- [ ] **Step 5: Run the probe, watch it pass**

Run: `nix fmt -- flake.nix`
Run: `nix path-info --derivation .#nixosConfigurations.probehost.config.system.build.toplevel`
Expected: PASS, prints `/nix/store/…-nixos-system-probehost-….drv`.

Run: `nix path-info --derivation .#nixosConfigurations.NOTAHOST.config.system.build.toplevel`
Expected: FAIL, `attribute 'NOTAHOST' missing`. The plain file is ignored.

Run: `nix path-info --derivation .#checks.x86_64-linux.lua-syntax`
Expected: PASS, prints a `…-krane-hypr-lua-syntax.drv` path.

- [ ] **Step 6: Remove the probe and check the invariant**

```bash
/etc/profiles/per-user/krane/bin/git rm -r -q --cached hosts/probehost hosts/NOTAHOST
rm -rf hosts/probehost hosts/NOTAHOST
```

Run: `/etc/profiles/per-user/krane/bin/git status --porcelain`
Expected: only `M flake.nix`, `M install.sh`, `M scripts/bootstrap-sops.sh` and `M scripts/docker-check.sh`.

Run the Task 1 Step 2 command with `> /tmp/install-new-host-after.txt`, then `diff /tmp/install-new-host-baseline.txt /tmp/install-new-host-after.txt`.
Expected: no output.

- [ ] **Step 7: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add flake.nix install.sh scripts/bootstrap-sops.sh scripts/docker-check.sh
/etc/profiles/per-user/krane/bin/git commit -m "Discover flake hosts from the hosts directory"
```

---

### Task 4: Host templates and `install.sh`'s renderer

**Files:**
- Create: `templates/host/default.nix.in`, `templates/host/disko.nix.in`, `templates/host/display.nix.in`, `templates/host/hardware-configuration.nix.in`, `templates/host/profiles/amd-igpu.nix.in`, `templates/host/profiles/intel-igpu.nix.in`, `templates/host/profiles/nvidia-desktop.nix.in`, `templates/host/profiles/intel-nvidia-prime.nix.in`, `templates/host/form-factors/laptop.nix.in`, `templates/host/form-factors/desktop.nix.in`
- Modify: `install.sh:58-64` (constants after `AVAILABLE_HOSTS`), `install.sh:76` (global), `install.sh:409-412` (arg case), `install.sh:569` (new functions after `choose_host`), `install.sh:1337` (hook after the prime-sed hook), `install.sh:1415` (self_test entry after the prime-sed entry), `modules/nixos/gpu/nvidia-desktop.nix:1-2`, `modules/nixos/gpu/nvidia-prime.nix:1-2` (comments)
- Test: `bash install.sh --self-test-check-scaffold`, `bash install.sh --self-test`

**Interfaces:**
- Produces (install.sh globals): `TEMPLATE_DIR`, `GPU_PROFILES=(amd-igpu intel-igpu nvidia-desktop intel-nvidia-prime)`, `FORM_FACTORS=(laptop desktop)`, `DEFAULT_INSTALL_USER=krane`, `DEFAULT_GIT_EMAIL=chris@krane.dev`, `DEFAULT_KB_LAYOUT=at`, `DEFAULT_KB_VARIANT=nodeadkeys`, `SELF_TEST_CHECK_SCAFFOLD`.
- Produces (install.sh functions):
  - `render_host_templates <dest> <host> <user> <git_name> <git_email> <profile> <form_factor> <kb_layout> <kb_variant>` writes `default.nix`, `disko.nix`, `display.nix` and `hardware-configuration.nix` into `<dest>` and dies on an unknown profile or form factor, or on a leftover token.
  - `parse_check_nix_dir <dir>` runs `nix-instantiate --parse` on every `<dir>/*.nix` and dies naming the file.
  - `template_section <file> <name>` prints a `#== <name>` section.
  - `replace_block_token <file> <TOKEN> <text>` replaces lines that are exactly `@TOKEN@`.
  - `nix_string_escape <value>` and `sed_replacement_escape <value>`.
- Produces (flag): `--self-test-check-scaffold` (hidden), which prints `self-test-check-scaffold: OK` on success. Task 5 extends it.
- Template tokens: scalars `@HOST@ @USERNAME@ @GIT_NAME@ @GIT_EMAIL@ @PROFILE_NAME@ @FORM_FACTOR@ @KB_LAYOUT@ @KB_VARIANT@`; blocks (alone on a line) `@PROFILE_IMPORTS@ @FORM_FACTOR_IMPORTS@ @PROFILE@ @TOUCHPAD@`.

- [ ] **Step 1: Write the failing self-test hook**

`install.sh`, after line 76 `SELF_TEST_CHECK_PRIME_SED=false`, add:

```bash
SELF_TEST_CHECK_SCAFFOLD=false
```

In the arg `case`, after the `--self-test-check-prime-sed)` arm (lines 409-412), add:

```bash
        --self-test-check-scaffold)
            SELF_TEST_CHECK_SCAFFOLD=true
            shift
            ;;
```

After the `if $SELF_TEST_CHECK_PRIME_SED; then … fi` hook (ends line 1337), add:

```bash
# Renders every GPU profile x form factor from templates/host/ into a
# throwaway dir with the real (non-dry-run) helpers and parse-checks each
# result, the same checks scaffold_host runs before it writes hosts/<name>/.
if $SELF_TEST_CHECK_SCAFFOLD; then
    self_test_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest.XXXXXX")
    trap 'rc=$?; rm -rf "$self_test_tmpdir"; (exit $rc); on_exit' EXIT
    DRY_RUN=false
    command -v nix-instantiate >/dev/null 2>&1 || die "nix-instantiate not found, cannot parse-check the templates"
    for st_profile in "${GPU_PROFILES[@]}"; do
        for st_ff in "${FORM_FACTORS[@]}"; do
            st_dir="$self_test_tmpdir/$st_profile-$st_ff"
            render_host_templates "$st_dir" testhost tester "Test Er" tester@example.invalid \
                "$st_profile" "$st_ff" at nodeadkeys
            parse_check_nix_dir "$st_dir"
            for st_file in default.nix disko.nix display.nix hardware-configuration.nix; do
                [ -f "$st_dir/$st_file" ] || die "$st_profile/$st_ff: $st_file was not rendered"
            done
            grep -qF 'name = "tester";' "$st_dir/default.nix" \
                || die "$st_profile/$st_ff: default.nix has no krane.user name line"
            grep -qF 'system.stateVersion = "26.05";' "$st_dir/default.nix" \
                || die "$st_profile/$st_ff: default.nix has no stateVersion 26.05"
            grep -qF 'device = "/dev/CHANGE-ME";' "$st_dir/disko.nix" \
                || die "$st_profile/$st_ff: disko.nix lost the CHANGE-ME placeholder patch_disko needs"
            grep -qF 'kb_layout = "at";' "$st_dir/display.nix" \
                || die "$st_profile/$st_ff: display.nix has no kb_layout line"
            if [ "$st_ff" = laptop ]; then
                grep -qF 'tap_to_click = true;' "$st_dir/display.nix" \
                    || die "$st_profile/$st_ff: laptop display.nix has no touchpad block"
            else
                ! grep -qF 'touchpad' "$st_dir/display.nix" \
                    || die "$st_profile/$st_ff: desktop display.nix has a touchpad block"
            fi
            # host_uses_cuda keys on this import.
            if [ "$st_profile" = nvidia-desktop ]; then
                grep -q 'gpu/nvidia-desktop' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: default.nix does not import gpu/nvidia-desktop.nix"
            else
                ! grep -q 'gpu/nvidia-desktop' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: default.nix imports gpu/nvidia-desktop.nix"
            fi
            # patch_prime keys on these two lines, with its own regex.
            if [ "$st_profile" = intel-nvidia-prime ]; then
                grep -qE '^[[:space:]]*krane\.prime\.intelBusId[[:space:]]*=[[:space:]]*"' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: no intelBusId line in the form patch_prime expects"
                grep -qE '^[[:space:]]*krane\.prime\.nvidiaBusId[[:space:]]*=[[:space:]]*"' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: no nvidiaBusId line in the form patch_prime expects"
                patch_prime_line "$st_dir/default.nix" intelBusId PCI:9:9:9
                patch_prime_line "$st_dir/default.nix" nvidiaBusId PCI:8:8:8
                parse_check_nix_dir "$st_dir"
            else
                ! grep -qE '^[[:space:]]*krane\.prime\.' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: non-PRIME profile has krane.prime lines"
            fi
        done
    done
    # sed's / & \ and Nix's " \ ${ must land as the same string, not break
    # the sed expression or the Nix string.
    st_dir="$self_test_tmpdir/escaping"
    # shellcheck disable=SC2016 # the literal ${x} is the point of this value.
    render_host_templates "$st_dir" testhost tester 'A/B & C\D "q" ${x}' 'a&b/c\d@example.invalid' \
        amd-igpu laptop at nodeadkeys
    parse_check_nix_dir "$st_dir"
    # shellcheck disable=SC2016 # matches the escaped Nix text literally.
    grep -qF 'gitName = "A/B & C\\D \"q\" \${x}";' "$st_dir/default.nix" \
        || die "git name with / & \\ \" \${ was not escaped for Nix and sed"
    grep -qF 'gitEmail = "a&b/c\\d@example.invalid";' "$st_dir/default.nix" \
        || die "git email with & / \\ was not escaped for Nix and sed"
    echo "self-test-check-scaffold: OK"
    exit 0
fi
```

In `self_test()`, after the `patch_prime_line sed` block (ends line 1415), add:

```bash
    echo "== self-test: new-host templates render and parse (real, non-dry-run) ==" >&2
    local out7 rc7=0
    out7=$(bash "$0" --self-test-check-scaffold 2>&1) || rc7=$?
    if [ "$rc7" -eq 0 ] && printf '%s' "$out7" | grep -q "self-test-check-scaffold: OK"; then
        echo "OK: every GPU profile x form factor renders, parses and keeps its install.sh hooks" >&2
    else
        echo "FAIL: new-host template check failed (rc=$rc7)" >&2
        echo "  captured output: $out7" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash install.sh --self-test-check-scaffold; echo rc=$?`
Expected: FAIL, `rc=1` with an error box. Because `set -u` is on, the first failure is `GPU_PROFILES[@]: unbound variable`, or `render_host_templates: command not found` if the arrays already exist.

- [ ] **Step 3: Add the constants**

After the `AVAILABLE_HOSTS` loop (`unset _d`, line 64), add:

```bash

# templates/host/ is what the new-host flow renders hosts/<name>/ from.
# Profile and form-factor names are the file names under its profiles/ and
# form-factors/ (and scripts/check-new-host.sh mirrors both lists).
TEMPLATE_DIR="$REPO_ROOT/templates/host"
GPU_PROFILES=(amd-igpu intel-igpu nvidia-desktop intel-nvidia-prime)
FORM_FACTORS=(laptop desktop)
# Defaults for a new host's answers, the values the original hosts use.
DEFAULT_INSTALL_USER=krane
DEFAULT_GIT_EMAIL=chris@krane.dev
DEFAULT_KB_LAYOUT=at
DEFAULT_KB_VARIANT=nodeadkeys
```

- [ ] **Step 4: Add the render helpers**

After `choose_host()` (ends line 569), add:

```bash

# Escapes $1 for a Nix double-quoted string: \ first, then " and ${, so
# any git name or email renders as the same string it was typed as.
nix_string_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//\$\{/\\\$\{}
    printf '%s' "$s"
}

# Escapes $1 for the replacement side of a sed s/// using / as delimiter:
# / ends the expression, & inserts the match and \ escapes, so all three
# get a backslash.
sed_replacement_escape() {
    printf '%s' "$1" | sed -e 's/[\/&\\]/\\&/g'
}

# Prints section $2 of template $1: the lines after a "#== $2" header up to
# the next "#== " header. Lines before the first header are the file's own
# comment and never printed. A missing section prints nothing.
template_section() {
    awk -v want="$2" '/^#== / { cur = $2; next } cur == want' "$1"
}

# Replaces every line of $1 that is exactly @$2@ (surrounding blanks
# ignored) with $3, in place. An empty $3 drops the line. $3 reaches awk
# through ENVIRON, not -v, so awk never rewrites its backslashes.
replace_block_token() {
    local file="$1" token="@$2@" tmp
    tmp=$(mktemp "$file.XXXXXX")
    BLOCK="$3" awk -v tok="$token" '
        { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t) }
        t == tok { if (ENVIRON["BLOCK"] != "") print ENVIRON["BLOCK"]; next }
        { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
}

# Renders templates/host/ into $1 for host $2: the profile's and form
# factor's #== sections first, then every scalar @TOKEN@ through sed with
# its value Nix- and sed-escaped. Writes only under $1, which callers point
# at a temp dir, so this runs for real under --dry-run too.
render_host_templates() {
    local dest="$1" host="$2" user="$3" git_name="$4" git_email="$5"
    local profile="$6" form_factor="$7" kb_layout="$8" kb_variant="$9"
    local profile_file="$TEMPLATE_DIR/profiles/$profile.nix.in"
    local ff_file="$TEMPLATE_DIR/form-factors/$form_factor.nix.in"
    [ -f "$profile_file" ] || die "unknown GPU profile '$profile', expected one of: ${GPU_PROFILES[*]}"
    [ -f "$ff_file" ] || die "unknown form factor '$form_factor', expected one of: ${FORM_FACTORS[*]}"
    mkdir -p "$dest"
    local name
    for name in default.nix disko.nix display.nix hardware-configuration.nix; do
        cp "$TEMPLATE_DIR/$name.in" "$dest/$name"
    done
    replace_block_token "$dest/default.nix" PROFILE_IMPORTS "$(template_section "$profile_file" imports)"
    replace_block_token "$dest/default.nix" FORM_FACTOR_IMPORTS "$(template_section "$ff_file" imports)"
    replace_block_token "$dest/default.nix" PROFILE "$(template_section "$profile_file" body)"
    replace_block_token "$dest/display.nix" TOUCHPAD "$(template_section "$ff_file" touchpad)"
    # GIT_NAME and GIT_EMAIL go last so a value can never feed a later token.
    local sed_args=() pair key value
    for pair in "HOST=$host" "USERNAME=$user" "PROFILE_NAME=$profile" "FORM_FACTOR=$form_factor" \
        "KB_LAYOUT=$kb_layout" "KB_VARIANT=$kb_variant" "GIT_NAME=$git_name" "GIT_EMAIL=$git_email"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        sed_args+=(-e "s/@${key}@/$(sed_replacement_escape "$(nix_string_escape "$value")")/g")
    done
    for name in default.nix disko.nix display.nix hardware-configuration.nix; do
        sed -i "${sed_args[@]}" "$dest/$name"
    done
    if grep -nE '@(HOST|USERNAME|GIT_NAME|GIT_EMAIL|PROFILE_NAME|FORM_FACTOR|KB_LAYOUT|KB_VARIANT|PROFILE_IMPORTS|FORM_FACTOR_IMPORTS|PROFILE|TOUCHPAD)@' "$dest"/*.nix >&2; then
        die "unrendered @TOKEN@ left in $dest, see the lines above"
    fi
}

# nix-instantiate --parse catches a template or substitution mistake before
# anything lands in hosts/ or the disk is touched.
parse_check_nix_dir() {
    local file
    for file in "$1"/*.nix; do
        nix-instantiate --parse "$file" >/dev/null \
            || die "rendered $(basename "$file") does not parse as Nix, see the error above"
    done
}
```

- [ ] **Step 5: Create the templates**

`templates/host/default.nix.in`:

```nix
# @HOST@: scaffolded by install.sh from templates/host/ (GPU profile @PROFILE_NAME@,
# form factor @FORM_FACTOR@). From here on it is an ordinary host config: edit it freely.
{ config, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
@PROFILE_IMPORTS@
@FORM_FACTOR_IMPORTS@
  ];
@PROFILE@

  # The login account and its git identity (modules/nixos/user.nix).
  krane.user = {
    name = "@USERNAME@";
    gitName = "@GIT_NAME@";
    gitEmail = "@GIT_EMAIL@";
  };

  system.stateVersion = "26.05";

  # display.nix sets krane.hypr.*, a home-manager module, imported at the user level.
  home-manager.users.${config.krane.user.name}.imports = [ ./display.nix ];
}
```

`templates/host/disko.nix.in`:

```nix
# disko disk layout for @HOST@ (@FORM_FACTOR@): GPT + ESP + btrfs with subvolumes,
# zstd-compressed, the same layout as the other hosts. See docs/INSTALL.md.
{ ... }:
{
  disko.devices.disk.main = {
    # CHANGE-ME: install.sh's patch_disko fills in the disk picked at install time, preferring
    # a /dev/disk/by-id/ path so it survives disk reordering.
    device = "/dev/CHANGE-ME";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          priority = 1;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
              "@snapshots" = {
                mountpoint = "/.snapshots";
                mountOptions = [
                  "compress=zstd:1"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
```

Note that the subvolume names `"@"`, `"@home"`, … contain `@` but never match `@[A-Z_]+@`, so the leftover-token check ignores them.

`templates/host/display.nix.in`:

```nix
# home-manager module: display / input layout for @HOST@, imported at the user level from
# hosts/@HOST@/default.nix, rendered to Lua by modules/home/hypr-config.nix. Scaffolded with
# one catch-all monitor rule because the live ISO runs no Hyprland to detect outputs: after
# first login, check `hyprctl monitors -j` and name the real outputs here (see
# hosts/tariognatha/display.nix for a multi-monitor layout).
{ ... }:
{
  krane.hypr = {
    monitors = [
      # Empty output: the rule applies to every monitor, at its preferred mode.
      {
        output = "";
        mode = "preferred";
        position = "auto";
        scale = 1;
      }
    ];

    settings.input = {
      kb_layout = "@KB_LAYOUT@";
      kb_variant = "@KB_VARIANT@";
@TOUCHPAD@
    };

    # Same as the other hosts. See hosts/tariognatha/display.nix for why.
    variables = {
      terminal = "kitty";
      browser = "zen-beta";
      codeEditor = "kitty -1 nvim";
      textEditor = "kitty -1 nvim";
      fileManager = "dolphin";
    };
  };
}
```

`templates/host/hardware-configuration.nix.in`:

```nix
# Placeholder written by install.sh's scaffold_host so hosts/@HOST@ evaluates (run_disko
# builds the disko script from it) before generate_hardware_config replaces this file with
# `nixos-generate-config --no-filesystems` output. Never boot a system built from this one.
{ ... }:
{ }
```

`templates/host/profiles/amd-igpu.nix.in`:

```nix
# GPU profile amd-igpu: AMD CPU with an integrated Radeon GPU and no dGPU, taractias's setup.
# install.sh's render_host_templates splices "imports" into default.nix's imports list and
# "body" after it. Each section keeps its own leading blank line.
#== imports

    # Sets hardware.cpu.amd.updateMicrocode = mkDefault enableRedistributableFirmware, already true.
    inputs.nixos-hardware.nixosModules.common-cpu-amd

    # Sets videoDrivers/hardware.graphics/amdgpu.initrd as mkDefault, matched below, no conflict.
    inputs.nixos-hardware.nixosModules.common-gpu-amd
#== body

  # Explicit rather than left to common-gpu-amd's mkDefault, so this reads correctly standalone.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # VA-API decode goes through Mesa's radeonsi, not the NVIDIA hosts' shim.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  # modules/nixos/hardware.nix sets hardware.cpu.intel.updateMicrocode = mkDefault true. This
  # host is AMD, so plain `false` overrides it. AMD microcode uses common-cpu-amd's mkDefault.
  hardware.cpu.intel.updateMicrocode = false;
```

`templates/host/profiles/intel-igpu.nix.in`:

```nix
# GPU profile intel-igpu: Intel CPU with its integrated GPU and no dGPU.
# install.sh's render_host_templates splices "imports" into default.nix's imports list and
# "body" after it. Each section keeps its own leading blank line.
#== imports

    # Intel microcode plus nixos-hardware's Intel GPU module, which installs intel-media-driver.
    inputs.nixos-hardware.nixosModules.common-cpu-intel
#== body

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # VA-API decode through intel-media-driver (iHD), installed by common-cpu-intel above.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
```

`templates/host/profiles/nvidia-desktop.nix.in`:

```nix
# GPU profile nvidia-desktop: a single NVIDIA GPU, no PRIME, tariognatha's setup. Everything
# lives in modules/nixos/gpu/nvidia-desktop.nix, so there is no body. install.sh's
# host_uses_cuda greps default.nix for this import to grant the CUDA cache.
#== imports
    ../../modules/nixos/gpu/nvidia-desktop.nix
#== body
```

`templates/host/profiles/intel-nvidia-prime.nix.in`:

```nix
# GPU profile intel-nvidia-prime: Intel iGPU plus NVIDIA dGPU with PRIME offload, tarmantria's
# setup. The two krane.prime lines must keep the `krane.prime.<key> = "…";` form that
# install.sh's patch_prime detects and patch_prime_line rewrites.
#== imports
    ../../modules/nixos/gpu/nvidia-prime.nix
#== body

  # PCI bus IDs, patched by install.sh's patch_prime from `lspci -D` at install time. If the
  # install could not detect them, fill them in from `lspci | grep -E 'VGA|3D'` by hand.
  krane.prime.intelBusId = "PCI:0:2:0"; # FILL AT INSTALL
  krane.prime.nvidiaBusId = "PCI:1:0:0"; # FILL AT INSTALL
```

`templates/host/form-factors/laptop.nix.in`:

```nix
# Form factor laptop: nixos-hardware's laptop and SSD profiles, plus a touchpad block in
# display.nix. install.sh's render_host_templates splices "imports" into default.nix and
# "touchpad" into display.nix's settings.input.
#== imports

    # Sets services.tlp.enable = mkDefault (!power-profiles-daemon.enable), so tlp stays disabled.
    inputs.nixos-hardware.nixosModules.common-pc-laptop

    # Same as common-pc-ssd (fstrim only), redundant with boot.nix's services.fstrim.enable = true.
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
#== touchpad
      touchpad = {
        natural_scroll = true;
        tap_to_click = true;
      };
```

`templates/host/form-factors/desktop.nix.in`:

```nix
# Form factor desktop: nixos-hardware's SSD profile, no touchpad block.
# install.sh's render_host_templates splices "imports" into default.nix.
#== imports

    # fstrim only, redundant with boot.nix's services.fstrim.enable = true.
    inputs.nixos-hardware.nixosModules.common-pc-ssd
#== touchpad
```

Run: `/etc/profiles/per-user/krane/bin/git add templates/host`

- [ ] **Step 6: Point the GPU modules' headers at the profiles**

`modules/nixos/gpu/nvidia-desktop.nix` lines 1-2:

```nix
# tariognatha, the desktop: single NVIDIA GPU, RTX 4070 Ti class, no
# PRIME offload. Imported only by hosts/tariognatha/default.nix.
```

become

```nix
# tariognatha, the desktop: single NVIDIA GPU, RTX 4070 Ti class, no
# PRIME offload. Imported by hosts/tariognatha/default.nix and by hosts
# scaffolded with templates/host/profiles/nvidia-desktop.nix.in.
```

`modules/nixos/gpu/nvidia-prime.nix` lines 1-2:

```nix
# tarmantria, the laptop: Intel iGPU and NVIDIA dGPU, PRIME offload.
# Imported only by hosts/tarmantria/default.nix.
```

become

```nix
# tarmantria, the laptop: Intel iGPU and NVIDIA dGPU, PRIME offload.
# Imported by hosts/tarmantria/default.nix and by hosts scaffolded with
# templates/host/profiles/intel-nvidia-prime.nix.in.
```

- [ ] **Step 7: Run the hook and the full self-test, watch them pass**

Run: `bash install.sh --self-test-check-scaffold; echo rc=$?`
Expected: PASS. The last lines are `self-test-check-scaffold: OK` and `rc=0`. You will see `log_info` lines from `patch_prime_line`.

Run: `bash install.sh --self-test; echo rc=$?`
Expected: PASS, `self-test: all checks passed`, `rc=0`, including `OK: every GPU profile x form factor renders, parses and keeps its install.sh hooks`.

Run: `shellcheck -x -S style install.sh`
Expected: no output.

- [ ] **Step 8: Check the invariant**

Only comments changed in Nix files. Run the Task 1 Step 2 command with `> /tmp/install-new-host-after.txt` and diff it against the baseline.
Expected: no output.

- [ ] **Step 9: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add install.sh templates/host modules/nixos/gpu/nvidia-desktop.nix modules/nixos/gpu/nvidia-prime.nix
/etc/profiles/per-user/krane/bin/git commit -m "Add new-host templates and install.sh's renderer with a scaffold self-test"
```

---

### Task 5: Register a new host's sops placeholders

**Files:**
- Modify: `install.sh:1009` (new function after `sops_placeholder_present`), the `--self-test-check-scaffold` hook from Task 4 (insert before its `echo "self-test-check-scaffold: OK"`)
- Test: `bash install.sh --self-test-check-scaffold`

**Interfaces:**
- Produces: `register_sops_host <sops_yaml> <host>`. It inserts `  - &admin_<host> age1PLACEHOLDER_ADMIN_<HOST>_REPLACE_VIA_BOOTSTRAP_SOPS_SH` and `  - &host_<host> age1PLACEHOLDER_HOST_<HOST>_REPLACE_VIA_BOOTSTRAP_SOPS_SH` after the last `keys:` entry, before the blank lines that precede `creation_rules:`. It then appends a `creation_rules` block (`path_regex: secrets/<host>\.yaml$`, `*admin_<host>`, `*host_<host>`). If `&admin_<host>` or `&host_<host>` already exists as a whole anchor, it makes no change and returns 0. It dies when the file is missing or has no top-level `creation_rules:`. It overwrites the file in place, keeping its mode.
- Consumes: `sops_placeholder_present` (unchanged).

- [ ] **Step 1: Write the failing sops checks**

In the `--self-test-check-scaffold` hook, directly before `    echo "self-test-check-scaffold: OK"`, insert:

```bash
    # .sops.yaml: the new anchors land as the last keys: entries, a second
    # run is a no-op, and a host whose name prefixes an existing one (tar vs
    # taractias) is still added.
    st_sops="$self_test_tmpdir/sops.yaml"
    cp "$REPO_ROOT/.sops.yaml" "$st_sops"
    register_sops_host "$st_sops" testhost
    sops_placeholder_present "$st_sops" testhost \
        || die "sops_placeholder_present missed testhost's new placeholders"
    ! sops_placeholder_present "$st_sops" taractias \
        || die "registering testhost made taractias read as not bootstrapped"
    [ "$(grep -c '&admin_testhost ' "$st_sops")" = 1 ] || die "&admin_testhost is not in .sops.yaml exactly once"
    st_rules_line=$(grep -n '^creation_rules:' "$st_sops" | cut -d: -f1)
    st_key_line=$(grep -n '&host_testhost ' "$st_sops" | cut -d: -f1)
    [ "$st_key_line" -lt "$st_rules_line" ] || die "&host_testhost landed after creation_rules:"
    grep -qF 'path_regex: secrets/testhost\.yaml$' "$st_sops" || die "no creation rule for secrets/testhost.yaml"
    if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q mikefarah; then
        [ "$(yq 'explode(.) | .creation_rules[-1].key_groups[0].age[1]' "$st_sops")" = age1PLACEHOLDER_HOST_TESTHOST_REPLACE_VIA_BOOTSTRAP_SOPS_SH ] \
            || die "yq does not resolve testhost's creation rule to its host placeholder"
    else
        log_warn "mikefarah yq not found, skipping the YAML structure check"
    fi
    cp "$st_sops" "$st_sops.once"
    register_sops_host "$st_sops" testhost
    cmp -s "$st_sops" "$st_sops.once" || die "a second register_sops_host testhost changed .sops.yaml"
    register_sops_host "$st_sops" tar
    grep -qF '&admin_tar age1PLACEHOLDER_ADMIN_TAR_REPLACE_VIA_BOOTSTRAP_SOPS_SH' "$st_sops" \
        || die "host 'tar' was treated as already registered because of &admin_taractias"
    register_sops_host "$st_sops" my-box
    sops_placeholder_present "$st_sops" my-box \
        || die "sops_placeholder_present missed a dashed host's placeholders"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash install.sh --self-test-check-scaffold; echo rc=$?`
Expected: FAIL, `rc=1`, with the error box `command failed (exit 127): register_sops_host …` (`register_sops_host: command not found`).

- [ ] **Step 3: Implement `register_sops_host`**

After `sops_placeholder_present()` (ends line 1009), add:

```bash

# Adds host $2's two age1PLACEHOLDER_* recipients to the sops config $1 as
# the last `keys:` entries and appends a creation rule for secrets/$2.yaml:
# the same shape the committed hosts had before scripts/bootstrap-sops.sh
# replaced their placeholders, so setup mode's run_bootstrap_sops and
# sops_placeholder_present work unchanged. No secrets/$2.yaml is created:
# modules/nixos/sops.nix's pathExists gate handles its absence. A no-op when
# either anchor already exists, matched whole so `tar` never hits
# `&admin_taractias`.
register_sops_host() {
    local sops_yaml="$1" host="$2" host_upper tmp
    [ -f "$sops_yaml" ] || die "$sops_yaml not found, cannot register sops placeholders for $host"
    if grep -qE "&(admin|host)_${host}([[:space:]]|\$)" "$sops_yaml"; then
        log_info "$sops_yaml already has anchors for $host, leaving it as is"
        return 0
    fi
    grep -q '^creation_rules:' "$sops_yaml" \
        || die "$sops_yaml has no top-level creation_rules:, cannot place $host's recipients"
    host_upper=$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')
    tmp=$(mktemp "${TMPDIR:-/tmp}/krane-install-sops.XXXXXX")
    # Blank lines are held back until the next non-blank line, so the new keys
    # go right after the last keys: entry and the gap stays before
    # creation_rules:.
    awk -v host="$host" -v upper="$host_upper" '
        /^creation_rules:/ && !done {
            printf "  - &admin_%s age1PLACEHOLDER_ADMIN_%s_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n", host, upper
            printf "  - &host_%s age1PLACEHOLDER_HOST_%s_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n", host, upper
            printf "%s", gap
            gap = ""
            done = 1
            print
            next
        }
        /^[[:space:]]*$/ && !done { gap = gap $0 "\n"; next }
        { printf "%s", gap; gap = ""; print }
        END {
            printf "%s", gap
            printf "\n  - path_regex: secrets/%s\\.yaml$\n", host
            printf "    key_groups:\n      - age:\n          - *admin_%s\n          - *host_%s\n", host, host
        }
    ' "$sops_yaml" >"$tmp"
    grep -qF "&host_${host} age1PLACEHOLDER_HOST_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH" "$tmp" \
        || die "post-awk verification failed for $host in $sops_yaml"
    # cat into the original, not mv, so the file keeps its mode and owner.
    cat "$tmp" >"$sops_yaml"
    rm -f "$tmp"
}
```

- [ ] **Step 4: Run it, watch it pass**

Run: `bash install.sh --self-test-check-scaffold; echo rc=$?`
Expected: PASS, `self-test-check-scaffold: OK`, `rc=0`. The second `register_sops_host testhost` logs `…already has anchors for testhost, leaving it as is`.

Run: `bash install.sh --self-test; echo rc=$?` and `shellcheck -x -S style install.sh`
Expected: `self-test: all checks passed`, `rc=0`; shellcheck prints nothing.

- [ ] **Step 5: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add install.sh
/etc/profiles/per-user/krane/bin/git commit -m "Register a new host's sops placeholders in .sops.yaml"
```

---

### Task 6: New-host validators, profile detection and flags

**Files:**
- Modify: `install.sh:88` (globals), `install.sh:321-339` (`usage`), `install.sh:355-421` (arg parsing), `install.sh:569` (new functions after Task 4's block), `install.sh:1263-1283` (`main`), `self_test()` (insert before the final `if [ "$SELF_TEST_FAILURES" -eq 0 ]`, line 1558), plus a new helper `self_test_validator` right above `self_test()` (line 1339)
- Test: `bash install.sh --self-test`

**Interfaces:**
- Produces (globals): `NEW_HOST_MODE` (bool), `NEW_HOST`, `NEW_USER`, `NEW_GIT_NAME`, `NEW_GIT_EMAIL`, `NEW_PROFILE`, `NEW_FORM_FACTOR`, `NEW_KB_LAYOUT`, `NEW_KB_VARIANT`, `NEW_KB_VARIANT_SET` (bool), `SYSTEM_ACCOUNT_NAMES`.
- Produces (flags): `--new-host NAME`, `--user NAME`, `--git-name NAME`, `--git-email EMAIL`, `--profile PROFILE`, `--form-factor FF`, `--kb-layout LAYOUT` and `--kb-variant VARIANT`, each also in `--flag=value` form.
- Produces (functions): each validator prints the reason on stdout and returns 1 when the value is invalid, and returns 0 silently when it is valid. They are `check_new_hostname <name>`, `check_new_username <name>`, `check_git_name <v>`, `check_git_email <v>`, `check_kb_layout <v>`, `check_kb_variant <v>`, `check_profile <v>` and `check_form_factor <v>`. Also:
  - `suggest_profile` prints `<gpu-profile> <form-factor>` separated by exactly one space, with either field possibly empty.
  - `validate_new_host_flags` calls `usage_die` on any rule violation.
  - `self_test_validator valid|invalid <validator> <value>...`.
- Consumes: `AVAILABLE_HOSTS`, `GPU_PROFILES`, `FORM_FACTORS`, `DEFAULT_*` (Task 4).

- [ ] **Step 1: Write the failing self-tests**

Above `self_test() {` (line 1339), add:

```bash
# For self_test: runs validator $2 on each remaining argument and prints a
# FAIL line for each one whose verdict is not $1 (valid or invalid).
# Returns 1 if any verdict was wrong.
self_test_validator() {
    local want="$1" validator="$2" value rc=0
    shift 2
    for value in "$@"; do
        if "$validator" "$value" >/dev/null; then
            [ "$want" = valid ] || { echo "FAIL: $validator accepted '$value'" >&2; rc=1; }
        else
            [ "$want" = invalid ] || { echo "FAIL: $validator rejected '$value'" >&2; rc=1; }
        fi
    done
    return "$rc"
}
```

In `self_test()`, before `    if [ "$SELF_TEST_FAILURES" -eq 0 ]; then`, insert:

```bash
    echo "== self-test: new-host input validators ==" >&2
    local vd_ok=true long63 long64 long32 long33
    long63=$(printf 'a%.0s' {1..63})
    long64=$(printf 'a%.0s' {1..64})
    long32=$(printf 'u%.0s' {1..32})
    long33=$(printf 'u%.0s' {1..33})
    self_test_validator valid check_new_hostname newbox a b2 my-box "$long63" || vd_ok=false
    # box- passes the bare regex but NixOS's networking.hostName rejects it.
    self_test_validator invalid check_new_hostname "" 9box Box -box box- my_box my.box "my box" \
        tariognatha-vm "${AVAILABLE_HOSTS[@]}" "$long64" || vd_ok=false
    self_test_validator valid check_new_username krane alice _svc a-b a_b "$long32" || vd_ok=false
    self_test_validator invalid check_new_username "" root nobody daemon sshd greeter nixbld nixbld1 \
        systemd-network Alice 1abc "a b" a.b "$long33" || vd_ok=false
    # shellcheck disable=SC2016 # the literal ${x} is the point of this value.
    self_test_validator valid check_git_name krane "Test Er" "Zoë O'Brien" 'A/B & C\D "q" ${x}' || vd_ok=false
    self_test_validator invalid check_git_name "" "a@b" "$(printf 'a\nb')" || vd_ok=false
    self_test_validator valid check_git_email chris@krane.dev a+b@x.y root@localhost || vd_ok=false
    self_test_validator invalid check_git_email "" nodomain a@b@c "a b@c.d" a@ @b || vd_ok=false
    self_test_validator valid check_kb_layout at us de,us || vd_ok=false
    self_test_validator invalid check_kb_layout "" AT "at;rm" "at us" || vd_ok=false
    self_test_validator valid check_kb_variant "" nodeadkeys altgr-intl || vd_ok=false
    self_test_validator invalid check_kb_variant "no dead" 'x"y' || vd_ok=false
    self_test_validator valid check_profile "${GPU_PROFILES[@]}" || vd_ok=false
    self_test_validator invalid check_profile "" amd-nvidia-prime || vd_ok=false
    self_test_validator valid check_form_factor "${FORM_FACTORS[@]}" || vd_ok=false
    self_test_validator invalid check_form_factor "" tablet || vd_ok=false
    if $vd_ok; then
        echo "OK: hostname, username, git, keyboard, profile and form-factor validators" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: suggest_profile keeps each field in its slot ==" >&2
    local sp_ok=true sp_got
    sp_got=$(
        lspci() { printf '00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Notebook; }
        suggest_profile
    )
    [ "$sp_got" = "intel-igpu laptop" ] || { echo "FAIL: Intel-only notebook suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '00:02.0 VGA compatible controller: Intel Corporation UHD\n01:00.0 3D controller: NVIDIA Corporation GA107M\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Laptop; }
        suggest_profile
    )
    [ "$sp_got" = "intel-nvidia-prime laptop" ] || { echo "FAIL: Intel+NVIDIA laptop suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '0a:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Raphael\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Desktop; }
        suggest_profile
    )
    [ "$sp_got" = "amd-igpu desktop" ] || { echo "FAIL: AMD desktop suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '01:00.0 VGA compatible controller: NVIDIA Corporation AD104 [GeForce RTX 4070 Ti]\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Tower; }
        suggest_profile
    )
    [ "$sp_got" = "nvidia-desktop desktop" ] || { echo "FAIL: NVIDIA tower suggested '$sp_got'" >&2; sp_ok=false; }
    # Unknown GPU, known chassis: the profile slot stays empty and laptop
    # stays in the form-factor slot.
    sp_got=$(
        lspci() { :; }
        dmidecode() { [ "$2" = chassis-type ] && echo Notebook; }
        suggest_profile
    )
    [ "${sp_got%% *}" = "" ] && [ "${sp_got#* }" = laptop ] \
        || { echo "FAIL: unknown GPU on a notebook split as profile='${sp_got%% *}' form='${sp_got#* }'" >&2; sp_ok=false; }
    # Both probes fail, as without dmidecode/lspci: no suggestion at all.
    sp_got=$(
        lspci() { return 1; }
        dmidecode() { return 1; }
        suggest_profile
    )
    [ "$sp_got" = " " ] || { echo "FAIL: failed probes suggested '$sp_got'" >&2; sp_ok=false; }
    if $sp_ok; then
        echo "OK: suggest_profile maps lspci/dmidecode output and never shifts fields" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: new-host flag rules are usage errors ==" >&2
    local fl_ok=true fl_want fl_case fl_out fl_rc
    while IFS='|' read -r fl_want fl_case; do
        fl_rc=0
        # shellcheck disable=SC2086 # fl_case is a flag list, split on purpose.
        fl_out=$(bash "$REPO_ROOT/install.sh" $fl_case 2>&1) || fl_rc=$?
        if [ "$fl_rc" -eq 0 ] || ! printf '%s' "$fl_out" | grep -qF -- "$fl_want"; then
            echo "FAIL: install.sh $fl_case: rc=$fl_rc, expected an error containing '$fl_want'" >&2
            fl_ok=false
        fi
    done <<'EOF'
only works in install mode|--mode setup --dry-run --new-host newbox --user alice --profile amd-igpu --form-factor laptop
only apply together with --new-host|--mode install --dry-run --host taractias --disk /dev/null --user alice
also requires --user --profile --form-factor|--mode install --dry-run --disk /dev/null --new-host newbox
mutually exclusive|--mode install --dry-run --disk /dev/null --host taractias --new-host newbox --user alice --profile amd-igpu --form-factor laptop
must start with a lowercase letter|--mode install --dry-run --disk /dev/null --new-host 9box --user alice --profile amd-igpu --form-factor laptop
already exists|--mode install --dry-run --disk /dev/null --new-host taractias --user alice --profile amd-igpu --form-factor laptop
system account|--mode install --dry-run --disk /dev/null --new-host newbox --user root --profile amd-igpu --form-factor laptop
unknown GPU profile|--mode install --dry-run --disk /dev/null --new-host newbox --user alice --profile amd-nvidia-prime --form-factor laptop
EOF
    if $fl_ok; then
        echo "OK: misused new-host flags stop with a usage error" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash install.sh --self-test; echo rc=$?`
Expected: FAIL, `rc=1`. `self_test_validator` reports `FAIL: check_new_hostname rejected 'newbox'`, because `check_new_hostname: command not found` makes every verdict "rejected". The `suggest_profile` block fails the same way, and every flag-rules case fails with `unknown argument: --new-host`, `unknown argument: --user` and so on.

- [ ] **Step 3: Add the globals**

After line 88, `INSTALL_SWAP_ON=false`, add:

```bash
# New-host flow (--new-host, or "+ new host" in the host menu). Empty means
# not given yet: prompt_new_host fills the rest from a prompt or, under
# --yes, from the DEFAULT_* values.
NEW_HOST_MODE=false
NEW_HOST=""
NEW_USER=""
NEW_GIT_NAME=""
NEW_GIT_EMAIL=""
NEW_PROFILE=""
NEW_FORM_FACTOR=""
NEW_KB_LAYOUT=""
NEW_KB_VARIANT=""
# --kb-variant "" is a real answer (no variant), so it needs its own flag.
NEW_KB_VARIANT_SET=false
# Account names a new host's login user must not take: root and the system
# accounts NixOS or this flake's modules create. nixbld* and systemd-* are
# matched as prefixes in check_new_username.
SYSTEM_ACCOUNT_NAMES=(root nobody daemon bin sys sync games man lp mail news uucp proxy backup operator
    sshd messagebus polkituser rtkit avahi geoclue nscd dhcpcd greeter flatpak ollama pipewire colord
    cups usbmux qemu-libvirtd nm-openvpn nm-iodine fwupd-refresh)
```

- [ ] **Step 4: Parse the flags**

In the arg `case`, after the `--disk=*)` arm (ends line 383), add:

```bash
        --new-host)
            require_arg "$@"
            NEW_HOST_MODE=true
            NEW_HOST="$2"
            shift 2
            ;;
        --new-host=*)
            NEW_HOST_MODE=true
            NEW_HOST="${1#*=}"
            shift
            ;;
        --user)
            require_arg "$@"
            NEW_USER="$2"
            shift 2
            ;;
        --user=*)
            NEW_USER="${1#*=}"
            shift
            ;;
        --git-name)
            require_arg "$@"
            NEW_GIT_NAME="$2"
            shift 2
            ;;
        --git-name=*)
            NEW_GIT_NAME="${1#*=}"
            shift
            ;;
        --git-email)
            require_arg "$@"
            NEW_GIT_EMAIL="$2"
            shift 2
            ;;
        --git-email=*)
            NEW_GIT_EMAIL="${1#*=}"
            shift
            ;;
        --profile)
            require_arg "$@"
            NEW_PROFILE="$2"
            shift 2
            ;;
        --profile=*)
            NEW_PROFILE="${1#*=}"
            shift
            ;;
        --form-factor)
            require_arg "$@"
            NEW_FORM_FACTOR="$2"
            shift 2
            ;;
        --form-factor=*)
            NEW_FORM_FACTOR="${1#*=}"
            shift
            ;;
        --kb-layout)
            require_arg "$@"
            NEW_KB_LAYOUT="$2"
            shift 2
            ;;
        --kb-layout=*)
            NEW_KB_LAYOUT="${1#*=}"
            shift
            ;;
        --kb-variant)
            require_arg "$@"
            NEW_KB_VARIANT="$2"
            NEW_KB_VARIANT_SET=true
            shift 2
            ;;
        --kb-variant=*)
            NEW_KB_VARIANT="${1#*=}"
            NEW_KB_VARIANT_SET=true
            shift
            ;;
```

- [ ] **Step 5: Document the flags in `usage`**

Replace line 326, `  --host HOST             One of: ${AVAILABLE_HOSTS[*]}`, with:

```
  --host HOST             One of: ${AVAILABLE_HOSTS[*]}
  --new-host NAME         Install mode only: create hosts/NAME from
                            templates/host/ instead of using an existing
                            host. Asks for the settings below unless given.
  --user NAME             New host's login user (default $DEFAULT_INSTALL_USER).
  --git-name NAME         New host's git user.name (default: the login user).
  --git-email EMAIL       New host's git user.email (default $DEFAULT_GIT_EMAIL).
  --profile PROFILE       New host's GPU profile: ${GPU_PROFILES[*]}
  --form-factor FF        New host's form factor: ${FORM_FACTORS[*]}
  --kb-layout LAYOUT      New host's keyboard layout (default $DEFAULT_KB_LAYOUT).
  --kb-variant VARIANT    New host's keyboard variant (default
                            $DEFAULT_KB_VARIANT). --yes --new-host also
                            requires --user, --profile and --form-factor.
```

- [ ] **Step 6: Add the validators, `suggest_profile` and `validate_new_host_flags`**

After Task 4's `parse_check_nix_dir()`, add:

```bash

# Each check_* prints why its value is unusable and returns 1, or returns 0
# silently. prompt_validated re-prompts on 1; validate_new_host_flags turns
# it into a usage error.

# Beyond the spec regex: no trailing -, since NixOS's networking.hostName
# type rejects it and that would only surface in nixos-install, after the
# wipe. tariognatha-vm is flake.nix's VM check target, not a hosts/ dir.
check_new_hostname() {
    local name="$1" h
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
        echo "hostname '$name' must start with a lowercase letter and use only a-z, 0-9 and -, at most 63 characters"
        return 1
    fi
    if [[ "$name" == *- ]]; then
        echo "hostname '$name' must not end in -, NixOS's networking.hostName rejects that"
        return 1
    fi
    if [ "$name" = tariognatha-vm ]; then
        echo "hostname 'tariognatha-vm' is taken by flake.nix's VM check target"
        return 1
    fi
    for h in "${AVAILABLE_HOSTS[@]}"; do
        if [ "$h" = "$name" ]; then
            echo "hosts/$name already exists, pick it from the host list instead"
            return 1
        fi
    done
    if [ -e "$REPO_ROOT/hosts/$name" ]; then
        echo "hosts/$name already exists"
        return 1
    fi
    return 0
}

check_new_username() {
    local name="$1" sys
    if ! [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "username '$name' must start with a-z or _ and use only a-z, 0-9, _ and -, at most 32 characters"
        return 1
    fi
    case "$name" in
        nixbld* | systemd-*)
            echo "username '$name' is reserved for a NixOS system account"
            return 1
            ;;
    esac
    for sys in "${SYSTEM_ACCOUNT_NAMES[@]}"; do
        if [ "$sys" = "$name" ]; then
            echo "username '$name' is a system account name"
            return 1
        fi
    done
    return 0
}

# No @: no git name needs one, and it keeps render_host_templates'
# leftover-@TOKEN@ check unambiguous. Nix and sed escaping covers the rest.
check_git_name() {
    if [ -z "$1" ]; then
        echo "git name must not be empty"
        return 1
    fi
    if [[ "$1" == *@* || "$1" == *[[:cntrl:]]* ]]; then
        echo "git name must not contain @ or control characters"
        return 1
    fi
    return 0
}

check_git_email() {
    if ! [[ "$1" =~ ^[^@[:space:][:cntrl:]]+@[^@[:space:][:cntrl:]]+$ ]]; then
        echo "git email '$1' must look like name@domain, with one @ and no spaces"
        return 1
    fi
    return 0
}

check_kb_layout() {
    if ! [[ "$1" =~ ^[a-z0-9_]+(,[a-z0-9_]+)*$ ]]; then
        echo "keyboard layout '$1' must be an XKB layout such as at or de,us"
        return 1
    fi
    return 0
}

# Empty is valid: no variant.
check_kb_variant() {
    if ! [[ "$1" =~ ^[a-z0-9_,-]*$ ]]; then
        echo "keyboard variant '$1' must be an XKB variant such as nodeadkeys, or empty"
        return 1
    fi
    return 0
}

check_profile() {
    local p
    for p in "${GPU_PROFILES[@]}"; do
        [ "$p" != "$1" ] || return 0
    done
    echo "unknown GPU profile '$1', expected one of: ${GPU_PROFILES[*]}"
    return 1
}

check_form_factor() {
    local f
    for f in "${FORM_FACTORS[@]}"; do
        [ "$f" != "$1" ] || return 0
    done
    echo "unknown form factor '$1', expected one of: ${FORM_FACTORS[*]}"
    return 1
}

# Prints "<gpu-profile> <form-factor>" from the same dmidecode/lspci probes
# as suggest_host, separated by exactly one space so callers split with
# ${s%% *} / ${s#* } and an empty field stays empty. Missing tools or no
# match mean no pre-selection, never a failure. AMD+NVIDIA PRIME is out of
# scope, so an NVIDIA GPU without an Intel one suggests nvidia-desktop.
suggest_profile() {
    local chassis="" gpu_info="" profile="" form_factor=""
    if command -v dmidecode >/dev/null 2>&1; then
        chassis=$(dmidecode -s chassis-type 2>/dev/null || true)
    fi
    if command -v lspci >/dev/null 2>&1; then
        gpu_info=$(lspci 2>/dev/null | grep -iE 'vga|3d controller' || true)
    fi
    if printf '%s' "$chassis" | grep -qiE 'laptop|notebook|portable|convertible|detachable'; then
        form_factor=laptop
    elif printf '%s' "$chassis" | grep -qiE 'desktop|tower|mini pc|all in one'; then
        form_factor=desktop
    fi
    if printf '%s' "$gpu_info" | grep -qi nvidia; then
        if printf '%s' "$gpu_info" | grep -qi intel; then
            profile=intel-nvidia-prime
        else
            profile=nvidia-desktop
        fi
    elif printf '%s' "$gpu_info" | grep -qiE 'amd|advanced micro devices'; then
        profile=amd-igpu
    elif printf '%s' "$gpu_info" | grep -qi intel; then
        profile=intel-igpu
    fi
    printf '%s %s\n' "$profile" "$form_factor"
}

# Enforces the new-host flag rules before anything runs. The new-host
# flags need --new-host. --new-host needs install mode and excludes --host.
# --yes needs --user, --profile and --form-factor. Every value given must
# pass the same check_* prompt_new_host applies. Any violation is a usage
# error.
validate_new_host_flags() {
    local given=() reason
    [ -z "$NEW_USER" ] || given+=(--user)
    [ -z "$NEW_GIT_NAME" ] || given+=(--git-name)
    [ -z "$NEW_GIT_EMAIL" ] || given+=(--git-email)
    [ -z "$NEW_PROFILE" ] || given+=(--profile)
    [ -z "$NEW_FORM_FACTOR" ] || given+=(--form-factor)
    [ -z "$NEW_KB_LAYOUT" ] || given+=(--kb-layout)
    if $NEW_KB_VARIANT_SET; then
        given+=(--kb-variant)
    fi
    if ! $NEW_HOST_MODE; then
        [ "${#given[@]}" -eq 0 ] || usage_die "${given[*]} only apply together with --new-host"
        return 0
    fi
    [ "$MODE" = install ] || usage_die "--new-host only works in install mode, setup mode runs on a host already in hosts/"
    [ -z "$HOST" ] || usage_die "--host and --new-host are mutually exclusive"
    reason=$(check_new_hostname "$NEW_HOST") || usage_die "--new-host: $reason"
    if $YES; then
        local missing=()
        [ -n "$NEW_USER" ] || missing+=(--user)
        [ -n "$NEW_PROFILE" ] || missing+=(--profile)
        [ -n "$NEW_FORM_FACTOR" ] || missing+=(--form-factor)
        [ "${#missing[@]}" -eq 0 ] || usage_die "--yes --new-host also requires ${missing[*]}"
    fi
    if [ -n "$NEW_USER" ]; then
        reason=$(check_new_username "$NEW_USER") || usage_die "--user: $reason"
    fi
    if [ -n "$NEW_GIT_NAME" ]; then
        reason=$(check_git_name "$NEW_GIT_NAME") || usage_die "--git-name: $reason"
    fi
    if [ -n "$NEW_GIT_EMAIL" ]; then
        reason=$(check_git_email "$NEW_GIT_EMAIL") || usage_die "--git-email: $reason"
    fi
    if [ -n "$NEW_PROFILE" ]; then
        reason=$(check_profile "$NEW_PROFILE") || usage_die "--profile: $reason"
    fi
    if [ -n "$NEW_FORM_FACTOR" ]; then
        reason=$(check_form_factor "$NEW_FORM_FACTOR") || usage_die "--form-factor: $reason"
    fi
    if [ -n "$NEW_KB_LAYOUT" ]; then
        reason=$(check_kb_layout "$NEW_KB_LAYOUT") || usage_die "--kb-layout: $reason"
    fi
    if $NEW_KB_VARIANT_SET; then
        reason=$(check_kb_variant "$NEW_KB_VARIANT") || usage_die "--kb-variant: $reason"
    fi
}
```

- [ ] **Step 7: Call it from `main`**

In `main()`, directly after the `case "$MODE" in … esac` block (ends line 1270), add:

```bash

    validate_new_host_flags
```

- [ ] **Step 8: Run the self-test, watch it pass**

Run: `bash install.sh --self-test; echo rc=$?`
Expected: PASS, `self-test: all checks passed`, `rc=0`, including `OK: hostname, username, git, keyboard, profile and form-factor validators`, `OK: suggest_profile maps lspci/dmidecode output and never shifts fields` and `OK: misused new-host flags stop with a usage error`.

Run: `bash install.sh --help` and `shellcheck -x -S style install.sh`
Expected: help shows the new flags with the four profile names; shellcheck prints nothing.

Run: `bash install.sh --mode install --host taractias --disk /dev/null --yes --dry-run > /tmp/install-new-host-dryrun-existing.log 2>&1; echo rc=$?`
Expected: `rc=0`. The existing-host dry-run is unaffected.

- [ ] **Step 9: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add install.sh
/etc/profiles/per-user/krane/bin/git commit -m "Add new-host validators, profile detection and flags to install.sh"
```

---

### Task 7: The new-host flow: menu, prompts, scaffold and rollback

**Files:**
- Modify: `install.sh` globals (after Task 6's block), `install.sh:105` (`rollback_scaffold` after `teardown_install_swap`), `install.sh:186-196` (`on_exit`), `install.sh:439-444` (`host_uses_cuda`), `install.sh:559-569` (`choose_host`), `install.sh:663-680` (`confirm_wipe_target`, then `scaffold_host` after it), `install.sh:699-703` (`patch_disko`), `install.sh:791-792` (`patch_prime`), `install.sh:958-976` (`run_install_mode`), arg parsing (`--self-test-scaffold`), a hook before `self_test_validator`, `self_test()`
- Test: `bash install.sh --self-test`, plus a `--dry-run` end-to-end run of a new host

**Interfaces:**
- Produces (globals): `SCAFFOLD_STAGING`, `SCAFFOLD_PREVIEW_DIR`, `SCAFFOLD_PENDING` (bool), `SELF_TEST_SCAFFOLD` (bool), `NEW_HOST_MENU_ENTRY="+ new host"`.
- Produces (functions):
  - `prompt_validated <prompt> <default> <validator>` prints the accepted answer.
  - `prompt_new_host` fills every `NEW_*` value and sets `HOST="$NEW_HOST"`.
  - `scaffold_host` renders into `$SCAFFOLD_STAGING`, parse-checks it, then runs `run mkdir`/`run cp`/`run register_sops_host`.
  - `rollback_scaffold` is called from `on_exit`.
  - `host_dir` prints `$SCAFFOLD_PREVIEW_DIR` under `--dry-run` for a new host, otherwise `$REPO_ROOT/hosts/$HOST`.
- Produces (hidden flag): `--self-test-scaffold`, used with `--new-host … --user … --profile … --form-factor …`. It requires `KRANE_ALLOW_SCAFFOLD_HOOK=1`, scaffolds for real into its own checkout, patches `disko.nix` with `/dev/disk/by-id/check-new-host-fake-disk`, and prints `self-test-scaffold: OK <host>`. Task 10's `scripts/check-new-host.sh` consumes it.
- Consumes: Tasks 4-6 (`render_host_templates`, `parse_check_nix_dir`, `register_sops_host`, `check_*`, `suggest_profile`, `validate_new_host_flags`).

- [ ] **Step 1: Write the failing rollback / landing / repeat self-test**

In `self_test()`, before `    if [ "$SELF_TEST_FAILURES" -eq 0 ]; then`, insert:

```bash
    echo "== self-test: a failed scaffold rolls back, a good one lands, a repeat is refused ==" >&2
    local sb_tmp sb_out sb_rc sb_ok=true
    sb_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-scaffold.XXXXXX")
    cp "$REPO_ROOT/install.sh" "$sb_tmp/install.sh"
    cp -r "$REPO_ROOT/templates" "$sb_tmp/templates"
    mkdir -p "$sb_tmp/hosts/taractias"
    cp "$REPO_ROOT/hosts/taractias/default.nix" "$sb_tmp/hosts/taractias/default.nix"
    # No creation_rules: line, so register_sops_host dies after hosts/rbhost/
    # has already been copied in: on_exit's rollback_scaffold must remove it.
    printf 'keys:\n  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n' >"$sb_tmp/.sops.yaml"
    (
        cd "$sb_tmp"
        git init -q
        git add -A
        git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m init
    )
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host rbhost --user tester --profile amd-igpu --form-factor laptop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -eq 0 ] || ! printf '%s' "$sb_out" | grep -q 'no top-level creation_rules'; then
        echo "FAIL: scaffolding into a .sops.yaml without creation_rules: did not die in register_sops_host (rc=$sb_rc)" >&2
        echo "  captured output: $sb_out" >&2
        sb_ok=false
    fi
    [ ! -e "$sb_tmp/hosts/rbhost" ] || { echo "FAIL: hosts/rbhost survived the failed scaffold" >&2; sb_ok=false; }
    [ -f "$sb_tmp/hosts/taractias/default.nix" ] || { echo "FAIL: the rollback touched hosts/taractias" >&2; sb_ok=false; }
    git -C "$sb_tmp" diff --quiet -- .sops.yaml || { echo "FAIL: .sops.yaml was not restored" >&2; sb_ok=false; }
    printf 'keys:\n  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n\ncreation_rules:\n  - path_regex: secrets/taractias\\.yaml$\n    key_groups:\n      - age:\n          - *admin_taractias\n' >"$sb_tmp/.sops.yaml"
    git -C "$sb_tmp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -am sops
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host goodhost --user tester --profile intel-nvidia-prime --form-factor desktop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -ne 0 ] || [ ! -f "$sb_tmp/hosts/goodhost/default.nix" ] \
        || ! grep -qF '&host_goodhost age1PLACEHOLDER_HOST_GOODHOST_REPLACE_VIA_BOOTSTRAP_SOPS_SH' "$sb_tmp/.sops.yaml" \
        || ! grep -qF 'device = "/dev/disk/by-id/check-new-host-fake-disk";' "$sb_tmp/hosts/goodhost/disko.nix"; then
        echo "FAIL: a valid scaffold of goodhost did not land (rc=$sb_rc)" >&2
        echo "  captured output: $sb_out" >&2
        sb_ok=false
    fi
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host goodhost --user tester --profile amd-igpu --form-factor laptop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -eq 0 ] || ! printf '%s' "$sb_out" | grep -q 'already exists'; then
        echo "FAIL: a second scaffold of goodhost was not refused (rc=$sb_rc)" >&2
        sb_ok=false
    fi
    [ -f "$sb_tmp/hosts/goodhost/default.nix" ] || { echo "FAIL: the refused repeat deleted hosts/goodhost" >&2; sb_ok=false; }
    rm -rf "$sb_tmp"
    if $sb_ok; then
        echo "OK: scaffold rolls back on failure, lands on success, refuses an existing host" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: host_uses_cuda follows a new host's GPU profile ==" >&2
    local nc_ok=true saved_new_mode="$NEW_HOST_MODE" saved_new_profile="$NEW_PROFILE" saved_host2="$HOST"
    NEW_HOST_MODE=true
    HOST=newbox
    NEW_PROFILE=nvidia-desktop
    host_uses_cuda || { echo "FAIL: host_uses_cuda false for a new nvidia-desktop host" >&2; nc_ok=false; }
    NEW_PROFILE=intel-nvidia-prime
    ! host_uses_cuda || { echo "FAIL: host_uses_cuda true for a new intel-nvidia-prime host" >&2; nc_ok=false; }
    NEW_HOST_MODE="$saved_new_mode"
    NEW_PROFILE="$saved_new_profile"
    HOST="$saved_host2"
    if $nc_ok; then
        echo "OK: host_uses_cuda true only for a new nvidia-desktop host" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash install.sh --self-test; echo rc=$?`
Expected: FAIL, `rc=1`. The sandbox children die with `unknown argument: --self-test-scaffold`, so the output shows `FAIL: … did not die in register_sops_host`, `FAIL: a valid scaffold of goodhost did not land` and `FAIL: host_uses_cuda false for a new nvidia-desktop host`.

- [ ] **Step 3: Globals, the hook flag and rollback**

After Task 6's `SYSTEM_ACCOUNT_NAMES=(…)`, add:

```bash
SELF_TEST_SCAFFOLD=false
NEW_HOST_MENU_ENTRY="+ new host"
# scaffold_host state. SCAFFOLD_STAGING is its render dir, removed on exit.
# SCAFFOLD_PREVIEW_DIR points host_dir at it under --dry-run, which never
# writes hosts/<name>/. SCAFFOLD_PENDING is true only while hosts/$HOST/ and
# .sops.yaml may be half-written, which is when on_exit rolls them back.
SCAFFOLD_STAGING=""
SCAFFOLD_PREVIEW_DIR=""
SCAFFOLD_PENDING=false
```

After `teardown_install_swap()` (ends line 105), add. It is defined this early for the same reason as `teardown_install_swap`: `on_exit` can run before arg parsing finishes.

```bash

# Undoes a scaffold_host that did not finish: removes the new hosts/$HOST/
# and restores .sops.yaml from the index. SCAFFOLD_PENDING is only true
# between scaffold_host's "does not exist yet" check and its last step, and
# never under --dry-run, so this can never touch an existing host. Warns
# instead of dying, like teardown_install_swap.
rollback_scaffold() {
    if ! $SCAFFOLD_PENDING || [ -z "$HOST" ]; then
        return 0
    fi
    SCAFFOLD_PENDING=false
    log_warn "rolling back the partial hosts/$HOST scaffold"
    rm -rf "${REPO_ROOT:?}/hosts/$HOST" || log_warn "could not remove hosts/$HOST, delete it by hand"
    git -C "$REPO_ROOT" checkout -- .sops.yaml \
        || log_warn "could not restore .sops.yaml, run git checkout -- .sops.yaml"
}
```

Replace `on_exit()` (lines 186-196) with:

```bash
on_exit() {
    local rc=$?
    if [ "$rc" -ne 0 ] && ! $HANDLED_EXIT && ! $USAGE_EXIT; then
        if $LOG_WRITABLE; then
            gum style --foreground 244 "See $LOG for the full transcript, exit $rc." >&2
        else
            gum style --foreground 244 "exit $rc, no log file was writable this run." >&2
        fi
    fi
    teardown_install_swap
    rollback_scaffold
    if [ -n "$SCAFFOLD_STAGING" ]; then
        rm -rf "$SCAFFOLD_STAGING"
    fi
}
```

In the arg `case`, after Task 4's `--self-test-check-scaffold)` arm, add:

```bash
        --self-test-scaffold)
            SELF_TEST_SCAFFOLD=true
            shift
            ;;
```

- [ ] **Step 4: `host_dir`, and `host_uses_cuda`/`patch_disko`/`patch_prime` on top of it**

Replace `host_uses_cuda()` and its comment (lines 439-444) with:

```bash
# True only when $HOST's own default.nix imports the NVIDIA desktop GPU
# module, confirmed with `git grep -n nvidia-desktop hosts/`: tariognatha
# only, among the committed hosts. A new host is not written until after
# check_dns runs, so it answers from its chosen GPU profile instead. Empty
# $HOST (interactive host choice not made yet) reads as false.
host_uses_cuda() {
    if $NEW_HOST_MODE && [ -n "$NEW_PROFILE" ]; then
        [ "$NEW_PROFILE" = nvidia-desktop ]
        return
    fi
    grep -q 'gpu/nvidia-desktop' "$REPO_ROOT/hosts/$HOST/default.nix" 2>/dev/null
}

# hosts/$HOST, or under --dry-run for a new host the staging copy
# scaffold_host rendered, since --dry-run never writes hosts/<name>/.
host_dir() {
    if [ -n "$SCAFFOLD_PREVIEW_DIR" ]; then
        printf '%s\n' "$SCAFFOLD_PREVIEW_DIR"
    else
        printf '%s\n' "$REPO_ROOT/hosts/$HOST"
    fi
}
```

In `patch_disko()` (lines 699-703), replace `    patch_disko_file "$REPO_ROOT/hosts/$HOST/disko.nix" "$DISK"` with:

```bash
    patch_disko_file "$(host_dir)/disko.nix" "$DISK"
```

In `patch_prime()`, replace line 792, `    local default_nix="$REPO_ROOT/hosts/$HOST/default.nix"`, with:

```bash
    local default_nix
    default_nix="$(host_dir)/default.nix"
```

- [ ] **Step 5: Prompts and the host menu**

After Task 6's `validate_new_host_flags()`, add:

```bash

# Prompts until $3 accepts the answer, printing the validator's reason and
# asking again otherwise. $2 is pre-filled. Never reached under --yes:
# validate_new_host_flags requires or defaults every answer there.
prompt_validated() {
    local prompt="$1" default="$2" validator="$3" answer reason
    while true; do
        answer=$(gum_tty input --prompt "$prompt: " --value "$default" --placeholder "$default")
        if reason=$("$validator" "$answer"); then
            log_info "$prompt: $answer"
            printf '%s\n' "$answer"
            return 0
        fi
        log_warn "$reason"
    done
}

# Collects every new-host answer before anything is written: flags win,
# then --yes takes the DEFAULT_*s (validate_new_host_flags already required
# --user/--profile/--form-factor), else a prompt pre-filled with the
# default or suggest_profile's guess. Sets HOST last.
prompt_new_host() {
    log_step "New host"
    if [ -z "$NEW_HOST" ]; then
        NEW_HOST=$(prompt_validated "Hostname" "" check_new_hostname)
    fi
    if [ -z "$NEW_USER" ]; then
        NEW_USER=$(prompt_validated "Login username" "$DEFAULT_INSTALL_USER" check_new_username)
    fi
    if [ -z "$NEW_GIT_NAME" ]; then
        if $YES; then
            NEW_GIT_NAME="$NEW_USER"
        else
            NEW_GIT_NAME=$(prompt_validated "git user.name" "$NEW_USER" check_git_name)
        fi
    fi
    if [ -z "$NEW_GIT_EMAIL" ]; then
        if $YES; then
            NEW_GIT_EMAIL="$DEFAULT_GIT_EMAIL"
        else
            NEW_GIT_EMAIL=$(prompt_validated "git user.email" "$DEFAULT_GIT_EMAIL" check_git_email)
        fi
    fi
    if [ -z "$NEW_PROFILE" ] || [ -z "$NEW_FORM_FACTOR" ]; then
        local suggestion
        suggestion=$(suggest_profile)
        if [ -z "$NEW_PROFILE" ]; then
            NEW_PROFILE=$(choose_one "GPU profile for $NEW_HOST" "${suggestion%% *}" "${GPU_PROFILES[@]}")
        fi
        if [ -z "$NEW_FORM_FACTOR" ]; then
            NEW_FORM_FACTOR=$(choose_one "Form factor for $NEW_HOST" "${suggestion#* }" "${FORM_FACTORS[@]}")
        fi
    fi
    if [ -z "$NEW_KB_LAYOUT" ]; then
        if $YES; then
            NEW_KB_LAYOUT="$DEFAULT_KB_LAYOUT"
        else
            NEW_KB_LAYOUT=$(prompt_validated "Keyboard layout" "$DEFAULT_KB_LAYOUT" check_kb_layout)
        fi
    fi
    if ! $NEW_KB_VARIANT_SET; then
        if $YES; then
            NEW_KB_VARIANT="$DEFAULT_KB_VARIANT"
        else
            NEW_KB_VARIANT=$(prompt_validated "Keyboard variant (may be empty)" "$DEFAULT_KB_VARIANT" check_kb_variant)
        fi
        NEW_KB_VARIANT_SET=true
    fi
    HOST="$NEW_HOST"
    log_info "new host $HOST: user $NEW_USER, git $NEW_GIT_NAME <$NEW_GIT_EMAIL>, $NEW_PROFILE, $NEW_FORM_FACTOR, keyboard $NEW_KB_LAYOUT/${NEW_KB_VARIANT:-<none>}"
}
```

Replace `choose_host()` (lines 559-569) with:

```bash
choose_host() {
    if $NEW_HOST_MODE; then
        prompt_new_host
        return
    fi
    if [ -n "$HOST" ]; then
        return
    fi
    if $YES; then
        die "--host or --new-host is required together with --yes or --dry-run, no interactive prompts under --yes"
    fi
    local suggestion
    suggestion=$(suggest_host)
    HOST=$(choose_one "Select the target host" "$suggestion" "${AVAILABLE_HOSTS[@]}" "$NEW_HOST_MENU_ENTRY")
    if [ "$HOST" = "$NEW_HOST_MENU_ENTRY" ]; then
        HOST=""
        NEW_HOST_MODE=true
        prompt_new_host
    fi
}
```

- [ ] **Step 6: `confirm_wipe_target` label and `scaffold_host`**

In `confirm_wipe_target()`, replace lines 668-671

```bash
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "This will ERASE ALL DATA on:" "" "  $DISK" "  resolves to /dev/$kernel_hl" "" "Host: $HOST" >&2
```

with

```bash
    local host_label="$HOST"
    if $NEW_HOST_MODE; then
        host_label="$HOST (new: hosts/$HOST is written after this confirmation)"
    fi
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "This will ERASE ALL DATA on:" "" "  $DISK" "  resolves to /dev/$kernel_hl" "" "Host: $host_label" >&2
```

After `confirm_wipe_target()` (ends line 680), add:

```bash

# Renders templates/host/ for $HOST into a staging dir, parse-checks every
# file, then copies it into hosts/$HOST/ and registers $HOST's sops
# placeholders. Runs only after the wipe is confirmed, so an abort before
# then leaves the repo untouched. Until it finishes, on_exit's
# rollback_scaffold removes hosts/$HOST/ and restores .sops.yaml. A later
# failure leaves the host in place, and a rerun picks it from the menu.
scaffold_host() {
    log_step "Scaffolding hosts/$HOST ($NEW_PROFILE, $NEW_FORM_FACTOR, user $NEW_USER)"
    require nix-instantiate awk
    local dest="$REPO_ROOT/hosts/$HOST"
    [ ! -e "$dest" ] || die "$dest already exists, rerun and pick $HOST from the host list instead"
    SCAFFOLD_STAGING=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-scaffold.XXXXXX")
    render_host_templates "$SCAFFOLD_STAGING" "$HOST" "$NEW_USER" "$NEW_GIT_NAME" "$NEW_GIT_EMAIL" \
        "$NEW_PROFILE" "$NEW_FORM_FACTOR" "$NEW_KB_LAYOUT" "$NEW_KB_VARIANT"
    parse_check_nix_dir "$SCAFFOLD_STAGING"
    log_ok "rendered and parse-checked hosts/$HOST in $SCAFFOLD_STAGING"
    if $DRY_RUN; then
        # Nothing below writes under --dry-run, so later steps read the
        # staging copy instead (host_dir).
        SCAFFOLD_PREVIEW_DIR="$SCAFFOLD_STAGING"
    else
        SCAFFOLD_PENDING=true
    fi
    run mkdir -p "$dest"
    run cp -a "$SCAFFOLD_STAGING/." "$dest/"
    run register_sops_host "$REPO_ROOT/.sops.yaml" "$HOST"
    SCAFFOLD_PENDING=false
}
```

- [ ] **Step 7: Wire it into `run_install_mode`**

In `run_install_mode()`, replace

```bash
    confirm_wipe_target
    patch_disko
```

with

```bash
    confirm_wipe_target
    if $NEW_HOST_MODE; then
        scaffold_host
    fi
    patch_disko
```

(`commit_hardware_config`'s `git add -A` already picks up `hosts/$HOST/` and `.sops.yaml`. Task 8 changes its commit message.)

- [ ] **Step 8: The `--self-test-scaffold` hook**

Directly above Task 6's `self_test_validator()` (so every function is defined), add:

```bash
# Scaffolds the --new-host flags' host for real (DRY_RUN=false) into this
# checkout's hosts/ and .sops.yaml, patches its disko.nix with a fake disk,
# then exits. For scripts/check-new-host.sh and self_test's rollback check,
# which both run it from a throwaway copy of the repo. The env guard keeps
# it from writing into a real checkout by accident.
if $SELF_TEST_SCAFFOLD; then
    [ "${KRANE_ALLOW_SCAFFOLD_HOOK:-}" = 1 ] \
        || die "--self-test-scaffold writes hosts/ and .sops.yaml for real, it only runs with KRANE_ALLOW_SCAFFOLD_HOOK=1 from a throwaway copy of the repo"
    YES=true
    DRY_RUN=false
    MODE=install
    validate_new_host_flags
    $NEW_HOST_MODE || usage_die "--self-test-scaffold needs --new-host"
    prompt_new_host
    scaffold_host
    patch_disko_file "$REPO_ROOT/hosts/$HOST/disko.nix" /dev/disk/by-id/check-new-host-fake-disk
    echo "self-test-scaffold: OK $HOST"
    exit 0
fi
```

- [ ] **Step 9: Run the self-test, watch it pass**

Run: `bash install.sh --self-test; echo rc=$?`
Expected: PASS, `self-test: all checks passed`, `rc=0`, including `OK: scaffold rolls back on failure, lands on success, refuses an existing host` and `OK: host_uses_cuda true only for a new nvidia-desktop host`.

Run: `shellcheck -x -S style install.sh`
Expected: no output.

- [ ] **Step 10: End-to-end `--dry-run` of a new host writes nothing**

```bash
/etc/profiles/per-user/krane/bin/git status --porcelain > /tmp/install-new-host-status-before.txt
bash install.sh --mode install --new-host newbox --user alice --git-name 'Alice A' --profile intel-nvidia-prime --form-factor laptop --disk /dev/null --yes --dry-run > /tmp/install-new-host-dryrun.log 2>&1; echo rc=$?
grep -E 'Scaffolding hosts/newbox|rendered and parse-checked hosts/newbox|\+ cp -a .*hosts/newbox/|\+ register_sops_host .*\.sops\.yaml newbox|Host: newbox \(new' /tmp/install-new-host-dryrun.log
/etc/profiles/per-user/krane/bin/git status --porcelain | diff /tmp/install-new-host-status-before.txt -
test ! -e hosts/newbox && echo "hosts/newbox not written"
```

Expected: `rc=0`. The grep shows all five markers. The `diff` prints nothing, and the last line is `hosts/newbox not written`. The log's `Patching hosts/newbox/disko.nix` step prints `+ sed -i s#device\ =\ \"/dev/CHANGE-ME\"\;#… /tmp/krane-install-scaffold.…/disko.nix`, which is the staging copy. On a machine with `lspci` showing Intel and NVIDIA, the PRIME step likewise prints `+ sed -i -E …krane\.prime\.intelBusId… /tmp/krane-install-scaffold.…/default.nix`. On any other machine it warns `could not find both an Intel and an NVIDIA PCI device…, continuing under --dry-run`.

- [ ] **Step 11: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add install.sh
/etc/profiles/per-user/krane/bin/git commit -m "Create a new host from install mode's host menu or --new-host"
```

---

### Task 8: Use the target host's login user throughout install mode

**Files:**
- Modify: `install.sh` globals (after Task 7's block), `install.sh:321-339` (`usage`, `--yes` text), `install.sh:826-841` (`commit_hardware_config`), `install.sh:899-930` (`set_krane_password` → `set_user_password`, `print_no_password_box`), `install.sh:932-956` (`finish_install`), `run_install_mode` (after `run git -C "$REPO_ROOT" add -A`), new `resolve_install_user` after `patch_disko()`, `scripts/bootstrap-sops.sh:83`
- Test: a grep for leftover account-name `krane` in those functions, plus two `--dry-run` runs

**Interfaces:**
- Produces: the global `INSTALL_USER` and `resolve_install_user`. For an existing host, or a new host after `git add -A`, `resolve_install_user` sets `INSTALL_USER` from `nix eval --raw "$REPO_ROOT#nixosConfigurations.$HOST.config.krane.user.name"`. Under `--dry-run` for a new host it uses `NEW_USER`. It dies when a new host evaluates to a different user than the one prompted. `set_user_password` replaces `set_krane_password`.
- Consumes: `krane.user.name` (Task 2), `NEW_HOST_MODE`/`NEW_USER` (Tasks 6-7), the flake's host discovery (Task 3).

- [ ] **Step 1: Write the failing checks**

Run: `grep -nE 'passwd krane|/home/krane|krane:users|user\.name=krane|krane@localhost|set_krane_password|krane.s password' install.sh`
Expected now: FAIL, a dozen matches in `set_krane_password`, `print_no_password_box`, `finish_install`, `commit_hardware_config` and `usage`. After this task: no output.

```bash
bash install.sh --mode install --new-host newbox --user alice --profile amd-igpu --form-factor laptop --disk /dev/null --yes --dry-run > /tmp/install-new-host-dryrun-user.log 2>&1; echo rc=$?
grep -E 'passwd alice|/mnt/home/alice/\.dotfiles|alice:users|login user for newbox: alice|Add\\ newbox\\ host|only as a local commit' /tmp/install-new-host-dryrun-user.log
```

Expected now: FAIL. `rc=0`, but the grep finds nothing (the log shows `passwd krane` and `/mnt/home/krane/.dotfiles`).

- [ ] **Step 2: Add the global and `resolve_install_user`**

After Task 7's `SCAFFOLD_PENDING=false` global, add:

```bash
# The target host's login account (its krane.user.name), set by
# resolve_install_user once the host is known and staged.
INSTALL_USER=""
```

After `patch_disko()`, add:

```bash

# Reads the target host's login account from its evaluated krane.user.name.
# Runs after patch_disko's `git add -A`, since a new host's files are
# invisible to the flake until staged. Under --dry-run a new host was never
# written or staged, so the prompted username stands in. The eval is
# read-only, so it runs for real under --dry-run for an existing host.
resolve_install_user() {
    if $NEW_HOST_MODE && $DRY_RUN; then
        INSTALL_USER="$NEW_USER"
        log_info "login user for $HOST: $INSTALL_USER (prompted, a new host is not evaluated under --dry-run)"
        return 0
    fi
    local user=""
    user=$(nix eval --raw "$REPO_ROOT#nixosConfigurations.$HOST.config.krane.user.name") || user=""
    if [ -z "$user" ]; then
        soft_fail "could not evaluate nixosConfigurations.$HOST.config.krane.user.name"
        user="${NEW_USER:-$DEFAULT_INSTALL_USER}"
    fi
    if $NEW_HOST_MODE && [ "$user" != "$NEW_USER" ]; then
        die "hosts/$HOST evaluates to login user '$user', but '$NEW_USER' was entered, check hosts/$HOST/default.nix"
    fi
    INSTALL_USER="$user"
    log_info "login user for $HOST: $INSTALL_USER"
}
```

In `run_install_mode()`, replace

```bash
    patch_disko
    run git -C "$REPO_ROOT" add -A
    run_disko
```

with

```bash
    patch_disko
    run git -C "$REPO_ROOT" add -A
    resolve_install_user
    run_disko
```

- [ ] **Step 3: Replace the hardcoded account**

Replace `commit_hardware_config()` (lines 826-841, including its comment) with:

```bash
# Commits before nixos-install so the copied repo starts with a clean
# history instead of the disko/PRIME patches left as a local diff. A new
# host's files, its .sops.yaml placeholders and its hardware config land in
# this one commit.
commit_hardware_config() {
    log_step "Committing local hardware config for $HOST"
    run git -C "$REPO_ROOT" add -A
    if ! $DRY_RUN && git -C "$REPO_ROOT" diff --cached --quiet; then
        log_info "nothing new to commit for $HOST hardware config"
        return 0
    fi
    local id_args=()
    # Commit identity is overridden only when none is configured.
    if [ -z "$(git -C "$REPO_ROOT" config user.email 2>/dev/null || true)" ]; then
        id_args=(-c "user.name=$INSTALL_USER" -c "user.email=$INSTALL_USER@localhost")
    fi
    local message="Configure $HOST hardware"
    if $NEW_HOST_MODE; then
        message="Add $HOST host"
    fi
    run git -C "$REPO_ROOT" "${id_args[@]}" commit -m "$message" --quiet
}
```

Replace `set_krane_password()` and `print_no_password_box()` (lines 899-930) with:

```bash
# Always runs for real outside --dry-run: --yes must never leave a fresh
# install with no login. Retries a few times for a mistyped password.
set_user_password() {
    log_step "Set $INSTALL_USER's password on the new install"

    if ! $DRY_RUN && [ ! -t 0 ]; then
        print_no_password_box
        PASSWORD_SET=false
        return 0
    fi

    local attempt=1
    while [ "$attempt" -le 3 ]; do
        if run nixos-enter --root /mnt -- passwd "$INSTALL_USER"; then
            PASSWORD_SET=true
            return 0
        fi
        log_warn "passwd failed (attempt $attempt/3)"
        attempt=$((attempt + 1))
    done
    print_no_password_box
    PASSWORD_SET=false
}

print_no_password_box() {
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "NO PASSWORD SET" "" \
        "Run this yourself before rebooting:" "" \
        "  nixos-enter --root /mnt -- passwd $INSTALL_USER" >&2
}
```

Replace `finish_install()` (lines 932-956) with:

```bash
finish_install() {
    [ -n "$INSTALL_USER" ] || die "INSTALL_USER is unset, resolve_install_user did not run"
    local home_dir="/home/$INSTALL_USER"
    log_step "Copying repo to /mnt$home_dir/.dotfiles"
    run mkdir -p "/mnt$home_dir/.dotfiles"
    run_sh "cp -a \"$REPO_ROOT/.\" \"/mnt$home_dir/.dotfiles/\""
    run nixos-enter --root /mnt -- chown -R "$INSTALL_USER:users" "$home_dir/.dotfiles"
    run_sh "test -f \"/mnt$home_dir/.dotfiles/flake.nix\"" \
        || die "repo copy to /mnt$home_dir/.dotfiles is missing flake.nix, see $LOG"

    PASSWORD_SET=true
    set_user_password

    banner "Install complete" \
        "Next steps:" \
        "  1. reboot" \
        "  2. ~/.dotfiles/install.sh --mode setup" \
        "  3. second switch, setup mode drives this"

    # The new host's only copies are this live ISO's checkout, gone at
    # reboot, and the one on the target disk.
    if $NEW_HOST_MODE; then
        gum style \
            --border double --border-foreground 226 --foreground 226 --bold \
            --padding "1 3" --margin "1 0" \
            "hosts/$HOST is new and not pushed anywhere" "" \
            "It exists only as a local commit in $home_dir/.dotfiles on the new install." \
            "Push it from there after first boot, or it is lost with this disk." >&2
    fi

    if $PASSWORD_SET; then
        if confirm "Reboot now?"; then
            run reboot
        fi
    else
        log_warn "not offering to reboot, set $INSTALL_USER's password first"
    fi
}
```

In `usage`, replace

```
  -y, --yes               Assume yes and auto-confirm every prompt. Live
                            install also requires --confirm-wipe unless
                            --dry-run is given too. Never skips setting
                            krane's password.
```

with

```
  -y, --yes               Assume yes and auto-confirm every prompt. Live
                            install also requires --confirm-wipe unless
                            --dry-run is given too. Never skips setting
                            the login user's password.
```

`scripts/bootstrap-sops.sh` line 83: replace `    echo "       Re-run as the admin user krane, or set SOPS_AGE_KEY_FILE to an" >&2` with:

```bash
    echo "       Re-run as this host's admin user, or set SOPS_AGE_KEY_FILE to an" >&2
```

- [ ] **Step 4: Run the checks, watch them pass**

Run: `grep -nE 'passwd krane|/home/krane|krane:users|user\.name=krane|krane@localhost|set_krane_password|krane.s password' install.sh`
Expected: no output.

Re-run the Step 1 new-host dry-run and grep.
Expected: `rc=0`, and the grep shows `login user for newbox: alice (prompted, …)`, `+ mkdir -p /mnt/home/alice/.dotfiles`, `+ nixos-enter --root /mnt -- chown -R alice:users /home/alice/.dotfiles`, `+ nixos-enter --root /mnt -- passwd alice`, a `commit -m Add\ newbox\ host` line and `It exists only as a local commit in /home/alice/.dotfiles on the new install.`.

```bash
bash install.sh --mode install --host taractias --disk /dev/null --yes --dry-run > /tmp/install-new-host-dryrun-taractias.log 2>&1; echo rc=$?
grep -E 'login user for taractias: krane|passwd krane|/mnt/home/krane/\.dotfiles|Configure\\ taractias\\ hardware' /tmp/install-new-host-dryrun-taractias.log
```

Expected: `rc=0`. All four markers appear, and `login user for taractias: krane` comes from a real `nix eval` (about 20 s). No `only as a local commit` line.

Run: `bash install.sh --self-test; echo rc=$?` and `shellcheck -x -S style install.sh scripts/bootstrap-sops.sh`
Expected: `self-test: all checks passed`, `rc=0`; shellcheck prints nothing.

- [ ] **Step 5: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add install.sh scripts/bootstrap-sops.sh
/etc/profiles/per-user/krane/bin/git commit -m "Use the target host's login user throughout install mode"
```

---

### Task 9: Setup-mode guard for hosts not in `hosts/`

**Files:**
- Modify: `install.sh:984-987` (`preflight_setup`), `self_test()`
- Test: `bash install.sh --self-test` (a `hostname` shim prints `bogushost`)

**Interfaces:**
- Produces: `preflight_setup` dies (even under `--dry-run`) with `host '<HOST>' not in hosts/ — install it via install mode, or pass --host` when `HOST` is not in `AVAILABLE_HOSTS`.
- Consumes: `AVAILABLE_HOSTS`.

- [ ] **Step 1: Write the failing self-test**

In `self_test()`, before `    if [ "$SELF_TEST_FAILURES" -eq 0 ]; then`, insert:

```bash
    echo "== self-test: setup mode refuses a hostname that is not in hosts/ ==" >&2
    local sg_tmp sg_out sg_rc=0
    sg_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-hostname.XXXXXX")
    printf '#!/bin/sh\necho bogushost\n' >"$sg_tmp/hostname"
    chmod +x "$sg_tmp/hostname"
    sg_out=$(PATH="$sg_tmp:$PATH" bash "$REPO_ROOT/install.sh" --mode setup --dry-run 2>&1) || sg_rc=$?
    rm -rf "$sg_tmp"
    if [ "$sg_rc" -ne 0 ] && printf '%s' "$sg_out" | grep -qF "host 'bogushost' not in hosts/"; then
        echo "OK: setup mode on an unknown hostname dies even under --dry-run (rc=$sg_rc)" >&2
    else
        echo "FAIL: setup mode on hostname bogushost: rc=$sg_rc, no \"not in hosts/\" error" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash install.sh --self-test; echo rc=$?`
Expected: FAIL, `rc=1`, `FAIL: setup mode on hostname bogushost: rc=…, no "not in hosts/" error`. Today `soft_fail` only warns (`unknown host 'bogushost'…, continuing under --dry-run`), and setup mode carries on. It usually runs to the end with rc 0, or it stops later for an unrelated reason.

- [ ] **Step 3: Implement the guard**

In `preflight_setup()`, replace lines 985-987

```bash
    if [ ! -d "$REPO_ROOT/hosts/$HOST" ]; then
        soft_fail "unknown host '$HOST', expected one of: ${AVAILABLE_HOSTS[*]}"
    fi
```

with

```bash
    # A die, not soft_fail: setup mode on a machine this flake never
    # installed has no host config to bootstrap or switch to, and a new host
    # can only be created from install mode.
    local known=false h
    for h in "${AVAILABLE_HOSTS[@]}"; do
        [ "$h" != "$HOST" ] || known=true
    done
    $known || die "host '$HOST' not in hosts/ — install it via install mode, or pass --host"
```

- [ ] **Step 4: Run it, watch it pass**

Run: `bash install.sh --self-test; echo rc=$?`
Expected: PASS, `OK: setup mode on an unknown hostname dies even under --dry-run (rc=1)`, `self-test: all checks passed`, `rc=0`.

Run: `bash install.sh --mode setup --host taractias --yes --dry-run > /tmp/install-new-host-setup.log 2>&1; echo rc=$?`
Expected: `rc=0`. A known host is unaffected.

- [ ] **Step 5: Commit**

```bash
/etc/profiles/per-user/krane/bin/git add install.sh
/etc/profiles/per-user/krane/bin/git commit -m "Refuse setup mode on a hostname that is not in hosts/"
```

---

### Task 10: `just check-new-host`, the install-lint dry-run, and docs

**Files:**
- Create: `scripts/check-new-host.sh`
- Modify: `justfile:42-44`, `scripts/docker-check.sh:140-160`, `docs/INSTALL.md:3,36,47-48,73-94,288-305`, `README.md:6,26,47-58,64,67,77`
- Test: `just check-new-host`

**Interfaces:**
- Produces: the `just check-new-host` recipe and `scripts/check-new-host.sh`. The script exits 0 only if all 8 combinations scaffold, are nixfmt-clean and evaluate, and if the account-wiring values match.
- Consumes: `install.sh --self-test-scaffold` with `KRANE_ALLOW_SCAFFOLD_HOOK=1` (Task 7), host auto-discovery (Task 3), `krane.user` (Task 2).

- [ ] **Step 1: Write the failing recipe**

In `justfile`, after the `install-lint:` recipe (lines 42-44), add:

```just

# Scaffolds a throwaway testhost for every GPU profile x form factor in a temporary git worktree of HEAD and evaluates each, needs local Nix, commit first.
check-new-host:
    scripts/check-new-host.sh
```

and change line 42's comment, `# bash -n, shellcheck and three --dry-run runs of install.sh, in docker.`, to:

```just
# bash -n, shellcheck and four --dry-run runs of install.sh, in docker.
```

Run: `just check-new-host; echo rc=$?`
Expected: FAIL, `rc` non-zero, `scripts/check-new-host.sh: No such file or directory`.

- [ ] **Step 2: Implement `scripts/check-new-host.sh`**

```bash
#!/usr/bin/env bash
# Scaffolds a throwaway host through install.sh's new-host flow for every
# GPU profile x form factor and evaluates each one, so a template change
# that breaks evaluation or formatting fails here instead of on a live ISO
# after the disk wipe. Works in a detached git worktree of HEAD under
# $TMPDIR, removed on exit: this checkout is never touched, and uncommitted
# changes are not tested. Needs local Nix with flakes, unlike the
# docker-backed recipes. Usage: just check-new-host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Mirrors install.sh's GPU_PROFILES and FORM_FACTORS.
PROFILES=(amd-igpu intel-igpu nvidia-desktop intel-nvidia-prime)
FORM_FACTORS=(laptop desktop)
HOST=testhost
USER_NAME=tester
GIT_NAME="Test Er"
GIT_EMAIL=tester@example.invalid
FAKE_DISK=/dev/disk/by-id/check-new-host-fake-disk

export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}experimental-features = nix-command flakes"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/check-new-host.XXXXXX")
WT="$SCRATCH/repo"
cleanup() {
    git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" worktree prune
    rm -rf "$SCRATCH"
}
trap cleanup EXIT
git -C "$REPO_ROOT" worktree add --detach --quiet "$WT" HEAD

CONFIG=".#nixosConfigurations.$HOST.config"
failures=0

# $1 what failed, $2 optional log to show the tail of.
fail() {
    echo "FAIL $1" >&2
    if [ -n "${2:-}" ]; then
        tail -n 20 "$2" >&2
    fi
    failures=$((failures + 1))
}

# $1 label, $2 attribute path under $CONFIG (a string, for --raw), $3 expected.
expect() {
    local got
    if ! got=$(cd "$WT" && nix eval --raw "$CONFIG.$2" 2>"$SCRATCH/eval.log"); then
        fail "$1: nix eval $2" "$SCRATCH/eval.log"
        return 0
    fi
    [ "$got" = "$3" ] || fail "$1: $2 is '$got', expected '$3'"
}

for profile in "${PROFILES[@]}"; do
    for ff in "${FORM_FACTORS[@]}"; do
        combo="$profile/$ff"
        # Back to HEAD's hosts/ and .sops.yaml before each scaffold.
        git -C "$WT" reset --quiet --hard HEAD
        git -C "$WT" clean --quiet -fdx -- hosts
        if ! KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$WT/install.sh" --self-test-scaffold \
            --new-host "$HOST" --user "$USER_NAME" --git-name "$GIT_NAME" --git-email "$GIT_EMAIL" \
            --profile "$profile" --form-factor "$ff" >"$SCRATCH/scaffold.log" 2>&1; then
            fail "$combo: scaffold" "$SCRATCH/scaffold.log"
            continue
        fi
        # Flakes only see tracked files.
        git -C "$WT" add -A
        # CI runs `nix fmt -- --ci`, so a pushed new host must already be formatted.
        if ! (cd "$WT" && nix shell --inputs-from . nixpkgs#nixfmt -c nixfmt --check \
            "hosts/$HOST/default.nix" "hosts/$HOST/disko.nix" "hosts/$HOST/display.nix") \
            >"$SCRATCH/fmt.log" 2>&1; then
            fail "$combo: rendered files are not nixfmt-clean" "$SCRATCH/fmt.log"
        fi
        if drv=$(cd "$WT" && nix eval --raw "$CONFIG.system.build.toplevel.drvPath" 2>"$SCRATCH/eval.log"); then
            echo "ok   $combo  $drv"
        else
            fail "$combo: toplevel eval" "$SCRATCH/eval.log"
        fi
    done
done

# Account wiring, checked on the last combination: every krane.user consumer
# follows the scaffolded values, not the "krane" default.
expect "user" "krane.user.name" "$USER_NAME"
expect "user" "users.users.$USER_NAME.home" "/home/$USER_NAME"
expect "home-manager" "home-manager.users.$USER_NAME.home.username" "$USER_NAME"
expect "git" "home-manager.users.$USER_NAME.programs.git.settings.user.name" "$GIT_NAME"
expect "git" "home-manager.users.$USER_NAME.programs.git.settings.user.email" "$GIT_EMAIL"
expect "autologin" "services.greetd.settings.initial_session.user" "$USER_NAME"
expect "hostname" "networking.hostName" "$HOST"
expect "disko" "disko.devices.disk.main.device" "$FAKE_DISK"

if [ "$failures" -ne 0 ]; then
    echo "check-new-host: $failures failures" >&2
    exit 1
fi
echo "check-new-host: all ${#PROFILES[@]}x${#FORM_FACTORS[@]} combinations evaluate"
```

Run: `chmod +x scripts/check-new-host.sh` and `/etc/profiles/per-user/krane/bin/git add scripts/check-new-host.sh`

- [ ] **Step 3: Add the new-host dry-run to `install-lint`**

In `scripts/docker-check.sh`'s `shellcheck)` arm, replace the comment lines 142-146

```bash
        # pipefail, the ERR trap, and the disko/PRIME sed helpers. The
        # three --dry-run runs cover install mode's plain and PRIME
        # branches plus setup mode, exiting 0 with no real hardware via
        # soft_fail. Wrapped in a git-state assertion: these must not
        # leave a staged change or a new commit behind.
```

with

```bash
        # pipefail, the ERR trap, the disko/PRIME sed helpers and the
        # new-host templates. The four --dry-run runs cover install mode's
        # plain and PRIME branches, a new host's scaffold, and setup mode,
        # exiting 0 with no real hardware via soft_fail. Wrapped in a
        # git-state assertion: these must not leave a staged change, a new
        # commit or a hosts/newbox/ behind.
```

and after line 159, `                ./install.sh --mode install --host tarmantria --disk /dev/null --yes --dry-run`, add:

```bash
                ./install.sh --mode install --new-host newbox --user alice --profile intel-nvidia-prime --form-factor laptop --disk /dev/null --yes --dry-run
```

- [ ] **Step 4: Docs**

`docs/INSTALL.md` line 3: replace `Full path from a blank machine to a working `tariognatha`, `tarmantria`, or `taractias`.` with:

```markdown
Full path from a blank machine to a working `tariognatha`, `tarmantria`, or `taractias`, or to a new host that `install.sh` scaffolds for you (see [Installing a new machine](#installing-a-new-machine)).
```

Line 36: replace `2. Host: suggests one of `tariognatha`, `tarmantria`, `taractias` from the chassis, in a `gum choose` list you can override.` with:

```markdown
2. Host: suggests one of the hosts under `hosts/` from the chassis, in a `gum choose` list you can override. The last entry, `+ new host`, creates a new host instead: see [Installing a new machine](#installing-a-new-machine).
```

Lines 47-48: replace

```markdown
10. Copies this repo to `/mnt/home/krane/.dotfiles`.
11. Sets krane's password. This always runs, even under `--yes`.
```

with

```markdown
10. Copies this repo to `/mnt/home/<user>/.dotfiles`, where `<user>` is the host's `krane.user.name` (`krane` on the three original hosts).
11. Sets that user's password. This always runs, even under `--yes`.
```

Insert before `## Flags` (line 73):

````markdown
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
    - Keyboard layout and variant, default `at` / `nodeadkeys`.
3. Disk selection and the typed wipe confirmation work as usual. Nothing is written to the repo before that confirmation, so aborting earlier leaves the checkout untouched.
4. `install.sh` renders `templates/host/` into `hosts/<name>/` (`default.nix`, `disko.nix`, `display.nix`, and a placeholder `hardware-configuration.nix`) and parse-checks every file. It then adds `age1PLACEHOLDER_*` recipients for the host to `.sops.yaml`. If rendering or parsing fails, it removes `hosts/<name>/` again and restores `.sops.yaml`. After that the normal flow runs: disko, hardware config, PRIME bus IDs (`intel-nvidia-prime` only), one local commit `Add <name> host`, and `nixos-install`.
5. The new host exists only as that local commit in `~/.dotfiles` on the new machine. After first boot, run setup mode as usual (it bootstraps the host's sops recipients), then push the branch from there.
6. `display.nix` starts with one catch-all `preferred` monitor rule, because the live ISO runs no Hyprland to detect outputs. After first login, check `hyprctl monitors -j` and name the real outputs.

Non-interactively:

```sh
./install.sh --new-host newbox --user alice --profile amd-igpu --form-factor laptop \
    --disk /dev/disk/by-id/<disk> --yes --confirm-wipe
```

`--yes --new-host` requires `--user`, `--profile` and `--form-factor`. `--git-name`, `--git-email`, `--kb-layout` and `--kb-variant` take the defaults above. All of these flags are usage errors without `--new-host` or outside install mode.

To check the templates without a machine, commit your change and run `just check-new-host`. It needs local Nix. It scaffolds a throwaway `testhost` for each GPU profile × form factor in a temporary git worktree, and checks that each one is nixfmt-clean and evaluates.

````

Flags table (lines 75-84): replace the `--host` row with the first line below, add the next eight rows after it, and replace the `--yes` row with the last line:

```markdown
| `--host HOST` | One of the directories under `hosts/`. |
| `--new-host NAME` | Install mode only: create `hosts/NAME` from `templates/host/`. See "Installing a new machine". |
| `--user NAME` | New host's login user, default `krane`. |
| `--git-name NAME` | New host's git `user.name`, default: the login user. |
| `--git-email EMAIL` | New host's git `user.email`, default `chris@krane.dev`. |
| `--profile PROFILE` | New host's GPU profile: `amd-igpu`, `intel-igpu`, `nvidia-desktop`, `intel-nvidia-prime`. |
| `--form-factor FF` | New host's form factor: `laptop` or `desktop`. |
| `--kb-layout LAYOUT` | New host's keyboard layout, default `at`. |
| `--kb-variant VARIANT` | New host's keyboard variant, default `nodeadkeys`. |
| `-y`, `--yes` | Auto-confirm every prompt. Never skips setting the login user's password. |
```

Line 86: replace ``--host`/`--disk` are required alongside `--yes`/`--dry-run`: neither mode falls back to an interactive prompt once prompts are off.`` with:

```markdown
`--host` (or `--new-host` with `--user`, `--profile` and `--form-factor`) and `--disk` are required alongside `--yes`/`--dry-run`: neither mode falls back to an interactive prompt once prompts are off.
```

Line 94 (`--self-test` paragraph): replace `…and that the disko and PRIME sed helpers produce the expected line when run for real against a throwaway fixture.` with:

```markdown
…that the disko and PRIME sed helpers produce the expected line when run for real against a throwaway fixture, that every new-host template combination renders and parses, and that a failed new-host scaffold rolls back.
```

Appendix B, live mode: replace the `choose_host` and `choose_disk` bullet (line 291) with the first bullet below. Insert the second bullet after the `confirm_wipe_target` bullet (line 292), and the third after the `patch_disko` bullet (line 293). Replace the `commit_hardware_config` bullet (line 296) with the fourth, and the `finish_install` bullet (line 298) with the fifth:

```markdown
- `choose_host` and `choose_disk`: `gum choose` over `suggest_host`'s guess plus `+ new host`, and `lsblk`'s disk list, excluding the ISO's own device and offering a stable `/dev/disk/by-id` path. `+ new host` (or `--new-host`) runs `prompt_new_host`, which collects every answer first, pre-selecting `suggest_profile`'s GPU profile and form factor.
- `scaffold_host`, new hosts only: renders `templates/host/` into a staging dir, runs `nix-instantiate --parse` on each file, copies it to `hosts/<name>/`, and adds the host's placeholders to `.sops.yaml` (`register_sops_host`). A failure before that finishes rolls both back from `on_exit`. Under `--dry-run` only the staging dir is written, and `patch_disko`/`patch_prime` patch that copy.
- `resolve_install_user`: after `git add -A`, reads the login user from `nix eval …#nixosConfigurations.$HOST.config.krane.user.name`, or from the prompt for a new host under `--dry-run`.
- `commit_hardware_config`: commits (`Add <name> host` for a new host) with a throwaway `<user>@localhost` identity if none is already configured.
- `finish_install`: copies the repo to `/mnt/home/<user>/.dotfiles`, chowns it, verifies `flake.nix` landed, sets the user's password, warns that a new host is only a local commit, and offers a reboot.
```

Setup mode: replace the `preflight_setup` bullet (line 302) with:

```markdown
- `preflight_setup`: refuses to run as root, requires `git just sops age ssh-to-age`, and dies when the host (`--host` or `hostname`) is not under `hosts/`.
```

`README.md`:
- Line 6: replace `A declarative NixOS + Hyprland flake for three hosts.` with `A declarative NixOS + Hyprland flake for three hosts, plus any new machine `install.sh` scaffolds from `templates/host/`.`
- Line 26: replace `evaluates the flake and dry-run-builds all three hosts' toplevel` with `evaluates the flake and dry-run-builds every host's toplevel`.
- Layout block: after the `hosts/<host>/ …` line (line 49), add `templates/host/               new-host templates install.sh renders into hosts/<name>/`.
- Line 64: replace ``- `modules/home/git.nix` bakes in the git identity `krane <chris@krane.dev>`.`` with ``- `modules/nixos/user.nix` defaults the git identity to `krane <chris@krane.dev>`; each host can override it through `krane.user`.``
- Line 67: replace ``- The username `krane`, hardcoded throughout.`` with ``- The default username `krane` (`krane.user.name`, overridable per host).``
- Line 77: replace ``- The username `krane` in `modules/nixos/users.nix`, `lib/mk-host.nix`, `modules/home/default.nix`, `modules/nixos/nix-settings.nix`, `modules/nixos/sops.nix`, and `install.sh`.`` with ``- The default username and git identity in `modules/nixos/user.nix`, or set `krane.user` per host. `./install.sh`'s new-host flow asks for both.``

- [ ] **Step 5: Run the recipe, watch it pass**

Commit first, since the script tests HEAD:

```bash
/etc/profiles/per-user/krane/bin/git add justfile scripts/check-new-host.sh scripts/docker-check.sh docs/INSTALL.md README.md
/etc/profiles/per-user/krane/bin/git commit -m "Add just check-new-host and document installing a new machine"
```

Run: `just check-new-host; echo rc=$?`
Expected: PASS. Eight `ok   <profile>/<ff>  /nix/store/…-nixos-system-testhost-….drv` lines, then `check-new-host: all 4x2 combinations evaluate`, then `rc=0`. It takes several minutes. Afterwards `/etc/profiles/per-user/krane/bin/git worktree list` shows no leftover `check-new-host.*` worktree.

If a combination fails, fix the template or the Nix module and amend the fix into this task's commit, or into the owning task's commit if it predates Task 10. If only `nixfmt --check` fails, apply the diff that `nixfmt` prints to the template text itself. Re-run until it passes.

Run: `shellcheck -x -S style scripts/check-new-host.sh scripts/docker-check.sh`
Expected: no output.

---

### Task 11: Final verification

**Files:**
- Test only. No planned changes. If something fails, fix it in the task that owns it and add a fix-up commit.

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: install.sh self-tests and lint**

Run each command, one at a time:
- `bash -n install.sh`
- `bash install.sh --self-test`
- `bash install.sh --self-test-check-disko-sed`
- `bash install.sh --self-test-check-prime-sed`
- `bash install.sh --self-test-check-scaffold`
- `shellcheck -x -S style install.sh scripts/bootstrap-sops.sh scripts/docker-check.sh scripts/check-new-host.sh scripts/proton-drive-rclone-mount.sh scripts/update-claude-code.sh`

Expected: `bash -n` prints nothing. The self-test prints `self-test: all checks passed`, and the three hooks print `… OK`. shellcheck prints nothing.

- [ ] **Step 2: drvPath invariant**

Run the Task 1 Step 2 command with `> /tmp/install-new-host-after.txt`, then `diff /tmp/install-new-host-baseline.txt /tmp/install-new-host-after.txt`.
Expected: no output.

- [ ] **Step 3: The CI gate, locally**

Run each command:
- `nix fmt -- --ci`
- `nix shell --inputs-from . nixpkgs#statix -c statix check .`
- `nix shell --inputs-from . nixpkgs#deadnix -c deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .`
- `nix build --no-link .#checks.x86_64-linux.lua-syntax .#checks.x86_64-linux.user-option`
- `nix flake check --no-build`

Expected: all exit 0. `flake check` prints only the existing `swww` rename warnings.

- [ ] **Step 4: Dry-runs and the new-host recipe**

Run: `just check-new-host` (expected: `check-new-host: all 4x2 combinations evaluate`).
If Docker is available, run `just install-lint`. Expected: it exits 0 and reports no `git state changed` error, which covers the four `--dry-run` runs, including the new-host one.
Without Docker, run the four `./install.sh … --dry-run` lines from `scripts/docker-check.sh`'s `shellcheck)` arm directly and compare `git status --porcelain` before and after. Expected: every run exits 0, and the status is identical.

- [ ] **Step 5: Tree and log state**

Run: `/etc/profiles/per-user/krane/bin/git status --porcelain` and `/etc/profiles/per-user/krane/bin/git log --oneline 4c96cbf..HEAD`
Expected: a clean tree. The log holds the plan commit plus one commit each for Tasks 2-10, all with subject-only messages and no attribution lines. Nothing has been pushed.

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| Decisions: install mode only; setup-mode guard | 6 (`--new-host` rejected outside install), 9 |
| Decisions: per-host username, git identity; auto-discovery; `@TOKEN@` templates | 2, 3, 4 |
| Part 1: `modules/nixos/user.nix` | 2 |
| Part 1: consumers table (users, desktop, nix-settings, sops, mk-host, hosts, vm-overrides, home default, git) plus `git grep` sweep (peripherals comment, flake lua-syntax) | 2 |
| Part 1: host discovery, delete list/`hostDirs`/`throwIf`, keep `tariognatha-vm`, "mirrors" comments | 3 |
| Part 1: drvPath invariant | 1, 2, 3, 4, 11 |
| Part 2: `templates/host/` default/disko/display/profiles/form-factors | 4 |
| Part 2: GPU profiles, form factors | 4 |
| Part 2: detection `suggest_profile`, pre-selected menus | 6, 7 |
| Part 3: `+ new host` menu, `--new-host NAME` | 6, 7 |
| Part 3: order (prompts → disk → confirm → scaffold → existing flow) | 7 |
| Part 3: `prompt_new_host` validation rules and defaults | 6, 7 |
| Part 3: `scaffold_host` sed escaping, parse check, `.sops.yaml` awk insert and idempotence, no `secrets/<name>.yaml` | 4, 5, 7 |
| Part 3: `commit_hardware_config` also commits the new host | 7 (staged by `git add -A`), 8 (message) |
| Part 3: `INSTALL_USER` via `nix eval`, dry-run fallback, `set_user_password`, copy/chown/check/messages, `<user>@localhost`, bootstrap-sops message | 8 |
| Part 3: end-of-run push warning | 8 |
| Part 3: non-interactive flag rules | 6 |
| Error handling: re-prompt / usage error; rollback on render/parse failure; later failures keep the host | 6, 7 |
| Testing: drvPath invariant | 1, 2, 3, 4, 11 |
| Testing: `--self-test-check-scaffold` (8 combos parse, sops idempotence and detection, PRIME regex) | 4, 5 |
| Testing: `just check-new-host` | 10 |
| Testing: existing self-tests keep passing | 4-9 (each runs `--self-test`), 11 |
| Docs: "Installing a new machine", README wording | 10 |

Additions beyond the spec, each tied to a real constraint:
- `checks.user-option` (Task 2). It is a durable, CI-run proof that overriding `krane.user` moves every consumer. `nix eval` value checks are not available to agents in this session.
- `templates/host/hardware-configuration.nix.in` stub (Task 4). `run_disko` evaluates the host before `generate_hardware_config` runs, and a missing import would fail that evaluation.
- Hostname must not end in `-` (Task 6). NixOS's `networking.hostName` type rejects it.
- The hidden `--self-test-scaffold` hook (Task 7). It lets `just check-new-host` and the rollback self-test drive the real `scaffold_host`.
- A fourth `install-lint` dry-run (Task 10).
