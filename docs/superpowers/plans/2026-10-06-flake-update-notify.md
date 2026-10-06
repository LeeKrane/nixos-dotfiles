# Flake Update Notifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A daily Home Manager timer that raises one desktop notification per new update pull request from the weekly `update` workflow.

**Architecture:** `scripts/flake-update-notify.sh` queries the public GitHub REST API with `curl`, dedupes on the pull request's head SHA in `$XDG_STATE_HOME`, and calls `notify-send` with a click action that opens the pull request. `pkgs/flake-update-notify` wraps the script with `writeShellApplication` (the `proton-drive-mount` pattern). `modules/home/flake-update-notify.nix` adds the oneshot service and the timer for every host.

**Tech Stack:** bash, curl, jq, awk, libnotify, xdg-utils, Nix `writeShellApplication`, Home Manager `systemd.user`.

**Spec:** `docs/superpowers/specs/2026-10-06-flake-update-notify-design.md`

## Global Constraints

- Repo: `LeeKrane/nixos-dotfiles`, head branch `ci/flake-update`. Unauthenticated API, no `gh`.
- State file: `${XDG_STATE_HOME:-$HOME/.local/state}/flake-update-notify/last-sha`.
- Summary text: `Flake update ready`, or `Flake update ready (gate failing)` with `--urgency=critical` when the title starts with `[gate failing]`.
- Body: one `<package> <before> → <after>` line per row of the `### Package versions` table. If there is no such table, use `<N> inputs updated`, counted from the `### Inputs` table. If that table is missing too, use the pull request title.
- `notify-send -a Dotfiles --action=open="Open PR" --wait`; `open` runs `xdg-open "$html_url"`.
- Timer: `OnCalendar=daily`, `OnStartupSec=5min`, `Persistent=true`, `RandomizedDelaySec=15min`, `WantedBy=timers.target`.
- Commit messages: one plain-English subject line, no body, no attribution, no `feat:` prefix (match `git log`).
- Use `command cat`, never bare `cat` (aliased to `bat`).

## Review Focus

1. Body with CRLF line endings (GitHub stores PR bodies typed in the web UI as `\r\n`). Expect: table parsing still works. Test: `crlf body` in Task 1.
2. `notify-send` fails (no session bus, notification daemon down). Expect: exit non-zero and remove the state file, so the next run retries instead of silently swallowing the update. Test: `notify-send failure` in Task 1.
3. API unreachable or returns an HTTP error. Expect: exit non-zero, no notification, state file untouched. Test: `curl failure` in Task 1.
4. Version cells wrapped in backticks or padded with spaces. Expect: clean `linux 7.2.3 → 7.2.5`. Test: `versions body` fixture uses padded and backticked cells.
5. Pull request closed, then reopened later with the same head SHA. Expect: notifies again. Test: `no pr clears state` in Task 1.

---

### Task 1: Notifier script with test harness

**Files:**
- Create: `scripts/flake-update-notify.sh`
- Create: `scripts/tests/flake-update-notify-test.sh`

**Interfaces:**
- Consumes: the PR body format from `scripts/update-summary.sh` (`### Package versions` table `| Package | Before | After |`, `### Inputs` table `| Input | From | To | Changes |`). If `scripts/update-summary.sh` exists by the time you run this, run it once and check the headings match. Adjust the fixtures, not the script, if only the cell contents differ.
- Produces: an executable script. Env `REPO` (required, `owner/name`) and `BRANCH` (required). `PULLS_URL` (optional) overrides the full API URL so tests can pass a `file://` fixture. Exit 0 on success or nothing to do, non-zero on curl or notify failure.

- [ ] **Step 1: Write the failing test harness**

Create `scripts/tests/flake-update-notify-test.sh`:

```bash
#!/usr/bin/env bash
# Tests scripts/flake-update-notify.sh against file:// fixtures, with
# notify-send and xdg-open stubbed on PATH. Run:
#   nix shell nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/flake-update-notify-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../flake-update-notify.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
# notify-send stub: records its arguments NUL-separated (bodies span lines),
# prints $STUB_ACTION (the clicked action), exits $STUB_EXIT.
cat >"$WORK/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$LOG_DIR/notify"
printf '%s' "${STUB_ACTION:-}"
exit "${STUB_EXIT:-0}"
EOF
cat >"$WORK/bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$LOG_DIR/xdg"
EOF
chmod +x "$WORK/bin/notify-send" "$WORK/bin/xdg-open"

STATE_FILE="$WORK/state/flake-update-notify/last-sha"
failures=0

# pr_json SHA TITLE BODY: one-element pulls array, written to $WORK/pulls.json.
pr_json() {
    jq -n --arg sha "$1" --arg t "$2" --arg b "$3" \
        '[{head: {sha: $sha}, html_url: "https://github.com/a/b/pull/3", title: $t, body: $b}]' \
        >"$WORK/pulls.json"
}

# run [ENV=VAL...]: runs the script with stubs; sets $status.
run() {
    rm -rf "$WORK/log"
    mkdir -p "$WORK/log"
    status=0
    env PATH="$WORK/bin:$PATH" LOG_DIR="$WORK/log" XDG_STATE_HOME="$WORK/state" \
        REPO=a/b BRANCH=ci/flake-update PULLS_URL="file://$WORK/pulls.json" \
        "$@" bash "$SCRIPT" >/dev/null 2>"$WORK/log/stderr" || status=$?
}

check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
notified() { [ -f "$WORK/log/notify" ]; }
notify_has() { # exact match against any single notify-send argument
    local arg
    while IFS= read -r -d '' arg; do [ "$arg" = "$1" ] && return 0; done <"$WORK/log/notify"
    return 1
}
state_is() { [ "$(command cat "$STATE_FILE" 2>/dev/null)" = "$1" ]; }

VERSIONS_BODY=$(printf '%s\n' \
    'Gate: ✅ passed ([run](https://example.invalid))' \
    '' \
    '### Package versions' \
    '| Package | Before | After |' \
    '| --- | --- | --- |' \
    '| linux | 7.2.3 | 7.2.5 |' \
    '|  `claude-code`  | `2.1.280` | `2.1.289` |' \
    '' \
    '### Inputs' \
    '| Input | From | To | Changes |' \
    '| --- | --- | --- | --- |' \
    '| nixpkgs | 2026-09-04 | 2026-10-03 | x |' \
    '' \
    'CI checks eval only.')
INPUTS_BODY=$(printf '%s\n' \
    '### Inputs' \
    '| Input | From | To | Changes |' \
    '| --- | --- | --- | --- |' \
    '| nixpkgs | 2026-09-04 | 2026-10-03 | x |' \
    '| disko | 2026-06-11 | 2026-09-18 | x |')

# versions body: first notification
rm -rf "$WORK/state"
pr_json sha1 'Update flake inputs' "$VERSIONS_BODY"
run
check 'versions body: exit 0' [ "$status" -eq 0 ]
check 'versions body: notified' notified
check 'versions body: summary' notify_has 'Flake update ready'
check 'versions body: normal urgency' notify_has 'normal'
check 'versions body: app name' notify_has 'Dotfiles'
check 'versions body: action' notify_has '--action=open=Open PR'
check 'versions body: lines' notify_has $'linux 7.2.3 → 7.2.5\nclaude-code 2.1.280 → 2.1.289'
check 'versions body: state written' state_is sha1
check 'versions body: no xdg-open' [ ! -f "$WORK/log/xdg" ]

# dedupe: same SHA stays silent
run
check 'dedupe: exit 0' [ "$status" -eq 0 ]
check 'dedupe: not notified' eval '! notified'

# new SHA notifies again
pr_json sha2 'Update flake inputs' "$VERSIONS_BODY"
run
check 'new sha: notified' notified
check 'new sha: state updated' state_is sha2

# no pr clears state
printf '[]' >"$WORK/pulls.json"
run
check 'no pr clears state: exit 0' [ "$status" -eq 0 ]
check 'no pr clears state: not notified' eval '! notified'
check 'no pr clears state: state removed' [ ! -e "$STATE_FILE" ]

# gate failing title
pr_json sha3 '[gate failing] Update flake inputs' "$VERSIONS_BODY"
run
check 'gate failing: summary' notify_has 'Flake update ready (gate failing)'
check 'gate failing: critical' notify_has 'critical'

# inputs-only body
pr_json sha4 'Update flake inputs' "$INPUTS_BODY"
run
check 'inputs only: count' notify_has '2 inputs updated'

# neither table: title fallback
pr_json sha5 'Update flake inputs' 'free text'
run
check 'no tables: title' notify_has 'Update flake inputs'

# crlf body
pr_json sha6 'Update flake inputs' "$(printf '%s' "$VERSIONS_BODY" | sed 's/$/\r/')"
run
check 'crlf body: lines' notify_has $'linux 7.2.3 → 7.2.5\nclaude-code 2.1.280 → 2.1.289'

# click opens the PR
pr_json sha7 'Update flake inputs' "$VERSIONS_BODY"
run STUB_ACTION=open
check 'click: xdg-open url' grep -qxF 'https://github.com/a/b/pull/3' "$WORK/log/xdg"

# curl failure: non-zero, no notification, state untouched
pr_json sha8 'Update flake inputs' "$VERSIONS_BODY"
run PULLS_URL="file://$WORK/missing.json"
check 'curl failure: non-zero' [ "$status" -ne 0 ]
check 'curl failure: not notified' eval '! notified'
check 'curl failure: state untouched' state_is sha7

# notify-send failure: non-zero, state removed so the next run retries
run STUB_EXIT=1
check 'notify-send failure: non-zero' [ "$status" -ne 0 ]
check 'notify-send failure: state removed' [ ! -e "$STATE_FILE" ]

# missing env
run REPO=
check 'missing REPO: non-zero' [ "$status" -ne 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
```

- [ ] **Step 2: Run the harness to verify it fails**

Run: `nix shell nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/flake-update-notify-test.sh`
Expected: every case reports `FAIL`, because `scripts/flake-update-notify.sh` does not exist yet (bash exits 127). Summary line `N failed`, exit 1.

- [ ] **Step 3: Write the script**

Create `scripts/flake-update-notify.sh`:

```bash
#!/usr/bin/env bash
# Raises a desktop notification when the weekly update workflow has an
# update pull request open, once per pushed head commit. Run by the
# flake-update-notify user timer (modules/home/flake-update-notify.nix).
#   REPO       owner/name                        required
#   BRANCH     head branch of the pull request   required
#   PULLS_URL  overrides the API URL, for tests  optional
set -euo pipefail

: "${REPO:?REPO must be owner/name}"
: "${BRANCH:?BRANCH must be set}"

url="${PULLS_URL:-https://api.github.com/repos/$REPO/pulls?head=${REPO%%/*}:$BRANCH&state=open}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/flake-update-notify"
state_file="$state_dir/last-sha"

# Prints the data rows of the Markdown table under the heading $1, without
# its header and separator rows.
table_rows() {
    awk -v heading="$1" '
        $0 == heading { in_section = 1; next }
        in_section && /^#/ { exit }
        in_section && /^\|/ { if (++rows > 2) print; next }
        in_section && rows { exit }
    '
}

# An error here exits non-zero through set -e: no notification, state
# untouched, the next timer run retries.
pulls=$(curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "$url")

if [ "$(jq 'length' <<<"$pulls")" -eq 0 ]; then
    # Forget the last head, so a reopened pull request notifies again.
    rm -f "$state_file"
    exit 0
fi

sha=$(jq -r '.[0].head.sha' <<<"$pulls")
if [ -f "$state_file" ] && [ "$(<"$state_file")" = "$sha" ]; then
    exit 0
fi

html_url=$(jq -r '.[0].html_url' <<<"$pulls")
title=$(jq -r '.[0].title' <<<"$pulls")
body=$(jq -r '.[0].body // ""' <<<"$pulls" | tr -d '\r')

summary='Flake update ready'
urgency=normal
case "$title" in
    '[gate failing]'*)
        summary='Flake update ready (gate failing)'
        urgency=critical
        ;;
esac

text=$(table_rows '### Package versions' <<<"$body" | awk -F'|' '{
    for (i = 2; i <= 4; i++) gsub(/^[ \t`]+|[ \t`]+$/, "", $i)
    print $2 " " $3 " → " $4
}')
if [ -z "$text" ]; then
    inputs=$(table_rows '### Inputs' <<<"$body" | wc -l)
    if [ "$inputs" -gt 0 ]; then text="$inputs inputs updated"; else text=$title; fi
fi

# Written before notifying, so a dismissed or ignored notification does not
# repeat. Removed again if notify-send fails, so that run is retried.
mkdir -p "$state_dir"
printf '%s\n' "$sha" >"$state_file"

if ! action=$(notify-send -a Dotfiles -u "$urgency" --action=open='Open PR' --wait "$summary" "$text"); then
    rm -f "$state_file"
    exit 1
fi
if [ "$action" = open ]; then
    xdg-open "$html_url"
fi
```

- [ ] **Step 4: Run the harness to verify it passes**

Run: `nix shell nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/flake-update-notify-test.sh`
Expected: every line `ok`, final line `all passed`, exit 0.

- [ ] **Step 5: Shellcheck both files**

Run: `nix run nixpkgs#shellcheck -- -S style scripts/flake-update-notify.sh scripts/tests/flake-update-notify-test.sh`
Expected: no output, exit 0. If the test file trips SC2016 on the single-quoted heredoc stubs, add a `# shellcheck disable=SC2016` comment that says why, matching the style in `scripts/docker-check.sh`.

- [ ] **Step 6: Commit**

```bash
git add scripts/flake-update-notify.sh scripts/tests/flake-update-notify-test.sh
git commit -m "Add a script that notifies about a pending flake update pull request"
```

### Task 2: Package, Home Manager module and timer

**Files:**
- Create: `pkgs/flake-update-notify/default.nix`
- Modify: `pkgs/default.nix` (add one `callPackage` line, alphabetical)
- Create: `modules/home/flake-update-notify.nix`
- Modify: `modules/home/default.nix` (add `./flake-update-notify.nix` to `imports`, after `./teamclaude.nix`)

**Interfaces:**
- Consumes: `scripts/flake-update-notify.sh` from Task 1 (env `REPO`, `BRANCH`).
- Produces: `pkgs.flake-update-notify` with `bin/flake-update-notify`; user units `flake-update-notify.service` and `flake-update-notify.timer`.

- [ ] **Step 1: Write the eval check that fails**

Run: `nix eval --raw .#nixosConfigurations.tarmantria.config.home-manager.users.krane.systemd.user.timers.flake-update-notify.Timer.OnCalendar`
Expected: error, attribute `flake-update-notify` missing.

- [ ] **Step 2: Add the package**

Create `pkgs/flake-update-notify/default.nix`:

```nix
# Wraps scripts/flake-update-notify.sh as a package, so it can be built and
# shellchecked on its own.
{
  lib,
  writeShellApplication,
  curl,
  jq,
  gawk,
  libnotify,
  xdg-utils,
  coreutils,
}:
writeShellApplication {
  name = "flake-update-notify";
  runtimeInputs = [
    curl
    jq
    gawk
    libnotify
    xdg-utils
    coreutils
  ];

  # Strips the original `#!/usr/bin/env bash` line. writeShellApplication adds
  # its own ahead of `text`.
  text = lib.concatStringsSep "\n" (
    lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/flake-update-notify.sh))
  );

  meta.mainProgram = "flake-update-notify";
}
```

In `pkgs/default.nix`, add after the `claude-code` entry:

```nix
  flake-update-notify = pkgs.callPackage ./flake-update-notify { };
```

- [ ] **Step 3: Build the package**

Run: `nix build .#flake-update-notify && ls result/bin`
Expected: build succeeds (shellcheck passes inside the build), prints `flake-update-notify`.

- [ ] **Step 4: Add the module**

Create `modules/home/flake-update-notify.nix`:

```nix
# Desktop notification when the weekly update workflow (.github/workflows/update.yml) has an
# update pull request open, once per pushed head commit. The repo is public, so the script
# needs no GitHub login. See docs/superpowers/specs/2026-10-06-flake-update-notify-design.md.
{ pkgs, ... }:
let
  repo = "LeeKrane/nixos-dotfiles";
in
{
  systemd.user.services.flake-update-notify = {
    Unit = {
      Description = "Notify about a pending flake update pull request";
      # notify-send and xdg-open need the session. Requisite fails the start outside one,
      # instead of pulling a session up; the timer's Persistent=true catches up later.
      Requisite = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      Environment = [
        "REPO=${repo}"
        "BRANCH=ci/flake-update"
      ];
      ExecStart = "${pkgs.flake-update-notify}/bin/flake-update-notify";
    };
  };

  systemd.user.timers.flake-update-notify = {
    Unit.Description = "Daily check for a pending flake update pull request";
    Timer = {
      OnCalendar = "daily";
      OnStartupSec = "5min";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
```

In `modules/home/default.nix`, add `./flake-update-notify.nix` to `imports` after `./teamclaude.nix`.

- [ ] **Step 5: Run the eval check, then eval every host**

Run: `nix eval --raw .#nixosConfigurations.tarmantria.config.home-manager.users.krane.systemd.user.timers.flake-update-notify.Timer.OnCalendar`
Expected: `daily`

Run: `for h in taractias tariognatha tarmantria; do nix eval --raw .#nixosConfigurations.$h.config.system.build.toplevel.drvPath && echo " $h ok"; done`
Expected: three `.drv` paths, each followed by `<host> ok`.

- [ ] **Step 6: Format and lint**

Run: `nix fmt -- pkgs/flake-update-notify/default.nix pkgs/default.nix modules/home/flake-update-notify.nix modules/home/default.nix && nix run nixpkgs#statix -- check . && nix run nixpkgs#deadnix -- pkgs/flake-update-notify modules/home/flake-update-notify.nix`
Expected: no diff left by `nix fmt` beyond what you then stage, no statix or deadnix findings in the new files.

- [ ] **Step 7: Live run against the real pull request**

Run: `XDG_STATE_HOME=$(mktemp -d) REPO=LeeKrane/nixos-dotfiles BRANCH=ci/flake-update ./result/bin/flake-update-notify; echo "exit $?"`
Expected: a desktop notification titled `Flake update ready`, with package version lines or an `N inputs updated` fallback if PR #3 still has the old body. Clicking `Open PR` opens PR #3 in the browser. The command prints `exit 0` once the notification is clicked or dismissed. Report what the notification showed.

- [ ] **Step 8: Commit**

```bash
git add pkgs/flake-update-notify/default.nix pkgs/default.nix modules/home/flake-update-notify.nix modules/home/default.nix
git commit -m "Add a daily user timer that notifies about the flake update pull request"
```

Activation (`just switch <host>`) is the user's call. Do not run it.
