# Automatic Server Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every server (taragarmr, taronychus, tarritator, tarronax) upgrades itself to each gated `main` commit with a health check, automatic rollback and a failure notification (ntfy plus at most one GitHub issue per upgrade cycle), and the weekly update PR reports on the Pis too.

**Architecture:** `check.yml` moves a `deploy` branch to every `main` commit that passed its gate. Upstream `system.autoUpgrade` (hourly, `allowReboot` with a per-host window) tracks `deploy`; two script hooks around it (`scripts/server-upgrade-hooks.sh`) skip no-op runs, health check, roll back and queue messages in an outbox; `scripts/server-upgrade-report.sh` files the GitHub issues. ntfy on taragarmr (WireGuard address only) carries the pushes.

**Tech Stack:** NixOS 26.05 modules, systemd, bash + curl + jq, ntfy-sh 2.26, GitHub Actions, sops-nix.

**Spec:** `docs/superpowers/specs/2026-11-23-server-auto-upgrade-design.md` (read it first; this plan departs from it only where "Spec deviations" says so).

## Spec deviations

Findings from the pinned nixpkgs-stable source (`/nix/store/7sa2x9c9566lfxkaxs36n3z4yayl5cy4-source`, `nixos/modules/tasks/auto-upgrade.nix`, `nixos/modules/services/misc/ntfy-sh.nix`, ntfy 2.26.0) that differ from the spec:

1. **`--refresh` is already added.** With `system.autoUpgrade.flake` set, upstream adds `--refresh --flake <flake>` itself. The spec's `flags = [ "--refresh" ]` would duplicate it, so it is dropped.
2. **The reboot is not "before ExecStartPost".** With `allowReboot`, upstream runs `nixos-rebuild boot`, then: same kernel/initrd/modules as the booted system means `nixos-rebuild switch`; outside the window it prints "Outside of configured reboot window, skipping." and exits 0 with the new generation only in the boot profile (not active); inside the window it runs `shutdown -r +1` (a minute later, so `ExecStartPost` does run first). Either way the new system is not active when `ExecStartPost` runs. So `post` health-checks only when `/run/current-system` equals the system profile, and otherwise writes `pending-check` (here, not in `ExecStartPre` as the spec says) and leaves the check to the boot-time unit.
3. **Rollback is explicit, not `nixos-rebuild switch --rollback`.** `--rollback` goes to the previous profile generation, which can be a generation that was built but never booted (kernel change waiting for the window). The hooks put the previously *running* system (`pre-switch`) back with `nix-env -p /nix/var/nix/profiles/system --set` and run its own `switch-to-configuration`. A rollback is needed when either the running system or the profile changed during the run (extra state file `pre-profile`).
4. **ntfy users, ACLs and tokens are declarative.** ntfy 2.26 reads `NTFY_AUTH_USERS`, `NTFY_AUTH_ACCESS` and `NTFY_AUTH_TOKENS` (also `auth-users`/`auth-access`/`auth-tokens` in settings); tokens are generated offline with `ntfy token generate` (format `tk_` plus 29 characters). So nothing is created with the `ntfy user`/`ntfy token` CLI on taragarmr, and the rollout order changes: all secrets are created first, then the code merges, then the hosts switch. The environment (with bcrypt hashes) goes into the sops secret `ntfy/server-env` on taragarmr.
5. **Secret layout.** `hasSection` gates per top-level section, so the ntfy secrets get their own `ntfy` section: `ntfy/publish-token` (four server files), `ntfy/server-env` (taragarmr), `ntfy/read-token` (three desktop files). The GitHub token stays `server-upgrade/github-token` (already in the four server files, commit 6ce88d4). The phone's ntfy app logs in with user `krane` and its password (the app's login form takes a password, not a token).
6. **Health check.** "No failed units" would fail every upgrade on a host that already has a failed unit (a failing restic job, say). The built-in check is "no unit failed since the run started" (baseline `failed-before` written by `pre`). The hub ping for WireGuard spokes is added automatically by the module; `krane.autoUpgrade.healthChecks` holds host-specific extras (taragarmr: a `curl` of its Caddy vhost).
7. **Recovery rule.** A recovery message is queued only when a host is healthy on a SHA other than `failed-sha`. After a boot-health rollback the pending SHA still equals `failed-sha`, so a successful rolled-back boot is silent instead of claiming "recovered".
8. **Boot-time unit is `Type=simple`.** `After=multi-user.target` plus `WantedBy=multi-user.target` is an ordering cycle, and `systemctl is-system-running --wait` inside a oneshot would wait for its own start job. `Type=simple` ends the start job at fork.
9. **Minor.** The failure message's log tail is `journalctl -u nixos-upgrade -u server-upgrade-health -n 30` (no `-b`: after a rollback reboot the upgrade's log is in the previous boot). The report test "recovery with no open issue makes no GitHub request" asserts no write request (it still lists issues with GETs). The server rows Hyprland, Quickshell and zen-browser in `update-versions.nix` are not null on servers (they read option defaults and flake inputs) but are identical across hosts, so they add no rows.

**Spike result (settled before this plan, 2026-11-23, tarmantria x86_64):** `nix build --dry-run "<tarronax aarch64 toplevel .drv>^*"` works on x86_64 (exit 0, "these 63 derivations will be built"; 70 without the nixos-raspberrypi substituter). The CI plan is therefore x86-only: no `ubuntu-24.04-arm` leg.

## Global Constraints

- Repo `LeeKrane/nixos-dotfiles`; flake URI `github:LeeKrane/nixos-dotfiles/deploy#<host>`; branch `deploy`; GitHub label and issue title `Server upgrade failed: <sha7>`, label `server-upgrade`.
- Reboot windows: tarronax 02:00-03:00, tarritator 03:00-04:00, taronychus 04:00-05:00, taragarmr 05:00-06:00. The option `krane.autoUpgrade.rebootWindow` has no default.
- `system.autoUpgrade`: `dates = "hourly"`, `randomizedDelaySec = "10min"`, `fixedRandomDelay = true`, `persistent = true`, `allowReboot = true`.
- State in `/var/lib/server-upgrade/` (`StateDirectory = "server-upgrade"`). ntfy topic `server-upgrades`, listening only on `192.168.82.1:2586` (taragarmr's wg0 address), `auth-default-access = "deny-all"`. ntfy users `upgrade-publisher` (write-only on the topic) and `krane` (read-only).
- Secrets: `server-upgrade/github-token`, `ntfy/publish-token`, `ntfy/read-token`, `ntfy/server-env`, each declared only when its top-level section exists in the host's secrets file (`lib/host-secrets.nix`).
- `check.yml`'s `promote` job runs only on `push` to `refs/heads/main`, needs every gate job, pushes `"$GITHUB_SHA":refs/heads/deploy` without `--force`, and is the only job with `contents: write`.
- CI: the nixos-raspberrypi substituter `https://nixos-raspberrypi.cachix.org` with key `nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=` (from `modules/nixos/common/nix-settings.nix`) in the security job.
- Repo conventions: commit on `main` directly, one subject line, no body, no Claude/Anthropic attribution, never push, never open a PR. If a background session's guard blocks edits in the shared checkout, use a worktree and fast-forward `main` at the end. Create and edit files only with the Write/Edit tools, not shell redirects or `sed -i`. Use `command cat`, never bare `cat`. Do not decrypt or edit any sops file (those are manual steps for the owner).
- Every implementation prompt: **follow ponytail** (smallest change that fully solves the task, reuse first). Format Nix with `nix fmt -- <the files you touched>` only; do not commit unrelated formatting changes (for example `pkgs/ani-cli-launcher/package.nix` is currently unformatted).

## Review Focus

Failure modes the spec implies that no single happy-path test would catch, most likely first. Each is pinned by a test in the named task.

1. A unit that was already failing before the upgrade (a failing restic job) must not fail every upgrade or roll it back; only units that failed since the run started count. Task 3: `post: a unit that was already failing does not fail the upgrade`.
2. A kernel-changing upgrade outside the reboot window: the new generation is only in the boot profile, so `post` must neither fail nor roll back, and must leave `pending-check` for the boot-time unit. Task 3: `post: new kernel not active yet defers the check`.
3. A broken SHA must not be retried hourly, a missing or unreachable `deploy` branch must be a silent skip, and an already-deployed SHA must not re-evaluate. Task 3: the `condition:` tests.
4. A new generation that does not come up healthy reboots into the previous one exactly once, and a rolled-back boot that is healthy sends no "recovered" message. Task 3: the `boot-health:` tests.
5. Several hosts failing on the same SHA in the same minute produce one issue; ntfy or GitHub being down keeps the message queued instead of losing it. Task 2: `race: ...`; Task 3: the `deliver:` tests.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/server-upgrade-report.sh` | create | GitHub issue handling (`failed`/`recovered`), curl + jq |
| `scripts/tests/server-upgrade-report-test.sh` | create | fake-GitHub tests for the above |
| `scripts/server-upgrade-hooks.sh` | create | systemd hooks: `condition`, `pre`, `post`, `failed`, `boot-health`, `deliver` |
| `scripts/tests/server-upgrade-hooks-test.sh` | create | stubbed tests for the hooks |
| `pkgs/server-upgrade/default.nix` | create | packages both scripts (`writeShellApplication`, shellchecked at build) |
| `pkgs/default.nix` | modify | expose `server-upgrade` |
| `lib/ntfy.nix` | create | shared ntfy address, port and topic |
| `modules/nixos/server/auto-upgrade.nix` | create | `krane.autoUpgrade.*` options, `system.autoUpgrade`, the four units, sops secrets |
| `modules/nixos/server/default.nix` | modify | import it |
| `lib/mk-host.nix` | modify | `system.configurationRevision` |
| `tests/server-host/default.nix` | modify | fixture reboot window |
| `hosts/{tarronax,tarritator,taronychus,taragarmr}/default.nix` | modify | reboot windows |
| `hosts/taragarmr/caddy.nix` | modify | Caddy health check |
| `hosts/taragarmr/ntfy.nix` | create | ntfy server (+ `default.nix` import) |
| `modules/nixos/desktop/server-upgrade-notify.nix` | create | `ntfy/read-token` secret (+ `default.nix` import) |
| `modules/home/desktop/server-upgrade-notify.nix` | create | `ntfy subscribe` user service (+ `default.nix` import) |
| `flake.nix` | modify | shared `upgradeExpectationsFor`, extra `server-eval`/`pi-eval` expectations |
| `scripts/update-versions.nix` | modify | host list as argument |
| `.github/workflows/update.yml` | modify | all hosts, substituter for the security job |
| `.github/workflows/check.yml` | modify | `promote` job, server-upgrade tests |
| `scripts/hosts.nix` | modify | header comment only |
| `secrets/README.md` | modify | the new secrets and how to create them |

---

### Task 1: Spike - aarch64 dry-run on x86 (no commit)

Settled before this plan was written; this task re-confirms it so a later nixpkgs bump does not silently change the CI design.

**Files:** none.

**Interfaces:**
- Consumes: nothing.
- Produces: the decision "x86-only security job, no ubuntu-24.04-arm leg" used by Task 7.

- [ ] **Step 1: Evaluate a Pi toplevel on the x86 machine**

Run: `nix eval --raw .#nixosConfigurations.tarronax.config.system.build.toplevel.drvPath`
Expected: a `/nix/store/...-nixos-system-tarronax-sd-card-26.05...drv` path (about 40 s).

- [ ] **Step 2: Dry-run it with only the substituters CI will have**

Run (put the path from step 1 into `D`):

```bash
D=/nix/store/...-nixos-system-tarronax-sd-card-26.05...drv
nix build --dry-run --no-link "${D}^*" \
  --option substituters "https://cache.nixos.org/ https://nixos-raspberrypi.cachix.org" \
  --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" \
  > /tmp/spike.log 2>&1; echo rc=$?
awk '/will be built:/{c=1;next}/will be fetched/{c=0} c&&/^  \//{print}' /tmp/spike.log | wc -l
```

Expected: `rc=0` and a count around 63 (a few dozen small local derivations such as `etc-zshrc`, plus the `modules` derivation of the rpi kernel). Repeating without the nixos-raspberrypi substituter gives a larger count (70 on 2026-11-23), which is why Task 7 adds it.

- [ ] **Step 3: Decide**

If `rc=0`: continue with the plan as written. If it fails with "required system or feature not available" or similar: stop and change Task 7 to a second matrix leg on `runs-on: ubuntu-24.04-arm` for the Pi hosts (the `update` job's `hosts` output then needs the split by `hostMeta.<n>.system`). No commit for this task.

---

### Task 2: GitHub issue reporter

**Files:**
- Create: `scripts/server-upgrade-report.sh`
- Create: `scripts/tests/server-upgrade-report-test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `server-upgrade-report.sh failed|recovered HOST SHA [STAGE] [ROLLED_BACK]`, env `GITHUB_TOKEN_FILE` (required), `REPO` (default `LeeKrane/nixos-dotfiles`), `API_URL` (default `https://api.github.com`). Exit non-zero on any API failure. Task 3's `deliver` calls it; Task 4 packages it as `server-upgrade-report`.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/server-upgrade-report-test.sh`:

```bash
#!/usr/bin/env bash
# Tests scripts/server-upgrade-report.sh against a fake GitHub API: `curl` on PATH serves JSON
# fixtures and records every request. Run:
#   nix shell nixpkgs#jq nixpkgs#curl --command bash scripts/tests/server-upgrade-report-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../server-upgrade-report.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/fix" "$WORK/log"
printf 'test-token' >"$WORK/token"

# curl stub: logs "METHOD PATH BODY" per request and answers from $FIX/<METHOD>_<PATH>[.N].json,
# the Nth call to that endpoint first, else the endpoint's catch-all, else {}.
command cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
method=GET url="" data=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -X) method="$2"; shift 2 ;;
        -d) data="$2"; shift 2 ;;
        -H | --max-time) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
path="${url#https://api.test}"
printf '%s %s %s\n' "$method" "$path" "$data" >>"$LOG_DIR/requests"
key="$(printf '%s_%s' "$method" "$path" | tr -c 'A-Za-z0-9' _)"
n=$(($(command cat "$FIX/$key.count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FIX/$key.count"
file="$FIX/$key.$n.json"
[ -f "$file" ] || file="$FIX/$key.json"
if [ -f "$file" ]; then command cat "$file"; else echo '{}'; fi
EOF
chmod +x "$WORK/bin/curl"

failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# fx METHOD PATH JSON [N]: canned response for the Nth call to the endpoint, or for all calls.
fx() {
    local key
    key="$(printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9' _)"
    printf '%s' "$3" >"$WORK/fix/$key${4:+.$4}.json"
}
LIST="/repos/a/b/issues?labels=server-upgrade&state=open&per_page=100"
SHA=aaaaaaa1111111111111111111111111111111aa
T="Server upgrade failed: aaaaaaa"
OLD_T="Server upgrade failed: 1111111"
issue() { jq -nc --argjson n "$1" --arg t "$2" '{number: $n, title: $t}'; }
# marker HOST STATUS: a comment carrying the hidden marker, as the script writes it.
marker() { jq -nc --arg b "<!-- server-upgrade host=$1 sha=$SHA status=$2 -->" '{body: $b}'; }

reset() {
    rm -rf "$WORK/fix" "$WORK/log"
    mkdir -p "$WORK/fix" "$WORK/log"
}
run() { # run KIND HOST [STAGE ROLLED]
    status=0
    env PATH="$WORK/bin:$PATH" FIX="$WORK/fix" LOG_DIR="$WORK/log" \
        GITHUB_TOKEN_FILE="$WORK/token" REPO=a/b API_URL=https://api.test \
        bash "$SCRIPT" "$1" "$2" "$SHA" "${3:-}" "${4:-}" >/dev/null 2>"$WORK/log/stderr" || status=$?
}
requested() { grep -qF -- "$1" "$WORK/log/requests"; }
wrote() { grep -qE '^(POST|PATCH) ' "$WORK/log/requests"; }

# failure, no open issue: creates it (labeled), comments with this host's report
reset
fx GET "$LIST" '[]' 1
fx GET "$LIST" "[$(issue 12 "$T")]" 2
fx POST /repos/a/b/issues '{"number":12}'
run failed tarronax build no
check 'new failure: exit 0' [ "$status" -eq 0 ]
check 'new failure: issue created with title' requested "POST /repos/a/b/issues {\"title\":\"$T\""
check 'new failure: labeled' requested '"labels":["server-upgrade"]'
check 'new failure: comment on the new issue' requested 'POST /repos/a/b/issues/12/comments'
check 'new failure: marker in comment' requested "status=failed"
check 'new failure: no close' eval '! requested PATCH'

# failure, an open issue for the same SHA: only a comment
reset
fx GET "$LIST" "[$(issue 5 "$T")]"
run failed taronychus activation yes
check 'same sha: exit 0' [ "$status" -eq 0 ]
check 'same sha: comment on the open issue' requested 'POST /repos/a/b/issues/5/comments'
check 'same sha: no new issue' eval '! requested "POST /repos/a/b/issues {"'
check 'same sha: no close' eval '! requested PATCH'

# race: another host created issue 11 in the same minute; the newer duplicate (12) closes itself
reset
fx GET "$LIST" '[]' 1
fx GET "$LIST" "[$(issue 11 "$T"),$(issue 12 "$T")]" 2
fx POST /repos/a/b/issues '{"number":12}'
run failed tarritator health no
check 'race: report handed to the older issue' requested 'POST /repos/a/b/issues/11/comments'
check 'race: duplicate closed' requested 'PATCH /repos/a/b/issues/12'
check 'race: older issue stays open' eval '! requested "PATCH /repos/a/b/issues/11"'

# failure on a newer SHA closes the issue of an older cycle as superseded
reset
fx GET "$LIST" "[$(issue 3 "$OLD_T")]" 1
fx GET "$LIST" "[$(issue 3 "$OLD_T"),$(issue 4 "$T")]" 2
fx POST /repos/a/b/issues '{"number":4}'
run failed tarronax build no
check 'superseded: old issue closed' requested 'PATCH /repos/a/b/issues/3'
check 'superseded: comment names the new issue' requested 'Superseded by #4.'
check 'superseded: new issue stays open' eval '! requested "PATCH /repos/a/b/issues/4"'

# recovery with no open issue: nothing is written
reset
fx GET "$LIST" '[]'
run recovered tarronax
check 'recovery, no issue: exit 0' [ "$status" -eq 0 ]
check 'recovery, no issue: no write' eval '! wrote'

# recovery, open issue without a failed marker for this host: nothing is written
reset
fx GET "$LIST" "[$(issue 7 "$T")]"
fx GET "/repos/a/b/issues/7/comments?per_page=100" "[$(marker tarritator failed)]"
run recovered tarronax
check 'recovery, other host only: no write' eval '! wrote'

# recovery while another host still fails: comment, issue stays open
reset
fx GET "$LIST" "[$(issue 7 "$T")]"
fx GET "/repos/a/b/issues/7/comments?per_page=100" "[$(marker tarronax failed),$(marker tarritator failed)]"
run recovered tarronax
check 'recovery, another host failing: comment' requested 'POST /repos/a/b/issues/7/comments'
check 'recovery, another host failing: recovered marker' requested 'status=recovered'
check 'recovery, another host failing: stays open' eval '! requested PATCH'

# the last recovery closes it; an earlier failed marker of the same host does not count
reset
fx GET "$LIST" "[$(issue 7 "$T")]"
fx GET "/repos/a/b/issues/7/comments?per_page=100" "[$(marker tarritator failed),$(marker tarritator recovered),$(marker tarronax failed)]"
run recovered tarronax
check 'last recovery: comment' requested 'POST /repos/a/b/issues/7/comments'
check 'last recovery: closed' requested 'PATCH /repos/a/b/issues/7'

# the API fails: non-zero exit, so the message stays in the outbox
reset
mkdir -p "$WORK/failbin"
printf '#!/usr/bin/env bash\nexit 22\n' >"$WORK/failbin/curl"
chmod +x "$WORK/failbin/curl"
status=0
env PATH="$WORK/failbin:$PATH" GITHUB_TOKEN_FILE="$WORK/token" REPO=a/b API_URL=https://api.test \
    bash "$SCRIPT" failed tarronax "$SHA" build no >/dev/null 2>&1 || status=$?
check 'API failure: non-zero exit' [ "$status" -ne 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `nix shell nixpkgs#jq nixpkgs#curl -c bash scripts/tests/server-upgrade-report-test.sh`
Expected: FAIL lines (the script does not exist yet, so `bash` reports "No such file" and every `exit 0` check fails).

- [ ] **Step 3: Write the script**

Create `scripts/server-upgrade-report.sh`:

```bash
#!/usr/bin/env bash
# GitHub side of the automatic server upgrade (modules/nixos/server/auto-upgrade.nix): keeps at
# most one open `server-upgrade` issue per upgrade cycle (target SHA), one comment per host.
# Called by `server-upgrade-hooks deliver` for each queued message. The repo is public, so
# comments carry no logs, only host, stage and whether the host rolled back.
#
# Usage: server-upgrade-report.sh failed|recovered HOST SHA [STAGE] [ROLLED_BACK]
#   GITHUB_TOKEN_FILE  file with a token that has Issues: read and write   required
#   REPO               owner/name, default LeeKrane/nixos-dotfiles
#   API_URL            default https://api.github.com (tests point it elsewhere)
set -euo pipefail

kind="${1:?usage: server-upgrade-report.sh failed|recovered HOST SHA [STAGE] [ROLLED_BACK]}"
host="${2:?HOST missing}"
sha="${3:?SHA missing}"
stage="${4:--}"
rolled="${5:--}"
: "${GITHUB_TOKEN_FILE:?GITHUB_TOKEN_FILE must be set}"
REPO="${REPO:-LeeKrane/nixos-dotfiles}"
API_URL="${API_URL:-https://api.github.com}"
LABEL=server-upgrade

token="$(<"$GITHUB_TOKEN_FILE")"
title="Server upgrade failed: ${sha:0:7}"

# api METHOD PATH [JSON]: a repo-relative GitHub API call; the response goes to stdout. The
# token is passed as a header file so it never shows up in the process list.
api() {
    local method="$1" path="$2"
    shift 2
    local body=()
    if [ "$#" -gt 0 ]; then body=(-d "$1"); fi
    curl -fsS --max-time 30 -X "$method" \
        -H @<(printf 'Authorization: Bearer %s\n' "$token") \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "${body[@]}" "$API_URL/repos/$REPO$path"
}

# Open server-upgrade issues (the issues endpoint also lists pull requests).
open_issues() {
    api GET "/issues?labels=$LABEL&state=open&per_page=100" | jq '[.[] | select(.pull_request == null)]'
}

# Lowest number among the listed issues titled for this SHA, empty if none (stdin: open_issues).
issue_for_sha() {
    jq -r --arg t "$title" '[.[] | select(.title == $t) | .number] | min // empty'
}

# Each host's latest marker in an issue: [{host, sha, status}].
latest_markers() {
    api GET "/issues/$1/comments?per_page=100" | jq '
        [.[].body
          | capture("<!-- server-upgrade host=(?<host>[^ ]+) sha=(?<sha>[^ ]+) status=(?<status>failed|recovered) -->")]
        | group_by(.host) | map(last)'
}

# shellcheck disable=SC2016 # literal backticks for Markdown
report_body() {
    printf '<!-- server-upgrade host=%s sha=%s status=%s -->\n' "$host" "$sha" "$1"
    if [ "$1" = failed ]; then
        printf '**%s** failed to upgrade to `%s` at stage `%s` (rolled back: %s).\n\n' "$host" "${sha:0:7}" "$stage" "$rolled"
        printf 'On the host: `journalctl -u nixos-upgrade -b`.\n'
    else
        printf '**%s** recovered on `%s`.\n' "$host" "${sha:0:7}"
    fi
}

comment() { # ISSUE TEXT
    api POST "/issues/$1/comments" "$(jq -nc --arg b "$2" '{body: $b}')" >/dev/null
}

close_issue() { # ISSUE
    api PATCH "/issues/$1" '{"state":"closed","state_reason":"not_planned"}' >/dev/null
}

on_failed() {
    local issues n created
    issues="$(open_issues)"
    n="$(issue_for_sha <<<"$issues")"
    if [ -n "$n" ]; then
        comment "$n" "$(report_body failed)"
    else
        created="$(api POST /issues "$(jq -nc --arg t "$title" --arg l "$LABEL" \
            --arg b "The automatic upgrade of the servers to \`$sha\` failed. Each host reports in a comment below." \
            '{title: $t, body: $b, labels: [$l]}')" | jq -r .number)"
        comment "$created" "$(report_body failed)"
        # Another host may have created its own issue for this SHA in the same minute: the
        # lowest number wins, a newer duplicate hands its report over and closes itself.
        issues="$(open_issues)"
        n="$(issue_for_sha <<<"$issues")"
        n="${n:-$created}"
        if [ "$n" != "$created" ]; then
            comment "$n" "$(report_body failed)"
            comment "$created" "Duplicate of #$n."
            close_issue "$created"
        fi
    fi
    # Issues of older upgrade cycles are obsolete once a newer SHA fails.
    local old
    while read -r old; do
        comment "$old" "Superseded by #$n."
        close_issue "$old"
    done < <(jq -r --argjson n "$n" --arg t "$title" '.[] | select(.title != $t and .number < $n) | .number' <<<"$issues")
}

on_recovered() {
    local n markers
    while read -r n; do
        markers="$(latest_markers "$n")"
        if jq -e --arg h "$host" 'any(.[]; .host == $h and .status == "failed")' <<<"$markers" >/dev/null; then
            comment "$n" "$(report_body recovered)"
            # Close once no other host still has a failed marker as its latest.
            if jq -e --arg h "$host" 'any(.[]; .host != $h and .status == "failed") | not' <<<"$markers" >/dev/null; then
                close_issue "$n"
            fi
        fi
    done < <(open_issues | jq -r '.[].number')
}

case "$kind" in
    failed) on_failed ;;
    recovered) on_recovered ;;
    *)
        echo "unknown kind: $kind" >&2
        exit 2
        ;;
esac
```

- [ ] **Step 4: Run the test and shellcheck**

Run:

```bash
nix shell nixpkgs#jq nixpkgs#curl nixpkgs#shellcheck -c bash -c \
  'shellcheck -x -S style scripts/server-upgrade-report.sh scripts/tests/server-upgrade-report-test.sh && bash scripts/tests/server-upgrade-report-test.sh'
```

Expected: every line `ok ...`, then `all passed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/server-upgrade-report.sh scripts/tests/server-upgrade-report-test.sh
git commit -m "Add the GitHub issue reporter for server upgrades"
```

---

### Task 3: Upgrade hooks

**Files:**
- Create: `scripts/server-upgrade-hooks.sh`
- Create: `scripts/tests/server-upgrade-hooks-test.sh`

**Interfaces:**
- Consumes: Task 2's `server-upgrade-report` (called as `$REPORT_CMD KIND HOST SHA STAGE ROLLED_BACK`).
- Produces: `server-upgrade-hooks condition|pre|post|failed|boot-health|deliver`. Environment: `HOST_NAME` (required), `HEALTH_CHECK`, `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN_FILE`, `GITHUB_TOKEN_FILE`, `REPORT_CMD`, `STATE_DIR`, `REMOTE_URL`, `CURRENT_SYSTEM`, `BOOTED_SYSTEM`, `SYSTEM_PROFILE`, `BOOT_SETTLE_TIMEOUT` (all but `HOST_NAME` default sensibly). Exit codes: `condition` exits 1 to skip (systemd treats 1 to 254 as "condition not met", not a failure); `deliver` exits 1 while any outbox message is undelivered. State files: see the script header. Task 4 wires each subcommand into a systemd unit.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/server-upgrade-hooks-test.sh`:

```bash
#!/usr/bin/env bash
# Tests scripts/server-upgrade-hooks.sh with git, nix-env, systemctl, journalctl, curl and the
# report command stubbed on PATH, and the system directories replaced by symlinks under a temp
# dir. Run:
#   nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/server-upgrade-hooks-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../server-upgrade-hooks.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STATE="$WORK/state"
LOG="$WORK/log"
mkdir -p "$WORK/bin"

# git stub: `ls-remote` prints "$STUB_SHA<TAB>refs/heads/deploy", or fails with $STUB_GIT_FAIL.
command cat >"$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
[ -z "${STUB_GIT_FAIL:-}" ] || exit 128
[ -z "${STUB_SHA:-}" ] || printf '%s\trefs/heads/deploy\n' "$STUB_SHA"
EOF
# systemctl stub: records every call; --failed lists $STUB_FAILED_UNITS (space separated).
command cat >"$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/systemctl"
if [ "$1" = --failed ]; then
    for u in ${STUB_FAILED_UNITS:-}; do printf '%s loaded failed failed x\n' "$u"; done
fi
exit 0
EOF
command cat >"$WORK/bin/nix-env" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/nix-env"
EOF
command cat >"$WORK/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
echo "journal line"
EOF
# curl stub (ntfy): records the url and body, fails with $STUB_CURL_EXIT.
command cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/curl"
exit "${STUB_CURL_EXIT:-0}"
EOF
command cat >"$WORK/bin/server-upgrade-report" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/report"
exit "${STUB_REPORT_EXIT:-0}"
EOF
command cat >"$WORK/health" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_HEALTH_EXIT:-0}"
EOF
chmod +x "$WORK"/bin/* "$WORK/health"

failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# mksystem NAME REVISION KERNEL: a fake system closure with its nixos-version, kernel link and
# switch-to-configuration (which records its argument).
mksystem() {
    local d="$WORK/store/$1"
    mkdir -p "$d/sw/bin" "$d/bin"
    printf '#!/usr/bin/env bash\necho %s\n' "$2" >"$d/sw/bin/nixos-version"
    # shellcheck disable=SC2016 # $LOG_DIR and $* belong to the generated script
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$LOG_DIR/switch"\n' "$1" >"$d/bin/switch-to-configuration"
    chmod +x "$d/sw/bin/nixos-version" "$d/bin/switch-to-configuration"
    ln -sfn "$WORK/store/kernel-$3" "$d/kernel"
    ln -sfn "$WORK/store/kernel-$3" "$d/initrd"
    ln -sfn "$WORK/store/kernel-$3" "$d/kernel-modules"
}
point() { ln -sfn "$WORK/store/$2" "$WORK/$1"; } # point LINK SYSTEM

# fresh: old system "old" (revision OLDREV, kernel k1) running, booted and in the profile.
fresh() {
    rm -rf "$STATE" "$LOG" "$WORK/store"
    mkdir -p "$STATE" "$LOG" "$WORK/store"
    mksystem old OLDREV k1
    mksystem newsame NEWREV k1
    mksystem newkern NEWREV k2
    point current old
    point booted old
    point profile old
    unset STUB_SHA STUB_GIT_FAIL STUB_FAILED_UNITS STUB_CURL_EXIT STUB_REPORT_EXIT STUB_HEALTH_EXIT || true
}
run() { # run SUBCOMMAND [ENV=VAL...]: sets $status
    local sub=$1
    shift
    status=0
    env PATH="$WORK/bin:$PATH" LOG_DIR="$LOG" HOST_NAME=tarronax STATE_DIR="$STATE" \
        CURRENT_SYSTEM="$WORK/current" BOOTED_SYSTEM="$WORK/booted" SYSTEM_PROFILE="$WORK/profile" \
        HEALTH_CHECK="$WORK/health" BOOT_SETTLE_TIMEOUT=5 REPORT_CMD="$WORK/bin/server-upgrade-report" \
        "$@" bash "$SCRIPT" "$sub" >"$LOG/stdout" 2>"$LOG/stderr" || status=$?
}
logged() { grep -qF -- "$2" "$LOG/$1" 2>/dev/null; } # logged FILE TEXT
state_is() { [ "$(command cat "$STATE/$1" 2>/dev/null)" = "$2" ]; }
outbox_count() { find "$STATE/outbox" -name '*.json' 2>/dev/null | wc -l; }
only_message() { jq -r "$1" "$STATE"/outbox/*.json; }

# --- condition -----------------------------------------------------------------------------
fresh
run condition STUB_SHA=NEWREV
check 'condition: new sha runs' [ "$status" -eq 0 ]
check 'condition: target sha recorded' state_is target-sha NEWREV

fresh
printf 'NEWREV\n' >"$STATE/failed-sha"
run condition STUB_SHA=NEWREV
check 'condition: a failed sha is skipped' [ "$status" -eq 1 ]

fresh
printf 'NEWREV\n' >"$STATE/failed-sha"
run condition STUB_SHA=NEWER
check 'condition: a newer sha than the failed one runs' [ "$status" -eq 0 ]

fresh
run condition STUB_SHA=OLDREV
check 'condition: already deployed, no reboot pending: skipped' [ "$status" -eq 1 ]

fresh
point current newsame
run condition STUB_SHA=NEWREV
check 'condition: deployed with the booted kernel: skipped' [ "$status" -eq 1 ]
point current newkern
point booted old
run condition STUB_SHA=NEWREV
check 'condition: deployed with a reboot pending: runs' [ "$status" -eq 0 ]

fresh
run condition STUB_GIT_FAIL=1
check 'condition: ls-remote failure skips the run' [ "$status" -eq 1 ]
run condition
check 'condition: missing deploy branch skips the run' [ "$status" -eq 1 ]

# --- pre / post ----------------------------------------------------------------------------
fresh
run pre STUB_FAILED_UNITS="old.service"
check 'pre: records the running system' state_is pre-switch "$(readlink -f "$WORK/store/old")"
check 'pre: records the profile' state_is pre-profile "$(readlink -f "$WORK/store/old")"
check 'pre: records already failed units' state_is failed-before old.service

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point current newsame
point profile newsame
run post
check 'post: healthy switch succeeds' [ "$status" -eq 0 ]
check 'post: no pending check' [ ! -e "$STATE/pending-check" ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point profile newkern
run post
check 'post: new kernel not active yet defers the check' [ "$status" -eq 0 ]
check 'post: pending check names the sha' state_is pending-check NEWREV

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre STUB_FAILED_UNITS="old.service"
point current newsame
point profile newsame
run post STUB_FAILED_UNITS="old.service"
check 'post: a unit that was already failing does not fail the upgrade' [ "$status" -eq 0 ]
run post STUB_FAILED_UNITS="old.service new.service"
check 'post: a newly failed unit fails the upgrade' [ "$status" -ne 0 ]
check 'post: failure is staged as health' state_is stage health
run post STUB_HEALTH_EXIT=1
check 'post: the host health check failing fails the upgrade' [ "$status" -ne 0 ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
printf 'BADREV\n' >"$STATE/failed-sha"
run pre
point current newsame
point profile newsame
run post
check 'post: recovery queues one message' [ "$(outbox_count)" -eq 1 ]
check 'post: recovery message kind' [ "$(only_message .kind)" = recovered ]
check 'post: recovery title' [ "$(only_message .title)" = 'tarronax recovered on NEWREV' ]
check 'post: failed sha cleared' [ ! -e "$STATE/failed-sha" ]

# --- failed --------------------------------------------------------------------------------
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
check 'failed: a build failure changes nothing, no rollback' eval '! logged nix-env --set'
check 'failed: stage is build' [ "$(only_message .stage)" = build ]
check 'failed: not rolled back' [ "$(only_message .rolled_back)" = no ]
check 'failed: sha marked failed' state_is failed-sha NEWREV
check 'failed: high priority' [ "$(only_message .priority)" = high ]
check 'failed: title' [ "$(only_message .title)" = 'tarronax upgrade failed (NEWREV)' ]
check 'failed: journal in the body' [ "$(only_message .body | grep -c 'journal line')" -eq 1 ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point current newsame
point profile newsame
run failed
check 'failed: a changed system is rolled back to the previous one' logged nix-env "--set $(readlink -f "$WORK/store/old")"
check 'failed: via its own switch-to-configuration' logged switch 'old switch'
check 'failed: stage is activation' [ "$(only_message .stage)" = activation ]
check 'failed: rolled back' [ "$(only_message .rolled_back)" = yes ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point current newsame
point profile newsame
printf 'health\n' >"$STATE/stage"
run failed
check 'failed: a health failure keeps its stage' [ "$(only_message .stage)" = health ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point profile newkern
printf 'NEWREV\n' >"$STATE/pending-check"
run failed
check 'failed: a moved profile alone is rolled back too' logged nix-env '--set'
check 'failed: a rollback drops the pending check' [ ! -e "$STATE/pending-check" ]

# --- boot-health ---------------------------------------------------------------------------
fresh
run boot-health
check 'boot-health: nothing pending, nothing done' [ "$status" -eq 0 ]
check 'boot-health: no reboot without a pending check' eval '! logged systemctl reboot'

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
run pre
run boot-health
check 'boot-health: healthy clears the pending check' [ ! -e "$STATE/pending-check" ]
check 'boot-health: healthy, no message without an earlier failure' [ "$(outbox_count)" -eq 0 ]

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
printf 'BADREV\n' >"$STATE/failed-sha"
run pre
run boot-health
check 'boot-health: recovery message after an earlier failure' [ "$(only_message .kind)" = recovered ]

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
run pre
run boot-health STUB_HEALTH_EXIT=1
check 'boot-health: unhealthy rolls back for the next boot' logged switch 'old boot'
check 'boot-health: unhealthy reboots' logged systemctl reboot
check 'boot-health: marks the sha failed' state_is failed-sha NEWREV
check 'boot-health: remembers the rollback' [ -e "$STATE/rolled-back" ]
check 'boot-health: stage' [ "$(only_message .stage)" = boot-health ]
check 'boot-health: keeps the pending check for the rolled-back boot' [ -e "$STATE/pending-check" ]
# second boot, rolled-back system still unhealthy: no further reboot
rm -f "$LOG/systemctl" "$STATE/outbox"/*.json
run boot-health STUB_HEALTH_EXIT=1
check 'boot-health: a second failure does not reboot again' eval '! logged systemctl reboot'
check 'boot-health: a second failure says the rollback did not help' [ "$(only_message .rolled_back)" = 'no, the rollback did not help' ]
check 'boot-health: second failure clears its markers' [ ! -e "$STATE/rolled-back" ]

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
printf 'NEWREV\n' >"$STATE/failed-sha"
: >"$STATE/rolled-back"
run pre
run boot-health
check 'boot-health: a healthy rolled-back system queues no recovery' [ "$(outbox_count)" -eq 0 ]
check 'boot-health: and clears the markers' [ ! -e "$STATE/pending-check" ]

# --- deliver -------------------------------------------------------------------------------
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
printf 'token' >"$WORK/ntfy-token"
printf 'token' >"$WORK/github-token"
DELIVER=(NTFY_URL=http://ntfy.test NTFY_TOKEN_FILE="$WORK/ntfy-token" GITHUB_TOKEN_FILE="$WORK/github-token")
run deliver STUB_CURL_EXIT=22 "${DELIVER[@]}"
check 'deliver: ntfy down keeps the message' [ "$(outbox_count)" -eq 1 ]
check 'deliver: ntfy down exits non-zero for the retry' [ "$status" -ne 0 ]
check 'deliver: github still received it' logged report 'failed tarronax NEWREV build no'
rm -f "$LOG/report" "$LOG/curl"
run deliver STUB_CURL_EXIT=22 "${DELIVER[@]}"
check 'deliver: a channel that already took it is not asked again' eval '! logged report tarronax'
rm -f "$LOG/curl"
run deliver "${DELIVER[@]}"
check 'deliver: both channels accepted: exit 0' [ "$status" -eq 0 ]
check 'deliver: both channels accepted: message removed' [ "$(outbox_count)" -eq 0 ]
check 'deliver: ntfy topic' logged curl 'http://ntfy.test/server-upgrades'
check 'deliver: ntfy title' logged curl 'Title: tarronax upgrade failed (NEWREV)'
check 'deliver: ntfy priority' logged curl 'Priority: high'

# GitHub down: the message stays until the report command succeeds
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
run deliver STUB_REPORT_EXIT=1 "${DELIVER[@]}"
check 'deliver: github down keeps the message' [ "$(outbox_count)" -eq 1 ]
run deliver "${DELIVER[@]}"
check 'deliver: github back: message removed' [ "$(outbox_count)" -eq 0 ]

# a host without tokens treats both channels as done
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
run deliver
check 'deliver: unconfigured channels do not hold messages back' [ "$(outbox_count)" -eq 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `nix shell nixpkgs#jq nixpkgs#gawk -c bash scripts/tests/server-upgrade-hooks-test.sh`
Expected: FAIL lines (script missing).

- [ ] **Step 3: Write the script**

Create `scripts/server-upgrade-hooks.sh`:

```bash
#!/usr/bin/env bash
# Hooks of the automatic server upgrade (modules/nixos/server/auto-upgrade.nix), one subcommand
# per systemd hook. State lives in $STATE_DIR (/var/lib/server-upgrade):
#   target-sha     deploy SHA the current run builds (written by `condition`)
#   pre-switch     /run/current-system before the run, what a rollback restores
#   pre-profile    the system profile before the run
#   failed-before  units already failed before the run, so only new failures count
#   stage          "health" once the post-switch health check failed
#   pending-check  SHA of a generation built but not yet activated (waits for the reboot window)
#   failed-sha     last SHA that failed here; `condition` never retries it
#   rolled-back    set before a boot-health rollback reboot, so that reboots at most once
#   outbox/        queued messages, one JSON file each, removed once ntfy and GitHub took them
#
#   condition    nixos-upgrade ExecCondition: exit 0 to upgrade, 1 to skip the run
#   pre          ExecStartPre: record the state a rollback restores
#   post         ExecStartPost: health check the freshly activated system
#   failed       OnFailure: roll back if anything changed, mark the SHA failed, queue a message
#   boot-health  health check a generation that came up after an upgrade reboot
#   deliver      send the queued messages to ntfy and GitHub (exit 1 while any is undelivered)
#
# Environment (tests override the paths; the module sets the rest):
#   HOST_NAME           this host                                          required
#   HEALTH_CHECK        executable that exits 0 when the host is healthy   optional
#   NTFY_URL            e.g. http://192.168.82.1:2586; with NTFY_TOKEN_FILE  optional
#   GITHUB_TOKEN_FILE   enables the GitHub channel (read by the report command) optional
set -euo pipefail

: "${HOST_NAME:?HOST_NAME must be set}"
STATE_DIR="${STATE_DIR:-/var/lib/server-upgrade}"
REMOTE_URL="${REMOTE_URL:-https://github.com/LeeKrane/nixos-dotfiles}"
CURRENT_SYSTEM="${CURRENT_SYSTEM:-/run/current-system}"
BOOTED_SYSTEM="${BOOTED_SYSTEM:-/run/booted-system}"
SYSTEM_PROFILE="${SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"
HEALTH_CHECK="${HEALTH_CHECK:-}"
NTFY_URL="${NTFY_URL:-}"
NTFY_TOPIC="${NTFY_TOPIC:-server-upgrades}"
NTFY_TOKEN_FILE="${NTFY_TOKEN_FILE:-}"
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-}"
REPORT_CMD="${REPORT_CMD:-server-upgrade-report}"
BOOT_SETTLE_TIMEOUT="${BOOT_SETTLE_TIMEOUT:-300}"
OUTBOX="$STATE_DIR/outbox"
export GITHUB_TOKEN_FILE

read_state() { command cat "$STATE_DIR/$1" 2>/dev/null || true; }
resolved() { readlink -f "$1"; }
failed_units() { systemctl --failed --plain --no-legend | awk '{ print $1 }' | sort; }

# The SHA the deploy branch points at, empty if the branch does not exist.
deploy_sha() { git ls-remote "$REMOTE_URL" refs/heads/deploy | awk 'NR == 1 { print $1 }'; }

# True when the booted kernel, initrd or kernel modules differ from the running system's.
reboot_pending() {
    local f
    for f in initrd kernel kernel-modules; do
        [ "$(readlink "$BOOTED_SYSTEM/$f")" = "$(readlink "$CURRENT_SYSTEM/$f")" ] || return 0
    done
    return 1
}

# Healthy: no unit failed since the run started (a unit that was already failing before it
# does not block upgrades), and the host's own HEALTH_CHECK passes.
health() {
    local new
    new="$(comm -13 <(read_state failed-before) <(failed_units))"
    if [ -n "$new" ]; then
        echo "health check failed, units failed since the upgrade started:" >&2
        echo "$new" >&2
        return 1
    fi
    if [ -n "$HEALTH_CHECK" ]; then "$HEALTH_CHECK"; fi
}

# Puts the previous running system back as the system profile and runs its own
# switch-to-configuration ($1: switch, or boot when a reboot follows). Not
# `nixos-rebuild --rollback`: the previous profile generation can be one that was built but
# never booted.
rollback() {
    local pre
    pre="$(read_state pre-switch)"
    [ -n "$pre" ] || return 1
    nix-env -p "$SYSTEM_PROFILE" --set "$pre"
    "$pre/bin/switch-to-configuration" "$1"
}

# queue KIND SHA STAGE ROLLED_BACK: one outbox message (KIND: failed or recovered), then a
# best-effort kick of the delivery unit.
queue() {
    local kind="$1" sha="$2" stage="$3" rolled="$4" sha7 title priority body
    sha7="${sha:0:7}"
    if [ "$kind" = failed ]; then
        title="$HOST_NAME upgrade failed ($sha7)"
        priority=high
        # No -b: after a boot-health rollback the upgrade's own log is in the previous boot.
        body="$(printf 'Stage: %s\nRolled back: %s\n\n' "$stage" "$rolled"
            journalctl -u nixos-upgrade -u server-upgrade-health -n 30 --no-pager 2>/dev/null || true)"
    else
        title="$HOST_NAME recovered on $sha7"
        priority=low
        body="Healthy again on $sha7."
    fi
    mkdir -p "$OUTBOX"
    jq -nc --arg kind "$kind" --arg host "$HOST_NAME" --arg sha "$sha" --arg stage "$stage" \
        --arg rolled "$rolled" --arg title "$title" --arg priority "$priority" --arg body "$body" \
        '{kind: $kind, host: $host, sha: $sha, stage: $stage, rolled_back: $rolled,
          title: $title, priority: $priority, body: $body, ntfy_done: false, github_done: false}' \
        >"$OUTBOX/.tmp"
    mv "$OUTBOX/.tmp" "$OUTBOX/$(date +%s%N)-$kind.json"
    systemctl start --no-block server-upgrade-notify.service || true
}

# A healthy run on SHA: tell the owner if this host had failed on an earlier SHA.
recover() {
    local failed
    failed="$(read_state failed-sha)"
    if [ -n "$failed" ] && [ "$failed" != "$1" ]; then
        rm -f "$STATE_DIR/failed-sha"
        queue recovered "$1" - -
    fi
}

cmd_condition() {
    local sha failed deployed
    sha="$(deploy_sha)" || exit 1
    [ -n "$sha" ] || exit 1
    failed="$(read_state failed-sha)"
    if [ "$sha" = "$failed" ]; then
        echo "$sha already failed on this host, skipping"
        exit 1
    fi
    deployed="$("$CURRENT_SYSTEM/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)"
    if [ "$sha" = "$deployed" ] && ! reboot_pending; then
        echo "already on $sha, nothing to do"
        exit 1
    fi
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$sha" >"$STATE_DIR/target-sha"
}

cmd_pre() {
    mkdir -p "$OUTBOX"
    resolved "$CURRENT_SYSTEM" >"$STATE_DIR/pre-switch"
    resolved "$SYSTEM_PROFILE" >"$STATE_DIR/pre-profile"
    failed_units >"$STATE_DIR/failed-before"
    rm -f "$STATE_DIR/stage"
}

cmd_post() {
    local sha
    sha="$(read_state target-sha)"
    # allowReboot: a new kernel is only built into the boot profile, then the host reboots
    # inside its window (or waits for it). Nothing is running yet, so boot-health checks it.
    if [ "$(resolved "$CURRENT_SYSTEM")" != "$(resolved "$SYSTEM_PROFILE")" ]; then
        printf '%s\n' "$sha" >"$STATE_DIR/pending-check"
        echo "new generation not active yet, its health check runs after the reboot"
        return 0
    fi
    if ! health; then
        echo health >"$STATE_DIR/stage"
        return 1
    fi
    rm -f "$STATE_DIR/pending-check"
    recover "$sha"
}

cmd_failed() {
    local sha stage rolled=no
    sha="$(read_state target-sha)"
    sha="${sha:-unknown}"
    stage="$(read_state stage)"
    if [ -z "$stage" ]; then
        if [ "$(resolved "$SYSTEM_PROFILE")" = "$(read_state pre-profile)" ]; then
            stage=build
        else
            stage=activation
        fi
    fi
    # Only a run that moved the profile or the running system needs undoing; a build failure
    # changed nothing.
    if [ -f "$STATE_DIR/pre-switch" ] \
        && { [ "$(resolved "$CURRENT_SYSTEM")" != "$(read_state pre-switch)" ] \
            || [ "$(resolved "$SYSTEM_PROFILE")" != "$(read_state pre-profile)" ]; }; then
        if rollback switch; then
            rolled=yes
            rm -f "$STATE_DIR/pending-check"
        else
            rolled="no, the rollback failed"
        fi
    fi
    printf '%s\n' "$sha" >"$STATE_DIR/failed-sha"
    queue failed "$sha" "$stage" "$rolled"
}

cmd_boot_health() {
    local sha
    [ -f "$STATE_DIR/pending-check" ] || return 0
    sha="$(read_state pending-check)"
    # Let the system settle; a degraded or timed-out answer is judged by health below.
    timeout "$BOOT_SETTLE_TIMEOUT" systemctl is-system-running --wait >/dev/null 2>&1 || true
    if health; then
        rm -f "$STATE_DIR/pending-check" "$STATE_DIR/rolled-back"
        recover "$sha"
        return 0
    fi
    if [ -f "$STATE_DIR/rolled-back" ]; then
        # Already rolled back once and still unhealthy: another reboot would not help.
        rm -f "$STATE_DIR/pending-check" "$STATE_DIR/rolled-back"
        queue failed "$sha" boot-health "no, the rollback did not help"
        return 0
    fi
    printf '%s\n' "$sha" >"$STATE_DIR/failed-sha"
    : >"$STATE_DIR/rolled-back"
    if rollback boot; then
        queue failed "$sha" boot-health yes
        systemctl reboot
    else
        queue failed "$sha" boot-health "no, the rollback failed"
    fi
}

mark_done() { # FILE KEY
    jq --arg k "$2" '.[$k] = true' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

send_ntfy() {
    [ -n "$NTFY_URL" ] && [ -n "$NTFY_TOKEN_FILE" ] || return 0
    curl -fsS --max-time 30 \
        -H @<(printf 'Authorization: Bearer %s\n' "$(<"$NTFY_TOKEN_FILE")") \
        -H "Title: $(jq -r .title "$1")" -H "Priority: $(jq -r .priority "$1")" \
        -d "$(jq -r .body "$1")" "$NTFY_URL/$NTFY_TOPIC" >/dev/null
}

send_github() {
    [ -n "$GITHUB_TOKEN_FILE" ] || return 0
    "$REPORT_CMD" "$(jq -r .kind "$1")" "$(jq -r .host "$1")" "$(jq -r .sha "$1")" \
        "$(jq -r .stage "$1")" "$(jq -r .rolled_back "$1")"
}

cmd_deliver() {
    local f undelivered=0
    shopt -s nullglob
    for f in "$OUTBOX"/*.json; do
        if [ "$(jq -r .ntfy_done "$f")" != true ] && send_ntfy "$f"; then mark_done "$f" ntfy_done; fi
        if [ "$(jq -r .github_done "$f")" != true ] && send_github "$f"; then mark_done "$f" github_done; fi
        if [ "$(jq -r '.ntfy_done and .github_done' "$f")" = true ]; then
            rm -f "$f"
        else
            undelivered=1
        fi
    done
    return "$undelivered"
}

case "${1:-}" in
    condition | pre | post | failed | boot-health | deliver) "cmd_${1//-/_}" ;;
    *)
        echo "usage: server-upgrade-hooks condition|pre|post|failed|boot-health|deliver" >&2
        exit 2
        ;;
esac
```

- [ ] **Step 4: Run the test and shellcheck**

Run:

```bash
nix shell nixpkgs#jq nixpkgs#gawk nixpkgs#curl nixpkgs#shellcheck -c bash -c \
  'shellcheck -x -S style scripts/server-upgrade-hooks.sh scripts/tests/server-upgrade-hooks-test.sh && bash scripts/tests/server-upgrade-hooks-test.sh'
```

Expected: every line `ok ...`, then `all passed`. (The real `readlink`, `comm`, `timeout`, `jq` and `awk` are used; only git, systemctl, nix-env, journalctl, curl and the report command are stubbed.)

- [ ] **Step 5: Commit**

```bash
git add scripts/server-upgrade-hooks.sh scripts/tests/server-upgrade-hooks-test.sh
git commit -m "Add the server upgrade hooks"
```

---

### Task 4: Package, module, revision stamp, windows and eval checks

**Files:**
- Create: `pkgs/server-upgrade/default.nix`, `lib/ntfy.nix`, `modules/nixos/server/auto-upgrade.nix`
- Modify: `pkgs/default.nix`, `modules/nixos/server/default.nix`, `lib/mk-host.nix`, `tests/server-host/default.nix`, `hosts/{tarronax,tarritator,taronychus,taragarmr}/default.nix`, `hosts/taragarmr/caddy.nix`, `flake.nix`

**Interfaces:**
- Consumes: the two scripts from Tasks 2 and 3 (`scripts/server-upgrade-hooks.sh`, `scripts/server-upgrade-report.sh`).
- Produces: `pkgs.server-upgrade` (binaries `server-upgrade-hooks`, `server-upgrade-report`); `lib/ntfy.nix` = `{ host, port, topic, url }` (used by Tasks 5 and 6); options `krane.autoUpgrade.rebootWindow` (`{ lower; upper; }`, no default), `krane.autoUpgrade.healthChecks` (list of str, default `[ ]`), read-only `krane.autoUpgrade.allHealthChecks`; units `nixos-upgrade` (hooked), `server-upgrade-failed`, `server-upgrade-health`, `server-upgrade-notify`; sops secrets `server-upgrade/github-token` and `ntfy/publish-token` (section-gated); flake helper `upgradeExpectationsFor name` and `serverHosts`.

- [ ] **Step 1: Write the failing eval checks**

In `flake.nix`, directly after the `desktopHosts = ...;` line (inside the outer `let`, before `in`), add:

```nix
      serverHosts = builtins.filter (name: hostMeta.${name}.role == "server") hosts;
      # Expectations for one server host's automatic upgrade (modules/nixos/server/auto-upgrade.nix),
      # shared by checks.server-eval (x86_64 servers) and checks.pi-eval (the Pis).
      upgradeExpectationsFor =
        name:
        let
          cfg = self.nixosConfigurations.${name}.config;
          au = cfg.system.autoUpgrade;
          upgrade = cfg.systemd.services.nixos-upgrade;
        in
        [
          {
            ok = au.enable && au.allowReboot && au.flake == "github:LeeKrane/nixos-dotfiles/deploy#${name}";
            what = "${name}: system.autoUpgrade does not follow the deploy branch with reboots allowed";
          }
          {
            ok =
              upgrade.onFailure == [ "server-upgrade-failed.service" ]
              && nixpkgs.lib.hasSuffix " post" (toString upgrade.serviceConfig.ExecStartPost)
              && nixpkgs.lib.hasSuffix " condition" (toString upgrade.serviceConfig.ExecCondition);
            what = "${name}: the upgrade hooks (condition, post, OnFailure) are not wired";
          }
          {
            ok = cfg.krane.autoUpgrade.allHealthChecks != [ ];
            what = "${name}: no health check configured for the upgrade";
          }
        ];
```

In `checks.server-eval`, replace the line `failed = map (e: e.what) (builtins.filter (e: !e.ok) expectations);` (the one right after the closing `];` of `expectations`, just before `in lib.throwIf (failed != [ ]) "checks.server-eval: ...`) with:

```nix
            x86Servers = builtins.filter (n: hostMeta.${n}.system == "x86_64-linux") serverHosts;
            windows = lib.genAttrs serverHosts (
              n: self.nixosConfigurations.${n}.config.system.autoUpgrade.rebootWindow
            );
            upgradeExpectations = lib.concatMap upgradeExpectationsFor x86Servers ++ [
              {
                ok =
                  lib.sort (a: b: a < b) (map (w: w.lower) (builtins.attrValues windows)) == [
                    "02:00"
                    "03:00"
                    "04:00"
                    "05:00"
                  ];
                what = "the servers' reboot windows are not four distinct hours 02:00 to 06:00";
              }
              {
                ok =
                  windows.taragarmr.lower == "05:00" && lib.all (w: w.upper > w.lower) (builtins.attrValues windows);
                what = "taragarmr's reboot window is not the last, or a window ends before it starts";
              }
              {
                ok = lib.all (n: !self.nixosConfigurations.${n}.config.system.autoUpgrade.enable) desktopHosts;
                what = "a desktop has system.autoUpgrade enabled";
              }
            ];
            failed = map (e: e.what) (builtins.filter (e: !e.ok) (expectations ++ upgradeExpectations));
```

In `checks.pi-eval`, replace its `failed = map (e: e.what) (builtins.filter (e: !e.ok) expectations);` (just after `) piHosts;`) with:

```nix
            upgradeExpectations = lib.concatMap upgradeExpectationsFor piHosts;
            failed = map (e: e.what) (builtins.filter (e: !e.ok) (expectations ++ upgradeExpectations));
```

- [ ] **Step 2: Run the checks to verify they fail**

Run: `nix build --no-link .#checks.x86_64-linux.server-eval .#checks.x86_64-linux.pi-eval`
Expected: FAIL, evaluation error about the missing option `krane.autoUpgrade` (`allHealthChecks`) or "does not exist".

- [ ] **Step 3: Package the scripts**

Create `pkgs/server-upgrade/default.nix`:

```nix
# The two scripts of the automatic server upgrade as one package (the flake-update-notify
# pattern, so they are built and shellchecked on their own): server-upgrade-hooks (systemd
# hooks, scripts/server-upgrade-hooks.sh) and server-upgrade-report (GitHub issues,
# scripts/server-upgrade-report.sh). The nixos-upgrade unit's own PATH supplies nix-env.
{
  lib,
  writeShellApplication,
  symlinkJoin,
  gitMinimal,
  jq,
  curl,
  gawk,
  coreutils,
  systemd,
}:
let
  # Strips the original `#!/usr/bin/env bash` line. writeShellApplication adds its own.
  script =
    name: runtimeInputs:
    writeShellApplication {
      inherit name runtimeInputs;
      text = lib.concatStringsSep "\n" (
        lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/${name}.sh))
      );
      meta.mainProgram = name;
    };
  report = script "server-upgrade-report" [
    curl
    jq
  ];
  hooks = script "server-upgrade-hooks" [
    gitMinimal
    jq
    curl
    gawk
    coreutils
    systemd
    report
  ];
in
symlinkJoin {
  name = "server-upgrade";
  paths = [
    hooks
    report
  ];
}
```

In `pkgs/default.nix`, add next to the other `callPackage` lines (alphabetical, before `skillspector`):

```nix
  server-upgrade = pkgs.callPackage ./server-upgrade { };
```

- [ ] **Step 4: Shared ntfy address, revision stamp, module**

Create `lib/ntfy.nix`:

```nix
# Where the ntfy server for the automatic server upgrades listens: taragarmr's WireGuard
# address (lib/wireguard.nix), never a public address. Shared by hosts/taragarmr/ntfy.nix (the
# server), modules/nixos/server/auto-upgrade.nix (publishers) and the desktops' subscriber.
let
  hub = (import ./wireguard.nix).wg0.hub;
in
rec {
  host = hub.ip;
  port = 2586;
  topic = "server-upgrades";
  url = "http://${host}:${toString port}";
}
```

In `lib/mk-host.nix`, in the first inline module (the one with `networking.hostName = hostName;`), add right after that line:

```nix
      # `nixos-version --configuration-revision` reads the commit a host runs; "dirty" for a
      # build from an unclean tree (`just switch`). The server upgrade hooks compare it with `deploy`.
      system.configurationRevision = inputs.self.rev or "dirty";
```

Create `modules/nixos/server/auto-upgrade.nix`:

```nix
# Automatic upgrades of every role = "server" host to the latest gated `main` commit: the
# `deploy` branch that .github/workflows/check.yml moves after its gate passes. Upstream
# system.autoUpgrade supplies the timer and the reboot window; the hooks (pkgs/server-upgrade,
# scripts/server-upgrade-hooks.sh) skip runs that have nothing to do, health check the new
# system, roll back and queue failure messages for ntfy and GitHub. See
# docs/superpowers/specs/2026-11-23-server-auto-upgrade-design.md.
#
# Secrets (declared only when the host's secrets file has the section, like every sops
# declaration here): server-upgrade/github-token, ntfy/publish-token.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  cfg = config.krane.autoUpgrade;
  ntfy = import ../../../lib/ntfy.nix;
  inherit (import ../../../lib/wireguard.nix) wg0;
  hostSecrets = import ../../../lib/host-secrets.nix { inherit lib hostName; };
  hasGithub = hostSecrets.hasSection "server-upgrade";
  hasNtfy = hostSecrets.hasSection "ntfy";
  secretPath = name: config.sops.secrets.${name}.path;

  hooks = "${pkgs.server-upgrade}/bin/server-upgrade-hooks";
  stateDirectory = "server-upgrade";

  # A spoke whose wg0 is configured must still reach the hub after an upgrade.
  hubReachable = lib.optional (
    config.krane.wireguard.enable
    && config.krane.wireguard.wg0PrivateKeyFile != null
    && wg0.peers ? ${hostName}
  ) "${lib.getExe' pkgs.iputils "ping"} -c 3 -W 5 ${wg0.hub.ip}";
  healthChecks = hubReachable ++ cfg.healthChecks;

  # One command per line; each must exit 0. Written as a script so the hooks only see one path.
  healthScript = pkgs.writeShellScript "server-upgrade-health-checks" ''
    ${lib.concatMapStringsSep "\n" (c: ''
      (${c}) || { echo ${lib.escapeShellArg "health check failed: ${c}"} >&2; exit 1; }
    '') healthChecks}
    exit 0
  '';

  environment = {
    HOST_NAME = hostName;
    HEALTH_CHECK = "${healthScript}";
    NTFY_URL = ntfy.url;
    NTFY_TOPIC = ntfy.topic;
    REPORT_CMD = "${pkgs.server-upgrade}/bin/server-upgrade-report";
  }
  // lib.optionalAttrs hasNtfy { NTFY_TOKEN_FILE = secretPath "ntfy/publish-token"; }
  // lib.optionalAttrs hasGithub { GITHUB_TOKEN_FILE = secretPath "server-upgrade/github-token"; };

  # A unit the upgrade itself may switch must not be restarted by that switch, like upstream's
  # nixos-upgrade.service.
  inert = {
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
  };
in
{
  options.krane.autoUpgrade = {
    rebootWindow = lib.mkOption {
      type = lib.types.submodule {
        options = {
          lower = lib.mkOption {
            type = lib.types.strMatching "[[:digit:]]{2}:[[:digit:]]{2}";
            example = "02:00";
          };
          upper = lib.mkOption {
            type = lib.types.strMatching "[[:digit:]]{2}:[[:digit:]]{2}";
            example = "03:00";
          };
        };
      };
      example = {
        lower = "02:00";
        upper = "03:00";
      };
      description = ''
        Window in which the host may reboot after an upgrade that changes the kernel, initrd
        or kernel modules. No default: a server without one fails evaluation, so two hosts
        cannot silently reboot at the same time. A one-hour window contains exactly one
        hourly run.
      '';
    };
    healthChecks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "${lib.getExe' pkgs.iputils "ping"} -c 3 -W 5 192.168.82.1" ];
      description = ''
        Shell commands that must all exit 0 for an upgrade to count as healthy, on top of the
        built-in check that no unit failed since the upgrade started and, on a WireGuard
        spoke, a ping of the hub. Use store paths, the commands run with a minimal PATH.
      '';
    };
    allHealthChecks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      default = healthChecks;
      description = "Every health check that runs: the hub ping on a spoke, then healthChecks.";
    };
  };

  config = {
    system.autoUpgrade = {
      enable = true;
      # With a flake set, upstream already adds --refresh (bypasses the tarball cache) and
      # `--flake <this>`.
      flake = "github:LeeKrane/nixos-dotfiles/deploy#${hostName}";
      dates = "hourly";
      randomizedDelaySec = "10min";
      fixedRandomDelay = true;
      persistent = true;
      allowReboot = true;
      inherit (cfg) rebootWindow;
    };

    sops.secrets =
      lib.optionalAttrs hasGithub {
        "server-upgrade/github-token" = {
          owner = "root";
          mode = "0400";
        };
      }
      // lib.optionalAttrs hasNtfy {
        "ntfy/publish-token" = {
          owner = "root";
          mode = "0400";
        };
      };

    systemd.services = {
      nixos-upgrade = {
        inherit environment;
        onFailure = [ "server-upgrade-failed.service" ];
        serviceConfig = {
          StateDirectory = stateDirectory;
          ExecCondition = "${hooks} condition";
          ExecStartPre = "${hooks} pre";
          ExecStartPost = "${hooks} post";
        };
      };

      # nix-env comes from nixos-upgrade's PATH in upstream; this unit needs it too.
      server-upgrade-failed = lib.recursiveUpdate inert {
        description = "Roll back and report a failed server upgrade";
        inherit environment;
        path = [ config.nix.package.out ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = stateDirectory;
          ExecStart = "${hooks} failed";
        };
      };

      # Type = simple: the start job ends once the process is forked, so waiting for the
      # system to settle inside the script cannot deadlock on this unit's own job.
      server-upgrade-health = lib.recursiveUpdate inert {
        description = "Health check after a reboot into a new upgrade";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        inherit environment;
        path = [ config.nix.package.out ];
        serviceConfig = {
          Type = "simple";
          StateDirectory = stateDirectory;
          ExecStart = "${hooks} boot-health";
        };
      };

      # Delivers queued messages; retried every 5 minutes until both channels took them.
      server-upgrade-notify = lib.recursiveUpdate inert {
        description = "Deliver server upgrade notifications";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        inherit environment;
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = stateDirectory;
          ExecStart = "${hooks} deliver";
          TimeoutStartSec = "3min";
          Restart = "on-failure";
          RestartSec = "5min";
        };
      };
    };
  };
}
```

In `modules/nixos/server/default.nix`, add `./auto-upgrade.nix` as the first entry of `imports` (alphabetical, before `./backup.nix`).

- [ ] **Step 5: Windows, health checks, fixture**

In `tests/server-host/default.nix`, add after the `boot.loader`/`fileSystems` block and before `krane.backup = {`:

```nix
  krane.autoUpgrade.rebootWindow = {
    lower = "02:00";
    upper = "03:00";
  };
```

In each host's `default.nix`, right after its `system.stateVersion = "26.05";` line, add (values per host: tarronax `02:00`/`03:00`, tarritator `03:00`/`04:00`, taronychus `04:00`/`05:00`, taragarmr `05:00`/`06:00`):

```nix
  # Reboots after a kernel-changing upgrade only inside this hour, one host per hour (the
  # Pis first, the WireGuard hub last).
  krane.autoUpgrade.rebootWindow = {
    lower = "02:00";
    upper = "03:00";
  };
```

In `hosts/taragarmr/caddy.nix`, change the header to take `lib` and `pkgs`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
```

and add, just before `networking.firewall = {`:

```nix
  # An upgrade is healthy only if Caddy still serves its vhost over TLS (resolved to this host, so
  # the check needs no DNS).
  krane.autoUpgrade.healthChecks = [
    "${lib.getExe pkgs.curl} -fsS --max-time 10 -o /dev/null --resolve couch.krane.dev:443:127.0.0.1 https://couch.krane.dev/"
  ];
```

- [ ] **Step 6: Run the checks**

Run: `nix fmt -- flake.nix lib pkgs/server-upgrade pkgs/default.nix modules/nixos/server hosts tests/server-host`, then `git diff --stat` (only the files above may be listed), then

```bash
nix build --no-link .#checks.x86_64-linux.pi-eval
nix build --no-link .#checks.x86_64-linux.server-eval
nix build --no-link --print-out-paths .#nixosConfigurations.taragarmr.pkgs.server-upgrade
nix shell --inputs-from . nixpkgs#statix nixpkgs#deadnix -c bash -c 'statix check . && deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .'
```

Expected: `pi-eval` and `server-eval` pass (a negative check: change taragarmr's `lower` to `"04:00"` and `server-eval` must fail with the windows messages; revert it). The package build runs shellcheck over both scripts and succeeds. statix and deadnix are clean.

- [ ] **Step 7: Commit**

```bash
git add pkgs lib modules/nixos/server hosts tests/server-host flake.nix
git commit -m "Upgrade servers automatically from the deploy branch with health checks and rollback"
```

---

### Task 5: ntfy on taragarmr

**Files:**
- Create: `hosts/taragarmr/ntfy.nix`
- Modify: `hosts/taragarmr/default.nix` (import), `flake.nix` (two `server-eval` expectations)

**Interfaces:**
- Consumes: `lib/ntfy.nix` and the `server-eval` `upgradeExpectations` list (Task 4); `lib/host-secrets.nix`.
- Produces: `services.ntfy-sh` on `192.168.82.1:2586` with `auth-default-access = "deny-all"`; reads the sops secret `ntfy/server-env` (when the `ntfy` section exists in `secrets/taragarmr.yaml`) as the unit's `EnvironmentFile`. Task 9 documents its content.

- [ ] **Step 1: The failing test**

In `flake.nix`, `checks.server-eval`, add these two entries to the `upgradeExpectations` list (before the "a desktop has system.autoUpgrade enabled" entry):

```nix
              {
                ok = lib.all (
                  n: self.nixosConfigurations.${n}.config.services.ntfy-sh.enable == (n == "taragarmr")
                ) hosts;
                what = "services.ntfy-sh is not enabled on taragarmr alone";
              }
              {
                ok =
                  let
                    ntfy = self.nixosConfigurations.taragarmr.config.services.ntfy-sh.settings;
                  in
                  ntfy.listen-http == "192.168.82.1:2586" && ntfy.auth-default-access == "deny-all";
                what = "ntfy does not listen on taragarmr's WireGuard address alone with deny-all as the default";
              }
```

Run: `nix build --no-link .#checks.x86_64-linux.server-eval`
Expected: FAIL (`services.ntfy-sh is not enabled on taragarmr alone`, or an error that the attribute `listen-http` is missing, since ntfy is not configured yet).

- [ ] **Step 2: Write the module**

Create `hosts/taragarmr/ntfy.nix`:

```nix
# ntfy for the automatic server upgrades (modules/nixos/server/auto-upgrade.nix): failure and
# recovery pushes to the phone and the desktops. Listens only on the WireGuard address, no
# Caddy vhost. Everything is denied by default; two provisioned users each get one right on
# the topic, so a leaked token can do one thing:
#   upgrade-publisher  write-only  token on the servers (ntfy/publish-token)
#   krane              read-only   token on the desktops (ntfy/read-token), password on the phone
# Users, ACLs and tokens are provisioned declaratively (ntfy 2.26: NTFY_AUTH_USERS,
# NTFY_AUTH_ACCESS, NTFY_AUTH_TOKENS) from the sops secret ntfy/server-env, so no CLI step on
# the host. See secrets/README.md for how to generate the values.
{
  config,
  lib,
  hostName,
  ...
}:
let
  ntfy = import ../../lib/ntfy.nix;
  hasEnv = (import ../../lib/host-secrets.nix { inherit lib hostName; }).hasSection "ntfy";
in
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = ntfy.url;
      listen-http = "${ntfy.host}:${toString ntfy.port}";
      auth-default-access = "deny-all";
    };
    environmentFile = lib.mkIf hasEnv config.sops.secrets."ntfy/server-env".path;
  };

  sops.secrets = lib.mkIf hasEnv {
    "ntfy/server-env" = {
      owner = "root";
      mode = "0400";
    };
  };

  # The listen address belongs to wg0, which comes up after the network; retry until it does.
  systemd.services.ntfy-sh = {
    after = [ "wg-quick-wg0.service" ];
    wants = [ "wg-quick-wg0.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
```

In `hosts/taragarmr/default.nix`, add `./ntfy.nix` to `imports` after `./caddy.nix`. Also extend the "Secrets (secrets/taragarmr.yaml)" comment there with `server-upgrade/github-token, ntfy/{publish-token,server-env}`.

- [ ] **Step 3: Run the checks**

Run: `nix fmt -- hosts/taragarmr flake.nix` then
`nix build --no-link .#checks.x86_64-linux.server-eval .#checks.x86_64-linux.pi-eval`
Expected: both pass. Also `nix eval --raw .#nixosConfigurations.taragarmr.config.systemd.services.ntfy-sh.after --apply 'builtins.concatStringsSep ","'` prints `network.target,wg-quick-wg0.service`.

- [ ] **Step 4: Commit**

```bash
git add hosts/taragarmr flake.nix
git commit -m "Run ntfy on taragarmr for server upgrade notifications"
```

---

### Task 6: Desktop subscriber

**Files:**
- Create: `modules/nixos/desktop/server-upgrade-notify.nix`, `modules/home/desktop/server-upgrade-notify.nix`
- Modify: `modules/nixos/desktop/default.nix`, `modules/home/desktop/default.nix` (imports)

**Interfaces:**
- Consumes: `lib/ntfy.nix` (Task 4); the sops secret `ntfy/read-token` (declared here, present only on desktop files with an `ntfy` section).
- Produces: user service `server-upgrade-notify` (running `ntfy subscribe`, one `notify-send` per message), active only when `osConfig.sops.secrets ? "ntfy/read-token"`.

- [ ] **Step 1: The failing test**

The server-eval check "a desktop has system.autoUpgrade enabled" already guards against crossing wires; the new behaviour needs its own evaluation test. Run (expect an error: the unit does not exist yet):

```bash
nix eval --raw --impure --expr 'let f = builtins.getFlake (toString ./.); c = (f.nixosConfigurations.tariognatha.extendModules { modules = [{ sops.secrets."ntfy/read-token" = {}; }]; }).config; in builtins.head c.home-manager.users.krane.systemd.user.services.server-upgrade-notify.Service.ExecStart'
```

Expected: FAIL, attribute `server-upgrade-notify` missing.

- [ ] **Step 2: Write the modules**

Create `modules/nixos/desktop/server-upgrade-notify.nix`:

```nix
# The read-only ntfy token that modules/home/desktop/server-upgrade-notify.nix subscribes with,
# owned by the login account. Declared only when the host's secrets file has the `ntfy`
# section, like every sops declaration here: sops-nix validates each declared key at build time.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hasNtfy = (import ../../../lib/host-secrets.nix { inherit lib hostName; }).hasSection "ntfy";
in
{
  sops.secrets = lib.mkIf hasNtfy {
    "ntfy/read-token" = {
      owner = config.krane.user.name;
      mode = "0400";
    };
  };
}
```

Create `modules/home/desktop/server-upgrade-notify.nix`:

```nix
# Desktop notification for every message on the server upgrade ntfy topic (failures with high
# priority, recoveries with low): `ntfy subscribe` over the WireGuard tunnel, one notify-send per
# message. Inactive until the host's secrets have ntfy/read-token
# (modules/nixos/desktop/server-upgrade-notify.nix). Messages sent while the desktop is off
# are not replayed; the phone and the GitHub issue cover that.
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  ntfy = import ../../../lib/ntfy.nix;
  tokenSecret = "ntfy/read-token";

  subscribe = pkgs.writeShellScript "server-upgrade-subscribe" ''
    NTFY_TOKEN="$(< ${osConfig.sops.secrets.${tokenSecret}.path})"
    export NTFY_TOKEN
    # ntfy runs the command through sh with the message in NTFY_* variables; priority 4 and up
    # (high, urgent) is a failure.
    exec ${lib.getExe pkgs.ntfy-sh} subscribe ${ntfy.url}/${ntfy.topic} \
      '[ "$NTFY_PRIORITY" -ge 4 ] && urgency=critical || urgency=normal
       ${lib.getExe pkgs.libnotify} -a Servers -u "$urgency" "$NTFY_TITLE" "$NTFY_MESSAGE"'
  '';
in
{
  config = lib.mkIf (osConfig.sops.secrets ? ${tokenSecret}) {
    systemd.user.services.server-upgrade-notify = {
      Unit = {
        Description = "Desktop notifications for server upgrade failures";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${subscribe}";
        # The tunnel or the session may not be up yet, or the connection drops: reconnect.
        Restart = "always";
        RestartSec = "30s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
```

Add `./server-upgrade-notify.nix` to the `imports` of `modules/nixos/desktop/default.nix` (after `./appimage.nix`) and of `modules/home/desktop/default.nix` (after `./flake-update-notify.nix`).

- [ ] **Step 3: Run the checks**

Re-run the Step 1 command. Expected: prints `/nix/store/...-server-upgrade-subscribe`. Then
`nix fmt -- modules/nixos/desktop modules/home/desktop` and
`nix build --no-link .#checks.x86_64-linux.server-eval` (still passes; a desktop without the section is unchanged) and
`nix eval --raw .#nixosConfigurations.tariognatha.config.system.build.toplevel.drvPath` (the desktop still evaluates without the secret).

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/desktop modules/home/desktop
git commit -m "Show server upgrade notifications on the desktops"
```

---

### Task 7: The Pis in the weekly update PR

**Files:**
- Modify: `scripts/update-versions.nix`, `.github/workflows/update.yml`, `scripts/hosts.nix` (comment)

**Interfaces:**
- Consumes: Task 1's decision (x86-only runner plus the nixos-raspberrypi substituter).
- Produces: `scripts/update-versions.nix` taking `configs: hosts:`; `update.yml`'s `hosts` output = every host in `lib.hostMeta`.

- [ ] **Step 1: Write the failing test**

The new call shape must work before the workflow uses it. Run:

```bash
HOSTS_JSON='["taragarmr","tarronax"]' nix eval --json --impure '.#nixosConfigurations' \
  --apply 'cfgs: import ./scripts/update-versions.nix cfgs (builtins.fromJSON (builtins.getEnv "HOSTS_JSON"))'
```

Expected: FAIL (the file still takes one argument: "called with unexpected argument" or a function value cannot be converted to JSON).

- [ ] **Step 2: Change `scripts/update-versions.nix`**

Replace the head comment's host-list paragraph and the first lines of the expression. The file currently starts with the paragraph beginning `# The host list (every nixosConfigurations attribute except ...` and its usage line, and contains `configs:` / `let` / `hosts = import ./hosts.nix configs;`. Make it:

```nix
# Evaluated against the flake's nixosConfigurations attrset (not a single host) to print
# the package versions update.yml shows in the weekly update PR body
# (scripts/update-summary.sh). Called once before `nix flake update` and once after.
# The host list is the second argument, as a list of names: update.yml passes every host of
# `lib.hostMeta` (the Pis included, unlike scripts/hosts.nix's x86_64-only list), read from the
# HOSTS_JSON environment variable (`--impure`):
#   HOSTS_JSON='["taragarmr"]' nix eval --json --impure '.#nixosConfigurations' \
#     --apply 'cfgs: import scripts/update-versions.nix cfgs (builtins.fromJSON (builtins.getEnv "HOSTS_JSON"))'
```

keep the following `# Every lookup goes through attrByPath ...` paragraph unchanged, then:

```nix
configs: hosts:
let
```

and delete the line `hosts = import ./hosts.nix configs;` plus its blank line. The rest of the file (`attrByPath`, `tryVersion`, `versionsFor`, the final `listToAttrs`) is unchanged: it already uses `hosts` and `configs.${host}`.

- [ ] **Step 3: Verify the new call**

Re-run the Step 1 command.
Expected: JSON with keys `taragarmr` and `tarronax`; `tarronax`'s `"Linux kernel"` is an rpi kernel (`6.18.59-unstable_...`), taragarmr's is `6.18.62`.

- [ ] **Step 4: Update `.github/workflows/update.yml`**

(a) `update` job, step `Compute host list`: replace its comment and `nix eval` line with:

```yaml
          # Every host, the Pis included: the version table and the security job report
          # on all of them. (scripts/hosts.nix, the x86_64-only list, still drives check.yml's
          # eval matrix: the x86 runners cannot build the Pis.)
          nix eval --json '.#lib.hostMeta' --apply builtins.attrNames > "$RUNNER_TEMP/hosts.json"
```

(b) Steps `Package versions after update` and `Package versions before update`: add, before each `run: |`,

```yaml
        env:
          HOSTS_JSON: ${{ steps.hosts.outputs.hosts }}
```

and replace the `--apply 'import ./scripts/update-versions.nix'` argument in both with

```yaml
            --apply 'cfgs: import ./scripts/update-versions.nix cfgs (builtins.fromJSON (builtins.getEnv "HOSTS_JSON"))' > "$RUNNER_TEMP/versions-after.json"
```

(`versions-before.json` for the before step).

(c) `security` job: replace the bare `- uses: cachix/install-nix-action@75c75c31ebece974e48ebc36b4ad125bd97bd97b # v31.11.3` (the one just before `- name: Evaluate toplevel derivations before and after`) with:

```yaml
      - uses: cachix/install-nix-action@75c75c31ebece974e48ebc36b4ad125bd97bd97b # v31.11.3
        with:
          # The Pis' kernels, firmware and images come from nixos-raspberrypi's cache (the same
          # substituter and key as modules/nixos/common/nix-settings.nix); without it every Pi
          # kernel would count as a local build.
          extra_nix_config: |
            extra-substituters = https://nixos-raspberrypi.cachix.org
            extra-trusted-public-keys = nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
```

(d) Same job, step `Evaluate toplevel derivations before and after`: add `env: HOSTS_JSON: ${{ needs.update.outputs.hosts }}` before its `run: |`, and replace the `apply=` line with:

```bash
          apply='cfgs: let hosts = builtins.fromJSON (builtins.getEnv "HOSTS_JSON"); in builtins.listToAttrs (map (h: { name = h; value = cfgs.${h}.config.system.build.toplevel.drvPath; }) hosts)'
```

In `scripts/hosts.nix`, replace the first three comment lines with:

```nix
# Host list shared by check.yml's eval matrix and docker-check.sh: every host whose host.nix
# says x86_64-linux (the aarch64 Pis: the x86 runners cannot build them, checks.pi-eval only
# evaluates them). update.yml's reports are not restricted to it: they cover every host.
# Takes the flake's `lib.hostMeta` (flake.nix), which has no `-vm`
```

(keep the following lines of that comment, `# check target and reads no nixpkgs, so the list lives in exactly one place.`, unchanged).

- [ ] **Step 5: Verify**

Run:

```bash
nix eval --json '.#lib.hostMeta' --apply builtins.attrNames
nix run nixpkgs#actionlint -- .github/workflows/update.yml .github/workflows/check.yml
```

Expected: the seven host names (`taractias`, `taragarmr`, `tariognatha`, `tarmantria`, `taronychus`, `tarritator`, `tarronax`); actionlint prints nothing. Then reproduce the security job's evaluation locally for the Pis:

```bash
HOSTS_JSON='["tarronax","taronychus","tarritator"]' nix eval --json --impure '.#nixosConfigurations' \
  --apply 'cfgs: let hosts = builtins.fromJSON (builtins.getEnv "HOSTS_JSON"); in builtins.listToAttrs (map (h: { name = h; value = cfgs.${h}.config.system.build.toplevel.drvPath; }) hosts)'
```

Expected: JSON with three `.drv` paths. After the commit lands on `main`, run the update workflow manually once (`gh workflow run update.yml`) and check that the PR body's `### Security` and `### Local builds` sections list the Pis (the manual verification from the spec).

- [ ] **Step 6: Commit**

```bash
git add scripts/update-versions.nix scripts/hosts.nix .github/workflows/update.yml
git commit -m "Report the Raspberry Pis in the weekly update PR"
```

---

### Task 8: `deploy` branch promotion and the script tests in CI

**Files:**
- Modify: `.github/workflows/check.yml`

**Interfaces:**
- Consumes: Tasks 2 and 3's test scripts; the job names `lint`, `hosts`, `eval`, `flake-check`, `nvim`.
- Produces: the `deploy` branch (created on the first push to `main` after this lands) that the servers' `system.autoUpgrade.flake` and `ExecCondition` read.

- [ ] **Step 1: Write the failing test**

actionlint is the test for workflow shape; first check that nothing promotes yet:
`grep -c promote .github/workflows/check.yml`
Expected: `0`.

- [ ] **Step 2: Add the test step to the `lint` job**

After the `flake-update-notify tests` step, add:

```yaml
      - name: server-upgrade tests
        run: |
          nix shell --inputs-from . nixpkgs#curl nixpkgs#jq nixpkgs#gawk -c bash scripts/tests/server-upgrade-report-test.sh
          nix shell --inputs-from . nixpkgs#curl nixpkgs#jq nixpkgs#gawk -c bash scripts/tests/server-upgrade-hooks-test.sh
```

In the `hosts` job's `Compute host list` step, replace its two comment lines with:

```yaml
          # scripts/hosts.nix is the one shared place for this list (x86_64 hosts: the
          # runners cannot build the Pis, which checks.pi-eval only evaluates).
```

- [ ] **Step 3: Add the `promote` job**

Append at the end of `.github/workflows/check.yml`:

```yaml

  # Moves the `deploy` branch (what every server upgrades to, see
  # modules/nixos/server/auto-upgrade.nix) to a commit that passed the whole gate. Only the
  # push to main: pull requests, and update.yml's workflow_call run on its staging commit, never
  # promote. The only job with write access.
  promote:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    needs: [lint, hosts, eval, flake-check, nvim]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      # Full history: git only fast-forwards a branch whose current tip it has.
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
      # No --force: a rewritten main makes this push fail, and the job with it.
      - name: Fast-forward deploy
        run: git push origin "$GITHUB_SHA":refs/heads/deploy
```

`needs` without a status function means "all of them succeeded"; a skipped `nvim` leg still counts as success because the job itself runs (its steps are conditional).

- [ ] **Step 4: Verify**

Run:

```bash
nix run nixpkgs#actionlint -- .github/workflows/*.yml
nix shell nixpkgs#jq nixpkgs#gawk nixpkgs#curl -c bash scripts/tests/server-upgrade-report-test.sh
nix shell nixpkgs#jq nixpkgs#gawk nixpkgs#curl -c bash scripts/tests/server-upgrade-hooks-test.sh
```

Expected: actionlint silent, both tests `all passed`. After the first push of this commit to `main` (the owner pushes), check `git ls-remote origin refs/heads/deploy` equals that commit (the third CI verification in the spec). If the `promote` job reports a rejected push, `main` was rewritten: fix `deploy` by hand (`git push origin <main-sha>:refs/heads/deploy --force`) once, deliberately.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/check.yml
git commit -m "Promote gated main commits to the deploy branch and run the server upgrade tests in CI"
```

---

### Task 9: Secrets documentation and rollout checklist

**Files:**
- Modify: `secrets/README.md`

**Interfaces:**
- Consumes: the secret names fixed by Tasks 4 to 6.
- Produces: the documented procedure the owner runs for the manual rollout (sops files are edited by the owner, never by an agent).

- [ ] **Step 1: Extend the key table and add the how-to**

In `secrets/README.md`, add these rows to the table under "`modules/nixos/common/sops.nix` reads:" (after the `ani-cli/curl-auth` row):

```markdown
| `server-upgrade/github-token` | `modules/nixos/server/auto-upgrade.nix` (fine-grained PAT, repository `LeeKrane/nixos-dotfiles` only, Issues: read and write; the four server files) | `root:0400` |
| `ntfy/publish-token` | same module (token of ntfy user `upgrade-publisher`, write-only on `server-upgrades`; the four server files) | `root:0400` |
| `ntfy/server-env` | `hosts/taragarmr/ntfy.nix` (`NTFY_AUTH_USERS`, `NTFY_AUTH_ACCESS`, `NTFY_AUTH_TOKENS` for ntfy; taragarmr only) | `root:0400` |
| `ntfy/read-token` | `modules/nixos/desktop/server-upgrade-notify.nix` (token of ntfy user `krane`, read-only; the three desktop files) | `krane:0400` |
```

and append at the end of the "Servers" section:

````markdown
### Server upgrade secrets

The three `ntfy/*` values are created together, before the code that declares them is deployed
(sops-nix validates every declared key at build time). Run on tariognatha or tarmantria, where
the admin key can edit every server file. Nothing below is written to the repo in clear text.

```sh
# Two tokens (tk_ plus 29 characters) and two bcrypt password hashes. `ntfy user hash` asks for a
# password: for upgrade-publisher type any random string and forget it; for krane use a password
# you keep in the password manager, the phone's ntfy app logs in with it.
nix shell nixpkgs#ntfy-sh
PUB=$(ntfy token generate); READ=$(ntfy token generate)
PUB_HASH=$(ntfy user hash); KRANE_HASH=$(ntfy user hash)
ENVFILE=$(printf "NTFY_AUTH_USERS='upgrade-publisher:%s:user,krane:%s:user'\nNTFY_AUTH_ACCESS='upgrade-publisher:server-upgrades:write-only,krane:server-upgrades:read-only'\nNTFY_AUTH_TOKENS='upgrade-publisher:%s:publisher,krane:%s:reader'\n" "$PUB_HASH" "$KRANE_HASH" "$PUB" "$READ")

sops set secrets/taragarmr.yaml '["ntfy"]["server-env"]' "$(jq -Rs . <<<"$ENVFILE")"
for h in taragarmr taronychus tarritator tarronax; do
  sops set secrets/$h.yaml '["ntfy"]["publish-token"]' "\"$PUB\""
done
for h in tariognatha tarmantria taractias; do
  sops set secrets/$h.yaml '["ntfy"]["read-token"]' "\"$READ\""
done
```

The GitHub token (`server-upgrade/github-token`) is a fine-grained personal access token limited to
this repository with Issues: read and write; replace a lost or leaked one by creating a new token
and `sops set secrets/<host>.yaml '["server-upgrade"]["github-token"]' '"<token>"'` on the four
server files.
````

- [ ] **Step 2: Verify the docs render and nothing else changed**

Run: `git diff --stat` (only `secrets/README.md`), and `rg -n "ntfy" secrets/README.md | head` shows the four table rows and the how-to.

- [ ] **Step 3: Commit**

```bash
git add secrets/README.md
git commit -m "Document the server upgrade secrets"
```

- [ ] **Step 4: Rollout checklist (owner, manual; not an agent task)**

1. Create the ntfy values and add them to the seven files as in the README above (the `server-upgrade/github-token` is already in the four server files).
2. Push the commits to `main`; wait for `check.yml` and confirm `git ls-remote origin refs/heads/deploy` shows the head SHA.
3. Switch every server once, since auto-upgrade is not running yet: `just switch taragarmr` on taragarmr, `nixos-rebuild switch --flake .#<host> --target-host krane@<host> --sudo --ask-sudo-password` for the Pis; switch the three desktops for the subscriber. Check `systemctl list-timers nixos-upgrade.timer` on each server and `systemctl status ntfy-sh` on taragarmr.
4. Subscribe the phone's ntfy app to `server-upgrades` on `http://192.168.82.1:2586` (user `krane` and its password, instant delivery on). A test push: `curl -H "Authorization: Bearer <publish token>" -d test http://192.168.82.1:2586/server-upgrades` from a server must reach the phone and the desktops, and the same request with the read token must be refused (HTTP 403).
5. Failure drill on tarronax: temporarily set `krane.autoUpgrade.healthChecks = [ "false" ];` in `hosts/tarronax/default.nix`, push, wait for `deploy` to move, then `sudo systemctl start nixos-upgrade` on tarronax. Expect a rollback to the previous generation, one ntfy push and exactly one GitHub issue with a `failed` comment. Revert the line, push, start the service again: expect a recovery push, a `recovered` comment and the issue closing.
6. Kernel-change drill (optional): the first upgrade that changes a Pi's kernel should wait for its window, reboot once, and `journalctl -u server-upgrade-health -b` on the host should show the boot-time health check passing.

---

## Self-Review

**Spec coverage.**
- Goal 1 (PR covers four servers): Task 7. Goal 2 (every server runs latest gated main within about an hour): Tasks 4 (module), 8 (`deploy`). Goal 3 (failed upgrade leaves previous generation): Task 3 (`failed`, `boot-health`). Goal 4 (ntfy within minutes plus one issue per cycle): Tasks 2, 3 (`deliver`), 5, 6. Goal 5 (kernel changes the same night, one host at a time): Task 4 windows and eval checks.
- Components 1 to 6 and Secrets: 1 = Task 7 (spike = Task 1); 2 = Task 8; 3 = Task 4 (`mk-host.nix`); 4 = Tasks 3 and 4; 5 = Tasks 5 and 6; 6 = Task 2; Secrets = Task 9 plus the section-gated declarations in Tasks 4 to 6.
- Error-handling table: each row maps to a test (`condition:` skip rows, `failed:` build/activation/health stages, `boot-health:` rows, `deliver:` outbox rows, the `race:` and `superseded:` report rows).
- Testing section: the report tests (7 listed cases, all present), the hooks tests (6 listed, all present plus more), the eval checks (autoUpgrade per server, windows, health/OnFailure wiring, no desktop autoUpgrade) in Task 4, the two ntfy expectations (taragarmr only, WireGuard address, deny-all) in Task 5, CI verification steps 1 to 3 in Tasks 1, 7 and 8. Rollout: Task 9 step 4 (reordered, see deviation 4).
- Gap check: the spec's "`healthChecks` ... taragarmr adds a `curl` of its Caddy endpoints" is Task 4 step 5; the Pi ping is automatic in the module (deviation 6).

**Placeholder scan.** No TBD/TODO/"similar to". Host window values are listed explicitly per host; all code steps contain the code.

**Type consistency.** Subcommand names (`condition pre post failed boot-health deliver`) match between the script, the test, the module's `ExecStart*` lines and the flake expectations (`" post"`, `" condition"` suffixes). Env names (`HOST_NAME`, `HEALTH_CHECK`, `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN_FILE`, `GITHUB_TOKEN_FILE`, `REPORT_CMD`) match between `server-upgrade-hooks.sh` and `auto-upgrade.nix`. Message JSON fields (`kind host sha stage rolled_back title priority body ntfy_done github_done`) match between `queue`, `send_*` and the tests. Report argument order (`KIND HOST SHA STAGE ROLLED_BACK`) matches `send_github` and the report script. Secret names match across Tasks 4 to 6 and 9. Unit names (`server-upgrade-failed`, `server-upgrade-health`, `server-upgrade-notify`) match `OnFailure`, `systemctl start --no-block server-upgrade-notify.service` and the journal command.

**Review Focus.** All five lines have a named test; none left without one.
