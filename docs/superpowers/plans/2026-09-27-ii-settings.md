# ii Settings Pages (sub-project 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the end4-pC settings pages into the pinned ii so that every control either persists into a reviewable file under `~/.dotfiles` and survives switches and reboots, or is removed with the reason recorded.

**Architecture:** The QML port is a `git format-patch` series, `patches/ii/05-settings/`, stacked after 01–04 on the clone's `krane` branch and applied by sub-project 1's `iiSeries` loader. config.json-only pages persist through a directory symlink from `~/.config/illogical-impulse` into `hosts/<host>/illogical-impulse/`. Hyprland options, idle, animation presets and monitor fields persist in `hosts/<host>/ii-settings.json`. That file is owned by a standard-library Python writer, `pkgs/krane-ii-settings`, which Nix also uses at build time to render `custom/krane_gui.lua`. One ownership rule, checked at eval time, keeps Nix and the GUI from both setting a key.

**Tech Stack:** Nix flakes, home-manager, nixpkgs `applyPatches` and `writers.writePython3Bin`, git (`format-patch`, `am -3`, `rerere`), Quickshell QML, Python 3 (standard library only), Lua 5.4 (`luac -p`), Hyprland 0.56.2 Lua config.

**Spec:** `docs/superpowers/specs/2026-09-27-ii-settings-design.md`. Sub-project 1's plan, `docs/superpowers/plans/2026-09-27-ii-fork-fixes.md`, defines the clone, the `iiSeries` loader and the workflow this plan reuses unchanged.

## Global Constraints

- Run every shell block with `bash` (the interactive shell is fish). Use `command cat`, never bare `cat`.
- Pinned dots-hyprland revision: `PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)` (currently `97c5bc651f68092351b24aaa935af708b1e04514`). Hyprland is 0.56.2.
- Fork source: pctrade/end4-pC at `dc2ca2600ee6d7852bf0ac91361db8e510f90a74` (short `dc2ca2600ee6`), fetched as raw files. Fork paths are relative to the ii root. Every fetch in this plan uses these variables:
  ```bash
  FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74
  F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
  II=~/src/dots-hyprland/dots/.config/quickshell/ii
  ```
  A fork page `modules/ii/settings/pages/<Page>.qml` goes to `$II/modules/settings/<Page>.qml`. `gh` is not installed; use `curl`.
- Clone: `~/src/dots-hyprland`, branch `krane`, `git rerere` on. Sub-projects 1 to 4 have landed: tags `krane/01-fixes` to `krane/04-agents` exist and `patches/ii/01-fixes` to `patches/ii/04-agents` are committed. This plan's commits go after `krane/04-agents`. The end of the series is tagged `krane/05-settings`.
- Export command, always exactly:
  ```bash
  mkdir -p ~/.dotfiles/patches/ii/05-settings
  git -C ~/src/dots-hyprland tag -f krane/05-settings krane
  rm -f ~/.dotfiles/patches/ii/05-settings/*.patch && git -C ~/src/dots-hyprland format-patch --zero-commit --no-signature --no-numbered -o ~/.dotfiles/patches/ii/05-settings krane/04-agents..krane/05-settings
  git -C ~/.dotfiles add patches/ii/05-settings
  ```
  Flakes only see git-tracked files, so the `git add` is part of every export.
- Clone commit messages (subject in conventional-commit style, like sub-project 1):
  ```
  <subject>

  Port of pctrade/end4-pC dc2ca2600ee6: <fork path(s), or "none (krane-only)">
  https://github.com/pctrade/end4-pC/tree/dc2ca2600ee6d7852bf0ac91361db8e510f90a74
  Problem: <one or two lines>
  Port: clean | hand-ported (<what was dropped or adapted>) | krane-only
  Drop when: <concrete condition>
  ```
- A script fetched with `curl` has no exec bit. `chmod +x` every `.py` and `.sh` before committing it in the clone, so the patch records mode 100755.
- Dotfiles commits: subject line only, no body, no attribution lines. Never push, never open a PR. Commits follow the spec's "Commits" section, so tasks stage (`git add`) and only the tasks that end a commit group commit. **The executor never commits a `config.json`**: that is the user's own commit, after their privacy review (Task 11).
- Porting rule (spec): a control is ported only if the feature it configures exists at the pin plus 01–04. Otherwise the control is removed and recorded as "fork-only feature" in the docs table (Task 25). In practice: a control whose `Config.options.*` key, type or service member `forkcheck.py` reports as missing is removed, unless a task below ports that key on purpose.
- `Config.qml`: add no key that exists after `04-agents` (no second declaration of `dock.*` or `sidebar.agents`), do not touch `sidebar.translator.enable`'s default, and never edit the `property bool launchOnStartup: false` line (the `launchOnStartup` sed in `iiPatches` matches it exactly).
- The replacement Interface page keeps the "Enable translator" switch and all eight Dock switches.
- Hyprland keys the GUI may write are exactly those in `pkgs/krane-ii-settings/schema.json`, each checked against Hyprland 0.56.2's source (`src/config/values/ConfigValues.cpp`, and `src/config/lua/bindings/LuaBindingsConfigRules.cpp` for `hl.monitor` fields). Unknown keys are hard errors at Hyprland start.
- No Niri code paths. Hosts: tariognatha first, then tarmantria. taractias checks wait until its hardware is verified.
- Scratch work: `mktemp -d -p "$XDG_RUNTIME_DIR"`. Porting tools that must survive a logout live in `~/src/ii-tools/` (outside both repos, never committed).

### Checking the built source

Prints the patched ii source path Nix built for tariognatha (same block as sub-project 1):

```bash
cd ~/.dotfiles
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.config.home-manager.users.krane.home.activationPackage)
iisrc=$(grep -rhoE '/nix/store/[a-z0-9]{32}-dots-hyprland-[a-z-]+' "$gen" | sort -u | head -1)
echo "$iisrc"
```

A clone file is in the build when `diff -q "$iisrc/<path>" ~/src/dots-hyprland/<path>` prints nothing, where `<path>` starts with `dots/`.

### Smoke-running the settings window from the clone

The settings window can run straight from the clone, without a switch. `XDG_CONFIG_HOME` points at a throwaway copy of the config dir so a page never writes the real (repo-backed) `config.json`. `II_SETTINGS_PAGE` (added in Task 3) picks the page. Define these once per shell:

```bash
II=~/src/dots-hyprland/dots/.config/quickshell/ii
smoke() {  # usage: smoke <PageFileNameWithoutQml> <logfile>
  local sb; sb=$(mktemp -d -p "$XDG_RUNTIME_DIR")
  mkdir -p "$sb/config"
  command cp -rL ~/.config/illogical-impulse "$sb/config/illogical-impulse"
  ln -s ~/.config/hypr "$sb/config/hypr"
  XDG_CONFIG_HOME="$sb/config" II_SETTINGS_PAGE="$1" timeout 12 qs -p "$II/settings.qml" > "$2" 2>&1
  rm -rf "$sb"
}
# QML problems in a log, with file line numbers stripped so logs from different revisions compare.
qmlerrs() {
  grep -E 'ERROR|WARN|TypeError|ReferenceError|is not a type|Cannot assign|non-existent|is not defined' "$1" \
    | sed -E 's#file://[^ ]*/quickshell/ii/##g; s#:[0-9]+(:[0-9]+)?##g; s#^[^A-Za-z]*##' | sort -u
}
# New QML problems in <log> compared with the baseline for the same page.
newerrs() { comm -13 <(qmlerrs ~/src/ii-tools/baseline/"$1".log) <(qmlerrs "$2"); }
```

`timeout` ends the window after 12 s (exit status 124 is expected). A page counts as clean when `newerrs <Page> <log>` prints nothing and the log contains `[settings] initial page: modules/settings/<Page>.qml`.

## Review Focus

1. **`krane-ii-settings` missing from qs's PATH** (a shell started before the switch that installed it). Expected: the Hyprland page says persistent settings are unavailable and `qs log` has one `[KraneSettings]` warning; nothing fails silently. Test: Task 19, Step 6.
2. **Repo not checked out at `krane.dotfilesDir`.** Expected: with an existing real `~/.config/illogical-impulse`, activation fails before changing anything and names the path. Without one (the VM check target), it warns and ii runs on its defaults. Test: Task 2, Step 5 (`migtest.sh`).
3. **A dragged slider firing many writes.** Expected: the repo file is valid JSON after every write and ends on the last value. Test: Task 13, Step 5 (20 concurrent writers) and the queue coalescing in `KraneSettings.qml` (Task 17).
4. **`hyprctl getoption` value shapes.** `general:gaps_in` comes back as the CSS string `"4 4 4 4"`, booleans as `true`/`false`. Expected: the controls show the live numbers and switch states, not `NaN` or unchecked. Test: Task 20, Step 5.
5. **A fresh host with an empty repo config dir** (assumed decision 1). Expected: ii writes `config.json` from its QML defaults through the symlink into the repo dir, and the directory stays a symlink. Test: Task 2, Step 7.

## Assumed decisions

These were not settled by the spec or the resolved decisions. Each is the smallest reading of the spec; change it before executing if it is wrong.

1. **Fresh host config.json comes from ii's QML defaults (confirmed by the user).** `hosts/<host>/illogical-impulse/` starts with only `.gitignore`. On first start ii writes `config.json` from `Config.qml` defaults (with the `launchOnStartup` sed applied) into the repo dir. Nothing is seeded from another host. The user reviews and commits it like any other host's (Task 11).
2. **The schema is a JSON file in the repo** (`pkgs/krane-ii-settings/schema.json`), read by Nix with `lib.importJSON` and by the writer at runtime. The spec has the writer dump its schema at build time; reading build output during evaluation would be import-from-derivation. One list, no IFD.
3. **Border colors stay at the fork's config.json path**, `hyprland.general.borderColor.*`, not `hyprland.borderColor` as the spec's table abbreviates it, so the fork's page code needs no edit.
4. **Boot-check timeout removes the whole unconfirmed `monitors.<output>` entry** (the spec says "the unconfirmed fields"; the file does not record which fields the last kept change touched). Unlock is detected through a new `isLocked()` function on ii's `lock` IPC handler.
5. **The writer locks with `flock(2)` through Python's `fcntl`**, on the spec's lock file, instead of calling the `flock` binary.
6. **Commits are grouped as the spec's "Commits" section lists them**, not one per task.
7. **`settings.qml` gains an `II_SETTINGS_PAGE` start-page variable and one `console.info` line**, used by `boot-check` and the smoke tests.
8. **`presets/` in the config dir is tracked**, like `actions/`. Local presets are copies of config.json, so the privacy review covers them.
9. **About's data:** the pin revision and patch count are written into `krane-build.json` by `applyPatches`' `postPatch`; the dotfiles path is read at runtime from the config-dir symlink. The fork's Packages and Updates cards are dropped (pacman-only).
10. **Monitor resets are immediate**, without confirm-or-revert. `reset` only returns a field to its Nix or Hyprland default. Only `set` goes through `try`.

## File structure

| Path | Responsibility |
|---|---|
| `modules/home/ii-config-dir.nix` (new) | `krane.dotfilesDir`, the `~/.config/illogical-impulse` symlink, the `kraneIiConfigMigrate` entry |
| `hosts/<host>/illogical-impulse/.gitignore` (new, ×3) | makes the per-host config dir exist in git, ignores `*.tmp` and `ai/` |
| `pkgs/krane-ii-settings/` (new) | the writer: `krane_ii_settings.py`, `schema.json`, `default.nix`, `tests/` |
| `hosts/<host>/ii-settings.json` (new, ×3) | GUI-owned sparse deltas, committed as `{}` |
| `modules/home/ii-settings.nix` (new) | manifest, host wrapper, build-time render into `custom/krane_gui.lua`, ownership assertions, idle activation, boot-check exec |
| `modules/home/hypr-config.nix` | `monitors.lua` trailer, `_rendered` no longer read-only, `krane.hypr.idle`, new monitor fields |
| `modules/home/illogical-impulse.nix` | `custom/krane_gui.lua` is owned; the hypridle sed entry goes |
| `lib/mk-host.nix` | `postPatch` writes `krane-build.json` for the About page |
| `flake.nix`, `pkgs/default.nix` | checks `ii-settings-writer` and `ii-settings-render`; package output |
| `patches/ii/05-settings/*.patch` (generated) | the ii side, one patch per hot file and per page |
| `docs/II-INTEGRATION.md`, `docs/VERIFY.md` | "Settings persistence", ported and dropped control table, per-page checks |

Phase A estimate: 5 working sessions (Tasks 1–11). Task 1 records the start. If Phase A takes more than 10 sessions, stop after Task 11 and re-scope Phases B and C with the user (spec, "Prerequisites and effort").

---

## Phase A: shell and config.json-only pages

### Task 1: Preflight and porting tools

Checks the prerequisites and installs the porting checker outside the repos.

**Files:**
- Create: `~/src/ii-tools/forkcheck.py`, `~/src/ii-tools/fork-files.txt`, `~/src/ii-tools/baseline/forkcheck.txt`, `~/src/ii-tools/phase-a-start` (not in any repo)

**Interfaces:**
- Produces: `forkcheck.py <ii-root> <file>...`, which prints one `path:line: kind: detail` per finding (`config`, `type`, `global`, `member`, `pattern`) and exits 1 when there are any. `~/src/ii-tools/baseline/forkcheck.txt`, the clone's own findings before any 05 change.

- [ ] **Step 1: Check the prerequisites**

```bash
cd ~/src/dots-hyprland
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
git status --short | head -5
echo "branch: $(git rev-parse --abbrev-ref HEAD)"
for t in krane/01-fixes krane/02-translator krane/03-dock krane/04-agents; do
  git rev-parse -q --verify "refs/tags/$t" >/dev/null && echo "ok $t" || echo "MISSING $t"
done
git merge-base --is-ancestor "$PIN" krane && echo "ok based on the pin"
[ "$(git rev-parse krane)" = "$(git rev-parse krane/04-agents)" ] && echo "ok nothing after 04-agents"
echo "rerere: $(git config rerere.enabled)"
command ls ~/.dotfiles/patches/ii/
```

Expected: a clean tree, `branch: krane`, four `ok` tags, both `ok` lines, `rerere: true`, and `01-fixes 02-translator 03-dock 04-agents`. If anything differs, stop and report: the spec makes sub-project 1 a hard prerequisite, and this plan assumes 2 to 4 have landed too.

Then ask the user to confirm that sub-project 1's workflow has been through at least one pin bump on the hosts (spec, "Prerequisites and effort"). Stop if not.

- [ ] **Step 2: Record the Phase A start**

```bash
mkdir -p ~/src/ii-tools/baseline
date -Is > ~/src/ii-tools/phase-a-start
```

- [ ] **Step 3: Install the fork file list**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74
curl -sfL "https://api.github.com/repos/pctrade/end4-pC/git/trees/$FORK?recursive=1" \
  | jq -r '.tree[] | select(.type=="blob") | .path' | grep -E '\.(qml|js)$' > ~/src/ii-tools/fork-files.txt
wc -l < ~/src/ii-tools/fork-files.txt
```

Expected: `574`.

- [ ] **Step 4: Write `~/src/ii-tools/forkcheck.py`**

```python
#!/usr/bin/env python3
"""Check ported QML against the clone it is being ported into.

usage: forkcheck.py <ii-root> <file>...

Reports, and exits 1 if any are found:
  config   Config.options.<path> not declared in <ii-root>/modules/common/Config.qml
  type     a type name that is a .qml/.js file in the end4-pC tree but not in <ii-root>
  global   GlobalStates.<member> not declared in <ii-root>/GlobalStates.qml
  member   <Service>.<member> for a singleton in <ii-root>/services that does not declare it
  pattern  a construct that cannot work on this setup (see FORBIDDEN)
"""
import pathlib
import re
import sys

TOOLS = pathlib.Path(__file__).resolve().parent
FORK_FILES = TOOLS / "fork-files.txt"

FORBIDDEN = {
    r"\bWM\.": "fork WM abstraction: Hyprland is the only compositor, make the check constant",
    r"settingsOpen": "fork panel-family settings: use Qt.quit() in the standalone window",
    r"settings\.style": "settings.style is dropped (standalone window only)",
    r"\"python3\"": "call scripts directly; their venv shebang picks the interpreter",
    r"/tmp/": "use $XDG_RUNTIME_DIR, /tmp is not cleared at boot here",
    r"\byay\b|pacman -S|git clone": "system/dots update buttons are out of scope",
    r"hostnamectl": "hostname is owned by networking.hostName; show it read-only",
    r"\bcurl\b": "no network fetches from settings (online presets are out of scope)",
    r"monitors\.lua": "monitors.lua is owned by krane.hypr.monitors; use krane-ii-settings",
    r"hypr/hyprlock\.conf": "hyprlock.conf is synced at runtime by shell.qml, not by pages",
}


def strip(line):
    line = re.sub(r'"(?:\\.|[^"\\])*"|`[^`]*`', '""', line)
    return line.split("//")[0]


def config_paths(qml):
    paths, objects, frames, depth, inside = set(), set(), [], 0, False
    for raw in pathlib.Path(qml).read_text().splitlines():
        s = strip(raw)
        if not inside:
            if re.match(r"\s*JsonAdapter\s*\{", s):
                inside, depth, frames = True, 1, [("", 0)]
            continue
        m = re.match(r"\s*(?:readonly\s+)?property\s+JsonObject\s+(\w+)\s*:\s*JsonObject\s*\{", s)
        if m:
            frames.append((m.group(1), depth))
            name = ".".join(f[0] for f in frames[1:])
            paths.add(name)
            objects.add(name)
        else:
            m = re.match(r"\s*(?:readonly\s+)?property\s+[\w<>.]+\s+(\w+)\s*:", s)
            if m:
                paths.add(".".join([f[0] for f in frames[1:]] + [m.group(1)]))
        depth += s.count("{") - s.count("}")
        while len(frames) > 1 and depth <= frames[-1][1]:
            frames.pop()
        if depth <= 0:
            break
    return paths, paths - objects


def declared_members(qml):
    text = pathlib.Path(qml).read_text()
    return set(re.findall(r"\bproperty\s+[\w<>.]+\s+(\w+)", text)) | set(
        re.findall(r"\bfunction\s+(\w+)", text)) | set(re.findall(r"\bsignal\s+(\w+)", text))


def main():
    root = pathlib.Path(sys.argv[1])
    files = [pathlib.Path(f) for f in sys.argv[2:]]
    cfg, leaves = config_paths(root / "modules/common/Config.qml")
    globals_ = declared_members(root / "GlobalStates.qml")
    services = {p.stem: declared_members(p) for p in (root / "services").glob("*.qml")}
    ours = {p.stem for p in root.rglob("*.qml")} | {p.stem for p in root.rglob("*.js")}
    fork = {pathlib.Path(l.strip()).stem for l in FORK_FILES.read_text().splitlines() if l.strip()}
    fork_only = fork - ours
    findings = []
    for f in files:
        text = f.read_text()
        for n, raw in enumerate(text.splitlines(), 1):
            code = strip(raw)
            for m in re.finditer(r"Config\.options\??\.([A-Za-z_]\w*(?:\??\.[A-Za-z_]\w*)*)", raw):
                p = m.group(1).replace("?", "")
                parts = p.split(".")
                if p not in cfg and not any(".".join(parts[:i]) in leaves for i in range(1, len(parts))):
                    findings.append((f, n, "config", p))
            for t in set(re.findall(r"\b([A-Z][A-Za-z0-9]+)\b", code)) & fork_only:
                findings.append((f, n, "type", t))
            for g in re.findall(r"\bGlobalStates\.(\w+)", code):
                if g not in globals_:
                    findings.append((f, n, "global", g))
            for svc, member in re.findall(r"\b([A-Z]\w+)\.([a-z]\w*)", code):
                if svc in services and member not in services[svc]:
                    findings.append((f, n, "member", f"{svc}.{member}"))
            for pat, why in FORBIDDEN.items():
                if re.search(pat, raw):
                    findings.append((f, n, "pattern", why))
    for f, n, kind, what in findings:
        print(f"{f}:{n}: {kind}: {what}")
    print(f"# {len(findings)} findings in {len(files)} files", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Check the tool against known inputs**

```bash
S=/nix/store/xwkyskh3ylwwbhvff97z8jivcxmnbcg8-source/dots/.config/quickshell/ii
python3 ~/src/ii-tools/forkcheck.py "$S" "$S"/modules/settings/*.qml; echo "exit $?"
```

Expected: exactly 7 findings (5 `config: notifications.forceMonitor.*` in `InterfaceConfig.qml`, a real upstream gap, and 2 `pattern: hyprlock.conf ...` in `GeneralConfig.qml`) and `exit 1`. Then a fork page:

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); curl -sfL "$F/modules/ii/settings/pages/About.qml" -o "$t/About.qml"
python3 ~/src/ii-tools/forkcheck.py "$S" "$t/About.qml" | cut -d: -f3 | sort | uniq -c; rm -rf "$t"
```

Expected: nonzero counts for `config`, `global`, `member`, `pattern` and `type` (AboutCard).

- [ ] **Step 6: Record the clone's own baseline**

```bash
II=~/src/dots-hyprland/dots/.config/quickshell/ii
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/*.qml > ~/src/ii-tools/baseline/forkcheck.txt
command cat ~/src/ii-tools/baseline/forkcheck.txt
```

Expected: the same 7 findings as Step 5, unless 02–04 changed those pages. Any `dock.*` or `sidebar.translator` finding means 02 or 03 did not land as assumed: stop and report.

No commit.

---

### Task 2: The config directory in the repo

`~/.config/illogical-impulse` becomes a symlink to `hosts/<host>/illogical-impulse`, with a migration entry that copies an existing real directory into the repo first.

**Files:**
- Create: `modules/home/ii-config-dir.nix`
- Create: `hosts/tariognatha/illogical-impulse/.gitignore`, `hosts/tarmantria/illogical-impulse/.gitignore`, `hosts/taractias/illogical-impulse/.gitignore`
- Modify: `modules/home/default.nix` (imports list)
- Create (tool, not committed): `~/src/ii-tools/migtest.sh`

**Interfaces:**
- Produces: option `krane.dotfilesDir` (str, default `"${config.home.homeDirectory}/.dotfiles"`), used by `modules/home/ii-settings.nix` (Task 15). Activation entry `kraneIiConfigMigrate` (before `writeBoundary`).

- [ ] **Step 1: Show the link does not exist yet (failing check)**

```bash
cd ~/.dotfiles
nix eval --json .#nixosConfigurations.tariognatha.config.home-manager.users.krane.home.file --apply 'f: f ? ".config/illogical-impulse"'
```

Expected: `false`.

- [ ] **Step 2: Write `modules/home/ii-config-dir.nix`**

```nix
# ~/.config/illogical-impulse (ii's config.json, actions/ and presets/) lives in this repo, one
# directory per host, so settings changed in the ii settings window can be reviewed and committed.
# The directory is linked, not the file: switchwall.sh rewrites config.json with
# `jq ... > config.json.tmp && mv config.json.tmp config.json`, which would replace a file symlink
# with a regular file on every wallpaper change. Nix never reads config.json.
# See docs/II-INTEGRATION.md "Settings persistence".
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  target = "${config.home.homeDirectory}/.config/illogical-impulse";
  repoDir = "${config.krane.dotfilesDir}/hosts/${hostName}/illogical-impulse";
in
{
  options.krane.dotfilesDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/.dotfiles";
    description = ''
      Absolute path of this repo's checkout on the host. install.sh and
      modules/nixvim/options.nix already assume ~/.dotfiles. Settings the ii settings
      window persists are written under it, so it must be the live checkout.
    '';
  };

  config = {
    home.file.".config/illogical-impulse".source = config.lib.file.mkOutOfStoreSymlink repoDir;

    # Before writeBoundary, so it runs before home-manager changes anything (like
    # checkLinkTargets). linkGeneration then moves a real directory aside as
    # illogical-impulse.hm-bak (backupFileExtension in lib/mk-host.nix).
    home.activation.kraneIiConfigMigrate = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      src=${lib.escapeShellArg target}
      dst=${lib.escapeShellArg repoDir}
      if [ -d "$src" ] && [ ! -L "$src" ]; then
        if [ ! -d "$dst" ]; then
          echo "kraneIiConfigMigrate: $dst does not exist, so $src cannot be moved into the repo." >&2
          echo "Check out this repo at ${config.krane.dotfilesDir} (krane.dotfilesDir). Nothing was changed." >&2
          exit 1
        elif [ ! -e "$dst/config.json" ]; then
          echo "kraneIiConfigMigrate: copying $src into $dst"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -an "$src/." "$dst/"
        elif [ -e "$src/config.json" ] && ! ${pkgs.diffutils}/bin/cmp -s "$src/config.json" "$dst/config.json"; then
          echo "kraneIiConfigMigrate: $src/config.json and $dst/config.json differ." >&2
          echo "Keep one by hand (move the other away), then switch again. Nothing was changed." >&2
          exit 1
        fi
      elif [ ! -d "$dst" ]; then
        # The VM check target has no checkout. Create the directory anyway: a dangling link would
        # make the soymou copy step's `mkdir -p ~/.config/illogical-impulse` fail and abort the
        # whole activation (set -e). ii then runs on its defaults into this stub directory.
        echo "kraneIiConfigMigrate: warning: $dst does not exist; creating it. ii settings are not in a checkout until this repo is at ${config.krane.dotfilesDir}." >&2
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$dst"
      fi
    '';

    # The link must exist before the soymou copy step runs its `mkdir -p` and config.json seed
    # check through it. Both are entryAfter writeBoundary, so pin the order instead of relying on
    # the DAG's tie-breaking. A second definition of copyIllogicalImpulseConfigs cannot add an
    # `after` (hm's dagEntryOf would treat it as a conflicting str), so this empty entry sits
    # between the two, like kraneIiSaveFishVars in illogical-impulse.nix.
    home.activation.kraneIiConfigLinkFirst =
      lib.hm.dag.entryBetween [ "copyIllogicalImpulseConfigs" ] [ "linkGeneration" ]
        ":";
  };
}
```

- [ ] **Step 3: Add the per-host directories and the import**

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do
  mkdir -p hosts/$h/illogical-impulse
  printf '%s\n' '# Written by ii at runtime (a symlink from ~/.config/illogical-impulse); reviewed and committed by hand.' '# See docs/II-INTEGRATION.md "Settings persistence".' '*.tmp' 'ai/' > hosts/$h/illogical-impulse/.gitignore
done
```

In `modules/home/default.nix`, add the import right after `./illogical-impulse.nix`:

```nix
    ./illogical-impulse.nix
    ./ii-config-dir.nix
```

Then `git add modules/home/ii-config-dir.nix modules/home/default.nix hosts/*/illogical-impulse/.gitignore`.

- [ ] **Step 4: Check the link and the entry order (passing check)**

```bash
cd ~/.dotfiles
nix eval --json .#nixosConfigurations.tariognatha.config.home-manager.users.krane.home.file --apply 'f: f ? ".config/illogical-impulse"'
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.config.home-manager.users.krane.home.activationPackage)
readlink -f "$gen/home-files/.config/illogical-impulse"
grep -n 'Activating %s' "$gen/activate" | grep -E 'checkLinkTargets|kraneIiConfigMigrate|writeBoundary|linkGeneration|kraneIiConfigLinkFirst|copyIllogicalImpulseConfigs'
```

Expected: `true`; `/home/krane/.dotfiles/hosts/tariognatha/illogical-impulse`; and the six entries in the order `checkLinkTargets`, `kraneIiConfigMigrate`, `writeBoundary`, `linkGeneration`, `kraneIiConfigLinkFirst`, `copyIllogicalImpulseConfigs`. The last pair matters: the soymou copy step's `mkdir -p` must run after the link exists, or a fresh host gets a real directory that `linkGeneration` then has to move aside. The empty `kraneIiConfigLinkFirst` entry pins it (today's order already has it, by tie-breaking only). If the order differs, stop and report.

- [ ] **Step 5: Test the migration entry against scratch directories**

Write `~/src/ii-tools/migtest.sh`:

```bash
#!/usr/bin/env bash
# Runs the built kraneIiConfigMigrate entry against scratch directories.
# usage: migtest.sh <home-manager-generation>
set -u
gen="$1"
t=$(mktemp -d -p "$XDG_RUNTIME_DIR")
body=$(sed -n '/"Activating %s" "kraneIiConfigMigrate"/,/"Activating %s" "writeBoundary"/p' "$gen/activate" | sed '1d;$d')
body=${body//\/home\/krane\/.config\/illogical-impulse/$t\/src}
body=$(printf '%s' "$body" | sed -E "s#/home/krane/\.dotfiles/hosts/[a-z]+/illogical-impulse#$t/dst#g")
run() { ( DRY_RUN_CMD=""; eval "$body" ) >"$t/out" 2>&1; echo "$?"; }
reset() { rm -rf "$t/src" "$t/dst"; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected $3, got $2"; command cat "$t/out"; fail=1; fi; }

reset; mkdir -p "$t/src" "$t/dst"; echo '{"a":1}' > "$t/src/config.json"
check "copies a real dir into an empty repo dir" "$(run)" 0
check "  config.json arrived" "$(command cat "$t/dst/config.json")" '{"a":1}'

reset; mkdir -p "$t/src" "$t/dst"; echo '{"a":1}' > "$t/src/config.json"; echo '{"a":2}' > "$t/dst/config.json"
check "fails on differing config.json" "$(run)" 1
check "  repo copy untouched" "$(command cat "$t/dst/config.json")" '{"a":2}'

reset; mkdir -p "$t/src" "$t/dst"; echo '{"a":1}' > "$t/src/config.json"; echo '{"a":1}' > "$t/dst/config.json"
check "proceeds when identical" "$(run)" 0

reset; mkdir -p "$t/src"; echo '{"a":1}' > "$t/src/config.json"
check "fails when the repo dir is missing and a real dir exists" "$(run)" 1

reset
check "warns only when neither exists" "$(run)" 0
grep -q warning "$t/out" && echo "ok     warning printed" || { echo "FAIL no warning"; fail=1; }
test -d "$t/dst" && echo "ok     stub repo dir created (no dangling link)" || { echo "FAIL no stub dir"; fail=1; }

reset; mkdir -p "$t/dst"; ln -s "$t/dst" "$t/src"
check "no-op when already linked" "$(run)" 0

rm -rf "$t"
exit $fail
```

```bash
chmod +x ~/src/ii-tools/migtest.sh
~/src/ii-tools/migtest.sh "$gen"; echo "exit $?"
```

Expected: ten lines starting with `ok`, and `exit 0`. This covers Review Focus 2.

- [ ] **Step 6: Switch tarmantria first (migration host)**

On tarmantria, first check the conflict path. The entry exits before home-manager or the soymou copy step touch anything, so running the activation script directly is safe here:

```bash
cd ~/.dotfiles && git add hosts/tarmantria/illogical-impulse/.gitignore
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.tarmantria.config.home-manager.users.krane.home.activationPackage)
jq '.bar.weather.enableGPS = (.bar.weather.enableGPS | not)' ~/.config/illogical-impulse/config.json > hosts/tarmantria/illogical-impulse/config.json
HOME_MANAGER_BACKUP_EXT=hm-bak "$gen/activate"; echo "exit $?"
```

(`HOME_MANAGER_BACKUP_EXT` is what the NixOS module's `home-manager-krane.service` sets from `backupFileExtension`; without it `checkLinkTargets` refuses first, which proves nothing.) Run it a second time with `DRY_RUN=1` in front: the same message (the spec's dry-run check). Expected, both times: `kraneIiConfigMigrate: ... differ.` naming both paths, a nonzero exit, and `~/.config/illogical-impulse` still a real directory (`test ! -L ~/.config/illogical-impulse && echo REAL`). Then remove the conflicting copy and switch:

```bash
rm hosts/tarmantria/illogical-impulse/config.json
sudo nixos-rebuild switch --flake .#tarmantria
readlink -f ~/.config/illogical-impulse
test -d ~/.config/illogical-impulse.hm-bak && echo BACKUP
git -C ~/.dotfiles status --short hosts/tarmantria/illogical-impulse
journalctl -u home-manager-krane -b --no-pager | grep kraneIiConfigMigrate
```

Expected: `/home/krane/.dotfiles/hosts/tarmantria/illogical-impulse`, `BACKUP`, untracked `config.json` (and `actions/`, if it existed), and the `copying ... into ...` log line. Then on tariognatha: `sudo nixos-rebuild switch --flake .#tariognatha` and the same three checks with `tariognatha`.

- [ ] **Step 7: A fresh host writes its defaults through the link (Review Focus 5)**

```bash
sb=$(mktemp -d -p "$XDG_RUNTIME_DIR")
mkdir -p "$sb/repo/hosts/x/illogical-impulse" "$sb/config"
ln -s "$sb/repo/hosts/x/illogical-impulse" "$sb/config/illogical-impulse"
ln -s ~/.config/hypr "$sb/config/hypr"
XDG_CONFIG_HOME="$sb/config" timeout 12 qs -p ~/.config/quickshell/ii/settings.qml >/dev/null 2>&1
test -s "$sb/repo/hosts/x/illogical-impulse/config.json" && echo SEEDED
test -L "$sb/config/illogical-impulse" && echo STILL-LINK
jq -r '.lock.launchOnStartup' "$sb/repo/hosts/x/illogical-impulse/config.json"
rm -rf "$sb"
```

Expected: `SEEDED`, `STILL-LINK`, `true` (the QML default after the `launchOnStartup` sed).

- [ ] **Step 8: Wallpaper change keeps the link**

Change the wallpaper through ii's wallpaper selector, then:

```bash
test -L ~/.config/illogical-impulse && echo LINK
jq -r .background.wallpaperPath ~/.dotfiles/hosts/tariognatha/illogical-impulse/config.json
```

Expected: `LINK` and the path of the wallpaper just picked (switchwall.sh's `mv` happened inside the repo directory).

No commit (Phase A commits in Task 11).

---

### Task 3: `Config.qml` subset and the settings window start page

Two hot-file patches, each its own commit: the `Config.qml` keys the ported settings code itself reads (`settings.collapsedSections` for `ContentSection`, `profile.*` for the Profile page), and the `II_SETTINGS_PAGE` start page in `settings.qml`.

**Files:**
- Modify (clone): `dots/.config/quickshell/ii/modules/common/Config.qml`, `dots/.config/quickshell/ii/settings.qml`
- Create (tool output): `~/src/ii-tools/baseline/<Page>.log` ×8
- Create (generated): `patches/ii/05-settings/0001-*.patch`, `0002-*.patch`

**Interfaces:**
- Produces: `Config.options.settings.collapsedSections` (`list<string>`), `Config.options.profile.{avatarPath, avatarPicture, descriptionText, displayName}` (strings). `II_SETTINGS_PAGE=<Page>` opens `modules/settings/<Page>.qml` first and logs `[settings] initial page: modules/settings/<Page>.qml`.

- [ ] **Step 1: Show the keys are missing (failing check)**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
II=~/src/dots-hyprland/dots/.config/quickshell/ii
t=$(mktemp -d -p "$XDG_RUNTIME_DIR")
curl -sfL "$F/modules/common/widgets/ContentSection.qml" -o "$t/ContentSection.qml"
curl -sfL "$F/modules/ii/settings/pages/Profile.qml" -o "$t/Profile.qml"
python3 ~/src/ii-tools/forkcheck.py "$II" "$t"/*.qml | grep -E 'config: (settings\.collapsedSections|profile\.(avatarPath|avatarPicture|descriptionText|displayName))' | cut -d' ' -f3 | sort -u
```

Expected: `profile.avatarPath`, `profile.avatarPicture`, `profile.descriptionText`, `profile.displayName`, `settings.collapsedSections` and its `.includes`/`.slice` forms. Keep `$t`.

- [ ] **Step 2: Apply and commit the `Config.qml` subset**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/modules/common/Config.qml
+++ b/dots/.config/quickshell/ii/modules/common/Config.qml
@@ -80,6 +80,19 @@
 
             property string panelFamily: "ii" // "ii", "waffle"
 
+            // Settings window state (patches/ii/05-settings): sections the user collapsed.
+            property JsonObject settings: JsonObject {
+                property list<string> collapsedSections: []
+            }
+
+            // Settings window Profile page (patches/ii/05-settings).
+            property JsonObject profile: JsonObject {
+                property string avatarPath: ""
+                property string avatarPicture: ""
+                property string descriptionText: "::distro::"
+                property string displayName: ""
+            }
+
             property JsonObject policies: JsonObject {
                 property int ai: 1 // 0: No | 1: Yes | 2: Local
                 property int weeb: 1 // 0: No | 1: Open | 2: Closet
PATCH
git add -A
git commit -F - <<'MSG'
feat(settings): declare the config keys the ported settings code reads

Port of pctrade/end4-pC dc2ca2600ee6: modules/common/Config.qml (subset)
https://github.com/pctrade/end4-pC/tree/dc2ca2600ee6d7852bf0ac91361db8e510f90a74
Problem: the ported ContentSection stores collapsed sections in settings.collapsedSections, and the Profile page edits profile.*; neither exists at the pin.
Port: hand-ported. Only these two objects; settings.style/borderColor/borderSize (fork panel styling) and profile.onlinePresets (online presets) are dropped.
Drop when: the pinned Config.qml declares settings.collapsedSections and profile.displayName.
MSG
```

If `git apply` fails because 02–04 changed the lines around `panelFamily`, add the two objects by hand right after the `property string panelFamily` line, exactly as in the patch.

- [ ] **Step 3: Apply and commit the start page hook**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/settings.qml
+++ b/dots/.config/quickshell/ii/settings.qml
@@ -65,7 +65,10 @@
             component: "modules/settings/About.qml"
         }
     ]
-    property int currentPage: 0
+    // II_SETTINGS_PAGE=<page file name without .qml> opens that page first. Used by
+    // krane-ii-settings boot-check and for smoke-testing single pages.
+    readonly property int initialPage: Math.max(0, root.pages.findIndex(p => p.component.endsWith(`/${Quickshell.env("II_SETTINGS_PAGE")}.qml`)))
+    property int currentPage: initialPage
 
     visible: true
     onClosing: Qt.quit()
@@ -74,6 +77,7 @@
     Component.onCompleted: {
         MaterialThemeLoader.reapplyTheme()
         Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
+        console.info(`[settings] initial page: ${root.pages[root.currentPage].component}`)
     }
 
     minimumWidth: 750
@@ -240,7 +244,7 @@
 
                     active: Config.ready
                     Component.onCompleted: {
-                        source = root.pages[0].component
+                        source = root.pages[root.currentPage].component
                     }
 
                     Connections {
PATCH
git add -A
git commit -F - <<'MSG'
feat(settings): open the page named by II_SETTINGS_PAGE first

Port of pctrade/end4-pC dc2ca2600ee6: none (krane-only)
https://github.com/pctrade/end4-pC/tree/dc2ca2600ee6d7852bf0ac91361db8e510f90a74
Problem: krane-ii-settings boot-check must open the settings window on the Hyprland page, and page smoke tests need to start on one page.
Port: krane-only. Unset or unknown names open the first page, as before.
Drop when: the dotfiles repo no longer runs krane-ii-settings boot-check or the page smoke tests.
MSG
```

- [ ] **Step 4: Check the keys resolve (passing check)**

```bash
python3 ~/src/ii-tools/forkcheck.py "$II" "$t"/*.qml | grep -cE 'config: (settings\.collapsedSections|profile\.(avatarPath|avatarPicture|descriptionText|displayName))'
rm -rf "$t"
```

Expected: `0`.

- [ ] **Step 5: Record the baseline logs, one per upstream page**

Define `smoke`, `qmlerrs` and `newerrs` from "Smoke-running the settings window from the clone".

```bash
for p in QuickConfig GeneralConfig BarConfig BackgroundConfig InterfaceConfig ServicesConfig AdvancedConfig About; do
  smoke "$p" ~/src/ii-tools/baseline/"$p".log
  grep -c "\[settings\] initial page: modules/settings/$p.qml" ~/src/ii-tools/baseline/"$p".log
done
```

Expected: eight `1` lines. These logs are the pre-05 noise every later page run is compared against; they already include the two commits above, which touch no page.

- [ ] **Step 6: Export**

Run the export command from Global Constraints. Expected: `0001-feat-settings-declare-the-config-keys-the-ported-set.patch` and `0002-feat-settings-open-the-page-named-by-II_SETTINGS_PAGE.patch`.

---

### Task 4: Shared widgets changed by the fork

The fork's versions of shared widgets the pages rely on. `ContentPage`, `ContentSection` and `ConfigSelectionArray` are hot files: one commit each. The small ones share a commit.

**Files:**
- Modify (clone, under `$II/modules/common/widgets/`): `ContentPage.qml`, `ContentSection.qml`, `ConfigSelectionArray.qml`; small set: `ConfigSwitch.qml`, `ConfigSlider.qml`, `NoticeBox.qml`, `ContentSubsection.qml`, `StyledComboBox.qml`, `RippleButton.qml`, `MaterialShapeWrappedMaterialSymbol.qml`, `MaterialTextArea.qml`, `MaterialLoadingIndicator.qml`, `SelectionGroupButton.qml`, `ToolbarPairedFab.qml`
- Not touched: `ThumbnailImage.qml` (01-fixes owns it), `WaveVisualizer.qml` (visualizer styles are a fork-only feature), `MaterialSymbol.qml` (the fork's takes its font family from a `Fonts` service that loads `assets/fonts/MaterialSymbolsRounded.ttf`, which the pin does not ship: `FontLoader.name` would be empty and every icon in the whole shell, not only settings, would render blank; it also drops the fill animation), `StyledImage.qml` (the fork's only removes the pin's HiDPI `sourceSize` block, which would blur images on DP-2 at scale 1.5; no ported page needs it)

**Interfaces:**
- Consumes: `Config.options.settings.collapsedSections` (Task 3).
- Produces: `ContentPage.forceWidth`, `ContentPage.bottomContentPadding`, `ContentSection.shape`/`collapsible`/`sectionId`, and the other properties the fork pages set on these widgets.

- [ ] **Step 1: Make sure 01–04 did not touch these files**

```bash
cd ~/src/dots-hyprland
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
W=dots/.config/quickshell/ii/modules/common/widgets
for w in ContentPage ContentSection ConfigSelectionArray ConfigSwitch ConfigSlider NoticeBox ContentSubsection StyledComboBox RippleButton MaterialShapeWrappedMaterialSymbol MaterialTextArea MaterialLoadingIndicator SelectionGroupButton ToolbarPairedFab; do
  git log --oneline "$PIN"..krane -- "$W/$w.qml" | sed "s/^/$w: /"
done
```

Expected: no output. For any file listed, do not take the fork's copy wholesale in the steps below: fetch it to a scratch dir, then carry the 01–04 hunks (`git show <commit> -- <file>`) onto it by hand before writing it into the clone.

- [ ] **Step 2: `ContentPage.qml`**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
II=~/src/dots-hyprland/dots/.config/quickshell/ii
curl -sfL "$F/modules/common/widgets/ContentPage.qml" -o "$II/modules/common/widgets/ContentPage.qml"
sed -i 's/property real bottomContentPadding: Config.options.settings.style === "minimal" ? 40 : 90/property real bottomContentPadding: 90/' "$II/modules/common/widgets/ContentPage.qml"
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/common/widgets/ContentPage.qml"; echo "exit $?"
```

Expected: no findings, `exit 0`. Then:

```bash
cd ~/src/dots-hyprland && git add -A && git commit -F - <<'MSG'
feat(settings): take end4-pC's ContentPage

Port of pctrade/end4-pC dc2ca2600ee6: modules/common/widgets/ContentPage.qml
https://github.com/pctrade/end4-pC/tree/dc2ca2600ee6d7852bf0ac91361db8e510f90a74
Problem: the ported pages set forceWidth, bottomContentPadding and other properties the pin's ContentPage lacks.
Port: hand-ported. bottomContentPadding is a constant 90: the fork's "minimal" settings style is dropped.
Drop when: the pinned ContentPage.qml has forceWidth and bottomContentPadding.
MSG
```

- [ ] **Step 3: `ContentSection.qml`**

```bash
curl -sfL "$F/modules/common/widgets/ContentSection.qml" -o "$II/modules/common/widgets/ContentSection.qml"
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/common/widgets/ContentSection.qml"; echo "exit $?"
```

Expected: `exit 0`. Commit with subject `feat(settings): take end4-pC's ContentSection`, fork path `modules/common/widgets/ContentSection.qml`, `Problem: the ported pages use collapsible sections with a MaterialShape icon.`, `Port: clean`, `Drop when: the pinned ContentSection.qml has collapsible and shape.`

- [ ] **Step 4: `ConfigSelectionArray.qml`**

```bash
curl -sfL "$F/modules/common/widgets/ConfigSelectionArray.qml" -o "$II/modules/common/widgets/ConfigSelectionArray.qml"
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/common/widgets/ConfigSelectionArray.qml"; echo "exit $?"
```

Expected: `exit 0`. Commit with subject `feat(settings): take end4-pC's ConfigSelectionArray`, fork path `modules/common/widgets/ConfigSelectionArray.qml`, `Problem: the ported pages give selection arrays a label and icon row the pin's version lacks.`, `Port: clean`, `Drop when: the pinned ConfigSelectionArray.qml has text and icon properties.`

- [ ] **Step 5: The small shared widgets**

```bash
for w in ConfigSwitch ConfigSlider NoticeBox ContentSubsection StyledComboBox RippleButton MaterialShapeWrappedMaterialSymbol MaterialTextArea MaterialLoadingIndicator SelectionGroupButton ToolbarPairedFab; do
  curl -sfL "$F/modules/common/widgets/$w.qml" -o "$II/modules/common/widgets/$w.qml" || echo "FETCH FAILED $w"
done
git -C ~/src/dots-hyprland diff -w --stat
git -C ~/src/dots-hyprland diff -w | grep '^-' | grep -v '^---' | head -60
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/common/widgets/{ConfigSwitch,ConfigSlider,NoticeBox,ContentSubsection,StyledComboBox,RippleButton,MaterialShapeWrappedMaterialSymbol,MaterialTextArea,MaterialLoadingIndicator,SelectionGroupButton,ToolbarPairedFab}.qml; echo "exit $?"
```

Read the removed (`-`) lines: most of each diff is re-indentation, which `-w` hides. If a removed line is a property or function the pin uses elsewhere (`grep -rn '<name>' "$II" --include=*.qml`), put it back. These widgets are used by the whole shell, not only settings, so also put back removed behaviour: in `ToolbarPairedFab.qml` keep the pin's `anchors { verticalCenter: parent.verticalCenter }` (the pin's toolbars rely on it). Checked at `dc2ca2600ee6`: the rest of the removals are the renamed default aliases in `NoticeBox`/`ContentSubsection` (`boxData`/`contentData` to `data`; nothing at the pin names them) and re-layout. Expected: `exit 0`. Commit with subject `feat(settings): take end4-pC's versions of small shared widgets`, the list of paths, `Problem: the ported pages set properties (for example ConfigSlider.showLabel, ConfigSwitch colBackgroundHover) these widgets lack at the pin.`, `Port: clean`, `Drop when: the pinned widgets have the properties the pages set, checked by running forkcheck and the page smoke tests with this commit reverted.`

- [ ] **Step 6: The upstream pages still load (regression check)**

```bash
for p in QuickConfig GeneralConfig BarConfig BackgroundConfig InterfaceConfig ServicesConfig AdvancedConfig About; do
  smoke "$p" "$XDG_RUNTIME_DIR/$p.log"; echo "== $p"; newerrs "$p" "$XDG_RUNTIME_DIR/$p.log"
done
```

Expected: only `== <Page>` lines. A new error names the widget and property; fix it in that widget's commit with `git commit --fixup=<sha>` and `git rebase --autosquash krane/04-agents` (git 2.44 or later runs autosquash without `-i`).

- [ ] **Step 7: Export**

Run the export command. Expected: patches `0001` to `0006`.

---

### Task 5: Fork-only widgets the pages use

New files, so they apply to any pin. Only widgets whose feature exists at the pin; the Hyprland page's `AutostartApps` comes in Task 17 and the display widgets in Task 23.

**Files:**
- Create (clone, `$II/modules/common/widgets/`): `AboutCard.qml`, `AndroidClock.qml`, `Carousel.qml`, `ColorSelectionArray.qml`, `ConfigComboBox.qml`, `ConfigSelectionShapeArray.qml`, `ConfigTextArea.qml`, `GroupedList.qml`, `LayoutSection.qml`, `WidgetsMonitorSelector.qml`, `WorldMap.qml`, `WorldMapDots.js`, `WorldCities.js`
- Not ported: `services/Fonts.qml` (used only by the fork's `MaterialSymbol` and the Background page's custom Text section, both not ported; it loads fonts the pin does not ship)

**Interfaces:**
- Produces: the QML types above, referenced by the pages in Tasks 6–10.

- [ ] **Step 1: Fetch**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
II=~/src/dots-hyprland/dots/.config/quickshell/ii
for w in AboutCard.qml AndroidClock.qml Carousel.qml ColorSelectionArray.qml ConfigComboBox.qml ConfigSelectionShapeArray.qml ConfigTextArea.qml GroupedList.qml LayoutSection.qml WidgetsMonitorSelector.qml WorldMap.qml WorldMapDots.js WorldCities.js; do
  test -e "$II/modules/common/widgets/$w" && echo "EXISTS $w"
  curl -sfL "$F/modules/common/widgets/$w" -o "$II/modules/common/widgets/$w" || echo "FETCH FAILED $w"
done
```

Expected: no output. `EXISTS` means 01–04 added a file of that name: stop and compare.

- [ ] **Step 2: Check what they need (failing until adapted)**

```bash
cd "$II"
python3 ~/src/ii-tools/forkcheck.py "$II" modules/common/widgets/{AboutCard,AndroidClock,Carousel,ColorSelectionArray,ConfigComboBox,ConfigSelectionShapeArray,ConfigTextArea,GroupedList,LayoutSection,WidgetsMonitorSelector,WorldMap}.qml
```

For each finding, apply the matching rule, then run the command again until it prints nothing:

| Finding | Edit |
|---|---|
| `pattern: fork WM abstraction` | `WM.compositor === "hyprland"` and `WM.compositor !== "niri"` become `true`; `WM.compositor === "niri"` becomes `false`. Then delete code guarded only by a constant `false`. |
| `type: <T>` where `<T>` is one of the files above | none; it resolves once all are in place (re-run). |
| `type: <T>` for anything else | the widget embeds a fork-only feature. Delete the element that uses `<T>`; if the whole widget exists for that feature, delete the widget file and remove it from this task's list. |
| `config: <path>` | the widget reads a fork-only key: delete the element or binding that reads it, keeping the widget's default behaviour. |
| `global` / `member` | same as `config`. |

- [ ] **Step 3: Nothing references the new files yet (regression check)**

Run the Task 4, Step 6 loop. Expected: only `== <Page>` lines.

- [ ] **Step 4: Commit and export**

```bash
cd ~/src/dots-hyprland && git add -A && git commit -F - <<'MSG'
feat(settings): add end4-pC widgets used by the settings pages

Port of pctrade/end4-pC dc2ca2600ee6: modules/common/widgets/{AboutCard,AndroidClock,Carousel,ColorSelectionArray,ConfigComboBox,ConfigSelectionShapeArray,ConfigTextArea,GroupedList,LayoutSection,WidgetsMonitorSelector,WorldMap}.qml, WorldMapDots.js, WorldCities.js
https://github.com/pctrade/end4-pC/tree/dc2ca2600ee6d7852bf0ac91361db8e510f90a74
Problem: the ported pages are built from these widgets, which do not exist at the pin.
Port: hand-ported. WM checks made constant (Hyprland only); see forkcheck for anything else removed.
Drop when: never on its own; drop together with the pages that use them.
MSG
```

Run the export command. Task 11 deletes any of these files no page ends up using.

---

### Task 6: Quick and General pages, and the hyprlock clock sync

**Files:**
- Modify (clone): `$II/modules/settings/QuickConfig.qml`, `$II/modules/settings/GeneralConfig.qml` (replaced by the fork's), `$II/shell.qml`

**Interfaces:**
- Consumes: widgets from Tasks 4–5.
- Produces: in `shell.qml`, `root.syncHyprlockClock()`, run when Config becomes ready, when `time.format` changes and on every `HyprlandConfig.reloaded` (Hyprland `configreloaded`).

- [ ] **Step 1: Fetch the pages and list what must go (failing check)**

```bash
for p in QuickConfig GeneralConfig; do
  curl -sfL "$F/modules/ii/settings/pages/$p.qml" -o "$II/modules/settings/$p.qml"
done
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/{QuickConfig,GeneralConfig}.qml; echo "exit $?"
```

Expected: `QuickConfig.qml` has `settings.style` (config and pattern); `GeneralConfig.qml` has `time.showDate` twice and the two `hyprlock.conf` patterns; `exit 1`.

- [ ] **Step 2: Adapt**

1. Both pages: `sed -i 's/Config\.options\.settings\.style === "minimal"/false/g' "$II"/modules/settings/{QuickConfig,GeneralConfig}.qml`.
2. `GeneralConfig.qml`: delete the whole element (from its `ConfigSwitch {` line to the matching `}`) whose `checked` reads `Config.options.time.showDate` (fork-only: the date under the lock clock).
3. `GeneralConfig.qml`: in the time format selector's `onSelected`, delete the `if (newValue === "hh:mm") { ... } else { ... }` block that runs `sed -i ... hypr/hyprlock.conf`, keeping `Config.options.time.format = newValue`. The shell now derives hyprlock's token (next step).

Run forkcheck again. Expected: no findings, `exit 0`.

- [ ] **Step 3: The hyprlock clock sync in `shell.qml`**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/shell.qml
+++ b/dots/.config/quickshell/ii/shell.qml
@@ -7,6 +7,7 @@
 ////@ pragma Env QT_SCALE_FACTOR=1
 
 import "modules/common"
+import "modules/common/functions"
 import "services"
 import "panelFamilies"
 
@@ -22,6 +23,29 @@
     // Stuff for every panel family
     ReloadPopup {}
 
+    // Keep hyprlock's clock in step with the 12h/24h setting. The settings page
+    // used to sed hyprlock.conf once, but every switch copies a fresh one, so
+    // derive it here: when Config is ready, when the format changes, and on
+    // every Hyprland config reload (a switch ends with one).
+    function syncHyprlockClock() {
+        if (!Config.ready)
+            return;
+        const expr = Config.options.time.format === "hh:mm" ? "s/\\$TIME12\\b/$TIME/" : "s/\\$TIME\\b/$TIME12/";
+        Quickshell.execDetached(["sed", "-i", expr, FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprlock.conf`)]);
+    }
+    Connections {
+        target: Config
+        function onReadyChanged() { root.syncHyprlockClock() }
+    }
+    Connections {
+        target: Config.ready ? Config.options.time : null
+        function onFormatChanged() { root.syncHyprlockClock() }
+    }
+    Connections {
+        target: HyprlandConfig
+        function onReloaded() { root.syncHyprlockClock() }
+    }
+
     Component.onCompleted: {
         MaterialThemeLoader.reapplyTheme()
         Hyprsunset.load()
PATCH
```

Check the sed expressions it runs against a copy of the pin's `hyprlock.conf`:

```bash
t=$(mktemp -p "$XDG_RUNTIME_DIR"); command cp ~/.config/hypr/hyprlock.conf "$t"; chmod u+w "$t"
sed -i 's/\$TIME\b/$TIME12/' "$t"; sed -i 's/\$TIME\b/$TIME12/' "$t"; grep -c 'text = \$TIME12$' "$t"
sed -i 's/\$TIME12\b/$TIME/' "$t"; grep -c 'text = \$TIME$' "$t"; rm "$t"
```

Expected: `1` and `1` (idempotent both ways).

- [ ] **Step 4: Smoke the pages**

```bash
for p in QuickConfig GeneralConfig; do smoke "$p" "$XDG_RUNTIME_DIR/$p.log"; echo "== $p"; newerrs "$p" "$XDG_RUNTIME_DIR/$p.log"; done
```

Expected: only the two `==` lines. A `type` or property error names a widget from Task 4 or 5 that is missing or unported; port it there, not here.

- [ ] **Step 5: Commit (three commits) and export**

- `shell.qml`: subject `feat(shell): keep hyprlock's clock in step with the time format`; `Port of ...: none (krane-only)`; `Problem: the settings page sed-edited hyprlock.conf once, but every switch copies a fresh hyprlock.conf, so the 12h clock reverted.`; `Port: krane-only`; `Drop when: hyprlock.conf is generated from config.json upstream.`
- `QuickConfig.qml`: subject `feat(settings): port end4-pC's Quick page`; fork path `modules/ii/settings/pages/QuickConfig.qml`; `Problem: replaces the pin's Quick page with the reworked one.`; `Port: hand-ported (minimal style dropped)`; `Drop when: upstream ships an equivalent Quick page, or the settings port is abandoned.`
- `GeneralConfig.qml`: subject `feat(settings): port end4-pC's General page`; `Port: hand-ported (lock-clock date switch dropped: fork-only; hyprlock.conf sed moved to shell.qml)`; same `Drop when` form.

Stage each file separately (`git add <file> && git commit -F -`). Run the export command.

---

### Task 7: Bar and Background pages

**Files:**
- Modify (clone): `$II/modules/settings/BarConfig.qml`, `$II/modules/settings/BackgroundConfig.qml` (replaced by the fork's)

- [ ] **Step 1: Fetch and list findings (failing check)**

```bash
for p in BarConfig BackgroundConfig; do curl -sfL "$F/modules/ii/settings/pages/$p.qml" -o "$II/modules/settings/$p.qml"; done
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/{BarConfig,BackgroundConfig}.qml | cut -d: -f3- | sort | uniq -c
```

Expected, against a post-04 clone, roughly these fork-only keys (the removal list for Step 2):
- Bar: `bar.centerOnlyReserveFrame`, `bar.divider.*`, `bar.dynamicIsland.*`, `bar.followFrameColor`, `bar.frameColor`, `bar.frameThickness`, `bar.groupColor`, `bar.layouts.*`, `bar.media.*`, `bar.resources.{alwaysShowCpuTemp,alwaysShowDisk,alwaysShowRam,showValue,style}`, `bar.showFrame`, `bar.tooltips.enable`, `bar.utilButtons.showWallpaperToggle`, `bar.workspaces.indicatorStyle`, `notifications.position`, and `global: refreshBar`.
- Background: `background.{blurRadius,centeredWallpaper*,enableWallpaperPreview,lockWall,showBlur,showGrid,showSnapLines,splitRatio,splitSide,wallpaperAnimation}`, `background.widgets.{calendar,customImage,customText,images,media,notes,resources,sticker,timers,todo,userCard,visualizer,worldClock}.*`, `background.widgets.clock.{color,pixel.orientation,quote.followClock}`, `wallpaperSelector.changeInterval`, `global: wallpaperSelectorTarget`, and four `WM` findings.

- [ ] **Step 2: Adapt**

1. `sed -i 's/WM\.compositor !== "niri"/true/g; s/WM\.compositor === "niri"/false/g' "$II/modules/settings/BackgroundConfig.qml"`, then delete elements whose `visible:` or `enabled:` is now the constant `false`.
2. Replace every `GlobalStates.wallpaperSelectorOpen = true` with `Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggle"])`. The settings window is its own process, so setting a `GlobalStates` flag there never reaches the main shell. Delete the lines that set `GlobalStates.wallpaperSelectorTarget` (the lock-screen wallpaper target is fork-only).
3. For every remaining `config`, `global`, `member` or `type` finding: delete the smallest enclosing control element (`ConfigSwitch`, `ConfigSpinBox`, `ConfigSelectionArray`, `ConfigRow`, `ContentSubsection`, ...) that reads it. If that leaves a `ContentSubsection` or `ContentSection` with no controls, delete it too. Record each removed control's title and key in `~/src/ii-tools/dropped.txt` as `<Page> | <control title> | <key> | fork-only feature` (Task 25 turns it into the docs table).
4. The `refreshBar` call sits inside the `bar.showFrame` switch, which step 3 removes.
5. Guards are not controls. Where a fork-only key appears only in a `visible:`/`enabled:` guard or a ternary on an element that configures a pin feature, replace the expression with its value at the fork's default and keep the element; delete only elements that configure the fork-only key itself. Known cases (checked at `dc2ca2600ee6` against the pin plus 01–04):
   - Background, "Wallpaper" section: the first `Carousel` shows the desktop and the lock-screen wallpaper (`background.lockWall`, fork-only). Its `model` becomes `[page.displayPathFor(Config.options.background.wallpaperPath)]` with `largeItemWidthRatio: 1; mediumItemWidthRatio: 0` (as the fork's second, niri-only carousel does, which step 1 deletes), and the "Desktop"/"Lockscreen" label `RowLayout` under it goes.
   - Background, "Widgets" section: the `Repeater` model is a list of widget entries; delete the entries whose `enabled:` reads a fork-only `background.widgets.<name>.enable` (images, media, resources, calendar, worldClock, userCard, notes, todo, timers, sticker) and keep the rest (Weather and every entry whose key exists at the pin). Delete the "Show widgets on" `ContentSubsection`: `WidgetsMonitorSelector` writes `background.screenList` through `configEntry`, a fork-only key that `forkcheck.py` cannot see (it only follows literal `Config.options.` paths).
   - Background, "Centered wallpaper" subsection and the "Custom Image", "Visualizer" and "Text" sections: every control in them configures a fork-only key, so each goes whole.
   - Bar: "Overlap windows when center-only", "Follow Frame Color", "Space width (px)" and "Click to show" are guarded by `bar.showFrame`, `bar.divider.style` or `bar.tooltips.enable` but configure fork-only keys themselves, so they go with their guards.

Expected after the edits: `forkcheck.py` prints nothing for both files, and `grep -c 'screenList\|lockWall' "$II/modules/settings/BackgroundConfig.qml"` prints `0`.

- [ ] **Step 3: Smoke**

```bash
for p in BarConfig BackgroundConfig; do smoke "$p" "$XDG_RUNTIME_DIR/$p.log"; echo "== $p"; newerrs "$p" "$XDG_RUNTIME_DIR/$p.log"; done
```

Expected: only the `==` lines.

- [ ] **Step 4: Commit (one per page) and export**

Subjects `feat(settings): port end4-pC's Bar page` and `feat(settings): port end4-pC's Background page`; fork paths `modules/ii/settings/pages/BarConfig.qml` and `.../BackgroundConfig.qml`; `Port: hand-ported (controls for fork-only features dropped, see docs/II-INTEGRATION.md; wallpaper selector opened over IPC)`; `Drop when: upstream ships equivalent pages, or the settings port is abandoned.` Run the export command.

---

### Task 8: Interface and Services pages

**Files:**
- Modify (clone): `$II/modules/settings/InterfaceConfig.qml`, `$II/modules/settings/ServicesConfig.qml` (replaced by the fork's)

- [ ] **Step 1: Fetch and list findings (failing check)**

```bash
for p in InterfaceConfig ServicesConfig; do curl -sfL "$F/modules/ii/settings/pages/$p.qml" -o "$II/modules/settings/$p.qml"; done
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/{InterfaceConfig,ServicesConfig}.qml | cut -d: -f3- | sort | uniq -c
```

Expected: no `dock.*` finding (03-dock declared those keys). Interface findings include `lock.{blur.size,showMedia,showToolbars,showWidgets}`, `overview.style`, `settings.{borderColor,borderSize,style}`, `sidebar.{banner,bottomGroup,media.*,mediaPlayer}`, `sidebar.cornerOpen.{bottomLeftAction,bottomRightAction}`, `wallpaperSelector.{changeInterval,closeAfterSelection,columns,liveWallpapersPath,showBlurBackground,showHomePath,showSearchbar,userPath}`, `global: hotCornerOptions`, `type: Player` and two `WM`. Services: `search.prefix.keybinds`, `search.prefix.symbols`.

- [ ] **Step 2: Adapt**

1. `sed -i 's/Config\.options\.settings\.style === "minimal"/false/g; s/WM\.compositor !== "niri"/true/g; s/WM\.compositor === "niri"/false/g' "$II/modules/settings/InterfaceConfig.qml"`.
2. Remove controls for every remaining finding, exactly as in Task 7, Step 2.3 and 2.5, recording them in `~/src/ii-tools/dropped.txt`. Guard cases on this page: the "Overview" section's "Default Settings" subsection, its rows/columns `GroupedList` and the direction selector are pin controls guarded by `visible: Config.options.overview.style !== "niri"`; replace each guard with `true` and delete only the "Style" selector (`overview.style`, the fork's niri-like overview). "Show media player info" configures `lock.showMedia` (fork-only), so it goes with its `lock.showToolbars` guard. In the "Right Sidebar" `GroupedList`, delete the "Banner", "Bottom Group" and "Media Player" switches and keep "Keep right sidebar loaded".
3. Do not remove any control for `sidebar.translator.enable` or `dock.*`.

- [ ] **Step 3: The translator and dock switches are still there**

```bash
for k in sidebar.translator.enable dock.enable dock.hoverToReveal dock.pinnedOnStartup dock.monochromeIcons dock.showBackground dock.showPinButton dock.showAppsButton dock.showMedia; do
  printf '%s %s\n' "$(grep -c "checked: Config.options.$k$" "$II/modules/settings/InterfaceConfig.qml")" "$k"
done
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/{InterfaceConfig,ServicesConfig}.qml; echo "exit $?"
```

Expected: `1` for all nine keys, then `exit 0`.

- [ ] **Step 4: Smoke, commit (one per page), export**

Smoke both pages as in Task 7, Step 3 (expected: only `==` lines). Subjects `feat(settings): port end4-pC's Interface page` and `feat(settings): port end4-pC's Services page`, same message form as Task 7. Run the export command.

---

### Task 9: About page

**Files:**
- Modify (clone): `$II/modules/settings/About.qml` (replaced by the fork's), `$II/services/SystemInfo.qml`
- Modify: `lib/mk-host.nix` (`patchedDotfiles`)

**Interfaces:**
- Produces: `$II/krane-build.json` in the built source, `{"rev": "<pin sha>", "patches": <count of iiSeries>}`. `SystemInfo.{hostname, cpu, gpu, memory, disk, shell, kernelVersion}` and `SystemInfo.refresh()`, `SystemInfo.refreshHostname()`.

- [ ] **Step 1: Write `krane-build.json` at build time**

In `lib/mk-host.nix`, extend the `patchedDotfiles` binding that sub-project 1 wrote:

```nix
              patchedDotfiles = inputs.nixpkgs.legacyPackages.${system}.applyPatches {
                name = "dots-hyprland-patched";
                src = inputs.illogical-flake.inputs.dotfiles;
                patches = [ ../patches/illogical-flake-cheatsheet-fkeys.patch ] ++ iiSeries;
                # Read by the settings window's About page (patches/ii/05-settings).
                postPatch = ''
                  printf '{"rev":"%s","patches":%d}\n' \
                    ${inputs.dots-hyprland.rev} ${toString (builtins.length iiSeries)} \
                    > dots/.config/quickshell/ii/krane-build.json
                '';
              };
```

Then:

```bash
cd ~/.dotfiles && git add lib/mk-host.nix
```

Run "Checking the built source", then `command cat "$iisrc/dots/.config/quickshell/ii/krane-build.json"`. Expected: the pin sha and the number of `.patch` files under `patches/ii/`.

- [ ] **Step 2: Port the SystemInfo members the pages read**

```bash
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); curl -sfL "$F/services/SystemInfo.qml" -o "$t/SystemInfo.qml"
```

From `$t/SystemInfo.qml` copy into `$II/services/SystemInfo.qml`:
1. the property declarations `hostname`, `cpu`, `gpu`, `memory`, `disk`, `shell`, `kernelVersion` (not `packages` or `installAge`: pacman and Arch-install specific);
2. the functions `refresh()` (without its `getPackages` and `getInstallAge` lines) and `refreshHostname()`;
3. the `Process` blocks with ids `getHostname`, `getKernel`, `getCpu`, `getGpu`, `getMemory`, `getDisk`, `getShell`;
4. the line `getHostname.running = true` into the pin's existing `Component.onCompleted`.

Then `python3 ~/src/ii-tools/forkcheck.py "$II" "$II/services/SystemInfo.qml"` (expected: `exit 0`) and `rm -rf "$t"`.

- [ ] **Step 3: Fetch the page and adapt**

```bash
curl -sfL "$F/modules/ii/settings/pages/About.qml" -o "$II/modules/settings/About.qml"
sed -i 's/Config\.options\.settings\.style === "minimal"/false/g' "$II/modules/settings/About.qml"
```

Edits in `About.qml`:
1. Delete the functions `runSystemUpdate()` and `runUpdateDots()` (they run `yay -Syu` and clone end4-pC into `~/.config/quickshell`; out of scope).
2. Delete the `RowLayout` that holds the `RippleButton` with `buttonText: Translation.tr("Update Dots")`.
3. Delete the `AboutCard` with `label: "Packages"` and the one with `label: "Updates"`.
4. Add, at the top level of the page (next to the other `Process`/functions), the build info and the repo path:
   ```qml
   // Pin revision and patch count, written by lib/mk-host.nix at build time.
   property var kraneBuildInfo: ({})
   FileView {
       path: Quickshell.shellPath("krane-build.json")
       printErrors: false
       onLoaded: {
           try { kraneBuildInfo = JSON.parse(text()); } catch (e) { kraneBuildInfo = ({}); }
       }
   }
   // The dotfiles checkout, from the config-dir symlink (…/hosts/<host>/illogical-impulse).
   property string dotfilesDir: ""
   Process {
       running: true
       command: ["readlink", "-f", FileUtils.trimFileProtocol(Directories.shellConfig)]
       stdout: StdioCollector {
           onStreamFinished: dotfilesDir = text.trim().replace(/\/hosts\/[^/]+\/illogical-impulse$/, "")
       }
   }
   ```
5. In the `GridLayout`, where the Updates card was, add:
   ```qml
   AboutCard {
       icon: "commit"
       label: "dots-hyprland"
       iconShape: MaterialShape.Shape.Cookie9Sided
       value: (kraneBuildInfo.rev ?? "unknown").slice(0, 12) + ` + ${kraneBuildInfo.patches ?? "?"} patches`
       Layout.fillWidth: true
   }
   AboutCard {
       icon: "folder_code"
       label: "Dotfiles"
       iconShape: MaterialShape.Shape.Sunny
       value: dotfilesDir || "Loading..."
       Layout.fillWidth: true
   }
   ```
6. If the page's `Component.onCompleted` does not call `SystemInfo.refresh()`, add it.

```bash
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/settings/About.qml"; echo "exit $?"
smoke About "$XDG_RUNTIME_DIR/About.log"; newerrs About "$XDG_RUNTIME_DIR/About.log"
```

Expected: `exit 0` and no new errors. (In the smoke run `krane-build.json` is absent, so the card shows `unknown + ? patches`; after the switch in Task 11 it shows the pin.)

- [ ] **Step 4: Commit (two commits) and export**

- `SystemInfo.qml`: subject `feat(settings): add the system facts the About page shows`; fork path `services/SystemInfo.qml`; `Port: hand-ported (packages and install age dropped: pacman-specific)`; `Drop when: the pinned SystemInfo.qml has cpu, gpu, memory, disk, shell and kernelVersion.`
- `About.qml`: subject `feat(settings): port end4-pC's About page`; `Port: hand-ported (update buttons, Packages and Updates cards dropped; pin revision, patch count and dotfiles path added)`.

Run the export command.

---

### Task 10: Profile page and local presets

**Files:**
- Create (clone): `$II/modules/settings/Profile.qml`, `$II/services/Presets.qml`, `$II/modules/common/widgets/PresetsCard.qml`, `$II/modules/common/widgets/PresetPopup.qml`, `$II/scripts/presets.sh`
- Modify (clone): `$II/modules/common/Directories.qml`, `$II/settings.qml` (page list)

**Interfaces:**
- Consumes: `Config.options.profile.*` (Task 3), `SystemInfo.hostname` (Task 9).
- Produces: `Directories.userPresetsPath` (`<config dir>/presets`, so inside the repo) and `Directories.presetsScriptPath`.

- [ ] **Step 1: Fetch**

```bash
curl -sfL "$F/modules/ii/settings/pages/Profile.qml" -o "$II/modules/settings/Profile.qml"
curl -sfL "$F/services/Presets.qml" -o "$II/services/Presets.qml"
for w in PresetsCard PresetPopup; do curl -sfL "$F/modules/common/widgets/$w.qml" -o "$II/modules/common/widgets/$w.qml"; done
curl -sfL "$F/scripts/presets.sh" -o "$II/scripts/presets.sh" && chmod +x "$II/scripts/presets.sh"
cd ~/src/dots-hyprland && git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/modules/common/Directories.qml
+++ b/dots/.config/quickshell/ii/modules/common/Directories.qml
@@ -45,6 +45,9 @@
     property string defaultAiPrompts: Quickshell.shellPath("defaults/ai/prompts")
     property string userAiPrompts: FileUtils.trimFileProtocol(`${Directories.shellConfig}/ai/prompts`)
     property string userActions: FileUtils.trimFileProtocol(`${Directories.shellConfig}/actions`)
+    // Profile page presets (patches/ii/05-settings). Inside the config dir, so in the repo.
+    property string userPresetsPath: FileUtils.trimFileProtocol(`${Directories.shellConfig}/presets`)
+    property string presetsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/presets.sh`)
     property string aiChats: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats`)
     property string aiTranslationScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/gemini-translate.sh`)
     property string recordScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/record.sh`)
PATCH
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/settings.qml
+++ b/dots/.config/quickshell/ii/settings.qml
@@ -55,6 +55,11 @@
             component: "modules/settings/ServicesConfig.qml"
         },
         {
+            name: Translation.tr("Profile"),
+            icon: "account_circle",
+            component: "modules/settings/Profile.qml"
+        },
+        {
             name: Translation.tr("Advanced"),
             icon: "construction",
             component: "modules/settings/AdvancedConfig.qml"
PATCH
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/Profile.qml "$II"/services/Presets.qml "$II"/modules/common/widgets/{PresetsCard,PresetPopup}.qml | cut -d: -f3- | sort | uniq -c
```

Expected (failing check): `config: profile.onlinePresets`, `global: settingsOpen` (with its pattern), the `hostnamectl` pattern, five `curl` patterns, and `member: SystemInfo.refreshHostname` only if Task 9 missed it.

- [ ] **Step 2: Adapt `Profile.qml`**

1. Online presets (out of scope, spec): delete the properties `onlinePresets`, `onlinePresetsError`, `onlinePresetsLoading`; the function that filters downloaded names, `refreshOnlinePresets`, `rawPresetUrl`, `onlinePresetsDir`, `assetCacheDir`, `shQuote`, `startOnlineAssetsFetch`, `downloadOnlinePreset`; the line in `Component.onCompleted` that calls `refreshOnlinePresets`; the `Process` blocks `onlinePresetsListProc`, `presetJsonFetchProc`, `presetMetaFetchProc`, `presetAssetsFetchProc` and the finalize process after them; and the UI that shows or toggles online presets (the `ConfigSwitch` bound to `Config.options.profile.onlinePresets` and the section listing online presets).
2. Hostname (read-only, spec): delete `property string hostnameInput`, the `hostnameSetProc` `Process`, `function applyHostname()` and the `Connections` whose `onHostnameChanged` rebinds `hostnameField.value`. In the `hostnameField` element set `enabled: false` and `value: SystemInfo.hostname`, and delete its `onValueChanged`, `confirmButtonVisible` and `onConfirmClicked` lines.
3. Replace `GlobalStates.settingsOpen = false` with `Qt.callLater(Qt.quit)`, placed after the `execDetached` it precedes.

- [ ] **Step 3: Adapt `Presets.qml` and the widgets**

In `Presets.qml` delete `property alias onlineFolderModel`, the `FolderListModel` with id `onlinePresetsFolderModel`, `refreshOnline()`, `applyOnline()`, `deleteOnline()` and `deleteOnlineProc`. In `PresetsCard.qml` and `PresetPopup.qml`, delete any branch that calls those. Leave `presets.sh` as fetched: its `--online` branch is never called.

```bash
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/Profile.qml "$II"/services/Presets.qml "$II"/modules/common/widgets/{PresetsCard,PresetPopup}.qml; echo "exit $?"
grep -n 'Presets\.\(onlineFolderModel\|refreshOnline\|applyOnline\|deleteOnline\)' -r "$II" --include=*.qml
smoke Profile "$XDG_RUNTIME_DIR/Profile.log"; newerrs QuickConfig "$XDG_RUNTIME_DIR/Profile.log"
grep -c '\[settings\] initial page: modules/settings/Profile.qml' "$XDG_RUNTIME_DIR/Profile.log"
```

Expected: `exit 0`; no grep output; `newerrs QuickConfig "$XDG_RUNTIME_DIR/Profile.log"` prints nothing (Profile has no baseline of its own, Quick's is the shared noise); `1`.

- [ ] **Step 4: Commit (three commits) and export**

- `Directories.qml` + `presets.sh` + `Presets.qml` + `PresetsCard.qml` + `PresetPopup.qml`: subject `feat(settings): add local settings presets`; fork paths as listed; `Port: hand-ported (online presets removed)`; `Drop when: the Profile page is dropped.`
- `Profile.qml`: subject `feat(settings): port end4-pC's Profile page`; `Port: hand-ported (hostname read-only; online presets removed)`.
- `settings.qml`: subject `feat(settings): list the Profile page`; `Port: krane-only`.

Run the export command.

---

### Task 11: Phase A build, switch, acceptance, privacy review and commit

**Files:**
- Delete (clone, if unused): any Task 5 widget no page references
- Commit (dotfiles): `patches/ii/05-settings/`, `lib/mk-host.nix`, `modules/home/ii-config-dir.nix`, `modules/home/default.nix`, `hosts/*/illogical-impulse/.gitignore`

- [ ] **Step 1: Drop ported widgets nothing uses**

```bash
cd "$II"
for w in AboutCard AndroidClock Carousel ColorSelectionArray ConfigComboBox ConfigSelectionShapeArray ConfigTextArea GroupedList LayoutSection WidgetsMonitorSelector WorldMap; do
  n=$(grep -rlw "$w" --include=*.qml . | grep -v "modules/common/widgets/$w.qml" | wc -l); echo "$n $w"
done
grep -rl 'WorldMapDots\|WorldCities' --include=*.qml .
```

Expected (checked against the fork source): `0` for `ConfigSelectionShapeArray`, `LayoutSection` and `WidgetsMonitorSelector` (only dropped controls used them), nonzero for the other eight. For each widget with `0`, `git rm` it in a commit `refactor(settings): drop end4-pC widgets no ported page uses` (`Port: krane-only`). Drop `WorldMapDots.js`/`WorldCities.js` with `WorldMap`. Record the final list and count (spec: "the count goes in the docs table") in `~/src/ii-tools/widgets.txt`. Run the export command.

- [ ] **Step 2: Whole-series checks**

```bash
cd ~/src/dots-hyprland
strip() { sed -E 's/:[0-9]+: /: /' | sort -u; }
comm -13 <(strip < ~/src/ii-tools/baseline/forkcheck.txt) \
  <(python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/settings/*.qml "$II"/modules/common/widgets/*.qml "$II"/services/*.qml 2>/dev/null | strip)
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
git switch -C krane-check "$PIN" -q
for d in ~/.dotfiles/patches/ii/*/; do git am -3 -q "$d"*.patch || { echo "AM FAILED in $d"; break; }; done
git diff --stat krane krane-check; git switch -q krane; git branch -D krane-check
```

Expected: `comm` prints nothing (no finding that was not already in the clone before this sub-project); `git am` applies everything; `git diff --stat` prints nothing.

- [ ] **Step 3: Build and dry-build**

```bash
cd ~/.dotfiles
nix flake check
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
```

Expected: `nix flake check` passes, no `FAIL` lines.

- [ ] **Step 4: Switch and check the logs (tariognatha, then tarmantria)**

```bash
qs log -c ii > $XDG_RUNTIME_DIR/qs-before.log 2>&1 || true
sudo nixos-rebuild switch --flake .#tariognatha && sudo nixos-rebuild switch --flake .#tariognatha
pkill -f '[q]s-wrapped -c ii'; hyprctl dispatch exec 'qs -c ii'; sleep 5
qs log -c ii > $XDG_RUNTIME_DIR/qs-after.log 2>&1 || true
comm -13 <(grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-before.log | sed -E 's/:[0-9]+//g' | sort -u) \
         <(grep -iE 'error|warn|TypeError|ReferenceError' $XDG_RUNTIME_DIR/qs-after.log | sed -E 's/:[0-9]+//g' | sort -u)
hyprctl configerrors
rm -f $XDG_RUNTIME_DIR/qs-before.log $XDG_RUNTIME_DIR/qs-after.log
```

Expected: no output from `comm` and an empty `configerrors`. Repeat on tarmantria.

- [ ] **Step 5: Acceptance checks (spec table, Phase A rows)**

Record pass, fail or not run for each:

1. **Settings window:** `SUPER + I` opens it; every page in the rail (Quick, General, Bar, Background, Interface, Services, Profile, Advanced, About) loads; closing it leaves the bar running (`pgrep -f '[q]s-wrapped -c ii'`). All hosts.
2. **config.json pages:** `config.json` stays untracked until Step 7, so compare against a snapshot instead of `git diff`. On each of Quick, General, Bar, Background, Interface and Services: `command cp ~/.dotfiles/hosts/<host>/illogical-impulse/config.json "$XDG_RUNTIME_DIR/cfg.json"`, change one control, then `diff <(jq -S . "$XDG_RUNTIME_DIR/cfg.json") <(jq -S . ~/.dotfiles/hosts/<host>/illogical-impulse/config.json)`. Expected: exactly that key. Switch, reboot: the value is still set. After Step 7 the same check is `git -C ~/.dotfiles diff hosts/<host>/illogical-impulse/config.json`.
3. **General 12h clock (tariognatha):** pick a 12h format, run `hyprlock` directly: AM/PM shows. Switch: `grep -c 'TIME12' ~/.config/hypr/hyprlock.conf` is `1` without opening settings.
4. **About:** shows the pin revision (first 12 characters of `$PIN`), the patch count and `/home/krane/.dotfiles`; no update buttons. All hosts.
5. **Profile (tariognatha):** change the display name; `jq -r .profile.displayName ~/.dotfiles/hosts/tariognatha/illogical-impulse/config.json` shows it; the hostname field is disabled and shows `tariognatha`. Save a local preset: it appears under `hosts/tariognatha/illogical-impulse/presets/`.
6. **Phase A calibration:** compare now with `~/src/ii-tools/phase-a-start`. More than 10 working sessions: stop here and re-scope Phases B and C with the user.

- [ ] **Step 6: Commit Phase A (code only)**

```bash
cd ~/.dotfiles
git add patches/ii/05-settings lib/mk-host.nix modules/home/ii-config-dir.nix modules/home/default.nix hosts/*/illogical-impulse/.gitignore
git status --short
git commit -m "Port the end4-pC settings pages into ii and keep ii's config directory in the repo"
```

`git status` must not list any `config.json`, `actions/` or `presets/` as staged.

- [ ] **Step 7: Privacy review, then the user commits each host's config (user step)**

The executor stops here and hands over. For each host, the user reads the **whole** file, not a diff:

```bash
less ~/.dotfiles/hosts/<host>/illogical-impulse/config.json
```

and, as a checklist while reading, these fields known to hold personal data:

```bash
jq '{city: .bar.weather.city, gps: .bar.weather.enableGPS, zerochan: .sidebar.booru.zerochan.username,
     extraModels: [.ai.extraModels[]? | {name, endpoint, key_id}], systemPrompt: .ai.systemPrompt,
     wallpaper: .background.wallpaperPath, recordings: .screenRecord.savePath, snips: .screenSnip.savePath,
     profile: .profile}' ~/.dotfiles/hosts/<host>/illogical-impulse/config.json
command ls -la ~/.dotfiles/hosts/<host>/illogical-impulse/{actions,presets} 2>/dev/null
```

The user removes or resets anything that should not reach the GitHub remote (there is no automatic scrubbing), reviews `presets/*.json` and `actions/` the same way, then commits it themselves, for example `git add hosts/<host>/illogical-impulse && git commit -m "Track <host>'s ii config"`.

---

## Phase B: Hyprland option writers

### Task 12: Writer core: schema and renderer

The allowlist of keys the GUI may write, and the renderer that turns `ii-settings.json` into `krane_gui.lua`. Test-first, in the dotfiles repo.

**Files:**
- Create: `pkgs/krane-ii-settings/schema.json`
- Create: `pkgs/krane-ii-settings/krane_ii_settings.py` (first part; Task 13 appends, Task 22 extends)
- Create: `pkgs/krane-ii-settings/tests/test_render.py`
- Create: `pkgs/krane-ii-settings/tests/fixtures/manifest.json`, `tests/fixtures/all-keys.json`
- Create: `pkgs/krane-ii-settings/tests/golden/empty.lua`, `tests/golden/all-keys.lua`

**Interfaces:**
- Produces (Python, module `krane_ii_settings`): `SettingsError(Exception)`; `load_schema(path=None) -> dict`; `parse_cli(spec, text, what)`; `check_value(spec, value, what)`; `validate_data(data, schema)`; `check_ownership(data, manifest)`; `render(data, manifest, schema) -> str`; `dump(data) -> str` (sorted keys, 2-space indent, trailing newline); constants `HEADER`, `MONITOR_ORDER`, `TOP_LEVEL`.
- Schema format: `{"hyprland": {<key>: spec}, "idle": {...}, "animationPreset": spec, "monitor": {<field>: spec}}`, where spec is `{"type": "bool"|"int"|"float"|"enum"|"str", "min", "max", "values", "pattern", "internal"}`.
- Manifest format (produced by Task 15, read here): `host`, `repoFile`, `liveFile`, `hypridleFile`, `idleConfigurator`, `qsBin`, `settingsQml`, `nixOwned: {hyprland: [key], idle: bool, monitors: {output: [field]}}`, `monitorBaselines: {output: {field: value}}`, `idleBaseline: {lock, screenOff, suspend}`.

- [ ] **Step 1: Write `pkgs/krane-ii-settings/schema.json`**

```json
{
  "animationPreset": { "type": "enum", "values": ["fast", "niri", "normal"] },
  "hyprland": {
    "animations:enabled": { "type": "bool" },
    "decoration:active_opacity": { "type": "float", "min": 0, "max": 1 },
    "decoration:blur:enabled": { "type": "bool" },
    "decoration:blur:passes": { "type": "int", "min": 0, "max": 10 },
    "decoration:blur:size": { "type": "int", "min": 0, "max": 100 },
    "decoration:inactive_opacity": { "type": "float", "min": 0, "max": 1 },
    "decoration:rounding": { "type": "int", "min": 0, "max": 20 },
    "decoration:shadow:enabled": { "type": "bool" },
    "decoration:shadow:range": { "type": "int", "min": 0, "max": 100 },
    "general:border_size": { "type": "int", "min": 0, "max": 20 },
    "general:gaps_in": { "type": "int", "min": 0, "max": 100 },
    "general:gaps_out": { "type": "int", "min": 0, "max": 200 },
    "general:layout": { "type": "enum", "values": ["dwindle", "master", "scrolling"] },
    "input:follow_mouse": { "type": "int", "min": 0, "max": 3 },
    "input:kb_layout": { "type": "str", "pattern": "^[a-z]+(,[a-z]+)*$" },
    "input:kb_variant": { "type": "str", "pattern": "^[a-z0-9_]*(,[a-z0-9_]*)*$" },
    "input:numlock_by_default": { "type": "bool" },
    "input:repeat_delay": { "type": "int", "min": 0, "max": 2000 },
    "input:repeat_rate": { "type": "int", "min": 0, "max": 200 },
    "input:touchpad:clickfinger_behavior": { "type": "bool" },
    "input:touchpad:disable_while_typing": { "type": "bool" },
    "input:touchpad:natural_scroll": { "type": "bool" },
    "input:touchpad:scroll_factor": { "type": "float", "min": 0, "max": 2 }
  },
  "idle": {
    "lock": { "type": "int", "min": 0, "max": 86400 },
    "screenOff": { "type": "int", "min": 0, "max": 86400 },
    "suspend": { "type": "int", "min": 0, "max": 86400 }
  },
  "monitor": {
    "bitdepth": { "type": "enum", "values": [8, 10] },
    "bootConfirmed": { "type": "bool", "internal": true },
    "cm": { "type": "enum", "values": ["adobe", "auto", "dcip3", "dp3", "edid", "hdr", "hdredid", "srgb", "wide"] },
    "disabled": { "type": "bool" },
    "max_avg_luminance": { "type": "int", "min": -1, "max": 10000 },
    "max_luminance": { "type": "int", "min": -1, "max": 10000 },
    "min_luminance": { "type": "float", "min": -1, "max": 10 },
    "mode": { "type": "str", "pattern": "^(preferred|highres|highrr|[0-9]+x[0-9]+(@[0-9]+(\\.[0-9]+)?)?)$" },
    "position": { "type": "str", "pattern": "^(auto|auto-(left|right|up|down|center-left|center-right|center-up|center-down)|-?[0-9]+x-?[0-9]+)$" },
    "scale": { "type": "float", "min": 0.25, "max": 4 },
    "sdr_max_luminance": { "type": "int", "min": 0, "max": 10000 },
    "sdr_min_luminance": { "type": "float", "min": 0, "max": 10 },
    "sdrbrightness": { "type": "float", "min": 0.5, "max": 3 },
    "sdrsaturation": { "type": "float", "min": 0, "max": 2 },
    "transform": { "type": "int", "min": 0, "max": 7 },
    "vrr": { "type": "int", "min": -1, "max": 3 }
  }
}
```

- [ ] **Step 2: Check every entry against Hyprland 0.56.2's source**

```bash
cd ~/.dotfiles
src=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.pkgs.hyprland.src)
V=$src/src/config/values/ConfigValues.cpp
R=$src/src/config/lua/bindings/LuaBindingsConfigRules.cpp
jq -r '.hyprland | keys[]' pkgs/krane-ii-settings/schema.json | while read -r k; do
  line=$(grep -A1 "MS<[A-Za-z]*>(\"$k\"" "$V" | tr -s ' ' | tr '\n' ' ' | cut -c1-160)
  [ -n "$line" ] && echo "ok $line" || echo "MISSING $k"
done
jq -r '.monitor | to_entries[] | select(.value.internal != true) | .key' pkgs/krane-ii-settings/schema.json | while read -r f; do
  grep -q "{\"$f\"," "$R" && echo "ok monitor $f" || echo "MISSING monitor $f"
done
grep -o '{"[a-z0-9]*", NCMType::[A-Z_0-9]*}' "$src/src/helpers/CMType.cpp" | cut -d'"' -f2 | sort | tr '\n' ' '; echo
grep -o 'which layout to use\. \[[^]]*\]' "$V"
```

Expected: no `MISSING` line. Each `ok` line shows the key's Hyprland type and, where set, `.min`/`.max`; they match the schema (for example `decoration:rounding` max 20, `input:touchpad:scroll_factor` max 2, `general:gaps_in` is a `CssGap` and takes an int). The `cm` list is `adobe auto dcip3 dp3 edid hdr hdredid srgb wide`; the layout list contains `dwindle/master/scrolling`. `input:kb_layout` and `input:kb_variant` are in the schema only so the writer can name them as Nix-owned rather than unknown.

- [ ] **Step 3: Write the test fixtures**

`pkgs/krane-ii-settings/tests/fixtures/manifest.json`:

```json
{
  "host": "testhost",
  "repoFile": "REPLACED-BY-TESTS",
  "liveFile": "REPLACED-BY-TESTS",
  "hypridleFile": "/nonexistent/hypridle.conf",
  "idleConfigurator": "/nonexistent/hypridleconfigurator.py",
  "qsBin": "/nonexistent/qs",
  "settingsQml": "/nonexistent/settings.qml",
  "nixOwned": {
    "hyprland": ["cursor:default_monitor", "input:kb_layout", "input:kb_variant"],
    "idle": false,
    "monitors": { "DP-2": ["disabled", "mode", "output", "position", "scale"] }
  },
  "monitorBaselines": {
    "DP-2": { "mode": "3840x2160@240", "output": "DP-2", "position": "0x0", "scale": 1.5 }
  },
  "idleBaseline": { "lock": 300, "screenOff": 600, "suspend": 900 }
}
```

`pkgs/krane-ii-settings/tests/fixtures/all-keys.json` (every schema key and every monitor field; used again by `checks.ii-settings-render`):

```json
{
  "animationPreset": "fast",
  "hyprland": {
    "animations:enabled": true,
    "decoration:active_opacity": 1.0,
    "decoration:blur:enabled": true,
    "decoration:blur:passes": 3,
    "decoration:blur:size": 6,
    "decoration:inactive_opacity": 0.9,
    "decoration:rounding": 12,
    "decoration:shadow:enabled": false,
    "decoration:shadow:range": 8,
    "general:border_size": 2,
    "general:gaps_in": 4,
    "general:gaps_out": 10,
    "general:layout": "master",
    "input:follow_mouse": 1,
    "input:kb_layout": "us",
    "input:kb_variant": "",
    "input:numlock_by_default": true,
    "input:repeat_delay": 250,
    "input:repeat_rate": 35,
    "input:touchpad:clickfinger_behavior": false,
    "input:touchpad:disable_while_typing": true,
    "input:touchpad:natural_scroll": true,
    "input:touchpad:scroll_factor": 0.7
  },
  "idle": { "lock": 600, "screenOff": 900, "suspend": 0 },
  "monitors": {
    "DP-2": {
      "bitdepth": 10,
      "bootConfirmed": false,
      "cm": "hdr",
      "max_avg_luminance": 400,
      "max_luminance": 1000,
      "min_luminance": 0.05,
      "sdr_max_luminance": 200,
      "sdr_min_luminance": 0.2,
      "sdrbrightness": 1.2,
      "sdrsaturation": 1.0,
      "transform": 0,
      "vrr": 1
    },
    "HDMI-A-1": {
      "disabled": true,
      "mode": "1920x1080@60",
      "position": "-1920x0",
      "scale": 1
    }
  }
}
```

- [ ] **Step 4: Write the golden files**

`pkgs/krane-ii-settings/tests/golden/empty.lua` (the header alone; what a host with `{}` gets):

```lua
-- GENERATED FILE -- DO NOT EDIT.
-- Rendered by krane-ii-settings from hosts/<host>/ii-settings.json.
-- Installed as ~/.config/hypr/custom/krane_gui.lua at switch time and
-- rewritten live by the ii settings GUI. Loaded from monitors.lua.
```

`pkgs/krane-ii-settings/tests/golden/all-keys.lua`:

```lua
-- GENERATED FILE -- DO NOT EDIT.
-- Rendered by krane-ii-settings from hosts/<host>/ii-settings.json.
-- Installed as ~/.config/hypr/custom/krane_gui.lua at switch time and
-- rewritten live by the ii settings GUI. Loaded from monitors.lua.

hl.config({
    animations = {
        enabled = true
    },
    decoration = {
        active_opacity = 1.0,
        blur = {
            enabled = true,
            passes = 3,
            size = 6
        },
        inactive_opacity = 0.9,
        rounding = 12,
        shadow = {
            enabled = false,
            range = 8
        }
    },
    general = {
        border_size = 2,
        gaps_in = 4,
        gaps_out = 10,
        layout = "master"
    },
    input = {
        follow_mouse = 1,
        kb_layout = "us",
        kb_variant = "",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,
        touchpad = {
            clickfinger_behavior = false,
            disable_while_typing = true,
            natural_scroll = true,
            scroll_factor = 0.7
        }
    }
})

require("hyprland.animationPresets.fast")

hl.monitor({
    output = "DP-2",
    mode = "3840x2160@240",
    position = "0x0",
    scale = 1.5,
    transform = 0,
    vrr = 1,
    bitdepth = 10,
    cm = "hdr",
    sdrbrightness = 1.2,
    sdrsaturation = 1.0,
    sdr_min_luminance = 0.2,
    sdr_max_luminance = 200,
    min_luminance = 0.05,
    max_luminance = 1000,
    max_avg_luminance = 400
})
hl.monitor({
    output = "HDMI-A-1",
    mode = "1920x1080@60",
    position = "-1920x0",
    scale = 1,
    disabled = true
})
```

Check it parses: `nix shell nixpkgs#lua5_4 -c luac -p pkgs/krane-ii-settings/tests/golden/all-keys.lua && echo OK`. Expected: `OK`.

- [ ] **Step 5: Write the failing tests**

`pkgs/krane-ii-settings/tests/test_render.py`:

```python
"""Render and schema tests for krane_ii_settings.
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import json
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import krane_ii_settings as k  # noqa: E402

FIXTURES = HERE / "fixtures"
GOLDEN = HERE / "golden"
SCHEMA = k.load_schema()


class RenderBase(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((FIXTURES / "manifest.json").read_text())


class TestRender(RenderBase):
    def test_empty_is_header_only(self):
        self.assertEqual(k.render({}, self.manifest, SCHEMA), k.HEADER)
        self.assertEqual(k.render({}, self.manifest, SCHEMA), (GOLDEN / "empty.lua").read_text())

    def test_all_keys_golden(self):
        data = json.loads((FIXTURES / "all-keys.json").read_text())
        self.assertEqual(k.render(data, self.manifest, SCHEMA), (GOLDEN / "all-keys.lua").read_text())

    def test_fixture_covers_every_schema_key(self):
        data = json.loads((FIXTURES / "all-keys.json").read_text())
        self.assertEqual(set(data["hyprland"]), set(SCHEMA["hyprland"]))
        self.assertEqual(set(data["idle"]), set(SCHEMA["idle"]))
        fields = set(data["monitors"]["DP-2"]) | set(data["monitors"]["HDMI-A-1"])
        self.assertEqual(fields, set(SCHEMA["monitor"]))

    def test_render_rejects_unknown_key(self):
        with self.assertRaisesRegex(k.SettingsError, "unknown key"):
            k.render({"hyprland": {"general:nope": 1}}, self.manifest, SCHEMA)

    def test_render_rejects_out_of_range(self):
        with self.assertRaisesRegex(k.SettingsError, "above the maximum"):
            k.render({"hyprland": {"decoration:rounding": 99}}, self.manifest, SCHEMA)

    def test_monitor_rule_is_complete(self):
        out = k.render({"monitors": {"DP-2": {"cm": "hdr"}}}, self.manifest, SCHEMA)
        self.assertIn('mode = "3840x2160@240"', out)
        self.assertIn('cm = "hdr"', out)
        self.assertNotIn("bootConfirmed", out)


if __name__ == "__main__":
    unittest.main()
```

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v 2>&1 | tail -3
```

Expected: an error, `ModuleNotFoundError: No module named 'krane_ii_settings'`.

- [ ] **Step 6: Write the first part of `krane_ii_settings.py`**

```python
"""krane-ii-settings: persist ii settings GUI changes in the dotfiles repo.

hosts/<host>/ii-settings.json holds sparse deltas that the GUI owns. Nix
renders it into ~/.config/hypr/custom/krane_gui.lua at switch time with
`render`. At runtime the GUI changes it with `set` and `reset`, which write
the repo file, re-render the live file and reload Hyprland. The manifest,
generated by modules/home/ii-settings.nix, names the keys Nix owns and
carries the monitor and idle baselines. See docs/II-INTEGRATION.md,
"Settings persistence".

Standard library only. Tool paths in the constants below are substituted by
pkgs/krane-ii-settings/default.nix.
"""

import argparse
import contextlib
import copy
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile

HYPRCTL = "@hyprctl@"
SYSTEMD_RUN = "@systemdRun@"
SYSTEMCTL = "@systemctl@"
PKILL = "@pkill@"
SETSID = "@setsid@"
HYPRIDLE = "@hypridle@"
SCHEMA_FILE = "@schema@"

REVERT_UNIT = "krane-ii-settings-revert"
REVERT_SECONDS = 15
TOP_LEVEL = ("animationPreset", "hyprland", "idle", "monitors")
OUTPUT_RE = re.compile(r"^[A-Za-z0-9-]+$")
LUA_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

HEADER = (
    "-- GENERATED FILE -- DO NOT EDIT.\n"
    "-- Rendered by krane-ii-settings from hosts/<host>/ii-settings.json.\n"
    "-- Installed as ~/.config/hypr/custom/krane_gui.lua at switch time and\n"
    "-- rewritten live by the ii settings GUI. Loaded from monitors.lua.\n"
)

# Field order of a rendered hl.monitor rule (same order as hypr-config.nix).
MONITOR_ORDER = (
    "output", "mode", "position", "scale", "transform", "vrr", "mirror",
    "bitdepth", "disabled", "cm", "sdrbrightness", "sdrsaturation",
    "sdr_min_luminance", "sdr_max_luminance", "min_luminance",
    "max_luminance", "max_avg_luminance",
)


class SettingsError(Exception):
    """A refusal shown to the user. Exit status 1."""


# Schema and values


def load_schema(path=None):
    if path is None:
        path = SCHEMA_FILE
        if path.startswith("@"):
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.json")
    with open(path) as f:
        return json.load(f)


def parse_cli(spec, text, what):
    """Turn a command-line string into a typed value for `spec`."""
    kind = spec["type"]
    try:
        if kind == "bool":
            low = text.lower()
            if low in ("true", "1", "yes", "on"):
                return True
            if low in ("false", "0", "no", "off"):
                return False
            raise ValueError(text)
        if kind == "int":
            return int(text)
        if kind == "float":
            number = float(text)
            return int(number) if number.is_integer() and "." not in text else number
        if kind == "enum":
            if all(isinstance(v, int) for v in spec["values"]):
                return int(text)
            return text
        return text
    except ValueError:
        raise SettingsError(f"{what}: {text!r} is not a valid {kind}")


def check_value(spec, value, what):
    """Raise SettingsError unless `value` fits `spec`. Returns the value."""
    kind = spec["type"]
    ok = False
    if kind == "bool":
        ok = isinstance(value, bool)
    elif kind == "int":
        ok = isinstance(value, int) and not isinstance(value, bool)
    elif kind == "float":
        ok = isinstance(value, (int, float)) and not isinstance(value, bool)
    elif kind == "enum":
        ok = value in spec["values"] and not isinstance(value, bool)
    elif kind == "str":
        ok = isinstance(value, str) and re.fullmatch(spec["pattern"], value) is not None
    if not ok:
        raise SettingsError(f"{what}: {value!r} is not a valid {kind}")
    if kind in ("int", "float"):
        if "min" in spec and value < spec["min"]:
            raise SettingsError(f"{what}: {value} is below the minimum {spec['min']}")
        if "max" in spec and value > spec["max"]:
            raise SettingsError(f"{what}: {value} is above the maximum {spec['max']}")
    return value


def validate_data(data, schema):
    """Check a whole ii-settings.json document against the schema."""
    if not isinstance(data, dict):
        raise SettingsError("ii-settings.json: the top level must be a JSON object")
    for key in data:
        if key not in TOP_LEVEL:
            raise SettingsError(f"ii-settings.json: unknown top-level key {key!r}")
    for key, value in data.get("hyprland", {}).items():
        if key not in schema["hyprland"]:
            raise SettingsError(f"hyprland.{key}: unknown key (not in the schema)")
        check_value(schema["hyprland"][key], value, f"hyprland.{key}")
    for key, value in data.get("idle", {}).items():
        if key not in schema["idle"]:
            raise SettingsError(f"idle.{key}: unknown key")
        check_value(schema["idle"][key], value, f"idle.{key}")
    if "animationPreset" in data:
        check_value(schema["animationPreset"], data["animationPreset"], "animationPreset")
    for output, fields in data.get("monitors", {}).items():
        if not OUTPUT_RE.match(output):
            raise SettingsError(f"monitors: {output!r} is not an output name")
        if not isinstance(fields, dict):
            raise SettingsError(f"monitors.{output}: must be an object")
        for field, value in fields.items():
            if field not in schema["monitor"]:
                raise SettingsError(f"monitors.{output}.{field}: unknown field")
            check_value(schema["monitor"][field], value, f"monitors.{output}.{field}")


def check_ownership(data, manifest):
    """Refuse any key the manifest says Nix owns."""
    owned = manifest["nixOwned"]
    for key in data.get("hyprland", {}):
        if key in owned["hyprland"]:
            raise SettingsError(f"hyprland.{key}: set in Nix ({nix_hint(manifest)})")
    if data.get("idle") and owned["idle"]:
        raise SettingsError(f"idle: set in Nix ({nix_hint(manifest)})")
    for output, fields in data.get("monitors", {}).items():
        for field in fields:
            if field in owned["monitors"].get(output, []):
                raise SettingsError(f"monitors.{output}.{field}: set in Nix ({nix_hint(manifest)})")


def nix_hint(manifest):
    return f"hosts/{manifest['host']}/display.nix or modules/home"


# Rendering


def lua_str(text):
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return '"' + escaped + '"'


def lua_key(key):
    return key if LUA_IDENT_RE.match(key) else "[" + lua_str(key) + "]"


def lua_value(value, indent):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return lua_str(value)
    if isinstance(value, dict):
        if not value:
            return "{}"
        pad = indent + "    "
        items = [pad + lua_key(k) + " = " + lua_value(value[k], pad) for k in sorted(value)]
        return "{\n" + ",\n".join(items) + "\n" + indent + "}"
    raise SettingsError(f"cannot render {value!r} to Lua")


def nest(flat):
    """{"a:b:c": 1} -> {"a": {"b": {"c": 1}}}"""
    tree = {}
    for key, value in flat.items():
        node = tree
        parts = key.split(":")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    return tree


def monitor_lua(rule):
    pad = "    "
    items = []
    for field in MONITOR_ORDER:
        if field not in rule or rule[field] is None:
            continue
        if field == "disabled" and rule[field] is not True:
            continue
        items.append(pad + field + " = " + lua_value(rule[field], pad))
    return "hl.monitor({\n" + ",\n".join(items) + "\n})\n"


def render(data, manifest, schema):
    validate_data(data, schema)
    out = [HEADER]
    hypr = data.get("hyprland", {})
    if hypr:
        out.append("\nhl.config(" + lua_value(nest(hypr), "") + ")\n")
    preset = data.get("animationPreset")
    if preset:
        out.append(f'\nrequire("hyprland.animationPresets.{preset}")\n')
    monitors = data.get("monitors", {})
    if monitors:
        out.append("\n")
        baselines = manifest.get("monitorBaselines", {})
        for output in sorted(monitors):
            rule = dict(baselines.get(output, {}))
            rule.update({k: v for k, v in monitors[output].items() if k != "bootConfirmed"})
            rule["output"] = output
            out.append(monitor_lua(rule))
    return "".join(out)
```

- [ ] **Step 7: Run the tests**

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v 2>&1 | tail -3
```

Expected: `Ran 6 tests`, `OK`.

- [ ] **Step 8: Stage**

```bash
cd ~/.dotfiles && git add pkgs/krane-ii-settings
```

No commit (commit B1 is in Task 14).

---

### Task 13: Writer commands: set, reset, get, apply

**Files:**
- Modify: `pkgs/krane-ii-settings/krane_ii_settings.py` (append)
- Create: `pkgs/krane-ii-settings/tests/test_commands.py`

**Interfaces:**
- Consumes: everything from Task 12.
- Produces: `atomic_write(path, text)`, `read_repo(path) -> (data, text)` (never creates the file), `locked()` (flock on `$XDG_RUNTIME_DIR/krane-ii-settings.lock`), `read_pending()`/`write_pending(obj)`/`clear_pending()` (`$XDG_RUNTIME_DIR/krane-ii-settings-pending.json`), `hyprctl(args) -> str | None`, class `Runtime(manifest)` with `read_live`, `write_live`, `reload(full=False) -> bool`, `config_errors`, `live_monitor(output)`, `apply_idle(values)`, `start_revert_timer(command)`, `stop_revert_timer`, `revert_timer_active`, `lock_state`, `open_settings`; `effective_idle(data, manifest)`; `edit_set(data, section, key, pairs, schema)`; `complete_rule(data, output, manifest, runtime)`; `edit_reset(data, section, key, fields, manifest)`; `check_owner(section, key, fields, manifest)`; class `Settings(manifest, schema, runtime)` with `get() -> str` (JSON), `set(section, key, pairs)`, `reset(section, key, fields)`, `apply()`, each returning a status string or raising `SettingsError`; `load_manifest(path)`; `pairs_from(args, what)`; `main(argv=None, runtime_factory=Runtime) -> int`.
- CLI: `krane-ii-settings [--manifest FILE] get | set <hyprland|idle|animation|monitor> <key> <value | FIELD VALUE...> | reset <section> <key> [FIELD...] | apply | render --json FILE | schema`. `--manifest` defaults to `$KRANE_II_SETTINGS_MANIFEST`. Exit 0 on success, 1 on a refusal (message on stderr, prefixed `krane-ii-settings: `). `get` exits 0 even when the repo file cannot be parsed and reports it in `error`.

- [ ] **Step 1: Write the failing tests**

`pkgs/krane-ii-settings/tests/test_commands.py`:

```python
"""Command tests for krane_ii_settings (set, reset, apply, get, idle, CLI).
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import json
import os
import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import krane_ii_settings as k  # noqa: E402

FIXTURES = HERE / "fixtures"
SCHEMA = k.load_schema()


class FakeRuntime:
    """Records side effects instead of touching Hyprland, systemd or hypridle."""

    def __init__(self, manifest, errors="", live_monitors=None, running=True):
        self.manifest = manifest
        self.errors = errors
        self.live_monitors = live_monitors or {}
        self.running = running
        self.calls = []
        self.timer = False
        self.lock_states = []

    def read_live(self):
        try:
            return pathlib.Path(self.manifest["liveFile"]).read_text()
        except FileNotFoundError:
            return None

    def write_live(self, text):
        pathlib.Path(self.manifest["liveFile"]).write_text(text)
        self.calls.append(("write_live",))

    def reload(self, full=False):
        self.calls.append(("reload", full))
        return self.running

    def config_errors(self):
        return self.errors

    def live_monitor(self, output):
        return self.live_monitors.get(output)

    def apply_idle(self, values):
        self.calls.append(("apply_idle", dict(values)))

    def start_revert_timer(self, command):
        self.timer = True
        self.calls.append(("start_timer", tuple(command)))

    def stop_revert_timer(self):
        self.timer = False
        self.calls.append(("stop_timer",))

    def revert_timer_active(self):
        return self.timer

    def lock_state(self):
        return self.lock_states.pop(0) if self.lock_states else "false"

    def open_settings(self):
        self.calls.append(("open_settings",))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        os.environ["XDG_RUNTIME_DIR"] = str(self.dir)
        self.manifest = json.loads((FIXTURES / "manifest.json").read_text())
        self.manifest["repoFile"] = str(self.dir / "ii-settings.json")
        self.manifest["liveFile"] = str(self.dir / "krane_gui.lua")
        self.manifest["path"] = str(self.dir / "manifest.json")
        self.repo = pathlib.Path(self.manifest["repoFile"])
        self.repo.write_text("{}\n")
        self.runtime = FakeRuntime(self.manifest)
        self.s = k.Settings(self.manifest, SCHEMA, self.runtime)

    def tearDown(self):
        self.tmp.cleanup()

    def repo_data(self):
        return json.loads(self.repo.read_text())


class TestSetReset(Base):
    def test_sparse_sorted_write(self):
        self.assertEqual(self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")]), "written")
        self.assertEqual(self.repo.read_text(), '{\n  "hyprland": {\n    "general:gaps_in": 12\n  }\n}\n')
        self.assertIn("gaps_in = 12", pathlib.Path(self.manifest["liveFile"]).read_text())
        self.assertIn(("reload", False), self.runtime.calls)

    def test_unchanged_is_noop(self):
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        before = self.repo.stat().st_mtime_ns
        self.runtime.calls.clear()
        self.assertEqual(self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")]), "unchanged")
        self.assertEqual(self.repo.stat().st_mtime_ns, before)
        self.assertEqual(self.runtime.calls, [])

    def test_reset_removes_key_and_section(self):
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.s.reset("hyprland", "general:gaps_in", [])
        self.assertEqual(self.repo_data(), {})
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), k.HEADER)

    def test_bool_from_cli(self):
        self.s.set("hyprland", "decoration:blur:enabled", [("decoration:blur:enabled", "0")])
        self.assertIs(self.repo_data()["hyprland"]["decoration:blur:enabled"], False)

    def test_refuses_nix_owned_key(self):
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.set("hyprland", "input:kb_layout", [("input:kb_layout", "us")])
        self.assertEqual(self.repo.read_text(), "{}\n")

    def test_refuses_nix_owned_reset(self):
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.reset("hyprland", "input:kb_layout", [])

    def test_refuses_unknown_key(self):
        with self.assertRaisesRegex(k.SettingsError, "unknown key"):
            self.s.set("hyprland", "general:nope", [("general:nope", "1")])

    def test_refuses_bad_json_and_leaves_file(self):
        self.repo.write_text('{\n<<<<<<< HEAD\n')
        with self.assertRaisesRegex(k.SettingsError, "cannot parse"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo.read_text(), '{\n<<<<<<< HEAD\n')
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())

    def test_refuses_missing_file_and_never_creates_it(self):
        self.repo.unlink()
        with self.assertRaisesRegex(k.SettingsError, "not persisted"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertFalse(self.repo.exists())

    def test_hyprland_error_reverts(self):
        self.runtime.errors = "error in custom/krane_gui.lua:3: bad value"
        pathlib.Path(self.manifest["liveFile"]).write_text("OLD LIVE\n")
        with self.assertRaisesRegex(k.SettingsError, "rejected"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo.read_text(), "{}\n")
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), "OLD LIVE\n")

    def test_no_hyprland_still_writes(self):
        self.runtime.running = False
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo_data(), {"hyprland": {"general:gaps_in": 12}})

    def test_keeps_external_edits(self):
        self.repo.write_text('{"hyprland": {"general:gaps_out": 7}}\n')
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo_data()["hyprland"], {"general:gaps_in": 12, "general:gaps_out": 7})

    def test_animation_preset(self):
        self.s.set("animation", "preset", [("preset", "fast")])
        self.assertIn('require("hyprland.animationPresets.fast")',
                      pathlib.Path(self.manifest["liveFile"]).read_text())
        with self.assertRaisesRegex(k.SettingsError, "not a valid enum"):
            self.s.set("animation", "preset", [("preset", "bouncy")])


class TestIdle(Base):
    def test_set_idle_applies(self):
        self.s.set("idle", "lock", [("lock", "60")])
        self.assertEqual(self.repo_data(), {"idle": {"lock": 60}})
        self.assertIn(("apply_idle", {"lock": 60, "screenOff": 600, "suspend": 900}), self.runtime.calls)

    def test_idle_owned_by_nix(self):
        self.manifest["nixOwned"]["idle"] = True
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.set("idle", "lock", [("lock", "60")])


class TestCli(Base):
    def test_get_reports_parse_error(self):
        self.repo.write_text("not json")
        (self.dir / "manifest.json").write_text(json.dumps(self.manifest))
        state = json.loads(k.Settings(self.manifest, SCHEMA, self.runtime).get())
        self.assertIn("cannot parse", state["error"])
        self.assertEqual(state["nixOwned"]["hyprland"], ["cursor:default_monitor", "input:kb_layout", "input:kb_variant"])

    def test_main_exit_codes(self):
        (self.dir / "manifest.json").write_text(json.dumps(self.manifest))
        mp = str(self.dir / "manifest.json")
        factory = lambda m: FakeRuntime(m)  # noqa: E731
        self.assertEqual(k.main(["--manifest", mp, "set", "hyprland", "input:kb_layout", "us"], factory), 1)
        self.assertEqual(k.main(["--manifest", mp, "set", "hyprland", "general:gaps_in", "12"], factory), 0)
        self.assertEqual(k.main(["--manifest", mp, "reset", "hyprland", "general:gaps_in"], factory), 0)
        self.assertEqual(self.repo.read_text(), "{}\n")


if __name__ == "__main__":
    unittest.main()
```

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests 2>&1 | tail -3
```

Expected: `FAILED (errors=17)`, with `AttributeError: module 'krane_ii_settings' has no attribute 'Settings'`.

- [ ] **Step 2: Append the commands to `krane_ii_settings.py`**

Append this to the end of the file (it starts with the `# Files` section comment):

```python

# Files


def dump(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def atomic_write(path, text):
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".krane-ii-settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        mode = os.stat(path).st_mode & 0o7777 if os.path.exists(path) else 0o644
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def read_repo(path):
    """Return (data, text). Never creates the file."""
    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        raise SettingsError(f"not persisted: {path} missing")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        raise SettingsError(f"cannot parse {path}: {e}")
    if not isinstance(data, dict):
        raise SettingsError(f"{path}: the top level must be a JSON object")
    return data, text


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def pending_path():
    return os.path.join(runtime_dir(), "krane-ii-settings-pending.json")


def read_pending():
    try:
        with open(pending_path()) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def write_pending(obj):
    atomic_write(pending_path(), json.dumps(obj, sort_keys=True) + "\n")


def clear_pending():
    with contextlib.suppress(FileNotFoundError):
        os.unlink(pending_path())


@contextlib.contextmanager
def locked():
    with open(os.path.join(runtime_dir(), "krane-ii-settings.lock"), "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


# Side effects outside the repo file. Tests pass a fake with the same methods.


def hyprland_signatures():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig:
        return [sig]
    base = os.path.join(runtime_dir(), "hypr")
    try:
        names = sorted(os.listdir(base))
    except FileNotFoundError:
        return []
    return [n for n in names if os.path.exists(os.path.join(base, n, ".socket.sock"))]


def hyprctl(args):
    """Run hyprctl against the first instance that answers. None if none does."""
    for sig in hyprland_signatures():
        env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=sig)
        result = subprocess.run([HYPRCTL, *args], env=env, capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
    return None


class Runtime:
    def __init__(self, manifest):
        self.manifest = manifest

    def read_live(self):
        try:
            with open(self.manifest["liveFile"]) as f:
                return f.read()
        except FileNotFoundError:
            return None

    def write_live(self, text):
        os.makedirs(os.path.dirname(self.manifest["liveFile"]), exist_ok=True)
        atomic_write(self.manifest["liveFile"], text)

    def reload(self, full=False):
        return hyprctl(["reload"] if full else ["reload", "config-only"]) is not None

    def config_errors(self):
        return hyprctl(["configerrors"]) or ""

    def live_monitor(self, output):
        out = hyprctl(["monitors", "all", "-j"])
        if out is None:
            return None
        for mon in json.loads(out):
            if mon.get("name") == output:
                refresh = round(float(mon["refreshRate"]), 3)
                return {
                    "mode": f"{mon['width']}x{mon['height']}@{refresh:g}",
                    "position": f"{mon['x']}x{mon['y']}",
                    "scale": float(mon["scale"]),
                }
        return None

    def apply_idle(self, values):
        conf = self.manifest["hypridleFile"]
        script = self.manifest["idleConfigurator"]
        if not (os.path.isfile(conf) and os.path.isfile(script)):
            return
        subprocess.run(
            [sys.executable, script, "--file", conf,
             "--lock", str(values["lock"]),
             "--screen-off", str(values["screenOff"]),
             "--suspend", str(values["suspend"])],
            check=True, capture_output=True, text=True)
        subprocess.run([PKILL, "-x", "hypridle"], capture_output=True)
        subprocess.run([SETSID, "-f", HYPRIDLE], stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def start_revert_timer(self, command):
        units = [f"{REVERT_UNIT}.timer", f"{REVERT_UNIT}.service"]
        subprocess.run([SYSTEMCTL, "--user", "stop", *units], capture_output=True)
        subprocess.run([SYSTEMCTL, "--user", "reset-failed", *units], capture_output=True)
        subprocess.run(
            [SYSTEMD_RUN, "--user", f"--unit={REVERT_UNIT}", "--collect",
             f"--on-active={REVERT_SECONDS}s", "--timer-property=AccuracySec=100ms",
             f"--setenv=KRANE_II_SETTINGS_MANIFEST={self.manifest['path']}",
             os.path.realpath(sys.argv[0]), *command],
            check=True, capture_output=True, text=True)

    def stop_revert_timer(self):
        # Only the timer: the service may be the process calling this.
        subprocess.run([SYSTEMCTL, "--user", "stop", f"{REVERT_UNIT}.timer"], capture_output=True)

    def revert_timer_active(self):
        result = subprocess.run(
            [SYSTEMCTL, "--user", "is-active", "--quiet", f"{REVERT_UNIT}.timer"])
        return result.returncode == 0

    def lock_state(self):
        """"true"/"false" from ii's lock IPC, or None while it is not up."""
        result = subprocess.run(
            [self.manifest["qsBin"], "-c", "ii", "ipc", "call", "lock", "isLocked"],
            capture_output=True, text=True)
        text = result.stdout.strip()
        return text if result.returncode == 0 and text in ("true", "false") else None

    def open_settings(self):
        env = dict(os.environ, II_SETTINGS_PAGE="HyprlandConfig")
        subprocess.run([SETSID, "-f", self.manifest["qsBin"], "-p", self.manifest["settingsQml"]],
                       env=env, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# Edits


def effective_idle(data, manifest):
    idle = dict(manifest["idleBaseline"])
    if not manifest["nixOwned"]["idle"]:
        idle.update(data.get("idle", {}))
    return idle


def edit_set(data, section, key, pairs, schema):
    """Return a copy of `data` with the change applied. `pairs` is a list of
    (field, raw string) for monitors and [(key, raw)] otherwise."""
    new = copy.deepcopy(data)
    if section == "hyprland":
        if key not in schema["hyprland"]:
            raise SettingsError(f"hyprland.{key}: unknown key (not in the schema)")
        (_, raw), = pairs
        spec = schema["hyprland"][key]
        new.setdefault("hyprland", {})[key] = check_value(
            spec, parse_cli(spec, raw, f"hyprland.{key}"), f"hyprland.{key}")
    elif section == "idle":
        if key not in schema["idle"]:
            raise SettingsError(f"idle.{key}: unknown key")
        (_, raw), = pairs
        spec = schema["idle"][key]
        new.setdefault("idle", {})[key] = check_value(
            spec, parse_cli(spec, raw, f"idle.{key}"), f"idle.{key}")
    elif section == "animation":
        if key != "preset":
            raise SettingsError(f"animation.{key}: unknown key")
        (_, raw), = pairs
        new["animationPreset"] = check_value(schema["animationPreset"], raw, "animationPreset")
    elif section == "monitor":
        if not OUTPUT_RE.match(key):
            raise SettingsError(f"monitor: {key!r} is not an output name")
        entry = new.setdefault("monitors", {}).setdefault(key, {})
        for field, raw in pairs:
            spec = schema["monitor"].get(field)
            if spec is None or spec.get("internal"):
                raise SettingsError(f"monitors.{key}.{field}: unknown field")
            what = f"monitors.{key}.{field}"
            entry[field] = check_value(spec, parse_cli(spec, raw, what), what)
    else:
        raise SettingsError(f"unknown section {section!r}")
    return new


def complete_rule(data, output, manifest, runtime):
    """An output Nix does not know needs a complete rule in the GUI file."""
    if output in manifest["monitorBaselines"]:
        return data
    entry = data["monitors"][output]
    missing = [f for f in ("mode", "position", "scale") if f not in entry]
    if not missing:
        return data
    live = runtime.live_monitor(output)
    if live is None:
        raise SettingsError(
            f"monitors.{output}: not in krane.hypr.monitors, and its current rule cannot be "
            "read from Hyprland")
    for field in missing:
        entry[field] = live[field]
    return data


def edit_reset(data, section, key, fields, manifest):
    new = copy.deepcopy(data)
    if section == "hyprland":
        new.get("hyprland", {}).pop(key, None)
    elif section == "idle":
        new.get("idle", {}).pop(key, None)
    elif section == "animation":
        if key != "preset":
            raise SettingsError(f"animation.{key}: unknown key")
        new.pop("animationPreset", None)
    elif section == "monitor":
        monitors = new.get("monitors", {})
        if key in monitors:
            gui_owned_rule = key not in manifest["monitorBaselines"]
            if not fields or (gui_owned_rule and {"mode", "position", "scale"} & set(fields)):
                # No fields, or a field without which a GUI-owned rule is incomplete.
                del monitors[key]
            else:
                for field in fields:
                    monitors[key].pop(field, None)
    else:
        raise SettingsError(f"unknown section {section!r}")
    for output in list(new.get("monitors", {})):
        if not set(new["monitors"][output]) - {"bootConfirmed"}:
            del new["monitors"][output]
    for name in ("hyprland", "idle", "monitors"):
        if name in new and not new[name]:
            del new[name]
    return new


def check_owner(section, key, fields, manifest):
    owned = manifest["nixOwned"]
    if section == "hyprland" and key in owned["hyprland"]:
        raise SettingsError(f"hyprland.{key}: set in Nix ({nix_hint(manifest)})")
    if section == "idle" and owned["idle"]:
        raise SettingsError(f"idle: set in Nix ({nix_hint(manifest)})")
    if section == "monitor":
        for field in fields:
            if field in owned["monitors"].get(key, []):
                raise SettingsError(f"monitors.{key}.{field}: set in Nix ({nix_hint(manifest)})")


# Commands. Each returns the text to print; SettingsError means exit 1.


class Settings:
    def __init__(self, manifest, schema, runtime):
        self.manifest = manifest
        self.schema = schema
        self.runtime = runtime
        self.repo = manifest["repoFile"]

    def render(self, data):
        return render(data, self.manifest, self.schema)

    def commit(self, old_text, new, full_reload=False):
        """Write `new` to the repo and live file and reload; revert if
        Hyprland reports an error in krane_gui.lua. No-op when unchanged."""
        validate_data(new, self.schema)
        check_ownership(new, self.manifest)
        new_text = dump(new)
        if new_text == old_text:
            return "unchanged"
        old_live = self.runtime.read_live()
        atomic_write(self.repo, new_text)
        self.runtime.write_live(self.render(new))
        if self.runtime.reload(full=full_reload):
            errors = self.runtime.config_errors()
            if "krane_gui" in errors:
                atomic_write(self.repo, old_text)
                if old_live is None:
                    old_live = self.render(json.loads(old_text))
                self.runtime.write_live(old_live)
                self.runtime.reload(full=full_reload)
                raise SettingsError("Hyprland rejected the change; reverted.\n" + errors.strip())
        old = json.loads(old_text)
        if old.get("idle") != new.get("idle"):
            self.runtime.apply_idle(effective_idle(new, self.manifest))
        return "written"

    def get(self):
        state = {
            "host": self.manifest["host"],
            "repoFile": self.repo,
            "liveFile": self.manifest["liveFile"],
            "nixOwned": self.manifest["nixOwned"],
            "monitorBaselines": self.manifest["monitorBaselines"],
            "idleBaseline": self.manifest["idleBaseline"],
            "repo": None,
            "error": None,
            "pending": read_pending(),
            "revertPending": self.runtime.revert_timer_active(),
            "unconfirmed": [],
        }
        try:
            data, _ = read_repo(self.repo)
            validate_data(data, self.schema)
            state["repo"] = data
            state["idle"] = effective_idle(data, self.manifest)
            state["unconfirmed"] = sorted(
                o for o, e in data.get("monitors", {}).items() if e.get("bootConfirmed") is False)
        except SettingsError as e:
            state["error"] = str(e)
            state["idle"] = dict(self.manifest["idleBaseline"])
        return json.dumps(state, sort_keys=True)

    def set(self, section, key, pairs):
        check_owner(section, key, [f for f, _ in pairs], self.manifest)
        with locked():
            data, text = read_repo(self.repo)
            new = edit_set(data, section, key, pairs, self.schema)
            if section == "monitor":
                new = complete_rule(new, key, self.manifest, self.runtime)
                new["monitors"][key]["bootConfirmed"] = False
            return self.commit(text, new, full_reload=section == "monitor")

    def reset(self, section, key, fields):
        check_owner(section, key, fields, self.manifest)
        with locked():
            data, text = read_repo(self.repo)
            new = edit_reset(data, section, key, fields, self.manifest)
            return self.commit(text, new, full_reload=section == "monitor")

    def apply(self):
        with locked():
            pending = read_pending()
            try:
                data, _ = read_repo(self.repo)
                validate_data(data, self.schema)
                check_ownership(data, self.manifest)
            except SettingsError:
                # The revert timer of a `try` must work even if the repo file broke
                # in the meantime: put back the live file from before the try.
                if pending and pending.get("kind") == "try":
                    self.runtime.stop_revert_timer()
                    self.runtime.write_live(pending.get("previousLive") or HEADER)
                    clear_pending()
                    self.runtime.reload(full=True)
                raise
            full = pending is not None
            self.runtime.stop_revert_timer()
            self.runtime.write_live(self.render(data))
            clear_pending()
            self.runtime.reload(full=full)
            if "idle" in data:
                self.runtime.apply_idle(effective_idle(data, self.manifest))
            return "applied"


def load_manifest(path):
    if not path:
        raise SettingsError("no manifest: pass --manifest or set KRANE_II_SETTINGS_MANIFEST")
    with open(path) as f:
        manifest = json.load(f)
    manifest["path"] = path
    return manifest


def pairs_from(args, what):
    if len(args) % 2:
        raise SettingsError(f"{what}: expected FIELD VALUE pairs")
    return [(args[i], args[i + 1]) for i in range(0, len(args), 2)]


def main(argv=None, runtime_factory=Runtime):
    parser = argparse.ArgumentParser(prog="krane-ii-settings")
    parser.add_argument("--manifest", default=os.environ.get("KRANE_II_SETTINGS_MANIFEST"))
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("get")
    p_set = sub.add_parser("set")
    p_set.add_argument("section", choices=["hyprland", "idle", "animation", "monitor"])
    p_set.add_argument("key")
    p_set.add_argument("rest", nargs="+")
    p_reset = sub.add_parser("reset")
    p_reset.add_argument("section", choices=["hyprland", "idle", "animation", "monitor"])
    p_reset.add_argument("key")
    p_reset.add_argument("fields", nargs="*")
    sub.add_parser("apply")
    p_render = sub.add_parser("render")
    p_render.add_argument("--json", required=True)
    sub.add_parser("schema")
    args = parser.parse_args(argv)
    schema = load_schema()
    try:
        if args.cmd == "schema":
            print(dump(schema), end="")
            return 0
        manifest = load_manifest(args.manifest)
        if args.cmd == "render":
            data, _ = read_repo(args.json)
            print(render(data, manifest, schema), end="")
            return 0
        settings = Settings(manifest, schema, runtime_factory(manifest))
        if args.cmd == "get":
            out = settings.get()
        elif args.cmd == "set":
            if args.section == "monitor":
                pairs = pairs_from(args.rest, "set monitor")
            else:
                if len(args.rest) != 1:
                    raise SettingsError(f"set {args.section} {args.key}: expected one value")
                pairs = [(args.key, args.rest[0])]
            out = settings.set(args.section, args.key, pairs)
        elif args.cmd == "reset":
            out = settings.reset(args.section, args.key, args.fields)
        else:
            out = settings.apply()
        print(out)
        return 0
    except SettingsError as e:
        print(f"krane-ii-settings: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Run the tests**

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests 2>&1 | grep -E '^(Ran|OK|FAILED)'
```

Expected: `Ran 23 tests`, `OK`.

- [ ] **Step 4: Lint like the package build will**

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings && nix run nixpkgs#python3Packages.flake8 -- --ignore=E501,W503 krane_ii_settings.py && echo FLAKE-OK
```

Expected: `FLAKE-OK` (`writePython3Bin` runs flake8 with the same ignore list and fails the build otherwise).

- [ ] **Step 5: Concurrent writers keep the file valid (Review Focus 3)**

The source file has no tool paths yet, so this runs with no Hyprland instance visible (a scratch `XDG_RUNTIME_DIR` without `hypr/`, and `HYPRLAND_INSTANCE_SIGNATURE` unset), which the writer treats as "write, skip the reload".

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); echo '{}' > "$t/ii.json"
jq --arg r "$t/ii.json" --arg l "$t/live.lua" '.repoFile = $r | .liveFile = $l' tests/fixtures/manifest.json > "$t/m.json"
w() { env -u HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR="$t" python3 krane_ii_settings.py --manifest "$t/m.json" "$@"; }
for i in $(seq 1 20); do w set hyprland general:gaps_in "$i" >/dev/null & done; wait
jq -e '.hyprland["general:gaps_in"] | . >= 1 and . <= 20' "$t/ii.json"
command ls -A "$t" | grep -c '\.tmp$'
for i in $(seq 1 20); do w set hyprland general:gaps_in "$i" >/dev/null; done
jq '.hyprland["general:gaps_in"]' "$t/ii.json"
grep -c 'gaps_in = 20' "$t/live.lua"
rm -rf "$t"
```

Expected: `true`, `0` (no leftover temp files), `20`, `1`.

- [ ] **Step 6: Stage**

```bash
cd ~/.dotfiles && git add pkgs/krane-ii-settings
```

---

### Task 14: Package, flake check and the per-host files (commit B1)

**Files:**
- Create: `pkgs/krane-ii-settings/default.nix`
- Modify: `pkgs/default.nix`, `flake.nix` (`checks`)
- Create: `hosts/tariognatha/ii-settings.json`, `hosts/tarmantria/ii-settings.json`, `hosts/taractias/ii-settings.json`

**Interfaces:**
- Produces: `pkgs.callPackage ./pkgs/krane-ii-settings { }`, a derivation with `bin/krane-ii-settings`; flake output `packages.x86_64-linux.krane-ii-settings`; check `checks.x86_64-linux.ii-settings-writer`.

- [ ] **Step 1: Show the check does not exist (failing check)**

```bash
cd ~/.dotfiles && nix build --no-link .#checks.x86_64-linux.ii-settings-writer 2>&1 | tail -1
```

Expected: an error that the attribute `ii-settings-writer` is missing.

- [ ] **Step 2: Write `pkgs/krane-ii-settings/default.nix`**

```nix
# krane-ii-settings: the only writer of hosts/<host>/ii-settings.json, used by the ii settings
# GUI's persistent controls and by modules/home/ii-settings.nix to render krane_gui.lua at
# build time. Standard library only; tool paths are baked in here.
# See docs/II-INTEGRATION.md "Settings persistence".
{
  lib,
  writers,
  hyprland,
  hypridle,
  systemd,
  procps,
  util-linux,
}:
let
  source =
    builtins.replaceStrings
      [
        "@hyprctl@"
        "@systemdRun@"
        "@systemctl@"
        "@pkill@"
        "@setsid@"
        "@hypridle@"
        "@schema@"
      ]
      [
        (lib.getExe' hyprland "hyprctl")
        (lib.getExe' systemd "systemd-run")
        (lib.getExe' systemd "systemctl")
        (lib.getExe' procps "pkill")
        (lib.getExe' util-linux "setsid")
        (lib.getExe' hypridle "hypridle")
        "${./schema.json}"
      ]
      (builtins.readFile ./krane_ii_settings.py);
in
writers.writePython3Bin "krane-ii-settings" {
  # Long lines are tables and messages; W503 conflicts with the house style.
  flakeIgnore = [
    "E501"
    "W503"
  ];
} source
```

In `pkgs/default.nix` add, after the `claude-code` entry (and after `claude-notify`, if sub-project 4's Task 1 added it):

```nix
  krane-ii-settings = pkgs.callPackage ./krane-ii-settings { };
```

- [ ] **Step 3: Add the check to `flake.nix`**

In `checks.${system}`, before the `# NixVim's own startup test` comment:

```nix
        # pkgs/krane-ii-settings unit tests: schema validation, sparse writes, no-op on
        # unchanged content, refusals (bad JSON, Nix-owned or unknown key), render goldens.
        ii-settings-writer =
          pkgs.runCommand "ii-settings-writer-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              export PYTHONDONTWRITEBYTECODE=1
              cd ${./pkgs/krane-ii-settings}
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';

```

- [ ] **Step 4: The per-host files, committed as `{}`**

```bash
cd ~/.dotfiles
for h in tariognatha tarmantria taractias; do printf '{}\n' > hosts/$h/ii-settings.json; done
git add pkgs/default.nix pkgs/krane-ii-settings flake.nix hosts/*/ii-settings.json
```

- [ ] **Step 5: Build and run (passing check)**

```bash
cd ~/.dotfiles
out=$(nix build --no-link --print-out-paths .#krane-ii-settings)
grep -nE '^(HYPRCTL|SCHEMA_FILE) =' "$out/bin/krane-ii-settings"
"$out/bin/krane-ii-settings" schema | jq -r '.hyprland | length'
"$out/bin/krane-ii-settings" get; echo "exit $?"
nix build --no-link -L .#checks.x86_64-linux.ii-settings-writer 2>&1 | tail -3
```

Expected: both constants are `/nix/store/...` paths (`hyprland-0.56.2/bin/hyprctl`, `...-schema.json`); `23`; `krane-ii-settings: no manifest: ...` and `exit 1`; the check ends with `Ran 23 tests` and `OK`.

- [ ] **Step 6: Commit B1**

```bash
cd ~/.dotfiles
git commit -m "Add the krane-ii-settings writer, its schema and tests, and an empty ii-settings.json per host"
```

---

### Task 15: Render GUI settings at build time (commit B2)

**Files:**
- Create: `modules/home/ii-settings.nix`
- Modify: `modules/home/default.nix` (import), `modules/home/hypr-config.nix` (`monitorsFile`, `_rendered`), `modules/home/illogical-impulse.nix` (`ownedFiles`), `flake.nix` (`checks`)

**Interfaces:**
- Consumes: `krane.dotfilesDir` (Task 2), `pkgs/krane-ii-settings` (Task 14), `krane.hypr.{settings, monitors, idleTimeouts}`.
- Produces: option `krane.hypr.guiLocked` (`listOf str`); internal read-only `krane.iiSettings.manifestFile` (path); `krane.hypr._rendered."custom/krane_gui.lua"`; `home.packages` gains `krane-ii-settings` (the writer with this host's manifest in `KRANE_II_SETTINGS_MANIFEST`); check `ii-settings-render`.

- [ ] **Step 1: Show nothing renders yet (failing check)**

```bash
cd ~/.dotfiles
nix eval --json .#nixosConfigurations.tariognatha.config.home-manager.users.krane.krane.hypr._rendered --apply 'r: r ? "custom/krane_gui.lua"'
```

Expected: `false`.

- [ ] **Step 2: Write `modules/home/ii-settings.nix`**

```nix
# Hyprland settings saved from the ii settings window. The GUI writes them, through
# krane-ii-settings (pkgs/krane-ii-settings), as sparse deltas into hosts/<host>/ii-settings.json.
# This module renders that file into the owned custom/krane_gui.lua, which monitors.lua requires
# last, and gives the writer its manifest: which keys Nix owns, and the monitor and idle
# baselines. Every key has exactly one owner, Nix or the GUI file; a key set in both fails
# evaluation. See docs/II-INTEGRATION.md "Settings persistence".
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  cfg = config.krane.hypr;
  home = config.home.homeDirectory;
  writer = pkgs.callPackage ../../pkgs/krane-ii-settings { };
  # One key list for Nix and the writer; read here without building anything.
  schema = lib.importJSON ../../pkgs/krane-ii-settings/schema.json;

  where = "hosts/${hostName}/ii-settings.json";
  src = ../../hosts + "/${hostName}/ii-settings.json";
  gui = if builtins.pathExists src then lib.importJSON src else { };
  guiHypr = gui.hyprland or { };
  guiMonitors = gui.monitors or { };

  # { input = { kb_layout = "at"; }; } -> [ "input:kb_layout" ]
  flatten =
    prefix: attrs:
    lib.concatLists (
      lib.mapAttrsToList (
        k: v:
        let
          key = if prefix == "" then k else "${prefix}:${k}";
        in
        if builtins.isAttrs v then flatten key v else [ key ]
      ) attrs
    );
  nixHyprKeys = lib.unique (flatten "" cfg.settings ++ cfg.guiLocked);

  # These have defaults, so every monitor Nix declares sets them.
  fixedMonitorFields = [
    "output"
    "mode"
    "position"
    "scale"
    "disabled"
  ];
  # Nix-owned only when non-null. `or null` keeps this valid for fields the monitor submodule
  # does not have yet.
  optionalMonitorFields = [
    "transform"
    "vrr"
    "mirror"
    "bitdepth"
    "cm"
    "sdrbrightness"
    "sdrsaturation"
    "sdr_min_luminance"
    "sdr_max_luminance"
    "min_luminance"
    "max_luminance"
    "max_avg_luminance"
  ];
  nixMonitors = lib.listToAttrs (
    map (
      m:
      let
        setFields = lib.filter (f: (m.${f} or null) != null) optionalMonitorFields;
      in
      lib.nameValuePair m.output {
        owned = fixedMonitorFields ++ setFields;
        baseline = {
          inherit (m)
            output
            mode
            position
            scale
            ;
        }
        // lib.optionalAttrs m.disabled { disabled = true; }
        // lib.genAttrs setFields (f: m.${f});
      }
    ) cfg.monitors
  );

  # idleTimeouts = false is shorthand for all zeros. null: not set by Nix.
  nixIdle =
    if !cfg.idleTimeouts then
      {
        lock = 0;
        screenOff = 0;
        suspend = 0;
      }
    else
      null;
  # ii's own hypridle.conf listeners at the pinned revision.
  iiIdle = {
    lock = 300;
    screenOff = 600;
    suspend = 900;
  };

  manifest = {
    host = hostName;
    repoFile = "${config.krane.dotfilesDir}/${where}";
    liveFile = "${home}/.config/hypr/custom/krane_gui.lua";
    hypridleFile = "${home}/.config/hypr/hypridle.conf";
    idleConfigurator = "${home}/.config/quickshell/ii/scripts/hyprland/hypridleconfigurator.py";
    qsBin = "${config.home.profileDirectory}/bin/qs";
    settingsQml = "${home}/.config/quickshell/ii/settings.qml";
    nixOwned = {
      hyprland = lib.sort lib.lessThan nixHyprKeys;
      idle = nixIdle != null;
      monitors = lib.mapAttrs (_: v: lib.sort lib.lessThan v.owned) nixMonitors;
    };
    monitorBaselines = lib.mapAttrs (_: v: v.baseline) nixMonitors;
    idleBaseline = if nixIdle != null then nixIdle else iiIdle;
  };
  manifestFile = pkgs.writeText "krane-ii-settings-manifest-${hostName}.json" (
    builtins.toJSON manifest
  );

  # The writer with this host's manifest baked in; what the GUI calls.
  wrapped = pkgs.writeShellScriptBin "krane-ii-settings" ''
    export KRANE_II_SETTINGS_MANIFEST=${manifestFile}
    exec ${writer}/bin/krane-ii-settings "$@"
  '';

  # Same renderer as the GUI uses at runtime. Plain build-time runCommand on repo files, not
  # import-from-derivation: the result is only installed, never read back into evaluation.
  rendered = pkgs.runCommand "krane-hypr-custom-krane_gui.lua" { } ''
    ${writer}/bin/krane-ii-settings --manifest ${manifestFile} \
      render --json ${pkgs.writeText "ii-settings-${hostName}.json" (builtins.toJSON gui)} > $out
  '';

  unknownKeys =
    map (k: "${k} (top level)") (
      lib.filter (
        k:
        !(lib.elem k [
          "animationPreset"
          "hyprland"
          "idle"
          "monitors"
        ])
      ) (lib.attrNames gui)
    )
    ++ map (k: "hyprland.${k}") (lib.filter (k: !(schema.hyprland ? ${k})) (lib.attrNames guiHypr))
    ++ map (k: "idle.${k}") (lib.filter (k: !(schema.idle ? ${k})) (lib.attrNames (gui.idle or { })))
    ++ lib.concatLists (
      lib.mapAttrsToList (
        o: fields:
        map (f: "monitors.${o}.${f}") (lib.filter (f: !(schema.monitor ? ${f})) (lib.attrNames fields))
      ) guiMonitors
    );

  overlap =
    map (k: "hyprland.${k}") (lib.filter (k: lib.elem k nixHyprKeys) (lib.attrNames guiHypr))
    ++ lib.optional ((gui ? idle) && nixIdle != null) "idle"
    ++ lib.concatLists (
      lib.mapAttrsToList (
        o: fields:
        map (f: "monitors.${o}.${f}") (
          lib.filter (f: lib.elem f (nixMonitors.${o}.owned or [ ])) (lib.attrNames fields)
        )
      ) guiMonitors
    );
in
{
  options.krane.hypr.guiLocked = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "general:layout" ];
    description = ''
      Hyprland keys (`section:key`, as in pkgs/krane-ii-settings/schema.json) that Nix wants
      left at the upstream default. The ii settings window shows them disabled with "Set in
      Nix", like any key set in krane.hypr.settings.
    '';
  };

  options.krane.iiSettings.manifestFile = lib.mkOption {
    type = lib.types.path;
    internal = true;
    readOnly = true;
    description = "The krane-ii-settings manifest for this host; used by checks.ii-settings-render.";
  };

  config = {
    krane.hypr._rendered."custom/krane_gui.lua" = rendered;
    krane.iiSettings.manifestFile = manifestFile;
    home.packages = [ wrapped ];

    assertions = [
      {
        assertion = unknownKeys == [ ];
        message = ''
          ${where}: ${lib.concatStringsSep ", " unknownKeys} not in
          pkgs/krane-ii-settings/schema.json. Only keys checked against Hyprland 0.56 may be
          written; remove them, or add them to the schema after checking them.
        '';
      }
      {
        assertion = overlap == [ ];
        message = ''
          ${where} sets ${lib.concatStringsSep ", " overlap}, which Nix also sets
          (krane.hypr.settings, krane.hypr.guiLocked, krane.hypr.monitors or idle, in
          hosts/${hostName}/display.nix or modules/home). Every key has one owner: delete it
          from one of the two.
        '';
      }
      {
        assertion = lib.all (k: schema.hyprland ? ${k}) cfg.guiLocked;
        message = ''
          krane.hypr.guiLocked: ${
            lib.concatStringsSep ", " (lib.filter (k: !(schema.hyprland ? ${k})) cfg.guiLocked)
          } not in pkgs/krane-ii-settings/schema.json.
        '';
      }
    ];
  };
}
```

- [ ] **Step 3: Wire it in**

1. `modules/home/default.nix`: add `./ii-settings.nix` right after `./ii-config-dir.nix`.
2. `modules/home/illogical-impulse.nix`: add `"custom/krane_gui.lua"` as the last entry of `ownedFiles`.
3. `modules/home/hypr-config.nix`: replace

   ```nix
     monitorsFile = header "monitors.lua" + "\n" + lib.concatMapStrings monitorLua cfg.monitors;
   ```

   with

   ```nix
     # The trailer loads the settings saved from the ii settings window (modules/home/ii-settings.nix)
     # last, after every krane.hypr.* file, and before ii's transient shellOverrides.
     monitorsFile =
       header "monitors.lua"
       + "\n"
       + lib.concatMapStrings monitorLua cfg.monitors
       + ''

         if is_file_exists(HOME .. "/.config/hypr/custom/krane_gui.lua") then
             require("custom.krane_gui")
         end
       '';
   ```

4. `modules/home/hypr-config.nix`, option `_rendered`: delete the line `readOnly = true;` (ii-settings.nix now adds an entry), and change its description to:

   ```nix
      description = ''
        Rendered Lua files, keyed by their path relative to ~/.config/hypr.
        Set here and by modules/home/ii-settings.nix (custom/krane_gui.lua).
        Consumed by modules/home/illogical-impulse.nix (installation) and by
        the flake's `lua-syntax` check (`luac -p`).
      '';
   ```

5. `flake.nix`, in `checks.${system}` after `ii-settings-writer`:

   ```nix
        # Every schema key and every monitor field, rendered against tariognatha's real
        # manifest and parsed. checks.lua-syntax only sees what each host's JSON holds.
        ii-settings-render =
          let
            writer = pkgs.callPackage ./pkgs/krane-ii-settings { };
            manifest =
              self.nixosConfigurations.tariognatha.config.home-manager.users.krane.krane.iiSettings.manifestFile;
          in
          pkgs.runCommand "ii-settings-render" { } ''
            ${writer}/bin/krane-ii-settings --manifest ${manifest} \
              render --json ${./pkgs/krane-ii-settings/tests/fixtures/all-keys.json} > krane_gui.lua
            ${pkgs.lua5_4}/bin/luac -p krane_gui.lua
            grep -q 'require("hyprland.animationPresets.fast")' krane_gui.lua
            grep -q 'cm = "hdr"' krane_gui.lua
            touch "$out"
          '';

   ```

```bash
cd ~/.dotfiles && git add modules/home/ii-settings.nix modules/home/default.nix modules/home/hypr-config.nix modules/home/illogical-impulse.nix flake.nix
```

- [ ] **Step 4: `{}` renders the header only; `monitors.lua` loads it (passing check)**

```bash
cd ~/.dotfiles
H=.#nixosConfigurations.tariognatha.config.home-manager.users.krane
cmp "$(nix build --no-link --print-out-paths "$H.krane.hypr._rendered.\"custom/krane_gui.lua\"")" pkgs/krane-ii-settings/tests/golden/empty.lua && echo HEADER-ONLY
tail -4 "$(nix build --no-link --print-out-paths "$H.krane.hypr._rendered.\"monitors.lua\"")"
jq -c '.nixOwned, .idleBaseline' "$(nix build --no-link --print-out-paths "$H.krane.iiSettings.manifestFile")"
```

Expected: `HEADER-ONLY`; the `if is_file_exists(...krane_gui.lua) ... end` trailer; `{"hyprland":["cursor:default_monitor","input:kb_layout","input:kb_variant"],"idle":true,"monitors":{"DP-1":["disabled","mode","output","position","scale"],"DP-2":["disabled","mode","output","position","scale"]}}` and `{"lock":0,"screenOff":0,"suspend":0}`.

- [ ] **Step 5: Ownership and schema are enforced at eval time**

Each case edits a tracked file, evaluates, and restores it:

```bash
cd ~/.dotfiles
ev() { nix eval --raw .#nixosConfigurations.tariognatha.config.system.build.toplevel.drvPath 2>&1 | grep -A4 'Failed assertions' | head -5; }
printf '{"hyprland":{"input:kb_layout":"us"}}\n' > hosts/tariognatha/ii-settings.json; ev
printf '{"hyprland":{"general:nope":1}}\n' > hosts/tariognatha/ii-settings.json; ev
printf '{"hyprland":{"general:gaps_in":12}}\n' > hosts/tariognatha/ii-settings.json
sed -i 's|    settings.cursor.default_monitor = "DP-2";|    settings.cursor.default_monitor = "DP-2";\n    settings.general.gaps_in = 4;|' hosts/tariognatha/display.nix; ev
git checkout -- hosts/tariognatha/display.nix; printf '{}\n' > hosts/tariognatha/ii-settings.json
git diff --stat hosts/tariognatha
```

Expected: three assertion failures: `hosts/tariognatha/ii-settings.json sets hyprland.input:kb_layout, which Nix also sets ... hosts/tariognatha/display.nix`; `... hyprland.general:nope not in pkgs/krane-ii-settings/schema.json`; `... sets hyprland.general:gaps_in, which Nix also sets ...`. The final `git diff --stat` prints nothing.

- [ ] **Step 6: Flake check and dry-builds**

```bash
cd ~/.dotfiles
nix flake check
for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
```

Expected: passes (including `lua-syntax`, now with `custom/krane_gui.lua` for every host, and `ii-settings-render`); no `FAIL`.

- [ ] **Step 7: Switch and exercise the writer from the command line**

```bash
sudo nixos-rebuild switch --flake .#tariognatha
command cat ~/.config/hypr/custom/krane_gui.lua; hyprctl configerrors
krane-ii-settings set hyprland input:kb_layout us; echo "exit $?"
krane-ii-settings set hyprland general:gaps_in 12 && sleep 1 && hyprctl getoption general:gaps_in -j | jq -r .css
git -C ~/.dotfiles diff hosts/tariognatha/ii-settings.json
krane-ii-settings reset hyprland general:gaps_in && sleep 1 && hyprctl getoption general:gaps_in -j | jq -r .css
git -C ~/.dotfiles diff --stat hosts/tariognatha/ii-settings.json
```

Expected: the header only and no config errors; `krane-ii-settings: hyprland.input:kb_layout: set in Nix (hosts/tariognatha/display.nix or modules/home)` and `exit 1`; `12 12 12 12`; a diff adding `"general:gaps_in": 12`; the value back to ii's (for example `4 4 4 4`) with no switch; no diff.

- [ ] **Step 8: Commit B2**

```bash
cd ~/.dotfiles
git commit -m "Render settings saved from the ii settings window into krane_gui.lua, with one owner per key"
```

---

### Task 16: Idle timeouts (commit B3)

`krane.hypr.idle` replaces the `hypridle.conf` sed. The idle writer script comes from the fork.

**Files:**
- Create (clone): `$II/scripts/hyprland/hypridleconfigurator.py`
- Modify: `modules/home/hypr-config.nix` (`idleTimeouts`, new `idle`), `modules/home/ii-settings.nix` (idle mapping, activation, assertion), `modules/home/illogical-impulse.nix` (drop the hypridle `iiPatches` entry)

**Interfaces:**
- Produces: option `krane.hypr.idle` (`nullOr { lock, screenOff, suspend : ints.between 0 86400 }`, default `null`); activation entry `kraneIiIdle` (after `copyIllogicalImpulseConfigs`, only when there are values to write).
- Consumes: `hypridleconfigurator.py --file F --lock N --screen-off N --suspend N` (0 removes that listener).

- [ ] **Step 1: Port the script**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
II=~/src/dots-hyprland/dots/.config/quickshell/ii
curl -sfL "$F/scripts/hyprland/hypridleconfigurator.py" -o "$II/scripts/hyprland/hypridleconfigurator.py"
chmod +x "$II/scripts/hyprland/hypridleconfigurator.py"
head -1 "$II/scripts/hyprland/hypridleconfigurator.py"
grep -nE '^(import|from) ' "$II/scripts/hyprland/hypridleconfigurator.py"
```

Expected: the ii venv shebang (`#!/usr/bin/env -S /bin/sh -c "source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate...`) and only `argparse`, `os`, `re`, `tempfile`.

- [ ] **Step 2: Test it against the pin's `hypridle.conf`**

```bash
t=$(mktemp -d -p "$XDG_RUNTIME_DIR")
command cp /nix/store/xwkyskh3ylwwbhvff97z8jivcxmnbcg8-source/dots/.config/hypr/hypridle.conf "$t/a.conf"; chmod u+w "$t/a.conf"; command cp "$t/a.conf" "$t/b.conf"
python3 "$II/scripts/hyprland/hypridleconfigurator.py" --file "$t/a.conf" --lock 0 --screen-off 0 --suspend 0 >/dev/null
grep -c '^listener' "$t/a.conf"; grep -c '^general' "$t/a.conf"
python3 "$II/scripts/hyprland/hypridleconfigurator.py" --file "$t/b.conf" --lock 60 --screen-off 600 --suspend 0 >/dev/null
grep -A1 '^listener' "$t/b.conf" | grep timeout; grep -c suspend_cmd "$t/b.conf"
rm -rf "$t"
```

Expected: `0` and `1` (every listener gone, the `general` block kept: the old sed's result); then `timeout = 60` and `timeout = 600`, and `1` (only the `$suspend_cmd` definition line, no suspend listener).

- [ ] **Step 3: Commit in the clone and export**

```bash
cd ~/src/dots-hyprland && git add -A && git commit -F - <<'MSG'
feat(settings): add the hypridle listener writer

Port of pctrade/end4-pC dc2ca2600ee6: scripts/hyprland/hypridleconfigurator.py
https://github.com/pctrade/end4-pC/tree/dc2ca2600ee6d7852bf0ac91361db8e510f90a74
Problem: idle timeouts need rewriting hypridle.conf's listeners, at activation (Nix) and live (krane-ii-settings).
Port: clean
Drop when: hypridle.conf is generated from config values upstream.
MSG
```

Run the export command.

- [ ] **Step 4: The Nix side**

1. `modules/home/hypr-config.nix`: replace the `idleTimeouts` option's description with

   ```nix
      description = ''
        false is shorthand for `idle = { lock = 0; screenOff = 0; suspend = 0; }`: the session
        never locks, blanks or suspends on its own; manual lock and lock-before-sleep stay. Kept
        for compatibility; do not combine with `idle`.
      '';
   ```

   and add right after the `idleTimeouts` option:

   ```nix
    idle = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = lib.genAttrs [ "lock" "screenOff" "suspend" ] (
            _:
            lib.mkOption {
              type = lib.types.ints.between 0 86400;
              description = "Seconds idle before this hypridle listener fires; 0 removes it.";
            }
          );
        }
      );
      default = null;
      example = {
        lock = 600;
        screenOff = 900;
        suspend = 0;
      };
      description = ''
        hypridle timeouts. null (the default) leaves them to the ii settings window
        (hosts/<host>/ii-settings.json) or ii's own 300/600/900. Setting this makes idle
        Nix-owned: the settings window shows it disabled. Written into
        ~/.config/hypr/hypridle.conf at activation by modules/home/ii-settings.nix.
      '';
    };
   ```

2. `modules/home/illogical-impulse.nix`: delete the `++ lib.optional (!config.krane.hypr.idleTimeouts) { ... };` element (the hypridle sed, with its comment) so `iiPatches` ends with `];`.

3. `modules/home/ii-settings.nix`: replace the `nixIdle` binding and its comment with

   ```nix
  # krane.hypr.idle, or idleTimeouts = false as shorthand for all zeros. null: not set by Nix.
  nixIdle =
    if cfg.idle != null then
      { inherit (cfg.idle) lock screenOff suspend; }
    else if !cfg.idleTimeouts then
      {
        lock = 0;
        screenOff = 0;
        suspend = 0;
      }
    else
      null;
   ```

   add right before `manifest = {`:

   ```nix
  # What activation writes into hypridle.conf: Nix's values, else the GUI file's over ii's
  # defaults, else nothing (ii's copied hypridle.conf stays as it is).
  idleValues =
    if nixIdle != null then
      nixIdle
    else if gui ? idle then
      iiIdle // gui.idle
    else
      null;

   ```

   add after `home.packages = [ wrapped ];`:

   ```nix

    # Replaces the old hypridle.conf sed in illogical-impulse.nix. Runs ii's own
    # hypridleconfigurator.py (patches/ii/05-settings) with a pinned interpreter; the script is
    # standard-library only. hypridle reads its config at start: the change applies from the
    # next login, or at once when the GUI's writer restarts hypridle.
    home.activation.kraneIiIdle = lib.mkIf (idleValues != null) (
      lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] ''
        conf=${lib.escapeShellArg manifest.hypridleFile}
        script=${lib.escapeShellArg manifest.idleConfigurator}
        if [ -f "$conf" ] && [ -f "$script" ]; then
          $DRY_RUN_CMD ${pkgs.python3}/bin/python3 "$script" --file "$conf" \
            --lock ${toString idleValues.lock} \
            --screen-off ${toString idleValues.screenOff} \
            --suspend ${toString idleValues.suspend} >/dev/null
        fi
      ''
    );
   ```

   and add this assertion before the `guiLocked` one:

   ```nix
      {
        assertion = cfg.idle == null || cfg.idleTimeouts;
        message = ''
          krane.hypr.idle and krane.hypr.idleTimeouts = false are both set; idleTimeouts = false
          is shorthand for idle = { lock = 0; screenOff = 0; suspend = 0; }. Keep one.
        '';
      }
   ```

```bash
cd ~/.dotfiles && git add modules/home/hypr-config.nix modules/home/ii-settings.nix modules/home/illogical-impulse.nix
```

- [ ] **Step 5: Check what activation will run**

```bash
cd ~/.dotfiles
act() { gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.$1.config.home-manager.users.krane.home.activationPackage); sed -n '/"kraneIiIdle"/,/^fi$/p' "$gen/activate" | grep -oE -- '--(lock|screen-off|suspend) [0-9]+' | tr '\n' ' '; echo; grep -c 'listener {' "$gen/activate"; }
act tariognatha; act tarmantria
printf '{"idle":{"lock":60,"suspend":0}}\n' > hosts/tarmantria/ii-settings.json; act tarmantria; printf '{}\n' > hosts/tarmantria/ii-settings.json
```

Expected: tariognatha `--lock 0 --screen-off 0 --suspend 0` and `0` (the old sed is gone); tarmantria an empty line (no entry: ii's defaults stay) and `0`; with the JSON, `--lock 60 --screen-off 600 --suspend 0`.

- [ ] **Step 6: Switch and check (tariognatha, then tarmantria)**

```bash
sudo nixos-rebuild switch --flake .#tariognatha
grep -c '^listener' ~/.config/hypr/hypridle.conf
krane-ii-settings set idle lock 60; echo "exit $?"
```

Expected: `0`; `krane-ii-settings: idle: set in Nix (...)`, `exit 1`. On tarmantria:

```bash
sudo nixos-rebuild switch --flake .#tarmantria
old=$(pidof hypridle)
krane-ii-settings set idle lock 60 && krane-ii-settings set idle suspend 0
grep -A1 '^listener' ~/.config/hypr/hypridle.conf | grep timeout; grep -c 'on-timeout = \$suspend_cmd' ~/.config/hypr/hypridle.conf
[ "$(pidof hypridle)" != "$old" ] && echo RESTARTED
git -C ~/.dotfiles diff hosts/tarmantria/ii-settings.json
```

Expected: `timeout = 60` and `timeout = 600`, `0`, `RESTARTED`, and a diff with `"idle": {"lock": 60, "suspend": 0}`. Leave the machine idle for 60 s: it locks. Switch twice: `grep` still shows 60. Then `krane-ii-settings reset idle lock && krane-ii-settings reset idle suspend` to restore.

- [ ] **Step 7: Commit B3**

```bash
cd ~/.dotfiles
git add patches/ii/05-settings modules/home/hypr-config.nix modules/home/ii-settings.nix modules/home/illogical-impulse.nix
git commit -m "Set hypridle timeouts from krane.hypr.idle or the ii settings window instead of a sed"
```

---

### Task 17: ii service layer: KraneSettings, transient overrides, border colors, autostart

**Files (clone, under `$II`):**
- Modify: `scripts/hyprland/hyprconfigurator.py`, `modules/common/Config.qml`, `modules/common/models/hyprland/HyprlandConfigOption.qml`, `services/MaterialThemeLoader.qml`, `shell.qml`
- Replace: `services/HyprlandConfig.qml`
- Create: `services/KraneSettings.qml`, `scripts/hyprland/autostart.py`, `modules/common/widgets/AutostartApps.qml`

**Interfaces:**
- Consumes: the `krane-ii-settings` CLI (Tasks 13–15) on `PATH`.
- Produces (QML singleton `KraneSettings`): properties `state` (parsed `get` output), `available`, `lastError`, `externalChange`, `nixReason`; functions `isLocked(section, key)`, `isMonitorFieldLocked(output, field)`, `set(section, key, value)`, `reset(section, key, field?)`, `apply()`, `refresh()`. Commands run one at a time; a queued `set` of the same key is replaced by the newer one.
- Produces (`HyprlandConfigOption`): `locked`, `lockedReason`, `number` (CSS-gap strings read as their first number), `boolean`; `setValue(v)` and `reset()` now persist through `KraneSettings`.
- Produces (`HyprlandConfig` singleton): unchanged `set`/`setMany`/`reset`/`resetMany` (transient, `shellOverrides/main.lua`), plus `borderColorEntries()`, `applyBorderColors()`, `resetBorderColors()`, re-applied on Config ready, palette change and every `configreloaded`.
- Produces (Config): `Config.options.hyprland.autostartApps.{enable, apps}`, `Config.options.hyprland.general.borderColor.{enable, activeRole, inactiveRole, activeOpacity, inactiveOpacity}`.

- [ ] **Step 1: `hyprconfigurator.py` skips unchanged writes (test first)**

```bash
II=~/src/dots-hyprland/dots/.config/quickshell/ii
noop() {
  local t; t=$(mktemp -p "$XDG_RUNTIME_DIR")
  python3 "$II/scripts/hyprland/hyprconfigurator.py" --file "$t" --set general:col:active_border 'rgba(ffffff78)' >/dev/null 2>&1
  local a; a=$(stat -c %i "$t")
  python3 "$II/scripts/hyprland/hyprconfigurator.py" --file "$t" --set general:col:active_border 'rgba(ffffff78)' >/dev/null 2>&1
  [ "$a" = "$(stat -c %i "$t")" ] && echo UNCHANGED || echo REWRITTEN; rm -f "$t"
}
noop
```

Expected: `REWRITTEN` (a new inode: the script always replaces the file). Then:

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/scripts/hyprland/hyprconfigurator.py
+++ b/dots/.config/quickshell/ii/scripts/hyprland/hyprconfigurator.py
@@ -85,6 +85,12 @@
                     new_lines[-1] += '\n'
                 new_lines.append(generate_config_line(key, value))
                 
+    # Unchanged content: skip the write. Hyprland reloads on every write to this
+    # file, and the shell re-applies border colors on every reload, so writing
+    # the same content again would loop.
+    if os.path.exists(file_path) and "".join(new_lines) == "".join(lines):
+        return
+
     dir_name = os.path.dirname(os.path.abspath(file_path))
     os.makedirs(dir_name, exist_ok=True)
     temp_path = None
PATCH
noop
```

Expected: `UNCHANGED`. Commit: subject `fix(hyprconfigurator): skip the write when nothing changed`; `Port of ...: none (krane-only)`; `Problem: re-applying border colors on every configreloaded would rewrite shellOverrides/main.lua, which triggers another reload.`; `Port: krane-only`; `Drop when: the pinned hyprconfigurator.py compares before writing.`

- [ ] **Step 2: `Config.qml`: the two Hyprland-page subtrees that stay in config.json**

```bash
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/modules/common/Config.qml
+++ b/dots/.config/quickshell/ii/modules/common/Config.qml
@@ -85,6 +85,28 @@
                 property list<string> collapsedSections: []
             }
 
+            // Settings window Hyprland page (patches/ii/05-settings). Only the choices that
+            // stay in config.json: Hyprland options themselves go to
+            // hosts/<host>/ii-settings.json through krane-ii-settings.
+            property JsonObject hyprland: JsonObject {
+                property JsonObject autostartApps: JsonObject {
+                    property bool enable: false
+                    property list<var> apps: []
+                }
+                property JsonObject general: JsonObject {
+                    // Window border colors. Off by default so the colors matugen
+                    // writes to hyprland/colors.lua keep applying.
+                    property JsonObject borderColor: JsonObject {
+                        property bool enable: false
+                        // Palette roles, resolved by Appearance.getColorFromName()
+                        property string activeRole: "layer0Border"
+                        property string inactiveRole: "layer0Border"
+                        property real activeOpacity: 0.47
+                        property real inactiveOpacity: 0.2
+                    }
+                }
+            }
+
             // Settings window Profile page (patches/ii/05-settings).
             property JsonObject profile: JsonObject {
                 property string avatarPath: ""
PATCH
```

Commit: subject `feat(settings): declare the Hyprland page's config.json keys`; fork path `modules/common/Config.qml (hyprland.autostartApps, hyprland.general.borderColor)`; `Problem: autostart apps and custom border colors are shell choices kept in config.json.`; `Port: hand-ported (the rest of the fork's hyprland.* mirror is not ported: Hyprland options live in ii-settings.json)`; `Drop when: the pinned Config.qml declares hyprland.autostartApps.`

- [ ] **Step 3: `KraneSettings.qml` and `HyprlandConfigOption.qml`**

Write `$II/services/KraneSettings.qml`:

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Persistent settings, through krane-ii-settings from the dotfiles repo
 * (pkgs/krane-ii-settings). It validates each change against its schema,
 * refuses keys Nix owns, writes hosts/<host>/ii-settings.json and reloads
 * Hyprland. Transient overrides (game mode, anti-flashbang, border colors)
 * stay on HyprlandConfig.
 */
Singleton {
    id: root

    // Output of `krane-ii-settings get`: host, repoFile, repo, error,
    // nixOwned, monitorBaselines, idle, idleBaseline, pending, revertPending,
    // unconfirmed.
    property var state: ({})
    // False until `get` has answered: the writer is missing from PATH (qs
    // started before the switch that installed it) or failed.
    property bool available: false
    // stderr of the last failed command, shown by the pages.
    property string lastError: ""
    // The repo file changed outside the settings window (hand edit, git
    // checkout). Nothing is applied until the user presses Apply.
    property bool externalChange: false

    readonly property string nixReason: Translation.tr("Set in Nix (%1)").arg(`hosts/${root.state.host ?? "<host>"}/display.nix or modules/home`)

    function isLocked(section, key) {
        const owned = root.state.nixOwned;
        if (!owned)
            return false;
        if (section === "hyprland")
            return owned.hyprland.includes(key);
        if (section === "idle")
            return owned.idle;
        return false;
    }

    function isMonitorFieldLocked(output, field) {
        return (root.state.nixOwned?.monitors?.[output] ?? []).includes(field);
    }

    function set(section, key, value) {
        root._enqueue(["set", section, key, String(value)]);
    }

    // `field` only for section "monitor": one field of that output's entry.
    function reset(section, key, field) {
        const args = ["reset", section, key];
        if (field !== undefined)
            args.push(String(field));
        root._enqueue(args);
    }

    function apply() {
        root.externalChange = false;
        root._enqueue(["apply"]);
    }

    function refresh() {
        if (!getProc.running)
            getProc.running = true;
    }

    property list<var> _queue: []
    property real _selfWriteUntil: 0

    function _enqueue(args) {
        // A newer value for the same setting replaces a queued older one, so a
        // dragged slider ends on its final value without replaying every step.
        const same = a => a[0] === "set" && args[0] === "set" && a[1] === args[1] && a[2] === args[2];
        root._queue = root._queue.filter(a => !same(a)).concat([args]);
        root._next();
    }

    function _next() {
        if (runProc.busy || root._queue.length === 0)
            return;
        const args = root._queue[0];
        root._queue = root._queue.slice(1);
        root._selfWriteUntil = Date.now() + 3000;
        runProc.busy = true;
        runProc.exitedFlag = false;
        runProc.stderrDone = false;
        runProc.command = ["krane-ii-settings"].concat(args);
        runProc.running = true;
        startWatchdog.restart();
    }

    function _finish(code, errText) {
        runProc.busy = false;
        root.lastError = code === 0 ? "" : (errText.trim() || Translation.tr("krane-ii-settings failed (exit %1)").arg(code));
        root.refresh();
        Qt.callLater(root._next);
    }

    Process {
        id: runProc
        property bool busy: false
        property bool exitedFlag: false
        property bool stderrDone: false
        property int code: 0
        property string errText: ""
        stderr: StdioCollector {
            onStreamFinished: {
                runProc.errText = text;
                runProc.stderrDone = true;
                if (runProc.exitedFlag)
                    root._finish(runProc.code, runProc.errText);
            }
        }
        onExited: (exitCode, exitStatus) => {
            runProc.code = exitCode;
            runProc.exitedFlag = true;
            if (runProc.stderrDone)
                root._finish(runProc.code, runProc.errText);
        }
    }

    // A command that never started (not on PATH) emits nothing; do not wait forever.
    Timer {
        id: startWatchdog
        interval: 5000
        onTriggered: {
            if (runProc.busy && !runProc.running && !runProc.exitedFlag)
                root._finish(127, Translation.tr("krane-ii-settings is not on PATH. Switch, then restart the shell."));
        }
    }

    Process {
        id: getProc
        command: ["krane-ii-settings", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.state = JSON.parse(text);
                    root.available = true;
                } catch (e) {
                    root.available = false;
                }
            }
        }
    }

    FileView {
        path: root.state.repoFile ?? ""
        watchChanges: true
        printErrors: false
        onFileChanged: {
            if (Date.now() > root._selfWriteUntil)
                root.externalChange = true;
            root.refresh();
        }
    }

    // Say so in the log when the writer never answers (checked by the
    // settings smoke tests and useful in `qs log`).
    Timer {
        id: availabilityCheck
        interval: 5000
        onTriggered: {
            if (!root.available)
                console.warn("[KraneSettings] krane-ii-settings get did not answer; persistent settings are unavailable");
        }
    }

    Component.onCompleted: {
        root.refresh();
        availabilityCheck.start();
    }
}
```

Then:

```bash
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/modules/common/models/hyprland/HyprlandConfigOption.qml
+++ b/dots/.config/quickshell/ii/modules/common/models/hyprland/HyprlandConfigOption.qml
@@ -12,6 +12,14 @@
     property alias fetching: fetchProc.running
     property bool set
     property var value
+    // Nix owns this key (krane.hypr.settings or krane.hypr.guiLocked): show the
+    // control disabled with lockedReason.
+    readonly property bool locked: KraneSettings.isLocked("hyprland", root.key)
+    readonly property string lockedReason: KraneSettings.nixReason
+    // hyprctl reports CSS-gap options (general:gaps_in, gaps_out) as a
+    // "top right bottom left" string and bools as true/false.
+    readonly property real number: typeof root.value === "string" ? Number(root.value.split(" ")[0]) : Number(root.value ?? 0)
+    readonly property bool boolean: root.value === true || Number(root.value) === 1
 
     Component.onCompleted: fetch()
 
@@ -27,12 +35,14 @@
         fetchProc.running = true;
     }
 
+    // Persistent: written to hosts/<host>/ii-settings.json by krane-ii-settings.
+    // Transient overrides (game mode, anti-flashbang) call HyprlandConfig directly.
     function setValue(newValue) {
-        HyprlandConfig.set(root.key, newValue)
+        KraneSettings.set("hyprland", root.key, newValue)
     }
 
     function reset() {
-        HyprlandConfig.reset(root.key)
+        KraneSettings.reset("hyprland", root.key)
     }
 
     Process {
PATCH
grep -rl 'HyprlandConfigOption' "$II" --include=*.qml | grep -v -e 'modules/settings/' -e 'HyprlandConfigOption.qml' \
  | xargs grep -n '\.setValue(\|\.reset()'
```

Expected: no output. (The file list is `services/HyprlandAntiFlashbangShader.qml` and `modules/common/models/quickToggles/GameModeToggle.qml`; a bare repo-wide grep for `.reset()` also matches unrelated `lockContext.reset()` and `Ai.qml` calls.) Side effect to expect: those two files instantiate `HyprlandConfigOption` in the main shell, so the `KraneSettings` singleton (and its `get` call and file watch) also runs inside `qs -c ii`, not only in the settings window. `setValue`/`reset` on `HyprlandConfigOption` now persist, so no transient caller may use them; at the pin, game mode and the anti-flashbang shader only read through `HyprlandConfigOption` and write through `HyprlandConfig.setMany`/`resetMany`. If a line is printed, stop and report.

Commit: subject `feat(settings): persist Hyprland options through krane-ii-settings`; `Port of ...: none (krane-only)`; `Problem: Hyprland options set from the settings window must survive switches; shellOverrides/main.lua is wiped by every switch.`; `Port: krane-only (calls the dotfiles repo's writer)`; `Drop when: the dotfiles repo drops krane-ii-settings.`

- [ ] **Step 4: `HyprlandConfig.qml` and `MaterialThemeLoader.qml`**

Replace `$II/services/HyprlandConfig.qml` with:

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.common.functions

/**
 * Transient Hyprland overrides: game mode, the anti-flashbang shader and
 * custom window border colors. They go to hyprland/shellOverrides/main.lua,
 * which loads last and which every switch wipes. Persistent settings go
 * through KraneSettings (krane-ii-settings) instead.
 */
Singleton {
    id: root

    signal reloaded()

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    // The script runs through its own venv shebang; argv, not a shell string.
    function _run(args: var): void {
        Quickshell.execDetached([root.configuratorScriptPath, "--file", root.shellOverridesPath].concat(args));
    }

    function set(key: string, value: var): void {
        root._run(["--set", key, String(value)]);
    }

    function setMany(entries: var): void {
        let args = [];
        for (let key in entries)
            args.push("--set", key, String(entries[key]));
        root._run(args);
    }

    function reset(key: string): void {
        root._run(["--reset", key]);
    }

    function resetMany(keys: list<string>): void {
        let args = [];
        for (let i = 0; i < keys.length; i++)
            args.push("--reset", keys[i]);
        root._run(args);
    }

    readonly property string borderActiveKey: "general:col:active_border"
    readonly property string borderInactiveKey: "general:col:inactive_border"

    // Hyprland wants rgba(RRGGBBAA) without a leading '#'. Only the RGB of the
    // palette color is kept: some Appearance colors carry an alpha that encodes
    // a layer opacity inside the shell, which has nothing to do with a border.
    function toHyprColor(color, opacity) {
        const c = Qt.color(color);
        const hex = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        return `rgba(${hex(c.r)}${hex(c.g)}${hex(c.b)}${hex(opacity)})`;
    }

    // Custom window border colors, or {} when the option is off so the colors
    // matugen writes to hyprland/colors.lua keep applying. Roles are resolved
    // here rather than stored as colors, so the borders follow the wallpaper.
    function borderColorEntries() {
        const opts = Config.options?.hyprland?.general?.borderColor;
        if (!Config.ready || !opts?.enable)
            return ({});
        let entries = ({});
        entries[root.borderActiveKey] = root.toHyprColor(Appearance.getColorFromName(opts.activeRole), opts.activeOpacity);
        entries[root.borderInactiveKey] = root.toHyprColor(Appearance.getColorFromName(opts.inactiveRole), opts.inactiveOpacity);
        return entries;
    }

    // Also called by MaterialThemeLoader on every palette change.
    function applyBorderColors(): void {
        const entries = root.borderColorEntries();
        if (Object.keys(entries).length > 0)
            root.setMany(entries);
    }

    function resetBorderColors(): void {
        root.resetMany([root.borderActiveKey, root.borderInactiveKey]);
    }

    // The palette can be loaded before the config, in which case the first
    // apply from MaterialThemeLoader was skipped.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root.applyBorderColors();
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded();
                // A switch wipes shellOverrides/main.lua and ends with a reload.
                // hyprconfigurator.py skips unchanged writes, so this cannot loop.
                root.applyBorderColors();
            }
        }
    }
}
```

```bash
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/services/MaterialThemeLoader.qml
+++ b/dots/.config/quickshell/ii/services/MaterialThemeLoader.qml
@@ -31,6 +31,9 @@
         }
         
         Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
+        // Custom window border colors are stored as palette roles, so they
+        // have to be pushed to Hyprland again whenever the palette changes.
+        HyprlandConfig.applyBorderColors()
     }
 
     function resetFilePathNextTime() {
PATCH
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/services/{HyprlandConfig,KraneSettings,MaterialThemeLoader}.qml "$II"/modules/common/models/hyprland/HyprlandConfigOption.qml; echo "exit $?"
```

Expected: `exit 0`. Commit: subject `feat(settings): custom window border colors that follow the palette`; fork paths `services/HyprlandConfig.qml, services/MaterialThemeLoader.qml`; `Problem: the Hyprland page's border colors are palette roles and must be re-resolved on every palette change and after every switch, which wipes shellOverrides/main.lua.`; `Port: hand-ported (WM checks, setIdle and setAnimPreset dropped; scripts run through their venv shebang, not python3 from PATH; re-apply added on configreloaded)`; `Drop when: upstream ii ships border colors from palette roles.`

- [ ] **Step 5: Autostart apps**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
curl -sfL "$F/scripts/hyprland/autostart.py" -o "$II/scripts/hyprland/autostart.py"
curl -sfL "$F/modules/common/widgets/AutostartApps.qml" -o "$II/modules/common/widgets/AutostartApps.qml"
chmod +x "$II/scripts/hyprland/autostart.py"
```

Edit `autostart.py`:
1. Replace line 1 (`#!/usr/bin/env python3`) with line 1 of `hypridleconfigurator.py` (the ii venv shebang): `sed -i "1s|.*|$(head -1 "$II/scripts/hyprland/hypridleconfigurator.py" | sed 's/[&|]/\\&/g')|" "$II/scripts/hyprland/autostart.py"`.
2. Replace `lockfile = "/tmp/qs-autostart.lock"` with `lockfile = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "qs-autostart.lock")`. This repo sets no `boot.tmp.*`, so `/tmp` survives reboots and a lock there would block every later boot.

Then apply the `shell.qml` launcher:

```bash
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/shell.qml
+++ b/dots/.config/quickshell/ii/shell.qml
@@ -46,6 +46,22 @@
         function onReloaded() { root.syncHyprlockClock() }
     }
 
+    // Autostart apps from the settings window's Hyprland page (config.json,
+    // hyprland.autostartApps). autostart.py keeps a lock in $XDG_RUNTIME_DIR, so
+    // this runs once per boot, not on every shell restart.
+    Process {
+        id: autostartProc
+        command: [Quickshell.shellPath("scripts/hyprland/autostart.py")]
+    }
+    Connections {
+        target: Config
+        function onReadyChanged() {
+            if (Config.ready && Config.options.hyprland.autostartApps.enable
+                    && Config.options.hyprland.autostartApps.apps.length > 0)
+                autostartProc.running = true;
+        }
+    }
+
     Component.onCompleted: {
         MaterialThemeLoader.reapplyTheme()
         Hyprsunset.load()
PATCH
```

Test the script:

```bash
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); mkdir -p "$t/home/.config/illogical-impulse" "$t/run"
printf '{"hyprland":{"autostartApps":{"enable":false,"apps":[]}}}\n' > "$t/home/.config/illogical-impulse/config.json"
HOME="$t/home" XDG_RUNTIME_DIR="$t/run" python3 "$II/scripts/hyprland/autostart.py"; echo "exit $?"
test -e "$t/run/qs-autostart.lock" && echo LOCK-IN-RUNTIME
grep -c '/tmp' "$II/scripts/hyprland/autostart.py"; rm -rf "$t"
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/common/widgets/AutostartApps.qml" "$II/shell.qml"; echo "exit $?"
```

Expected: `exit 0`, `LOCK-IN-RUNTIME`, `0`, `exit 0`. Commit: subject `feat(settings): autostart apps`; fork paths `scripts/hyprland/autostart.py, modules/common/widgets/AutostartApps.qml, shell.qml (autostart launcher)`; `Port: hand-ported (lock moved to $XDG_RUNTIME_DIR; venv shebang; launcher runs the script directly)`; `Drop when: autostart apps are configured some other way.`

- [ ] **Step 6: Nothing regressed on the ported pages**

```bash
for p in QuickConfig GeneralConfig BarConfig BackgroundConfig InterfaceConfig ServicesConfig About; do smoke "$p" "$XDG_RUNTIME_DIR/$p.log"; echo "== $p"; newerrs "$p" "$XDG_RUNTIME_DIR/$p.log"; done
```

Expected: only `==` lines. Run the export command.

---

### Task 18: Animation presets as Lua files

**Files:**
- Create (clone): `dots/.config/hypr/hyprland/animationPresets/fast.lua`, `normal.lua`, `niri.lua`

**Interfaces:**
- Produces: `require("hyprland.animationPresets.<name>")` for `<name>` in `fast`, `normal`, `niri`, rendered by the writer when `animationPreset` is set.

- [ ] **Step 1: Show the module is missing (failing check)**

```bash
test -e ~/src/dots-hyprland/dots/.config/hypr/hyprland/animationPresets/fast.lua || echo MISSING
```

Expected: `MISSING`.

- [ ] **Step 2: Generate the three files from the fork's Python strings**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
D=~/src/dots-hyprland/dots/.config/hypr/hyprland/animationPresets; mkdir -p "$D"
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); curl -sfL "$F/scripts/hyprland/hyprconfigurator.py" -o "$t/h.py"
python3 - "$t/h.py" "$D" <<'PY'
import sys
src = open(sys.argv[1]).read()
start = src.index("ANIM_PRESETS = {")
end = src.index("\n}\n", start) + 3
ns = {}
exec(src[start:end], ns)
for name, body in ns["ANIM_PRESETS"].items():
    header = (f'-- Animation preset "{name}" for the ii settings window (patches/ii/05-settings).\n'
              f'-- Loaded by custom/krane_gui.lua when hosts/<host>/ii-settings.json sets\n'
              f'-- "animationPreset": "{name}". Ported from pctrade/end4-pC hyprconfigurator.py.\n')
    open(f"{sys.argv[2]}/{name}.lua", "w").write(header + body)
PY
rm -rf "$t"
for f in "$D"/*.lua; do nix shell nixpkgs#lua5_4 -c luac -p "$f" && echo "ok $(basename "$f")"; done
grep -c '^hl\.animation' "$D"/*.lua
```

Expected: `ok fast.lua`, `ok niri.lua`, `ok normal.lua`; 10, 10 and 13 `hl.animation` lines.

- [ ] **Step 3: Commit and export**

Commit: subject `feat(settings): animation presets as Lua modules`; fork path `scripts/hyprland/hyprconfigurator.py (ANIM_PRESETS)`; `Problem: the fork kept presets as Python strings and asked the user to add a require line to hyprland.lua by hand.`; `Port: hand-ported (moved to hypr/hyprland/animationPresets/*.lua, loaded from krane_gui.lua)`; `Drop when: upstream ships animation presets.` Run the export command.

---

### Task 19: Hyprland page

The fork's page, with every Hyprland control reading the live value and writing through `KraneSettings`. The Displays section waits for Task 23.

**Files:**
- Create (clone): `$II/modules/settings/HyprlandConfig.qml`
- Modify (clone): `$II/settings.qml` (page list)

**Interfaces:**
- Consumes: `HyprlandConfigOption.{value, number, boolean, locked, lockedReason, setValue, reset}`, `KraneSettings.*`, `HyprlandConfig.{applyBorderColors, resetBorderColors}`, `AutostartApps` (Task 17).

- [ ] **Step 1: Fetch and list findings (failing check)**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
curl -sfL "$F/modules/ii/settings/pages/HyprlandConfig.qml" -o "$II/modules/settings/HyprlandConfig.qml"
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/settings/HyprlandConfig.qml" | cut -d: -f3- | sort | uniq -c
```

Expected: `config` findings for every `hyprland.*` key except `hyprland.general.borderColor.*` and `hyprland.autostartApps.*` (about 25), `member: HyprlandConfig.setIdle`, the `python3` pattern, and `type: MonitorConfigOption`/`MonitorCanvas`.

- [ ] **Step 2: Remove what this design replaces**

In `$II/modules/settings/HyprlandConfig.qml`:
1. Delete the page's `Component.onCompleted: { ... HyprlandConfig.setMany(...) }` block. It pushed the fork's config.json mirror into Hyprland every time the page opened, overriding `display.nix` (spec, Design B.5).
2. Delete `MonitorConfigOption { id: monitorConfig }` and the whole Displays `ContentSection` (from the `// Displays` comment to the end of the `ContentSection` whose `title` is `Translation.tr("Displays")`). Task 23 restores them.
3. In the Idle section, delete `function applyIdle()`.
4. In the Animations section, delete the `NoticeBox` about adding a `require` line (with its copy button and `revertSourceTimer`), and the `Process` blocks `saveAnimProc` and `reloadAnimProc`.

- [ ] **Step 3: Bind every Hyprland control to its live option**

Each control gets a `HyprlandConfigOption` child and reads and writes through it, never through `Config.options.hyprland.*`. The value guard stops the write that would otherwise follow every refresh from `hyprctl`. A locked control is disabled and says why in its label.

Switch, for example "Blur":

```qml
                ConfigSwitch {
                    HyprlandConfigOption { id: optBlur; key: "decoration:blur:enabled" }
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur") + (optBlur.locked ? ` · ${optBlur.lockedReason}` : "")
                    enabled: !optBlur.locked
                    checked: optBlur.boolean
                    onCheckedChanged: {
                        if (optBlur.fetching || checked === optBlur.boolean) return
                        optBlur.setValue(checked)
                    }
                }
```

Spin box, for example "Window Rounding" (Hyprland 0.56 caps it at 20):

```qml
                ConfigSpinBox {
                    HyprlandConfigOption { id: optRounding; key: "decoration:rounding" }
                    icon: "rounded_corner"
                    text: Translation.tr("Window Rounding") + (optRounding.locked ? ` · ${optRounding.lockedReason}` : "")
                    enabled: !optRounding.locked
                    value: optRounding.number
                    from: 0; to: 20; stepSize: 1
                    onValueChanged: {
                        if (optRounding.fetching || value === optRounding.number) return
                        optRounding.setValue(value)
                    }
                }
```

Scaled spin box, for example "Active Opacity" (the spin box shows percent):

```qml
                ConfigSpinBox {
                    HyprlandConfigOption { id: optActiveOpacity; key: "decoration:active_opacity" }
                    icon: "opacity"
                    text: Translation.tr("Active Opacity") + (optActiveOpacity.locked ? ` · ${optActiveOpacity.lockedReason}` : "")
                    enabled: !optActiveOpacity.locked
                    value: Math.round(optActiveOpacity.number * 100)
                    from: 10; to: 100; stepSize: 5
                    onValueChanged: {
                        if (optActiveOpacity.fetching || value === Math.round(optActiveOpacity.number * 100)) return
                        optActiveOpacity.setValue(value / 100)
                    }
                }
```

Selection, for example "Tiling Layout":

```qml
                ConfigSelectionArray {
                    HyprlandConfigOption { id: optLayout; key: "general:layout" }
                    text: Translation.tr("Tiling Layout") + (optLayout.locked ? ` · ${optLayout.lockedReason}` : "")
                    icon: "responsive_layout"
                    enabled: !optLayout.locked
                    currentValue: optLayout.value
                    onSelected: newValue => optLayout.setValue(newValue)
                    options: [ /* the fork's three options, unchanged */ ]
                }
```

Text, "Keyboard layout" (`ConfigTextArea` with the fork's 1 s debounce): `value: optKbLayout.value ?? ""` instead of the `Component.onCompleted` assignment, `enabled: !optKbLayout.locked`, and the debounce timer calls `optKbLayout.setValue(kbLayoutField.value)` only. This key is Nix-owned on every host today, so the field shows "Set in Nix".

Apply the pattern to every control, then remove the `Config.options.hyprland.*` reads and writes each used:

| Control | Key | Pattern | Notes |
|---|---|---|---|
| Tiling Layout | `general:layout` | selection | options `dwindle`, `master`, `scrolling` |
| Keyboard layout | `input:kb_layout` | text | |
| Numlock by default | `input:numlock_by_default` | switch | |
| Repeat delay | `input:repeat_delay` | spin | `to: 2000` |
| Repeat rate | `input:repeat_rate` | spin | `to: 200` |
| Follow mouse | `input:follow_mouse` | selection | `currentValue: opt.number` (values 0–3) |
| Natural scroll | `input:touchpad:natural_scroll` | switch | |
| Disable while typing | `input:touchpad:disable_while_typing` | switch | |
| Clickfinger behavior | `input:touchpad:clickfinger_behavior` | switch | |
| Scroll factor | `input:touchpad:scroll_factor` | scaled spin ×10 | `from: 1; to: 20` (Hyprland max 2.0) |
| Window Rounding | `decoration:rounding` | spin | `to: 20` |
| Blur | `decoration:blur:enabled` | switch | |
| Blur size | `decoration:blur:size` | spin | |
| Blur passes | `decoration:blur:passes` | spin | `to: 10` |
| Gaps in | `general:gaps_in` | spin | `number` reads the `"4 4 4 4"` CSS form |
| Gaps out | `general:gaps_out` | spin | same |
| Active Opacity | `decoration:active_opacity` | scaled spin ×100 | |
| Inactive Opacity | `decoration:inactive_opacity` | scaled spin ×100 | |
| Border size | `general:border_size` | spin | `to: 20` |
| Animations: Enable | `animations:enabled` | switch | |

The border color controls stay as the fork wrote them: they keep `Config.options.hyprland.general.borderColor.*` and call `HyprlandConfig.applyBorderColors()`/`resetBorderColors()`. `AutostartApps {}` stays as is.

- [ ] **Step 4: Idle and animation presets through the writer**

Idle section: bind the three `IdleTimerRow`s to the writer's effective values and lock them together:

```qml
                IdleTimerRow {
                    icon: "lock_clock"
                    label: Translation.tr("Lock screen")
                    enabled: !KraneSettings.isLocked("idle", "")
                    seconds: KraneSettings.state.idle?.lock ?? 0
                    // The row's spin box also emits edited() when `seconds` arrives from
                    // `get` after loading; writing that value back would put ii's default
                    // into the sparse file on every page open.
                    onEdited: newSeconds => {
                        if (KraneSettings.state.idle && newSeconds !== KraneSettings.state.idle.lock)
                            KraneSettings.set("idle", "lock", newSeconds)
                    }
                    Component.onCompleted: loaded = true
                }
```

The same for `screenOff` ("Screen off") and `suspend` ("Standby"), each comparing with its own key. Above the `GroupedList`, add:

```qml
            NoticeBox {
                Layout.fillWidth: true
                visible: KraneSettings.isLocked("idle", "")
                text: Translation.tr("Idle timeouts are set in Nix: %1. 0 means never.").arg(KraneSettings.nixReason)
            }
```

Animations section: replace the presets `ConfigSelectionArray` with

```qml
                ConfigSelectionArray {
                    text: Translation.tr("Presets")
                    icon: "present_to_all"
                    currentValue: KraneSettings.state.repo?.animationPreset ?? ""
                    onSelected: newValue => {
                        if (newValue === "") KraneSettings.reset("animation", "preset")
                        else KraneSettings.set("animation", "preset", newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Stock"),     icon: "animation",            value: ""       },
                        { displayName: Translation.tr("Elastic"),   icon: "move_selection_right", value: "fast"   },
                        { displayName: Translation.tr("Normal"),    icon: "motion_photos_on",     value: "normal" },
                        { displayName: Translation.tr("Niri Like"), icon: "mobiledata_arrows",    value: "niri"   },
                    ]
                }
```

- [ ] **Step 5: Status notices at the top of the page**

As the first children of `mainLayout`:

```qml
        // krane-ii-settings did not answer, or refused the last change.
        NoticeBox {
            Layout.fillWidth: true
            visible: !KraneSettings.available || KraneSettings.lastError !== "" || !!KraneSettings.state.error
            text: !KraneSettings.available
                ? Translation.tr("Changes on this page cannot be saved: krane-ii-settings did not answer. Switch, then restart the shell.")
                : (KraneSettings.state.error || KraneSettings.lastError)
        }

        // hosts/<host>/ii-settings.json changed outside this window (hand edit, git checkout).
        NoticeBox {
            Layout.fillWidth: true
            visible: KraneSettings.externalChange
            text: Translation.tr("ii-settings.json changed outside settings")
            Item { Layout.fillWidth: true }
            RippleButtonWithIcon {
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                materialIcon: "sync"
                mainText: Translation.tr("Apply now")
                onClicked: KraneSettings.apply()
            }
        }
```

- [ ] **Step 6: List the page, check it, smoke it, and the missing-writer case (Review Focus 1)**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/settings.qml
+++ b/dots/.config/quickshell/ii/settings.qml
@@ -55,6 +55,11 @@
             component: "modules/settings/ServicesConfig.qml"
         },
         {
+            name: Translation.tr("Hyprland"),
+            icon: "desktop_windows",
+            component: "modules/settings/HyprlandConfig.qml"
+        },
+        {
             name: Translation.tr("Profile"),
             icon: "account_circle",
             component: "modules/settings/Profile.qml"
PATCH
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/settings/HyprlandConfig.qml"; echo "exit $?"
grep -c 'Config\.options\.hyprland\.\(input\|decoration\|animations\|idle\)\|Config\.options\.hyprland\.general\.\(layout\|gapsIn\|gapsOut\|borderSize\)' "$II/modules/settings/HyprlandConfig.qml"
smoke HyprlandConfig "$XDG_RUNTIME_DIR/h.log"; newerrs QuickConfig "$XDG_RUNTIME_DIR/h.log"; grep -c 'initial page: modules/settings/HyprlandConfig.qml' "$XDG_RUNTIME_DIR/h.log"
```

Expected: `exit 0`, `0`, no new errors, `1`. Then with the writer hidden from `PATH`:

```bash
qsbin=$(command -v qs)
nopath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '/etc/profiles/per-user' -e '\.nix-profile' | paste -sd:)
sb=$(mktemp -d -p "$XDG_RUNTIME_DIR"); mkdir -p "$sb/config"; command cp -rL ~/.config/illogical-impulse "$sb/config/"; ln -s ~/.config/hypr "$sb/config/hypr"
PATH="$nopath" XDG_CONFIG_HOME="$sb/config" II_SETTINGS_PAGE=HyprlandConfig timeout 12 "$qsbin" -p "$II/settings.qml" > "$sb/log" 2>&1
grep -c '\[KraneSettings\] krane-ii-settings get did not answer' "$sb/log"; rm -rf "$sb"
```

Expected: `1`. (Before Task 15's switch installed the writer, the normal smoke run above prints this warning too; that is expected.)

- [ ] **Step 7: Commit (two commits) and export**

- `HyprlandConfig.qml`: subject `feat(settings): port end4-pC's Hyprland page`; fork path `modules/ii/settings/pages/HyprlandConfig.qml`; `Problem: Hyprland options, idle, presets, border colors and autostart apps in one page.`; `Port: hand-ported (live values from hyprctl; writes through krane-ii-settings; startup setMany, require-line notice and Displays removed; Displays return with confirm-or-revert in a later commit)`; `Drop when: upstream ships an equivalent page, or the settings port is abandoned.`
- `settings.qml`: subject `feat(settings): list the Hyprland page`; `Port: krane-only`.

Run the export command.

---

### Task 20: Phase B switch, acceptance and commit B4

**Files:**
- Commit: `patches/ii/05-settings/` (the patches from Tasks 17–19)

- [ ] **Step 1: Whole-series and build checks**

Run Task 11, Step 2 (forkcheck delta and `git am` round trip) and Step 3 (`nix flake check`, dry-builds). Expected as there.

- [ ] **Step 2: Switch and logs**

Run Task 11, Step 4 on tariognatha, then tarmantria. Expected as there.

- [ ] **Step 3: Visual and Input (spec table)**

On each host, in the Hyprland page: set "Gaps in" to 12.

```bash
sleep 1; hyprctl getoption general:gaps_in -j | jq -r .css; jq '.hyprland' ~/.dotfiles/hosts/$(hostname)/ii-settings.json
```

Expected: `12 12 12 12` and `{"general:gaps_in": 12}`. Reset it (the control's reset, or `krane-ii-settings reset hyprland general:gaps_in`): the key is gone and the value is back to ii's without a switch. Set 12 again, switch twice, reboot: still 12. Repeat with "Repeat rate" (all hosts) and "Natural scroll" (laptops; on tarmantria `input:touchpad:natural_scroll` is Nix-owned, so expect the control disabled with "Set in Nix"; use "Disable while typing" instead).

- [ ] **Step 4: Ownership in the GUI**

The keyboard layout field is disabled and reads "Set in Nix (hosts/<host>/display.nix or modules/home)". On tariognatha the idle rows are disabled with the Nix notice.

- [ ] **Step 5: Live value shapes (Review Focus 4)**

Open the page with `general:gaps_in` at ii's value. Expected: "Gaps in" shows the first number of `hyprctl getoption general:gaps_in -j | jq -r .css`, "Blur" matches `hyprctl getoption decoration:blur:enabled -j | jq .bool`, "Inactive Opacity" shows `round(float * 100)`. No `NaN`, no switch unchecked while Hyprland reports `true`. Opening the page and closing it without touching anything leaves `git -C ~/.dotfiles diff --stat hosts/$(hostname)/ii-settings.json` empty (no value written back on load, idle rows included) on tarmantria, where idle is GUI-owned.

- [ ] **Step 6: External edit and parse error (tariognatha)**

With the page open: `f=~/.dotfiles/hosts/tariognatha/ii-settings.json; jq '.hyprland["general:gaps_out"] = 7' "$f" > "$f.new" && mv "$f.new" "$f"`. Expected: the "changed outside settings" notice appears and `hyprctl getoption general:gaps_out` is unchanged. Press "Apply now": the value becomes 7. Then put `<<<<<<< HEAD` on the first line of the file and change "Gaps in" in the page. Expected: the page shows `cannot parse ...`, the file is byte-for-byte unchanged, gaps unchanged. Restore the file with `git checkout`.

- [ ] **Step 7: Game mode (tariognatha)**

With "Gaps in" at 12, toggle game mode on (gaps 0) and off. Expected: `hyprctl getoption general:gaps_in` is back to 12.

- [ ] **Step 8: Border colors (tariognatha)**

Enable custom border colors; change the wallpaper. Expected: borders follow the palette; `git -C ~/.dotfiles diff --stat hosts/tariognatha/ii-settings.json` prints nothing. Watch for a reload loop:

```bash
# hyprconfigurator.py writes a temp file in the same directory and renames it, so count only
# renames onto main.lua. inotify-tools is not installed on the hosts.
nix shell nixpkgs#inotify-tools -c timeout 20 inotifywait -m -e moved_to --format '%f' ~/.config/hypr/hyprland/shellOverrides/ 2>/dev/null \
  | grep --line-buffered -x 'main.lua' | tee "$XDG_RUNTIME_DIR/ino.log" &
# change the wallpaper once now, then wait for the timeout
wait; wc -l < "$XDG_RUNTIME_DIR/ino.log"
```

Expected: at most one event per change. Switch: the custom colors are back with no qs restart.

- [ ] **Step 9: Animation presets (tariognatha)**

Pick "Elastic". Expected: `grep -c 'animationPresets.fast' ~/.config/hypr/custom/krane_gui.lua` is `1`, window-open animations change, and there is no "add a require line" notice. Switch: it persists. Pick "Stock": the `require` line and the key are gone.

- [ ] **Step 10: Autostart (tariognatha)**

Add an app (for example `kitty`) with workspace 2, enable autostart, reboot. Expected: it starts on the next boot and the one after; `test -e /tmp/qs-autostart.lock || echo NO-TMP-LOCK` prints `NO-TMP-LOCK`.

- [ ] **Step 11: Hyprland rejects a value (dev only, tariognatha)**

```bash
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); command cp -r ~/.dotfiles/pkgs/krane-ii-settings/. "$t/"
jq '.hyprland["general:nope"] = {"type": "int", "min": 0, "max": 9}' "$t/schema.json" > "$t/s" && mv "$t/s" "$t/schema.json"
sed -i "s#@hyprctl@#$(command -v hyprctl)#" "$t/krane_ii_settings.py"
cp ~/.dotfiles/hosts/tariognatha/ii-settings.json "$t/before.json"
manifest=$(grep -o '/nix/store/[a-z0-9]*-krane-ii-settings-manifest-[a-z]*\.json' "$(readlink -f "$(command -v krane-ii-settings)")")
python3 "$t/krane_ii_settings.py" --manifest "$manifest" set hyprland general:nope 1; echo "exit $?"
cmp "$t/before.json" ~/.dotfiles/hosts/tariognatha/ii-settings.json && echo REPO-UNCHANGED
hyprctl configerrors; rm -rf "$t"
```

Expected: `krane-ii-settings: Hyprland rejected the change; reverted.` with the error, `exit 1`, `REPO-UNCHANGED`, and empty `configerrors`. If the reported error does not name `krane_gui`, the revert did not fire: report it (the writer matches on that name).

- [ ] **Step 12: Commit B4**

```bash
cd ~/.dotfiles
git add patches/ii/05-settings
git commit -m "Add the ii Hyprland settings page, persisted through krane-ii-settings"
```

---

## Phase C: displays

### Task 21: Color management fields in the monitor submodule (commit C1)

**Files:**
- Modify: `modules/home/hypr-config.nix` (`monitorType`, `monitorLua`)

**Interfaces:**
- Produces: `krane.hypr.monitors.*.{cm, sdrbrightness, sdrsaturation, sdr_min_luminance, sdr_max_luminance, min_luminance, max_luminance, max_avg_luminance}`, all `nullOr`, default `null`, omitted from `hl.monitor` when null. `modules/home/ii-settings.nix` already treats non-null ones as Nix-owned (its `optionalMonitorFields`).

- [ ] **Step 1: Check each field name against Hyprland 0.56.2's Lua monitor parser**

```bash
cd ~/.dotfiles
src=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.pkgs.hyprland.src)
R=$src/src/config/lua/bindings/LuaBindingsConfigRules.cpp
for f in cm sdrbrightness sdrsaturation sdr_min_luminance sdr_max_luminance min_luminance max_luminance max_avg_luminance; do
  grep -o "{\"$f\", \[\]() -> ILuaConfigValue\* { return new CLuaConfig[A-Za-z]*" "$R" | sed "s/.*CLuaConfig/$f: /" || echo "MISSING $f"
done
```

Expected: `cm: String`, `sdrbrightness: Float`, `sdrsaturation: Float`, `sdr_min_luminance: Float`, `sdr_max_luminance: Int`, `min_luminance: Float`, `max_luminance: Int`, `max_avg_luminance: Int`; no `MISSING`. An unknown field is a hard error at Hyprland start, so do not continue past a `MISSING`.

- [ ] **Step 2: Show the option is missing (failing check)**

```bash
nix eval .#nixosConfigurations.tariognatha.config.home-manager.users.krane.krane.hypr.monitors --apply 'ms: (builtins.head ms) ? cm'
```

Expected: `false`.

- [ ] **Step 3: Add the options and render them**

In `monitorType`'s `options`, after `disabled`:

```nix
      cm = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "auto"
            "srgb"
            "wide"
            "edid"
            "hdr"
            "hdredid"
            "dcip3"
            "dp3"
            "adobe"
          ]
        );
        default = null;
        description = "Color management preset. `hdr` needs `bitdepth = 10`.";
      };
      sdrbrightness = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "SDR content brightness multiplier while in HDR mode.";
      };
      sdrsaturation = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "SDR content saturation multiplier while in HDR mode.";
      };
      sdr_min_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "SDR minimum luminance in nits, for SDR-to-HDR mapping.";
      };
      sdr_max_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "SDR maximum luminance in nits, for SDR-to-HDR mapping.";
      };
      min_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "Override the EDID minimum luminance, in nits.";
      };
      max_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override the EDID maximum luminance, in nits.";
      };
      max_avg_luminance = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override the EDID maximum average luminance, in nits.";
      };
```

Replace the start of `monitorLua`

```nix
  monitorLua =
    m:
    "hl.monitor("
    + luaFields "" [
```

with

```nix
  # Color management and luminance fields, in the order krane-ii-settings renders them. Each name
  # was checked against Hyprland 0.56's Lua monitor parser (LuaBindingsConfigRules.cpp): an
  # unknown hl.monitor field is a hard error at Hyprland start.
  colorFields = [
    "cm"
    "sdrbrightness"
    "sdrsaturation"
    "sdr_min_luminance"
    "sdr_max_luminance"
    "min_luminance"
    "max_luminance"
    "max_avg_luminance"
  ];

  monitorLua =
    m:
    "hl.monitor("
    + luaFields "" (
      [
```

and its end

```nix
      {
        name = "disabled";
        value = if m.disabled then true else null;
      }
    ]
    + ")\n";
```

with

```nix
      {
        name = "disabled";
        value = if m.disabled then true else null;
      }
    ]
    ++ map (f: {
      name = f;
      value = m.${f};
    }) colorFields
    )
    + ")\n";
```

Run `nix fmt modules/home/hypr-config.nix` (the formatter re-indents the list you wrapped), then `git add modules/home/hypr-config.nix`.

- [ ] **Step 4: Render, ownership and overlap (passing checks)**

Temporarily give DP-2 `cm = "hdr"; bitdepth = 10;`:

```bash
cd ~/.dotfiles
sed -i '0,/        scale = 1.5;/s//        scale = 1.5;\n        cm = "hdr";\n        bitdepth = 10;/' hosts/tariognatha/display.nix
H=.#nixosConfigurations.tariognatha.config.home-manager.users.krane
sed -n '/output = "DP-2"/,/})/p' "$(nix build --no-link --print-out-paths "$H.krane.hypr._rendered.\"monitors.lua\"")"
jq -c '.nixOwned.monitors["DP-2"]' "$(nix build --no-link --print-out-paths "$H.krane.iiSettings.manifestFile")"
printf '{"monitors":{"DP-2":{"cm":"srgb"}}}\n' > hosts/tariognatha/ii-settings.json
nix eval --raw .#nixosConfigurations.tariognatha.config.system.build.toplevel.drvPath 2>&1 | grep -A1 'Failed assertions'
git checkout -- hosts/tariognatha/display.nix; printf '{}\n' > hosts/tariognatha/ii-settings.json; git diff --stat hosts/tariognatha
```

Expected: the DP-2 rule ends `bitdepth = 10,` / `cm = "hdr"`; the owned list is `["bitdepth","cm","disabled","mode","output","position","scale"]`; the eval fails with `... sets monitors.DP-2.cm, which Nix also sets`; no diff left.

- [ ] **Step 5: Flake check and commit C1**

```bash
nix flake check && for h in tariognatha tarmantria taractias; do nixos-rebuild dry-build --flake .#$h || echo "FAIL $h"; done
git commit -m "Add color management and luminance fields to krane.hypr.monitors"
```

Expected: passes, no `FAIL`, one commit.

---

### Task 22: Writer display commands: try, confirm, boot check

**Files:**
- Modify: `pkgs/krane-ii-settings/krane_ii_settings.py`
- Create: `pkgs/krane-ii-settings/tests/test_displays.py`

**Interfaces:**
- Consumes: `Runtime.{start_revert_timer, stop_revert_timer, lock_state, open_settings}`, the pending file helpers (Task 13).
- Produces: `Settings.try_monitor(output, pairs)`, `Settings.confirm()`, `Settings.revert_unconfirmed()`, `Settings.boot_check(wait_seconds=60, poll=1.0)`; CLI `try monitor <output> FIELD VALUE...`, `confirm`, `revert-unconfirmed`, `boot-check`. The pending file holds `{"kind": "try", "output", "fields"}` or `{"kind": "boot", "outputs"}`. The revert timer is the transient systemd user unit `krane-ii-settings-revert` (15 s), which runs `apply` after a `try` and `revert-unconfirmed` after a boot check.

- [ ] **Step 1: Write the failing tests**

`pkgs/krane-ii-settings/tests/test_displays.py`:

```python
"""Display tests for krane_ii_settings (try, confirm, boot check).
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import pathlib
import unittest

from test_commands import Base, k


class TestMonitors(Base):
    def test_try_then_timeout_reverts(self):
        out = self.s.try_monitor("DP-2", [("cm", "hdr"), ("bitdepth", "10")])
        self.assertIn("reverting", out)
        self.assertEqual(self.repo.read_text(), "{}\n")
        self.assertIn('cm = "hdr"', pathlib.Path(self.manifest["liveFile"]).read_text())
        self.assertIn(("start_timer", ("apply",)), self.runtime.calls)
        self.s.apply()
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), k.HEADER)
        self.assertIn(("reload", True), self.runtime.calls)
        self.assertIsNone(k.read_pending())

    def test_try_then_confirm_persists_unconfirmed(self):
        self.s.try_monitor("DP-2", [("cm", "hdr"), ("bitdepth", "10")])
        self.s.confirm()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"bitdepth": 10, "bootConfirmed": False, "cm": "hdr"}}})
        self.assertFalse(self.runtime.timer)

    def test_no_revert_timer_means_no_change(self):
        def fail(command):
            raise OSError("systemd-run not found")
        self.runtime.start_revert_timer = fail
        with self.assertRaisesRegex(k.SettingsError, "nothing applied"):
            self.s.try_monitor("DP-2", [("cm", "hdr")])
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())
        self.assertIsNone(k.read_pending())

    def test_revert_survives_broken_repo_file(self):
        pathlib.Path(self.manifest["liveFile"]).write_text("BEFORE\n")
        self.s.try_monitor("DP-2", [("cm", "hdr")])
        self.repo.write_text("<<<<<<< HEAD\n")
        with self.assertRaisesRegex(k.SettingsError, "cannot parse"):
            self.s.apply()
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), "BEFORE\n")
        self.assertIsNone(k.read_pending())
        self.assertIn(("reload", True), self.runtime.calls)

    def test_try_refuses_nix_owned_field(self):
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.try_monitor("DP-2", [("scale", "1")])

    def test_gui_owned_output_gets_complete_rule(self):
        self.runtime.live_monitors = {"HDMI-A-1": {"mode": "1920x1080@60", "position": "3840x0", "scale": 1.0}}
        self.s.try_monitor("HDMI-A-1", [("position", "-1920x0")])
        self.s.confirm()
        entry = self.repo_data()["monitors"]["HDMI-A-1"]
        self.assertEqual(entry["position"], "-1920x0")
        self.assertEqual(entry["mode"], "1920x1080@60")
        self.assertEqual(entry["scale"], 1.0)

    def test_gui_owned_output_needs_hyprland(self):
        with self.assertRaisesRegex(k.SettingsError, "cannot be read"):
            self.s.try_monitor("HDMI-A-1", [("position", "0x0")])

    def test_boot_check_and_timeout(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.runtime.lock_states = ["false", "true", "true", "false"]
        self.assertIn("DP-2", self.s.boot_check(wait_seconds=5, poll=0))
        self.assertIn(("start_timer", ("revert-unconfirmed",)), self.runtime.calls)
        self.assertIn(("open_settings",), self.runtime.calls)
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {})

    def test_boot_check_keep(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.s.boot_check(wait_seconds=0, poll=0)
        self.s.confirm()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"cm": "hdr"}}})

    def test_boot_check_nothing_to_do(self):
        self.assertEqual(self.s.boot_check(wait_seconds=0, poll=0), "nothing to check")


if __name__ == "__main__":
    unittest.main()
```

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests 2>&1 | grep -E '^(Ran|OK|FAILED)'
```

Expected: `Ran 33 tests` and `FAILED (errors=10)` (`'Settings' object has no attribute 'try_monitor'` and similar).

- [ ] **Step 2: Implement**

1. Add `import time` after `import tempfile`.
2. In `class Settings`, after the `apply` method (after its `return "applied"`), add a blank line and:

```python
    def try_monitor(self, output, pairs):
        check_owner("monitor", output, [f for f, _ in pairs], self.manifest)
        with locked():
            data, _ = read_repo(self.repo)
            proposed = edit_set(data, "monitor", output, pairs, self.schema)
            proposed = complete_rule(proposed, output, self.manifest, self.runtime)
            validate_data(proposed, self.schema)
            check_ownership(proposed, self.manifest)
            live = self.render(proposed)
            # The live file from before the try goes into the pending file, so the
            # revert never depends on the repo file still being readable.
            write_pending({"kind": "try", "output": output,
                           "fields": proposed["monitors"][output],
                           "previousLive": self.runtime.read_live()})
            # Timer first: if it cannot be started, nothing has been applied yet.
            try:
                self.runtime.start_revert_timer(["apply"])
            except (OSError, subprocess.CalledProcessError) as e:
                clear_pending()
                raise SettingsError(f"cannot start the revert timer, nothing applied: {e}")
            self.runtime.write_live(live)
            self.runtime.reload(full=True)
            return f"trying {output}; reverting in {REVERT_SECONDS}s unless confirmed"

    def confirm(self):
        with locked():
            pending = read_pending()
            if pending is None:
                raise SettingsError("nothing to confirm")
            self.runtime.stop_revert_timer()
            data, text = read_repo(self.repo)
            new = copy.deepcopy(data)
            if pending["kind"] == "try":
                entry = dict(pending["fields"])
                entry["bootConfirmed"] = False
                new.setdefault("monitors", {})[pending["output"]] = entry
            else:
                for entry in new.get("monitors", {}).values():
                    entry.pop("bootConfirmed", None)
            validate_data(new, self.schema)
            check_ownership(new, self.manifest)
            new_text = dump(new)
            if new_text != text:
                atomic_write(self.repo, new_text)
            live = self.render(new)
            if live != self.runtime.read_live():
                self.runtime.write_live(live)
                self.runtime.reload(full=True)
            clear_pending()
            return "confirmed"

    def revert_unconfirmed(self):
        with locked():
            data, text = read_repo(self.repo)
            new = copy.deepcopy(data)
            for output, entry in list(new.get("monitors", {}).items()):
                if entry.get("bootConfirmed") is False:
                    del new["monitors"][output]
            if "monitors" in new and not new["monitors"]:
                del new["monitors"]
            new_text = dump(new)
            if new_text != text:
                atomic_write(self.repo, new_text)
            self.runtime.write_live(self.render(new))
            clear_pending()
            self.runtime.reload(full=True)
            return "reverted unconfirmed display settings"

    def boot_check(self, wait_seconds=60, poll=1.0):
        data, _ = read_repo(self.repo)
        unconfirmed = sorted(
            o for o, e in data.get("monitors", {}).items() if e.get("bootConfirmed") is False)
        if not unconfirmed:
            return "nothing to check"
        # lock-on-start locks the session once ii's lock IPC is up. Wait for
        # that lock (up to wait_seconds), then for the unlock, so the dialog
        # and its timer start only once the user can see and answer them.
        deadline = time.monotonic() + wait_seconds
        while time.monotonic() < deadline and self.runtime.lock_state() != "true":
            time.sleep(poll)
        while self.runtime.lock_state() == "true":
            time.sleep(poll)
        with locked():
            write_pending({"kind": "boot", "outputs": unconfirmed})
            self.runtime.start_revert_timer(["revert-unconfirmed"])
        self.runtime.open_settings()
        return "asking to keep " + ", ".join(unconfirmed)
```

3. Replace the whole `main` function with:

```python
def main(argv=None, runtime_factory=Runtime):
    parser = argparse.ArgumentParser(prog="krane-ii-settings")
    parser.add_argument("--manifest", default=os.environ.get("KRANE_II_SETTINGS_MANIFEST"))
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("get")
    p_set = sub.add_parser("set")
    p_set.add_argument("section", choices=["hyprland", "idle", "animation", "monitor"])
    p_set.add_argument("key")
    p_set.add_argument("rest", nargs="+")
    p_reset = sub.add_parser("reset")
    p_reset.add_argument("section", choices=["hyprland", "idle", "animation", "monitor"])
    p_reset.add_argument("key")
    p_reset.add_argument("fields", nargs="*")
    sub.add_parser("apply")
    p_render = sub.add_parser("render")
    p_render.add_argument("--json", required=True)
    p_try = sub.add_parser("try")
    p_try.add_argument("section", choices=["monitor"])
    p_try.add_argument("output")
    p_try.add_argument("rest", nargs="+")
    sub.add_parser("confirm")
    sub.add_parser("boot-check")
    sub.add_parser("revert-unconfirmed")
    sub.add_parser("schema")
    args = parser.parse_args(argv)
    schema = load_schema()
    try:
        if args.cmd == "schema":
            print(dump(schema), end="")
            return 0
        manifest = load_manifest(args.manifest)
        if args.cmd == "render":
            data, _ = read_repo(args.json)
            print(render(data, manifest, schema), end="")
            return 0
        settings = Settings(manifest, schema, runtime_factory(manifest))
        if args.cmd == "get":
            out = settings.get()
        elif args.cmd == "set":
            if args.section == "monitor":
                pairs = pairs_from(args.rest, "set monitor")
            else:
                if len(args.rest) != 1:
                    raise SettingsError(f"set {args.section} {args.key}: expected one value")
                pairs = [(args.key, args.rest[0])]
            out = settings.set(args.section, args.key, pairs)
        elif args.cmd == "reset":
            out = settings.reset(args.section, args.key, args.fields)
        elif args.cmd == "apply":
            out = settings.apply()
        elif args.cmd == "try":
            out = settings.try_monitor(args.output, pairs_from(args.rest, "try monitor"))
        elif args.cmd == "confirm":
            out = settings.confirm()
        elif args.cmd == "boot-check":
            out = settings.boot_check()
        else:
            out = settings.revert_unconfirmed()
        print(out)
        return 0
    except SettingsError as e:
        print(f"krane-ii-settings: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Run the tests and lint**

```bash
cd ~/.dotfiles/pkgs/krane-ii-settings
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests 2>&1 | grep -E '^(Ran|OK|FAILED)'
nix run nixpkgs#python3Packages.flake8 -- --ignore=E501,W503 krane_ii_settings.py && echo FLAKE-OK
cd ~/.dotfiles && git add pkgs/krane-ii-settings && nix build --no-link -L .#checks.x86_64-linux.ii-settings-writer 2>&1 | tail -2
```

Expected: `Ran 33 tests`, `OK`, `FLAKE-OK`, and the check ends with `OK`.

No commit (commit C2 is in Task 24).

---

### Task 23: ii display patches and the boot check

**Files (clone, under `$II`):**
- Create: `scripts/hyprland/monitor_caps.py`, `modules/common/widgets/MonitorCanvas.qml`, `modules/common/widgets/MonitorRect.qml`, `modules/common/models/hyprland/MonitorConfigOption.qml`
- Modify: `modules/common/panels/lock/LockScreen.qml`, `services/KraneSettings.qml`, `modules/settings/HyprlandConfig.qml`
- Modify (dotfiles): `modules/home/ii-settings.nix` (boot-check exec)

**Interfaces:**
- Consumes: CLI from Task 22; `KraneSettings.isMonitorFieldLocked`.
- Produces: `qs -c ii ipc call lock isLocked` prints `true`/`false`. `KraneSettings.tryMonitor(output, fields)`, `KraneSettings.confirm()`, `KraneSettings.revert()`; `MonitorConfigOption.save(index)` sends set fields through `try` and resets through `reset monitor`.

- [ ] **Step 1: `monitor_caps.py`, `MonitorRect.qml`, `MonitorCanvas.qml`**

```bash
FORK=dc2ca2600ee6d7852bf0ac91361db8e510f90a74; F=https://raw.githubusercontent.com/pctrade/end4-pC/$FORK
II=~/src/dots-hyprland/dots/.config/quickshell/ii
curl -sfL "$F/scripts/hyprland/monitor_caps.py" -o "$II/scripts/hyprland/monitor_caps.py" && chmod +x "$II/scripts/hyprland/monitor_caps.py"
for w in MonitorRect MonitorCanvas; do curl -sfL "$F/modules/common/widgets/$w.qml" -o "$II/modules/common/widgets/$w.qml"; done
head -1 "$II/scripts/hyprland/monitor_caps.py"
"$II/scripts/hyprland/monitor_caps.py" $(hyprctl monitors -j | jq -r '.[].name') | jq -c .
python3 ~/src/ii-tools/forkcheck.py "$II" "$II"/modules/common/widgets/Monitor{Rect,Canvas}.qml; echo "exit $?"
```

Expected: the venv shebang; on tariognatha a JSON object with `DP-1` and `DP-2`, each with `hdr` and `maxBpc` (DP-2 `hdr: true` if its EDID reports it); `exit 0` (make `WM` checks constant as in Task 5 if any are reported). Commit: subject `feat(settings): monitor layout canvas and EDID capability probe`; fork paths as fetched; `Port: clean`; `Drop when: the Displays section is dropped.`

- [ ] **Step 2: `MonitorConfigOption.qml`**

```bash
curl -sfL "$F/modules/common/models/hyprland/MonitorConfigOption.qml" -o "$II/modules/common/models/hyprland/MonitorConfigOption.qml"
```

Edits:
1. Delete the properties `configuratorScriptPath` and `monitorsLuaPath` (`monitor_configurator.py` is not ported: it edited `monitors.lua`, which Nix owns).
2. Delete `enabled: WM.compositor === "hyprland"` from the `Connections` on `Hyprland`.
3. Replace the functions `save`, `applyMonitor`, `applyAndSave` and `saveHdr` with:

   ```qml
       // Set fields go through krane-ii-settings try: applied live with a full reload, then
       // reverted after 15 s by a systemd timer unless the page's Keep calls confirm. Resets
       // go straight to the repo file: they return a field to its Nix or Hyprland default.
       function save(index) {
           const m = root.monitors[index]
           if (!m || !m.name) return
           const changed = root._pendingChanges[index]
           if (!changed) return
           const { setPairs, resetKeys } = root._fieldsToWrite(m, new Set(Object.keys(changed)))
           let pending = Object.assign({}, root._pendingChanges)
           delete pending[index]
           root._pendingChanges = pending
           for (const key of resetKeys)
               KraneSettings.reset("monitor", m.name, key)
           if (Object.keys(setPairs).length > 0)
               KraneSettings.tryMonitor(m.name, setPairs)
       }
   ```

4. In `fetchProc`'s handler, change `capsProc.command = ["python3", root.capsScriptPath]...` to `capsProc.command = [root.capsScriptPath].concat(root.monitors.map(mon => mon.name))`, delete the two `dumpProc` lines after it, and add `root._mergeSaved()`.
5. Delete the `Process` blocks `dumpProc`, `applyProc`, `saveProc` and `reloadProc`, and add:

   ```qml
       // Saved fields hyprctl does not report (bitdepth, luminance overrides) come from
       // krane-ii-settings get: the repo file over the Nix baseline.
       function _mergeSaved() {
           const saved = KraneSettings.state.repo?.monitors ?? {}
           const base = KraneSettings.state.monitorBaselines ?? {}
           let patch = {}
           for (const m of root.monitors) {
               const d = Object.assign({}, base[m.name] ?? {}, saved[m.name] ?? {})
               patch[m.name] = {
                   bitdepth:        d.bitdepth ?? null,
                   minLuminance:    d.min_luminance ?? null,
                   maxLuminance:    d.max_luminance ?? null,
                   maxAvgLuminance: d.max_avg_luminance ?? null,
               }
           }
           root._mergeByName(patch)
       }

       Connections {
           target: KraneSettings
           function onStateChanged() { root._mergeSaved() }
       }
   ```

```bash
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/common/models/hyprland/MonitorConfigOption.qml"; echo "exit $?"
grep -n 'monitors\.lua\|python3\|hyprctl", "keyword\|hyprctl", "reload' "$II/modules/common/models/hyprland/MonitorConfigOption.qml"
```

Expected: `exit 0` and no grep output. Commit: subject `feat(settings): monitor settings through krane-ii-settings`; fork path `modules/common/models/hyprland/MonitorConfigOption.qml`; `Port: hand-ported (monitors.lua writer and direct hyprctl apply replaced by krane-ii-settings try/reset; saved fields read from its get)`; `Drop when: the Displays section is dropped.`

- [ ] **Step 3: `isLocked()` on the lock IPC handler**

```bash
cd ~/src/dots-hyprland
git apply --ignore-whitespace <<'PATCH'
--- a/dots/.config/quickshell/ii/modules/common/panels/lock/LockScreen.qml
+++ b/dots/.config/quickshell/ii/modules/common/panels/lock/LockScreen.qml
@@ -109,6 +109,11 @@
         function focus(): void {
             lockContext.shouldReFocus();
         }
+        // For krane-ii-settings boot-check, which waits for the first unlock
+        // before asking to keep new display settings.
+        function isLocked(): bool {
+            return GlobalStates.screenLocked;
+        }
     }
 
     GlobalShortcut {
PATCH
```

Commit: subject `feat(lock): report the lock state over IPC`; `Port: krane-only`; `Problem: krane-ii-settings boot-check waits for the first unlock before asking to keep new display settings.`; `Drop when: the lock IPC handler reports its state upstream.`

- [ ] **Step 4: `KraneSettings.qml` display calls**

After `function apply()` add:

```qml
    function tryMonitor(output, fields) {
        const args = ["try", "monitor", output];
        for (const k in fields)
            args.push(k, String(fields[k]));
        root._enqueue(args);
    }

    function confirm() {
        root._enqueue(["confirm"]);
    }

    // Revert a pending display change now instead of waiting for the timer.
    function revert() {
        root._enqueue([root.state.pending?.kind === "boot" ? "revert-unconfirmed" : "apply"]);
    }
```

and before `Component.onCompleted`:

```qml
    // While a revert timer runs, poll so the page sees it fire.
    Timer {
        interval: 1000
        repeat: true
        running: root.state.revertPending === true
        onTriggered: root.refresh()
    }
```

- [ ] **Step 5: Displays section in the Hyprland page**

```bash
t=$(mktemp -d -p "$XDG_RUNTIME_DIR"); curl -sfL "$F/modules/ii/settings/pages/HyprlandConfig.qml" -o "$t/h.qml"
grep -n '// Displays\|MonitorConfigOption { id: monitorConfig }\|title: Translation.tr("Layout")' "$t/h.qml"
```

Copy back what Task 19 removed: the line `MonitorConfigOption { id: monitorConfig }` after the page's other top-level properties, and the fork's lines from `// Displays` up to (not including) the `ContentSection {` that holds `title: Translation.tr("Layout")`, into `mainLayout` right after the two status notices. Then edit that section:

1. `sed -i 's/monitorConfig\.applyAndSave(/monitorConfig.save(/g; s/monitorConfig\.saveHdr(/monitorConfig.save(/g' "$II/modules/settings/HyprlandConfig.qml"`.
2. Add to the page (next to `borderColorRoles`):
   ```qml
       // A field of the selected output that Nix sets in krane.hypr.monitors.
       function monitorLocked(field) {
           return KraneSettings.isMonitorFieldLocked(monitorConfig.monitors[monitorCanvas.selectedIndex]?.name ?? "", field)
       }
   ```
   and add `enabled: !page.monitorLocked("<field>")` (combined with any existing `enabled` by `&&`) to: the enable switch (`"disabled"`), the resolution selector (`"mode"`), the scale spin box (`"scale"`), the X and Y spin boxes (`"position"`), the transform selector (`"transform"`), the bit depth selector (`"bitdepth"`) and the color management selector (`"cm"`). Append ``(page.monitorLocked("<field>") ? ` · ${KraneSettings.nixReason}` : "")`` to each one's `text`.
3. In the "HDR & Color Management" `ContentSubsection`, set `visible: monitorConfig.monitors[monitorCanvas.selectedIndex]?.hdrSupported === true` and delete its two `NoticeBox`es (unknown and no HDR support). The spec shows HDR controls only when the EDID reports HDR.
4. In the color management selector's `onSelected`, turning HDR on sets 10 bits too:
   ```qml
                           onSelected: newValue => {
                               const hdr = newValue === "hdr" || newValue === "hdredid"
                               monitorConfig.updateMonitor(monitorCanvas.selectedIndex, hdr ? { cm: newValue, bitdepth: 10 } : { cm: newValue })
                               monitorConfig.save(monitorCanvas.selectedIndex)
                           }
   ```
5. As the first child of the Displays `ContentSection`, the keep-or-revert banner:
   ```qml
               // Shown while krane-ii-settings' revert timer runs: after a try, or after
               // boot-check found display settings not yet confirmed since this boot.
               NoticeBox {
                   id: keepBanner
                   Layout.fillWidth: true
                   visible: KraneSettings.state.revertPending === true
                   property int countdown: 15
                   onVisibleChanged: if (visible) countdown = 15
                   Timer {
                       interval: 1000; repeat: true; running: keepBanner.visible
                       onTriggered: keepBanner.countdown = Math.max(0, keepBanner.countdown - 1)
                   }
                   text: Translation.tr("Keep these display settings? Reverting in %1 s").arg(keepBanner.countdown)
                   Item { Layout.fillWidth: true }
                   RippleButtonWithIcon {
                       Layout.fillWidth: false
                       buttonRadius: Appearance.rounding.small
                       materialIcon: "check"
                       mainText: Translation.tr("Keep")
                       onClicked: KraneSettings.confirm()
                   }
                   RippleButtonWithIcon {
                       Layout.fillWidth: false
                       buttonRadius: Appearance.rounding.small
                       materialIcon: "undo"
                       mainText: Translation.tr("Revert")
                       onClicked: KraneSettings.revert()
                   }
               }
   ```

The page's root needs `id: page` (the fork's page already declares it). Then:

```bash
python3 ~/src/ii-tools/forkcheck.py "$II" "$II/modules/settings/HyprlandConfig.qml" "$II/services/KraneSettings.qml"; echo "exit $?"
smoke HyprlandConfig "$XDG_RUNTIME_DIR/h.log"; newerrs QuickConfig "$XDG_RUNTIME_DIR/h.log"; rm -rf "$t"
```

Expected: `exit 0`, no new errors. Commit `KraneSettings.qml` and `HyprlandConfig.qml` together: subject `feat(settings): displays with confirm-or-revert`; fork path `modules/ii/settings/pages/HyprlandConfig.qml (Displays)`; `Problem: display changes can leave a screen unusable; they must revert on their own unless confirmed.`; `Port: hand-ported (Nix-owned fields disabled; HDR only when the EDID reports it; HDR sets 10-bit; keep-or-revert banner driven by the writer's timer)`; `Drop when: the Displays section is dropped.` Run the export command.

- [ ] **Step 6: Run the boot check at login**

In `modules/home/ii-settings.nix`, in `config`, after `home.packages = [ wrapped ];`:

```nix

    # Display changes kept before this boot carry bootConfirmed = false. After the first
    # unlock, ask again and revert them 15 s later unless kept (krane-ii-settings boot-check).
    krane.hypr.execOnce = [ "${wrapped}/bin/krane-ii-settings boot-check" ];
```

```bash
cd ~/.dotfiles && git add modules/home/ii-settings.nix
gen=$(nix build --no-link --print-out-paths .#nixosConfigurations.tariognatha.config.home-manager.users.krane.krane.hypr._rendered.'"custom/execs.lua"')
grep -c 'krane-ii-settings boot-check' "$gen"
```

Expected: `1`.

---

### Task 24: Phase C switch, acceptance and commit C2

- [ ] **Step 1: Whole-series and build checks, switch**

Run Task 11, Steps 2, 3 and 4 (tariognatha, then tarmantria). Then `qs -c ii ipc call lock isLocked`. Expected: as there, and `false`.

- [ ] **Step 2: Ownership (tariognatha)**

Hyprland page, Displays, select DP-1: resolution, scale and position are disabled with "Set in Nix"; HDR and color fields are editable if DP-1's EDID reports HDR (otherwise hidden). Same for DP-2.

- [ ] **Step 3: Revert (tarmantria's eDP-1, plus an output not in `display.nix` if one can be attached)**

Every output in `display.nix` has Nix-owned `mode`, `position` and `scale` (resolved decision 4), so on eDP-1 the field to try is `transform` (Orientation, for example 180°: visible and harmless); position, mode and scale of eDP-1 are disabled with "Set in Nix". Position and the complete-rule check need an output Nix does not declare (an external monitor on tarmantria, or a third one on tariognatha); record "not run" if none is available.

1. Change the field; wait 15 s. Expected: it reverts, `git -C ~/.dotfiles diff --stat hosts/<host>/ii-settings.json` prints nothing, `systemctl --user is-active krane-ii-settings-revert.timer` is `inactive`.
2. Change it again, then `pkill -f settings.qml`. Expected: it still reverts after 15 s (the timer is outside the UI).
3. Change it and press Keep. Expected: `jq '.monitors' ~/.dotfiles/hosts/<host>/ii-settings.json` shows the output with `"bootConfirmed": false`: eDP-1 with only the GUI field, a non-Nix output with a complete rule (`mode`, `position`, `scale`).
3a. Revert without the repo file: change the field, then within 15 s put `<<<<<<< HEAD` on the first line of `ii-settings.json`. Expected: after 15 s the display still reverts (the timer restores the live file saved at `try`), `systemctl --user is-active krane-ii-settings-revert.timer` is `inactive`, and the page shows `cannot parse ...`. Restore the file with `git checkout`.
4. Reboot, unlock (typing the password blind works). Expected: the settings window opens on the Hyprland page with the keep banner. Keep: `bootConfirmed` is gone from the file.
5. Change it again, Keep, reboot, unlock, and let the banner time out. Expected: the `monitors.<output>` entry is gone from the repo file and the display is back to its Nix or default rule.

- [ ] **Step 4: HDR (tariognatha, DP-2)**

Turn HDR on. Expected: `hyprctl monitors -j | jq '.[] | select(.name=="DP-2") | {colorManagementPreset, currentFormat}'` shows `hdr` and a 10-bit format, or the timer reverts it (a link that cannot carry 3840x2160@240 at 10 bits). If kept: cold boot, unlock, Keep in the boot banner: it survives. SDR brightness changes are visible while in HDR.

- [ ] **Step 5: Laptop (tarmantria)**

eDP-1 scale, mode and position are disabled with "Set in Nix"; a transform change reverts (Step 3); the HDR subsection is hidden (no EDID HDR). taractias: not run until its hardware is verified; record that.

- [ ] **Step 6: Escape hatches work as documented**

With a GUI monitor entry present: `rm ~/.config/hypr/custom/krane_gui.lua && hyprctl reload`. Expected: every GUI delta is gone until the next switch. Restore with `krane-ii-settings apply`.

- [ ] **Step 7: Commit C2**

```bash
cd ~/.dotfiles
git add patches/ii/05-settings pkgs/krane-ii-settings modules/home/ii-settings.nix
git commit -m "Add display settings with confirm-or-revert and a first-boot check to the ii settings window"
```

---

### Task 25: Documentation

**Files:**
- Modify: `docs/II-INTEGRATION.md`, `docs/VERIFY.md`

- [ ] **Step 1: Update the text that calls the config dir ii-owned**

In `docs/II-INTEGRATION.md`:

1. Under "Wiped on every switch", replace the sentence ``Excluded: `~/.config/illogical-impulse`, whose `config.json` is the shell's own state and only seeded if absent.`` (wrapped over three lines) with:
   ```markdown
   Excluded: `~/.config/illogical-impulse`. It is a symlink into this repo,
   `hosts/<host>/illogical-impulse/` (see "Settings persistence"). The copy
   step's `mkdir -p` and its `config.json` seed check follow the link.
   ```
2. In "Owned vs appended", add a row: `` | `custom/krane_gui.lua` | owned | Rendered from `hosts/<host>/ii-settings.json` by `modules/home/ii-settings.nix`; rewritten live by the settings window. Required last by `monitors.lua`. | ``
3. In "How ii sources Lua", replace the paragraph that begins `There is no custom/monitors.lua.` with:
   ```markdown
   - There is no `custom/monitors.lua`. Monitor rules go in the top-level
     `monitors.lua`, which this repo owns and renders from
     `krane.hypr.monitors`. Its last lines require `custom/krane_gui.lua`,
     where display changes made in the ii settings window land. Do not use
     `nwg-displays`: whatever it writes into `monitors.lua` is replaced on
     the next switch.
   ```
4. In "Patched files", in the `Config.qml` `launchOnStartup` bullet, replace ``` `config.json` stays ii-owned after that, the GUI can still flip it back off.``` with `After that the value lives in this host's config.json in the repo, and the settings window can still turn it off.`
5. The subsections that sub-projects 3 and 4 added still call `config.json` ii's own state. In ``### Dock (`03-dock`)``, replace ``nothing in this repo turns it on: `config.json` is ii's own state.`` (wrapped over two lines) with ``Nix never turns it on; the setting lands in this host's `config.json` in the repo (see "Settings persistence").`` In `### Agents tab` (under `## Claude Code`), replace `(ii-owned, not written by Nix)` with `(this host's file in the repo, see "Settings persistence"; not written by Nix)`. The `jq` commands in the Translator and Dock subsections keep working: `mv` replaces the file inside the linked directory, and `*.tmp` is ignored.
6. Delete the `hypridle.conf` bullet under "Patched files" (the `idleTimeouts = false` sed) and add after the list: ``Idle timeouts are no longer a sed: `kraneIiIdle` (in `modules/home/ii-settings.nix`) runs ii's `hypridleconfigurator.py` with the values from `krane.hypr.idle`, `idleTimeouts = false` (all zeros) or the settings window. See "Settings persistence".``

- [ ] **Step 2: Add the "Settings persistence" section**

Add as a new `##` section directly after `## Backported fork fixes` (after its last subsection, `### When to stop using patches`) and before `## Claude Code`. The widget list and the dropped-control table below were filled from the fork source at `dc2ca2600ee6` against the pin plus the 02–04 changes; before committing, compare them with `~/src/ii-tools/widgets.txt` and `~/src/ii-tools/dropped.txt` and correct any row that differs (a control kept or dropped differently during the port):

````markdown
## Settings persistence

`patches/ii/05-settings` ports pctrade/end4-pC's settings pages (at
`dc2ca2600ee6`) into ii's standalone settings window (`SUPER + I`). Every
control either persists in this repo or was removed. The rule: persist
choices, derive consequences.

| Kind | Source of truth | Live apply |
|---|---|---|
| ii shell options | `hosts/<host>/illogical-impulse/config.json`, through the `~/.config/illogical-impulse` symlink | ii's own file watcher |
| Hyprland options (`hl.config` keys) | `hosts/<host>/ii-settings.json`, `hyprland` | writer re-renders `custom/krane_gui.lua`, `hyprctl reload config-only` |
| Monitor fields | `hosts/<host>/ii-settings.json`, `monitors` | same file, full reload, confirm-or-revert |
| Idle timeouts | `hosts/<host>/ii-settings.json`, `idle`, or `krane.hypr.idle` | writer edits `hypridle.conf`, restarts hypridle |
| Animation preset | `hosts/<host>/ii-settings.json`, `animationPreset` | `require("hyprland.animationPresets.<name>")` in `krane_gui.lua` |
| Border colors | config.json, `hyprland.general.borderColor` (roles and opacity) | resolved from the palette into `shellOverrides/main.lua` |
| Hyprlock 12h clock | config.json, `time.format` | `shell.qml` seds `hyprlock.conf` on ready, on change and on every reload |

### One owner per key

Nix owns every key it sets: each `krane.hypr.settings` leaf, every entry of
`krane.hypr.guiLocked`, the non-null fields of each `krane.hypr.monitors`
entry (`output`, `mode`, `position`, `scale` and `disabled` always), and
`idle` when `krane.hypr.idle` or `idleTimeouts = false` is set. The settings
window shows those controls disabled with "Set in Nix", and
`krane-ii-settings` refuses them. Every other key in
`pkgs/krane-ii-settings/schema.json` belongs to the GUI file. A key in
both places fails evaluation, naming both files: delete it from one. To hand
a key to the GUI, delete it from `display.nix` in the same commit that adds
it to `ii-settings.json`. Keyboard layout stays in Nix because
`qwertz-binds.nix` depends on it.

Only keys in `schema.json` can be written; each was checked against
Hyprland 0.56's source. Adding one means checking it the same way (Task 12
of `docs/superpowers/plans/2026-09-27-ii-settings.md`).

### The writer

`krane-ii-settings` (`pkgs/krane-ii-settings`, on `PATH` with this host's
manifest) is the only writer of `ii-settings.json`:

- `set` / `reset <section> <key>`: validate, write the repo file atomically
  under a lock, re-render the live file, reload. It never creates the repo
  file and refuses to write one it cannot parse. If Hyprland reports an error
  in `krane_gui.lua` after the reload, it restores both files.
- `apply`: re-render the live file from the repo file, after a hand edit or a
  `git checkout`. The settings window offers the same as "Apply now" when it
  sees the file change; nothing is applied on its own.
- `try monitor …` / `confirm`: a display change is live at once, and a
  transient systemd timer (`krane-ii-settings-revert`, 15 s) reverts it
  unless Keep is pressed. Kept changes carry `bootConfirmed: false`;
  `boot-check` (run at login) asks again after the first unlock and removes
  the entry if not kept.
- `get`: the state the settings window shows.

The GUI never commits. `config.json` changes on every wallpaper switch
(`wallpaperPath`), so `git status` shows it often; commit selectively.
`ai/` and `*.tmp` are ignored; `actions/` and `presets/` are tracked.
Read a host's whole `config.json` before committing it for the first time:
it can hold the weather city, a booru username and AI endpoints.

### Escape hatches

- A display setting leaves a screen unusable: wait 15 s (the revert timer),
  or unlock blind after a reboot and wait 15 s (the boot check).
- That fails too: from a TTY, remove the `monitors.<output>` entry from
  `hosts/<host>/ii-settings.json` and switch. Faster, until the next switch:
  `rm ~/.config/hypr/custom/krane_gui.lua && hyprctl reload` drops every GUI
  delta.
- The repo file is broken (merge conflict): the settings window says so and
  writes nothing. Fix the file, then `krane-ii-settings apply`.

### Ported and dropped controls

Ported pages: Quick, General, Bar, Background, Interface, Services, Profile,
Hyprland, About (plus upstream's Advanced, kept). Fork widgets, models and
services added: 15 (`AboutCard`, `AndroidClock`, `Carousel`,
`ColorSelectionArray`, `ConfigComboBox`, `ConfigTextArea`, `GroupedList`,
`WorldMap` with `WorldMapDots.js` and `WorldCities.js`, `PresetsCard`,
`PresetPopup`, `AutostartApps`, `MonitorCanvas`, `MonitorRect`, the
`MonitorConfigOption` model and the `Presets` service). Not taken: the fork's
`MaterialSymbol`, `StyledImage` and `Fonts` (they need font files the pin does
not ship, or only remove pin behaviour), and `ConfigSelectionShapeArray`,
`LayoutSection` and `WidgetsMonitorSelector` (only dropped controls used them).
Not ported: the Niri page, the fork's panel-style settings overlay, About's
"Update dots" and "System update", Profile's hostname editing and online
presets.

| Page | Control (section) | Key | Reason |
|---|---|---|---|
| General | Show date (Time) | `time.showDate` | fork-only feature |
| Bar | Bar layout (whole section) | `bar.layouts.{leftLayout,middleLayout,rightLayout}` | fork-only feature |
| Bar | Group Color (Positioning & Styles) | `bar.groupColor` | fork-only feature |
| Bar | Show Frame, Overlap windows when center-only, Follow Frame Color, Frame thickness, Frame Color (Positioning & Styles) | `bar.showFrame`, `bar.centerOnlyReserveFrame`, `bar.followFrameColor`, `bar.frameThickness`, `bar.frameColor` | fork-only feature |
| Bar | Dynamic Island (whole section: Left widget, Right widget, Visualizer style, Show media controls) | `bar.dynamicIsland.*` | fork-only feature |
| Bar | Popup position (Notifications) | `notifications.position` | fork-only feature |
| Bar | Divider (whole section: Style, Space width) | `bar.divider.{style,spacing}` | fork-only feature |
| Bar | Wallpapers Toggle (Utility buttons) | `bar.utilButtons.showWallpaperToggle` | fork-only feature |
| Bar | Indicator style (Workspaces) | `bar.workspaces.indicatorStyle` | fork-only feature |
| Bar | CPU Temperature, RAM, Disk, Style, Show Percentage (Resources) | `bar.resources.{alwaysShowCpuTemp,alwaysShowRam,alwaysShowDisk,style,showValue}` | fork-only feature |
| Bar | Media (whole section: Preferred Player, Pin media controls, Show only title, Max media width) | `bar.media.*` | fork-only feature |
| Bar | Tooltips (whole section: Enable, Click to show) | `bar.tooltips.enable` | fork-only feature |
| Background | Lock-screen half of the wallpaper carousel, Use same wallpaper for both (Wallpaper) | `background.lockWall` | fork-only feature |
| Background | Preview wallpaper, Blur wall, Blur Size, Split blur amount, Split blur side, Transitions (Wallpaper) | `background.{enableWallpaperPreview,showBlur,blurRadius,splitRatio,splitSide,wallpaperAnimation}` | fork-only feature |
| Background | Wallpaper change interval (Wallpaper) | `wallpaperSelector.changeInterval` | fork-only feature |
| Background | Centered wallpaper (whole subsection: Enable, Show only when locked, shape, Background Color, Size) | `background.centeredWallpaper*` | fork-only feature |
| Background | Automatic colors, Color (Digital clock settings) | `background.widgets.clock.color` | fork-only feature |
| Background | Pixel clock orientation (Pixel Clock Settings) | `background.widgets.clock.pixel.orientation` | fork-only feature |
| Background | Follow Clock Font (Quote) | `background.widgets.clock.quote.followClock` | fork-only feature |
| Background | Custom Image, Visualizer, Text (whole sections) | `background.widgets.{customImage,visualizer,customText}.*` | fork-only feature |
| Background | Show widgets on (Widgets) | `background.screenList` | fork-only feature |
| Background | Image converter, Media, Resources, Calendar, World clock, User card, Notes, Todo, Timers, Sticker entries (Widgets) | `background.widgets.{images,media,resources,calendar,worldClock,userCard,notes,todo,timers,sticker}.enable` | fork-only feature |
| Background | Show alignment grid while dragging, Show snap lines when dropping (Canvas) | `background.{showGrid,showSnapLines}` | fork-only feature |
| Interface | Settings Panel (whole section: Style, Border width, Border Color) | `settings.{style,borderSize,borderColor}` | fork panel-style settings overlay not ported |
| Interface | Enable, Follow Album Colors (Left Sidebar media) | `sidebar.media.{enable,artColors}` | fork-only feature |
| Interface | Banner, Bottom Group, Media Player (Right Sidebar) | `sidebar.{banner,bottomGroup,mediaPlayer}` | fork-only feature |
| Interface | Bottom-left, Bottom-right (hot corners) | `sidebar.cornerOpen.{bottomLeftAction,bottomRightAction}` | fork-only feature |
| Interface | Style (Overview) | `overview.style` | fork-only feature (niri-like overview) |
| Interface | Show Widgets, Show Toolbars, Show media player info (Lock screen) | `lock.{showWidgets,showToolbars,showMedia}` | fork-only feature |
| Interface | Samples (Style: Blurred) | `lock.blur.size` | fork-only feature |
| Interface | Show home directory in quick access, Close after selection, Show blur background, Columns in grid view, Wallpaper change interval, Always show search bar, Custom Wallpaper Folder, Live Wallpaper Folder (Wallpaper selector) | `wallpaperSelector.{showHomePath,closeAfterSelection,showBlurBackground,columns,changeInterval,showSearchbar,userPath,liveWallpapersPath}` | fork-only feature |
| Services | Icons, Keybinds (Prefixes) | `search.prefix.{symbols,keybinds}` | fork-only feature |
| About | Packages, Updates cards; Update Dots, System update buttons | none | pacman-only / out of scope (spec) |
| Profile | Online presets; hostname editing (shown read-only) | `profile.onlinePresets` | out of scope (spec) |
| Hyprland | Displays section of the fork's `monitors.lua` writer; "add a require line" notice | none | replaced by `krane-ii-settings` (Design B, C) |
````

Check the table against the recorded lists: every line of `dropped.txt` has a row, and every row names a control that is gone from the ported page (`grep -c` of its key in `$II/modules/settings/<Page>.qml` is `0`).

- [ ] **Step 3: `docs/VERIFY.md` per-page checks**

Append:

```markdown
## Settings window (after two consecutive switches)

- `readlink -f ~/.config/illogical-impulse` is `~/.dotfiles/hosts/<host>/illogical-impulse`.
- `krane-ii-settings render --json ~/.dotfiles/hosts/<host>/ii-settings.json | diff - ~/.config/hypr/custom/krane_gui.lua` prints nothing (the live file matches the repo file).
- `hyprctl configerrors` is empty; `qs log -c ii` has no `[KraneSettings]` warning.
- `SUPER + I` opens every page; closing it leaves the bar running.
- One control per config.json page changes exactly one key in `git diff hosts/<host>/illogical-impulse/config.json`.
- Hyprland page: gaps set to 12 shows in `hyprctl getoption general:gaps_in` within a second and in `git diff hosts/<host>/ii-settings.json`; reset removes the key and restores the value without a switch.
- Keyboard layout (and on tariognatha idle) is disabled with "Set in Nix".
- Displays: a change reverts after 15 s unless kept; a kept change asks again after the next reboot.
- `systemctl --user is-active krane-ii-settings-revert.timer` is `inactive` when no change is pending.
```

- [ ] **Step 4: Commit**

```bash
cd ~/.dotfiles
git add docs/II-INTEGRATION.md docs/VERIFY.md
git commit -m "Document how the ii settings window persists its settings"
```
