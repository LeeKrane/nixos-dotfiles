# Update Lanes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the weekly flake update into a server lane and a desktop lane. Each lane gets
its own branch and PR from the same workflow. A lane PR that conflicts after the other lane
merges regenerates by itself.

**Architecture:**
- `scripts/update-lanes.nix` says which flake inputs belong to which lane.
- `.github/workflows/update-lane.yml` is a reusable workflow: today's update/check/security/pr
  jobs, parameterized by `lane`.
- `update.yml` keeps the triggers and the concurrency group. It runs
  `scripts/update-select-lanes.sh` to pick lanes, then calls `update-lane.yml` once per lane
  through a matrix.
- PR bodies report only hosts whose toplevel drv changed. Host lists are collapsed by a
  shared jq function (`scripts/lib/collapse-hosts.jq`).
- The desktop notifier runs one systemd unit per lane.

**Tech Stack:** GitHub Actions, Nix (flakes, `nix eval`), bash, jq, home-manager systemd user
units.

**Spec:** `docs/superpowers/specs/2026-11-23-update-lanes-design.md`

## Global Constraints

- Lane branches: `ci/flake-update-servers` and `ci/flake-update-desktops`. Staging branches:
  `ci/flake-update-<lane>-staging`.
- Server-lane inputs: `nixos-raspberrypi home-manager-stable nixvim-stable sops-nix disko nix-index-database`.
  Only the server lane runs `scripts/update-claude-code.sh`.
- Desktop lane: every other updatable root input. Root inputs that are `follows` (a JSON list
  in `flake.lock`, e.g. `nixpkgs-stable`) belong to neither lane.
- Commit messages on lane branches: `Update server inputs and claude-code` and
  `Update desktop inputs`.
- PR titles: `Update server inputs` and `Update desktop inputs`, with the existing
  `[gate failing] ` prefix when the gate fails.
- Schedule `17 4 * * 1` runs both lanes. Dispatch input `lane`: `both` (default), `servers`
  or `desktops`. Push to `main` with paths `flake.lock` or `pkgs/claude-code/**` refreshes
  only lanes whose open PR is `CONFLICTING`.
- Poll for `mergeable`: every 10 s, for up to 120 s.
- Host collapsing:
  - every flake host gives `all`;
  - a complete role group gives `servers` or `desktops`;
  - leftover hosts follow the groups, by name, in input order.
- Notifier labels: `Server update` and `Desktop update`. Summary: `<LABEL> ready (#N)`, default
  `Flake update`.
- Files are created and changed only with Write/Edit, never with shell redirects. Commit
  messages are a subject line only, with no Claude attribution. Work on `main`, and never push
  unless the owner asks.
- New and changed shell scripts pass `shellcheck -x -S style` (`check.yml` lint job).

## Review Focus

1. A follows root input (`nixpkgs-stable`) must never be in a lane, because
   `nix flake update nixpkgs-stable` is not a real update. Pinned in Task 1.
2. A lane with no changed host must still render: collapsing `[]` gives an empty string, and
   the PR says "No host closure changed". Pinned in Tasks 2 and 5.
3. Running the summaries locally without `HOST_ROLES` must behave exactly as before. Pinned in
   Task 2.
4. `mergeable` can stay `UNKNOWN` forever. Then selection must end with `[]`, exit 0 and log
   a warning, not hang or fail. Pinned in Task 3.
5. A fork PR from a same-named branch must never select a lane. Pinned in Task 3.

---

### Task 1: Lane definition

**Files:**
- Create: `scripts/update-lanes.nix`
- Create: `scripts/tests/update-lanes-test.sh`
- Modify: `.github/workflows/check.yml` (lint job, after the `server-upgrade tests` step)

**Interfaces:**
- Produces: `import ./scripts/update-lanes.nix <parsed flake.lock>` gives
  `{ servers = [ string ]; desktops = [ string ]; }`, and throws when a server-lane name is
  not an updatable root input. CLI form:
  `nix eval --json --impure --expr 'import ./scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile ./flake.lock))'`.
  Task 5 uses this.

- [ ] **Step 1: Write the failing test** at `scripts/tests/update-lanes-test.sh`

```bash
#!/usr/bin/env bash
# Tests scripts/update-lanes.nix against a fixture lock and the real flake.lock. Run:
#   nix shell nixpkgs#jq --command bash scripts/tests/update-lanes-test.sh
set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")/../.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
lanes() { # lanes LOCKFILE: prints the lanes JSON, or fails
    nix eval --json --impure --expr \
        "import $ROOT/scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile $1))"
}

# Fixture: every server input, two desktop inputs and a follows input.
jq -n '{root: "root", version: 7, nodes: {root: {inputs: {
    "nixos-raspberrypi": "nixos-raspberrypi", "home-manager-stable": "home-manager-stable",
    "nixvim-stable": "nixvim-stable", "sops-nix": "sops-nix", "disko": "disko",
    "nix-index-database": "nix-index-database", "nixpkgs": "nixpkgs_5", "zen-browser": "zen-browser",
    "nixpkgs-stable": ["nixos-raspberrypi", "nixpkgs"]}}}}' >"$WORK/lock.json"
out="$(lanes "$WORK/lock.json")"
check 'fixture: servers' [ "$(jq -c '.servers | sort' <<<"$out")" = '["disko","home-manager-stable","nix-index-database","nixos-raspberrypi","nixvim-stable","sops-nix"]' ]
check 'fixture: desktops' [ "$(jq -c '.desktops | sort' <<<"$out")" = '["nixpkgs","zen-browser"]' ]
check 'fixture: follows input in no lane' [ "$(jq '[.servers[], .desktops[]] | index("nixpkgs-stable")' <<<"$out")" = null ]

# Unknown server-lane name: a lock without disko must fail evaluation.
jq 'del(.nodes.root.inputs.disko)' "$WORK/lock.json" >"$WORK/lock-nodisko.json"
check 'missing server input: eval fails' eval '! lanes "$WORK/lock-nodisko.json" >/dev/null 2>&1'

# Real lock: lanes partition the updatable root inputs exactly.
real="$(lanes "$ROOT/flake.lock")"
roots="$(jq -c '[.nodes[.root].inputs | to_entries[] | select(.value | type == "string") | .key] | sort' "$ROOT/flake.lock")"
check 'real: union is every updatable root' [ "$(jq -c '[.servers[], .desktops[]] | sort' <<<"$real")" = "$roots" ]
check 'real: no overlap' [ "$(jq '[.servers[] as $s | .desktops | index($s)] | map(select(. != null)) | length' <<<"$real")" = 0 ]

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
```

- [ ] **Step 2: Run it and verify that it fails**

Run: `nix shell nixpkgs#jq --command bash scripts/tests/update-lanes-test.sh`
Expected: FAIL lines (the file `scripts/update-lanes.nix` does not exist), exit 1.

- [ ] **Step 3: Write `scripts/update-lanes.nix`**

```nix
# Weekly update lanes (docs/superpowers/specs/2026-11-23-update-lanes-design.md). Takes the
# parsed flake.lock and returns { servers = [ input ]; desktops = [ input ]; }:
#   nix eval --json --impure --expr 'import ./scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile ./flake.lock))'
# servers: the stable channel (nixpkgs-stable moves with nixos-raspberrypi through its follows)
# plus the inputs both roles use. desktops: every other updatable root input, so a new input
# lands there by default. A `follows` root input (a list in flake.lock) is in neither lane: it
# moves with the input it follows.
lock:
let
  rootInputs = lock.nodes.${lock.root}.inputs;
  updatable = builtins.filter (n: builtins.isString rootInputs.${n}) (builtins.attrNames rootInputs);
  servers = [
    "nixos-raspberrypi"
    "home-manager-stable"
    "nixvim-stable"
    "sops-nix"
    "disko"
    "nix-index-database"
  ];
  unknown = builtins.filter (n: !(builtins.elem n updatable)) servers;
in
if unknown != [ ] then
  throw "update-lanes.nix: server-lane inputs not updatable root inputs of flake.lock: ${toString unknown}"
else
  {
    inherit servers;
    desktops = builtins.filter (n: !(builtins.elem n servers)) updatable;
  }
```

- [ ] **Step 4: Run the test and verify that it passes**

Run: `nix shell nixpkgs#jq --command bash scripts/tests/update-lanes-test.sh`
Expected: every line starts with `ok`, exit 0. Also run `nix fmt -- --check scripts/update-lanes.nix`
or the repo's `nixfmt`, if `just fmt` exists, and fix the formatting.

- [ ] **Step 5: Add the test to the CI lint job.** In `.github/workflows/check.yml`, after the
  `server-upgrade tests` step:

```yaml
      - name: update-lanes tests
        run: nix shell --inputs-from . nixpkgs#jq -c bash scripts/tests/update-lanes-test.sh
```

- [ ] **Step 6: Shellcheck and commit**

Run: `nix shell nixpkgs#shellcheck -c shellcheck -x -S style scripts/tests/update-lanes-test.sh`, expecting no output.

```bash
git add scripts/update-lanes.nix scripts/tests/update-lanes-test.sh .github/workflows/check.yml
git commit -m "Define the server and desktop update lanes"
```

---

### Task 2: Host-list collapsing in the PR summaries

**Files:**
- Create: `scripts/lib/collapse-hosts.jq`
- Create: `scripts/tests/collapse-hosts-test.sh`
- Modify: `scripts/update-summary.sh` (the `version-diff.jq` heredoc, about line 107, and its `jq` call, about line 142)
- Modify: `scripts/security-summary.sh` (the `grouped` function in the `diff.jq` heredoc, about lines 101-117, and its `jq` call, about line 119)
- Modify: `.github/workflows/check.yml` (lint job)

**Interfaces:**
- Produces: the jq module `collapse-hosts` (`-L scripts/lib`, `include "collapse-hosts";`)
  with `collapse_hosts($roles)`. It takes an array of host names as input, where `$roles` is
  `{host: role}` for every flake host, and returns a string.
- Produces: `update-summary.sh` and `security-summary.sh` read the optional env `HOST_ROLES`
  (JSON `{host: role}`). When it is unset, the output is unchanged from today. Task 5 sets it.

- [ ] **Step 1: Write the failing test** at `scripts/tests/collapse-hosts-test.sh`

```bash
#!/usr/bin/env bash
# Tests scripts/lib/collapse-hosts.jq and its use in update-summary.sh and security-summary.sh. Run:
#   nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/collapse-hosts-test.sh
set -euo pipefail

SCRIPTS="$(dirname "$(readlink -f "$0")")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
ROLES='{"taractias":"desktop","tariognatha":"desktop","tarmantria":"desktop","taragarmr":"server","taronychus":"server","tarritator":"server","tarronax":"server"}'
collapse() { # collapse JSON_ARRAY
    jq -rn -L "$SCRIPTS/lib" --argjson roles "$ROLES" --argjson h "$1" \
        'include "collapse-hosts"; $h | collapse_hosts($roles)'
}

check 'all hosts' [ "$(collapse '["taractias","tariognatha","tarmantria","taragarmr","taronychus","tarritator","tarronax"]')" = all ]
check 'servers' [ "$(collapse '["taragarmr","taronychus","tarritator","tarronax"]')" = servers ]
check 'desktops' [ "$(collapse '["tarmantria","taractias","tariognatha"]')" = desktops ]
check 'servers plus two desktops' [ "$(collapse '["taragarmr","taronychus","tarritator","tarronax","tariognatha","tarmantria"]')" = 'servers, tariognatha, tarmantria' ]
check 'single hosts only' [ "$(collapse '["taragarmr","taractias"]')" = 'taragarmr, taractias' ]
check 'empty list' [ "$(collapse '[]')" = '' ]

# update-summary.sh: a split version row names its hosts collapsed when HOST_ROLES is set,
# and plainly joined when it is not.
echo '{"nodes":{"root":{"inputs":{}}},"root":"root","version":7}' >"$WORK/lock.json"
jq -n '{taragarmr:{p:"1"},taronychus:{p:"1"},tarritator:{p:"1"},tarronax:{p:"1"},taractias:{p:"1"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' >"$WORK/before.json"
jq -n '{taragarmr:{p:"2"},taronychus:{p:"2"},tarritator:{p:"2"},tarronax:{p:"2"},taractias:{p:"3"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' >"$WORK/after.json"
with="$(HOST_ROLES="$ROLES" bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/before.json" "$WORK/after.json")"
without="$(bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/before.json" "$WORK/after.json")"
check 'update-summary: collapsed row' grep -qF '| p | 1 | 2 | servers |' <<<"$with"
check 'update-summary: no HOST_ROLES keeps join' grep -qF '| p | 1 | 2 | taragarmr, taronychus, tarritator, tarronax |' <<<"$without"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
```

Note: `update-summary.sh` sorts hosts by `keys`, which is alphabetical:
`taragarmr, taronychus, tarritator, tarronax`. That makes the expected `without` row
deterministic. If the exact row format differs from `| p | 1 | 2 | ... |`, check it with
`bash -x` and adjust only the expected string, not the script's format.

- [ ] **Step 2: Run it and verify that it fails**

Run: `nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/collapse-hosts-test.sh`
Expected: FAIL lines (the module is missing), exit 1.

- [ ] **Step 3: Write `scripts/lib/collapse-hosts.jq`**

```jq
# collapse_hosts($roles): an array of host names -> one display string for PR bodies
# (docs/superpowers/specs/2026-11-23-update-lanes-design.md, "Host list collapsing").
# $roles is {host: role} for EVERY host of the flake (lib.hostMeta), so "all" means the whole
# flake, not the hosts a lane touched. A complete role group shows as its role plus "s"
# ("servers", "desktops"); hosts outside a complete group follow by name, in input order.
def collapse_hosts($roles):
  . as $hs
  | ($roles | keys) as $all
  | if ($hs | length) == 0 then ""
    elif ($all - $hs | length) == 0 then "all"
    else
      ([$roles[]] | unique) as $roleNames
      | [ $roleNames[] as $r
          | [$roles | to_entries[] | select(.value == $r) | .key] as $members
          | select(($members - $hs | length) == 0)
          | { name: ($r + "s"), members: $members } ] as $full
      | [$full[].members[]] as $covered
      | ([$full[].name] + [$hs[] | select((. as $h | $covered | any(.[]; . == $h)) | not)])
      | join(", ")
    end;
```

- [ ] **Step 4: Use it in `scripts/update-summary.sh`**
  - Below `set -euo pipefail`, add `LIB="$(dirname "$(readlink -f "$0")")/lib"`.
  - In the `version-diff.jq` heredoc, add `include "collapse-hosts";` as its first line.
  - Change
    `| map({ before: .[0].before, after: .[0].after, hosts: (map(.host) | join(", ")) })` to:

```jq
      | map({ before: .[0].before, after: .[0].after,
              hosts: (map(.host) | if $roles == null then join(", ") else collapse_hosts($roles) end) })
```

Change the call that uses it:

```bash
  version_diff="$(jq -n -L "$LIB" \
    --argjson roles "${HOST_ROLES:-null}" \
    --slurpfile before "$VERSIONS_BEFORE" \
    --slurpfile after "$VERSIONS_AFTER" -f "$WORKDIR/version-diff.jq")"
```

- [ ] **Step 5: Use it in `scripts/security-summary.sh`.** Below `set -euo pipefail`, add
  `LIB="$(dirname "$(readlink -f "$0")")/lib"`. Put `include "collapse-hosts";` as the first
  line of the `diff.jq` heredoc. In `grouped`, replace

```jq
      hosts: (map(.host) | unique
        | if length == $nhosts then "all" else join(", ") end),
```

with

```jq
      hosts: (map(.host) | unique
        | if $roles != null then collapse_hosts($roles)
          elif length == $nhosts then "all" else join(", ") end),
```

Then update the comment above `def grouped` so its last sentence reads: "With HOST_ROLES set,
the hosts are collapsed against the whole flake (scripts/lib/collapse-hosts.jq). Without it,
a group spanning every scanned host shows "all"." Add `-L "$LIB" --argjson roles "${HOST_ROLES:-null}"`
to the `diff_json="$(jq -n ...` call. Add to the usage comment at the top: `#   HOST_ROLES  optional env, {host: role} JSON for every flake host: collapses host lists`.
Add the same line to `update-summary.sh`'s usage comment.

- [ ] **Step 6: Run the test and verify that it passes**

Run: `nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/collapse-hosts-test.sh`
Expected: every line `ok`, exit 0.

- [ ] **Step 7: Add the test to the CI lint job** in `.github/workflows/check.yml`, after the
  `update-lanes tests` step:

```yaml
      - name: collapse-hosts tests
        run: nix shell --inputs-from . nixpkgs#jq nixpkgs#gawk -c bash scripts/tests/collapse-hosts-test.sh
```

- [ ] **Step 8: Shellcheck and commit**

Run: `nix shell nixpkgs#shellcheck -c shellcheck -x -S style scripts/update-summary.sh scripts/security-summary.sh scripts/tests/collapse-hosts-test.sh`, expecting no output.

```bash
git add scripts/lib/collapse-hosts.jq scripts/tests/collapse-hosts-test.sh scripts/update-summary.sh scripts/security-summary.sh .github/workflows/check.yml
git commit -m "Collapse PR host lists to all, servers and desktops"
```

---

### Task 3: Lane selection

**Files:**
- Create: `scripts/update-select-lanes.sh`
- Create: `scripts/tests/update-select-lanes-test.sh`
- Modify: `.github/workflows/check.yml` (lint job)

**Interfaces:**
- Produces: `scripts/update-select-lanes.sh`, which prints a compact JSON array of lanes to
  stdout. Env:
  - `EVENT`: `schedule`, `workflow_dispatch` or `push`.
  - `LANE_INPUT`: `both`, `servers` or `desktops`, for dispatch.
  - `POLL_INTERVAL` (default 10) and `POLL_DEADLINE` (default 120).
  - `gh` reads `GH_TOKEN` and `GH_REPO`.
  - Unknown events or lanes exit 1.
  Task 5 calls it.

- [ ] **Step 1: Write the failing test** at `scripts/tests/update-select-lanes-test.sh`

```bash
#!/usr/bin/env bash
# Tests scripts/update-select-lanes.sh with `gh` and `sleep` stubbed on PATH. Run:
#   nix shell nixpkgs#jq --command bash scripts/tests/update-select-lanes-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../update-select-lanes.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fix"
failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# gh stub: `gh pr list --head BRANCH ... --jq EXPR`. Answers with line N of
# $FIX/<branch>.json on the Nth call for that branch (the last line repeats), or [] when the
# file is missing, and applies EXPR with the real jq like gh does.
command cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
head="" expr="."
while [ "$#" -gt 0 ]; do
    case "$1" in
        --head) head="$2"; shift 2 ;;
        --jq) expr="$2"; shift 2 ;;
        *) shift ;;
    esac
done
f="$FIX/${head//\//_}.json"
[ -f "$f" ] || { jq -r "$expr" <<<'[]'; exit 0; }
n=$(( $(command cat "$f.calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$f.calls"
total=$(wc -l <"$f")
[ "$n" -le "$total" ] || n=$total
sed -n "${n}p" "$f" | jq -r "$expr"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$WORK/bin/sleep"
chmod +x "$WORK/bin/gh" "$WORK/bin/sleep"

pr() { # pr MERGEABLE [CROSS=false]: one gh pr list JSON line
    jq -cn --arg m "$1" --argjson x "${2:-false}" '[{mergeable: $m, isCrossRepository: $x}]'
}
run() { # run ENV=VAL...: sets $out and $status; fixtures are reset by the caller
    status=0
    out="$(env PATH="$WORK/bin:$PATH" FIX="$WORK/fix" "$@" bash "$SCRIPT" 2>"$WORK/stderr")" || status=$?
}
reset() { rm -f "$WORK/fix/"*; }

run EVENT=schedule
check 'schedule: both' [ "$out" = '["servers","desktops"]' ]
run EVENT=workflow_dispatch LANE_INPUT=both
check 'dispatch both' [ "$out" = '["servers","desktops"]' ]
run EVENT=workflow_dispatch LANE_INPUT=desktops
check 'dispatch desktops' [ "$out" = '["desktops"]' ]
run EVENT=workflow_dispatch LANE_INPUT=nope
check 'dispatch unknown lane fails' [ "$status" -eq 1 ]
run EVENT=pull_request
check 'unsupported event fails' [ "$status" -eq 1 ]

reset
pr CONFLICTING >"$WORK/fix/ci_flake-update-desktops.json"
pr MERGEABLE >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push
check 'push: conflicting lane only' [ "$out" = '["desktops"]' ]

reset
run EVENT=push
check 'push: no open PRs' [ "$out" = '[]' ]
check 'push: no open PRs exit 0' [ "$status" -eq 0 ]

reset
{ pr UNKNOWN; pr UNKNOWN; pr CONFLICTING; } >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push
check 'push: UNKNOWN then CONFLICTING' [ "$out" = '["servers"]' ]

reset
pr UNKNOWN >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push POLL_INTERVAL=10 POLL_DEADLINE=30
check 'push: UNKNOWN until deadline selects nothing' [ "$out" = '[]' ]
check 'push: UNKNOWN until deadline exit 0' [ "$status" -eq 0 ]
check 'push: UNKNOWN until deadline warns' grep -q '::warning::' "$WORK/stderr"
check 'push: polled 4 times' [ "$(command cat "$WORK/fix/ci_flake-update-servers.json.calls")" = 4 ]

reset
pr CONFLICTING true >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push
check 'push: fork PR ignored' [ "$out" = '[]' ]

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
```

The deadline case polls at waited = 0, 10, 20 and 30. At 30 the deadline is reached, so
there are exactly 4 calls.

- [ ] **Step 2: Run it and verify that it fails**

Run: `nix shell nixpkgs#jq --command bash scripts/tests/update-select-lanes-test.sh`
Expected: FAIL lines (the script is missing).

- [ ] **Step 3: Write `scripts/update-select-lanes.sh`**

```bash
#!/usr/bin/env bash
# Prints the JSON list of update lanes .github/workflows/update.yml runs
# (docs/superpowers/specs/2026-11-23-update-lanes-design.md, "Triggers and lane selection").
#   EVENT          schedule | workflow_dispatch | push
#   LANE_INPUT     dispatch only: both (default) | servers | desktops
#   POLL_INTERVAL  seconds between mergeability polls (default 10)
#   POLL_DEADLINE  seconds to keep polling an UNKNOWN answer (default 120)
# On push (a lane PR merged), only lanes whose open same-repo PR now conflicts are selected:
# GitHub computes `mergeable` lazily, so UNKNOWN is polled until the deadline, then skipped
# with a warning (next Monday's run or a dispatch refreshes it). gh reads GH_TOKEN/GH_REPO.
set -euo pipefail

: "${EVENT:?EVENT must be set}"
case "$EVENT" in
    schedule)
        echo '["servers","desktops"]'
        exit 0
        ;;
    workflow_dispatch)
        case "${LANE_INPUT:-both}" in
            both) echo '["servers","desktops"]' ;;
            servers | desktops) printf '["%s"]\n' "$LANE_INPUT" ;;
            *)
                echo "unknown lane: $LANE_INPUT" >&2
                exit 1
                ;;
        esac
        exit 0
        ;;
    push) ;;
    *)
        echo "unsupported event: $EVENT" >&2
        exit 1
        ;;
esac

interval="${POLL_INTERVAL:-10}"
deadline="${POLL_DEADLINE:-120}"

# NONE when the lane has no open PR from this repo (fork PRs with the same branch name don't count).
mergeable() {
    gh pr list --head "ci/flake-update-$1" --base main --state open \
        --json mergeable,isCrossRepository \
        --jq '[.[] | select(.isCrossRepository | not)][0].mergeable // "NONE"'
}

selected=()
for lane in servers desktops; do
    waited=0
    while :; do
        state="$(mergeable "$lane")"
        if [ "$state" != UNKNOWN ] || [ "$waited" -ge "$deadline" ]; then break; fi
        sleep "$interval"
        waited=$((waited + interval))
    done
    case "$state" in
        CONFLICTING) selected+=("$lane") ;;
        UNKNOWN) echo "::warning::$lane update PR still UNKNOWN after ${deadline}s, not refreshed" >&2 ;;
    esac
done
jq -cn '$ARGS.positional' --args "${selected[@]}"
```

- [ ] **Step 4: Run the test and verify that it passes**

Run: `nix shell nixpkgs#jq --command bash scripts/tests/update-select-lanes-test.sh`
Expected: every line `ok`, exit 0. If `jq --args` with an empty array prints `[]` on one line,
the "no open PRs" check passes. If not, fix the script, not the test.

- [ ] **Step 5: Add the test to the CI lint job** in `.github/workflows/check.yml`, after the
  `collapse-hosts tests` step:

```yaml
      - name: update-select-lanes tests
        run: nix shell --inputs-from . nixpkgs#jq -c bash scripts/tests/update-select-lanes-test.sh
```

- [ ] **Step 6: Shellcheck and commit**

```bash
chmod +x scripts/update-select-lanes.sh
nix shell nixpkgs#shellcheck -c shellcheck -x -S style scripts/update-select-lanes.sh scripts/tests/update-select-lanes-test.sh
git add scripts/update-select-lanes.sh scripts/tests/update-select-lanes-test.sh .github/workflows/check.yml
git commit -m "Select update lanes per trigger, refreshing only conflicting lane PRs"
```

---

### Task 4: Notifier per lane

**Files:**
- Modify: `scripts/flake-update-notify.sh` (header comment lines 1-12, `state_file` about line 17, `summary` about lines 89-95)
- Modify: `scripts/tests/flake-update-notify-test.sh` (`STATE_FILE` about line 40; new cases at the end, before the final failure check)
- Modify: `modules/home/desktop/flake-update-notify.nix`

**Interfaces:**
- Consumes: the branch names `ci/flake-update-servers` and `ci/flake-update-desktops` (Global
  Constraints).
- Produces: the script reads env `LABEL` (default `Flake update`) and keeps its state file at
  `$XDG_STATE_HOME/flake-update-notify/last-seen-<BRANCH with every character outside [A-Za-z0-9._-] replaced by ->`.
  For example, `ci/flake-update-servers` gives `last-seen-ci-flake-update-servers`.

- [ ] **Step 1: Write the failing tests.** In `scripts/tests/flake-update-notify-test.sh`, change
  `STATE_FILE="$WORK/state/flake-update-notify/last-seen"` to
  `STATE_FILE="$WORK/state/flake-update-notify/last-seen-ci-flake-update"`. Then append before
  the script's final failure summary:

```bash
# lanes: LABEL names the lane in the summary; each branch keeps its own dedupe state
rm -rf "$WORK/state"
pr_json lane1 'Update server inputs' "$VERSIONS_BODY" 12
run LABEL='Server update' BRANCH=ci/flake-update-servers
check 'lane: summary uses LABEL' notify_has 'Server update ready (#12)'
check 'lane: state per branch' [ -f "$WORK/state/flake-update-notify/last-seen-ci-flake-update-servers" ]
pr_json lane1 'Update desktop inputs' "$VERSIONS_BODY" 13
run LABEL='Desktop update' BRANCH=ci/flake-update-desktops
check 'lane: other branch not deduped by first' notified
check 'lane: desktop summary' notify_has 'Desktop update ready (#13)'
pr_json lane1 '[gate failing] Update server inputs' "$VERSIONS_BODY" 14
rm -f "$WORK/state/flake-update-notify/last-seen-ci-flake-update-servers"
run LABEL='Server update' BRANCH=ci/flake-update-servers
check 'lane: gate failing summary' notify_has 'Server update ready (#14) (gate failing)'
```

`run` passes its arguments after the defaults to `env`, so `BRANCH=...` overrides
`BRANCH=ci/flake-update`. The second lane uses the same head SHA (`lane1`) on purpose: it
proves that dedupe is per branch.

- [ ] **Step 2: Run it and verify that it fails**

Run: `nix shell nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/flake-update-notify-test.sh`
Expected: FAIL on the `state written` checks (still `last-seen`) and on the new `lane:` checks.

- [ ] **Step 3: Change the script.**
  - In the header env table, below the `BRANCH` line, add:
    `#   LABEL                  notification summary prefix, e.g. "Server update"   optional`.
  - Replace `state_file="$state_dir/last-seen"` with:

```bash
# One state file per branch: each update lane (ci/flake-update-servers, -desktops) dedupes alone.
state_file="$state_dir/last-seen-$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' -)"
label="${LABEL:-Flake update}"
```

  - Replace both summary assignments: `summary="Flake update ready (#$number)"` becomes
    `summary="$label ready (#$number)"`, and the gate-failing one becomes
    `summary="$label ready (#$number) (gate failing)"`.

- [ ] **Step 4: Run the test and verify that it passes**

Run: `nix shell nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/flake-update-notify-test.sh`
Expected: every line `ok`, exit 0.

- [ ] **Step 5: Make one unit per lane in the module.** In
  `modules/home/desktop/flake-update-notify.nix`:
  - Change the function header to `{ lib, pkgs, ... }:`.
  - Add `lanes = { servers = "Server update"; desktops = "Desktop update"; };` to the `let`.
  - Replace the two attribute definitions `systemd.user.services.flake-update-notify = { ... };`
    and `systemd.user.timers.flake-update-notify = { ... };` with:

```nix
  # One unit per update lane (docs/superpowers/specs/2026-11-23-update-lanes-design.md), so
  # each lane keeps its own retry and once-per-head state.
  systemd.user.services = lib.mapAttrs' (
    lane: label:
    lib.nameValuePair "flake-update-notify-${lane}" {
      # (the existing service body, unchanged, except:)
      #   Unit.Description = "Notify about a pending ${lib.toLower label} pull request";
      #   Service.Environment = [ "REPO=${repo}" "BRANCH=ci/flake-update-${lane}" "LABEL=${label}" ];
    }
  ) lanes;

  systemd.user.timers = lib.mapAttrs' (
    lane: label:
    lib.nameValuePair "flake-update-notify-${lane}" {
      # (the existing timer body, unchanged, except:)
      #   Unit.Description = "Daily check for a pending ${lib.toLower label} pull request";
    }
  ) lanes;
```

  Move the existing bodies, with all their comments, into those two places verbatim, apply the
  listed field changes, and delete the placeholder comment lines. In the file's header comment,
  change "has an update pull request open" to "has an update pull request open (one unit per
  lane: servers, desktops)", and add the new spec to its "See" line.

- [ ] **Step 6: Evaluate a desktop host**

Run: `nix eval .#nixosConfigurations.tariognatha.config.home-manager.users.krane.systemd.user.services --apply builtins.attrNames --json | jq -c '[.[] | select(startswith("flake-update-notify"))]'`
Expected: `["flake-update-notify-desktops","flake-update-notify-servers"]`. If the user
attribute is not `krane`, use `config.home-manager.users` with `builtins.attrNames` first.
Also run `nix build .#flake-update-notify --no-link` (the package wraps the script) and expect
success.

- [ ] **Step 7: Shellcheck and commit**

```bash
nix shell nixpkgs#shellcheck -c shellcheck -x -S style scripts/flake-update-notify.sh scripts/tests/flake-update-notify-test.sh
git add scripts/flake-update-notify.sh scripts/tests/flake-update-notify-test.sh modules/home/desktop/flake-update-notify.nix
git commit -m "Notify per update lane with its own label and state"
```

---

### Task 5: Lane workflows

**Files:**
- Create: `.github/workflows/update-lane.yml`
- Modify: `.github/workflows/update.yml` (replace entirely)

**Interfaces:**
- Consumes:
  - `scripts/update-lanes.nix` (Task 1);
  - `HOST_ROLES` support in both summaries and `scripts/lib/collapse-hosts.jq` (Task 2);
  - `scripts/update-select-lanes.sh` (Task 3);
  - the branch names the notifier watches (Task 4).
- Produces: branches `ci/flake-update-<lane>`, `ci/flake-update-<lane>-staging` and one open PR
  per lane.

- [ ] **Step 1: Write `.github/workflows/update-lane.yml`.** Start from today's `update.yml`
  jobs (`git show HEAD:.github/workflows/update.yml`) and keep every comment that still holds.
  The full file:

```yaml
name: update-lane

# One lane of the weekly update (docs/superpowers/specs/2026-11-23-update-lanes-design.md),
# called by update.yml once per selected lane: bump the lane's inputs on
# ci/flake-update-<lane>, gate it with check.yml, report CVEs and local builds for the hosts
# whose closure changed, then create or edit the lane's pull request. No concurrency group
# here: update.yml's group already serialises runs, and a called workflow sharing the
# caller's group deadlocks.
on:
  workflow_call:
    inputs:
      lane:
        description: servers or desktops
        type: string
        required: true

permissions: {}

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    outputs:
      # Set only by the final step, after the update commit has been pushed. A failure
      # anywhere earlier fails the job and this output stays unset, so check/security/pr
      # never run against a half-done push (or last week's staging branch).
      changed: ${{ steps.push.outputs.changed }}
      sha: ${{ steps.push.outputs.sha }}
      # JSON list of the hosts whose toplevel drvPath this update changed.
      hosts: ${{ steps.evals.outputs.hosts }}
      roles: ${{ steps.meta.outputs.roles }}
    env:
      LANE: ${{ inputs.lane }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: main
      - uses: cachix/install-nix-action@75c75c31ebece974e48ebc36b4ad125bd97bd97b # v31.11.3
      - name: Host roles and lane inputs
        id: meta
        run: |
          # {host: role} for every host, the Pis included: drives the changed-host evals and
          # the host-list collapsing in the PR body (scripts/lib/collapse-hosts.jq).
          nix eval --json '.#lib.hostMeta' --apply 'builtins.mapAttrs (n: v: v.role)' > "$RUNNER_TEMP/roles.json"
          echo "roles=$(command cat "$RUNNER_TEMP/roles.json")" >> "$GITHUB_OUTPUT"
          nix eval --json --impure --expr \
            'import ./scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile ./flake.lock))' \
            > "$RUNNER_TEMP/lanes.json"
          echo "inputs=$(jq -r --arg l "$LANE" '.[$l] | join(" ")' "$RUNNER_TEMP/lanes.json")" >> "$GITHUB_OUTPUT"
      - name: Save old flake.lock
        run: cp flake.lock "$RUNNER_TEMP/flake.lock.old"
      - name: Update lane inputs
        env:
          INPUTS: ${{ steps.meta.outputs.inputs }}
        run: |
          set -o pipefail
          # shellcheck disable=SC2086 # INPUTS is a space-separated list of input names
          nix flake update $INPUTS 2>&1 | tee "$RUNNER_TEMP/update.log"
          # pkgs/claude-code is installed on servers too, so it rides the server lane.
          if [ "$LANE" = servers ]; then
            scripts/update-claude-code.sh 2>&1 | tee -a "$RUNNER_TEMP/update.log"
          fi
      - name: Check for changes
        id: diff
        run: |
          if [ -z "$(git status --porcelain -- flake.lock pkgs/claude-code)" ]; then
            echo "Nothing to update."
            echo "haschanges=false" >> "$GITHUB_OUTPUT"
          else
            echo "haschanges=true" >> "$GITHUB_OUTPUT"
          fi
      - name: Save updated flake.lock and claude-code
        if: steps.diff.outputs.haschanges == 'true'
        run: |
          cp flake.lock "$RUNNER_TEMP/flake.lock.new"
          rm -rf "$RUNNER_TEMP/claude-code.new"
          cp -r pkgs/claude-code "$RUNNER_TEMP/claude-code.new"
      - name: Evaluate changed hosts and package versions
        id: evals
        if: steps.diff.outputs.haschanges == 'true'
        env:
          ROLES_JSON: ${{ steps.meta.outputs.roles }}
        run: |
          # shellcheck disable=SC2016 # ${h} is Nix antiquotation, not a shell variable
          drvs='cfgs: let hosts = builtins.attrNames (builtins.fromJSON (builtins.getEnv "ROLES_JSON")); in builtins.listToAttrs (map (h: { name = h; value = cfgs.${h}.config.system.build.toplevel.drvPath; }) hosts)'
          versions='cfgs: import ./scripts/update-versions.nix cfgs (builtins.fromJSON (builtins.getEnv "HOSTS_JSON"))'
          nix eval --json --impure '.#nixosConfigurations' --apply "$drvs" > "$RUNNER_TEMP/drvs-after.json"
          # The update commit hasn't happened yet, so HEAD still holds the pre-update
          # content. If pkgs/claude-code is new (untracked at HEAD), restore fails on it with
          # "pathspec did not match" instead of deleting it: the step fails fail-safe,
          # before anything is committed or pushed.
          git restore --source=HEAD --worktree -- flake.lock pkgs/claude-code
          nix eval --json --impure '.#nixosConfigurations' --apply "$drvs" > "$RUNNER_TEMP/drvs-before.json"
          HOSTS_JSON="$(jq -cn --slurpfile a "$RUNNER_TEMP/drvs-after.json" --slurpfile b "$RUNNER_TEMP/drvs-before.json" \
            '$a[0] as $A | $b[0] as $B | [$A | keys[] | select($A[.] != $B[.])]')"
          export HOSTS_JSON
          echo "hosts=$HOSTS_JSON" >> "$GITHUB_OUTPUT"
          nix eval --json --impure '.#nixosConfigurations' --apply "$versions" > "$RUNNER_TEMP/versions-before.json"
          # Put the updated state back, so the versions-after eval and the commit see it.
          rm -rf pkgs/claude-code
          cp "$RUNNER_TEMP/flake.lock.new" flake.lock
          cp -r "$RUNNER_TEMP/claude-code.new" pkgs/claude-code
          nix eval --json --impure '.#nixosConfigurations' --apply "$versions" > "$RUNNER_TEMP/versions-after.json"
      - name: Render summary
        if: steps.diff.outputs.haschanges == 'true'
        env:
          HOST_ROLES: ${{ steps.meta.outputs.roles }}
        run: |
          scripts/update-summary.sh "$RUNNER_TEMP/flake.lock.old" flake.lock \
            "$RUNNER_TEMP/versions-before.json" "$RUNNER_TEMP/versions-after.json" \
            "$RUNNER_TEMP/update.log" > "$RUNNER_TEMP/summary.md"
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        if: steps.diff.outputs.haschanges == 'true'
        with:
          # Both lanes share one workflow run, so every artifact name carries the lane.
          name: update-summary-${{ inputs.lane }}
          path: ${{ runner.temp }}/summary.md
          retention-days: 7
          overwrite: true
      - name: Commit and push
        id: push
        if: steps.diff.outputs.haschanges == 'true'
        run: |
          git config user.name 'github-actions[bot]'
          git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
          git add flake.lock pkgs/claude-code
          if [ "$LANE" = servers ]; then
            git commit -m 'Update server inputs and claude-code'
          else
            git commit -m 'Update desktop inputs'
          fi
          # Pushed to a staging branch, not ci/flake-update-<lane> directly: the pr job moves
          # the lane branch to this exact commit only after it has built the PR body, so the
          # branch's head and its PR's body change together.
          git push --force origin "HEAD:refs/heads/ci/flake-update-$LANE-staging"
          echo "changed=true" >> "$GITHUB_OUTPUT"
          echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"

  check:
    needs: update
    if: needs.update.outputs.changed == 'true'
    # A called workflow gets at most what its caller grants; check.yml's nvim job asks for
    # pull-requests: read.
    permissions:
      contents: read
      pull-requests: read
    uses: ./.github/workflows/check.yml
    with:
      ref: ${{ needs.update.outputs.sha }}
      force-nvim: true
```

  Then append the `security` and `pr` jobs. Copy them from today's `update.yml`, with exactly
  these changes:
  - **security**
    - `if:` becomes
      `needs.update.outputs.changed == 'true' && needs.update.outputs.hosts != '[]'`.
    - Every `HOSTS_JSON: ${{ needs.update.outputs.hosts }}` stays as it is. It is now the
      changed-host list.
    - In the "Render summary" step, add the env
      `HOST_ROLES: ${{ needs.update.outputs.roles }}`.
    - Artifact names become `security-summary-${{ inputs.lane }}` and
      `local-builds-${{ inputs.lane }}`.
  - **pr**
    - Download `update-summary-${{ inputs.lane }}` and `security-summary-${{ inputs.lane }}`.
    - Upload `pr-body-full-${{ inputs.lane }}`.
    - The "Move" step becomes
      `git push --force origin "$SHA":"refs/heads/ci/flake-update-$LANE"`, with
      `LANE: ${{ inputs.lane }}` added to its env.
    - The "Create or update" step uses `--head "ci/flake-update-$LANE"` in both `gh pr list`
      and `gh pr create`, with `LANE` in its env.
    - In "Build pull request body", add to env:
      `LANE: ${{ inputs.lane }}`, `HOSTS: ${{ needs.update.outputs.hosts }}` and
      `ROLES: ${{ needs.update.outputs.roles }}`. Replace the script with:

```bash
          if [ "$LANE" = servers ]; then title='Update server inputs'; else title='Update desktop inputs'; fi
          if [ "$RESULT" != success ]; then
            title="[gate failing] $title"
          fi
          case "$RESULT" in
            success) gate='✅ passed' ;;
            failure) gate='❌ failing' ;;
            *) gate="$RESULT" ;;
          esac
          # Desktop-lane bumps can reach servers (unstable.codegraph in modules/home/server).
          servers_hit="$(jq -rn -L scripts/lib --argjson roles "$ROLES" --argjson hosts "$HOSTS" \
            'include "collapse-hosts"; [$hosts[] | select($roles[.] == "server")] | collapse_hosts($roles)')"
          body="$RUNNER_TEMP/body.md"
          {
            if [ "$LANE" = servers ]; then
              echo '**Merging deploys to every server within about an hour (promote.yml moves deploy).**'
              echo
            elif [ -n "$servers_hit" ]; then
              echo "**Also changes: $servers_hit (user profile).**"
              echo
            fi
            echo "Gate: $gate ([run]($RUN_URL))"
            echo
            if [ "$HOSTS" = '[]' ]; then
              echo 'No host closure changed.'
              echo
            fi
            command cat "$RUNNER_TEMP/summary.md"
            echo
            if [ "$SECURITY_RESULT" = success ]; then
              command cat "$RUNNER_TEMP/security-summary.md"
              echo
              echo "Full local-build logs: \`local-builds-$LANE\` artifact on [this run]($RUN_URL)."
            elif [ "$SECURITY_RESULT" != skipped ]; then
              echo "Security scan failed ([run]($RUN_URL))"
            fi
            echo
            echo 'CI checks eval only. Before merging, on one machine, run:'
            echo
            if [ "$LANE" = servers ]; then host=taragarmr; else host='<host>'; fi
            # Two fenced blocks, so GitHub gives each command its own copy button.
            # shellcheck disable=SC2016 # literal backticks for Markdown
            printf '```sh\n%s\n```\n\n```sh\n%s\n```\n' \
              "git fetch origin ci/flake-update-$LANE && git switch -C ci/flake-update-$LANE FETCH_HEAD" \
              "just switch $host"
            echo
            echo 'Checks do not appear on this pull request: it is opened with GITHUB_TOKEN, which triggers no workflows. Merging runs the gate on main.'
          } > "$body"
          echo "title=$title" >> "$GITHUB_OUTPUT"
```

    The `security-summary-<lane>` download keeps
    `if: needs.security.result == 'success'`. The `pr` job's `if:` stays
    `${{ !cancelled() && needs.update.outputs.changed == 'true' }}`.

- [ ] **Step 2: Replace `.github/workflows/update.yml`** with:

```yaml
name: update

# Weekly flake update in two lanes, one PR each
# (docs/superpowers/specs/2026-11-23-update-lanes-design.md): servers (stable channel, shared
# inputs, claude-code) and desktops (everything else). update-lane.yml does a lane's work.
on:
  schedule:
    - cron: '17 4 * * 1'
  workflow_dispatch:
    inputs:
      lane:
        description: Lanes to update
        type: choice
        options: [both, servers, desktops]
        default: both
  # A merged lane PR can leave the other lane's PR conflicting on flake.lock: refresh only
  # that lane (scripts/update-select-lanes.sh decides).
  push:
    branches: [main]
    paths:
      - flake.lock
      - 'pkgs/claude-code/**'

# A manual run or conflict refresh queues behind a running one instead of racing it on the
# lane branches.
concurrency:
  group: update
  cancel-in-progress: false

permissions: {}

jobs:
  select:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    outputs:
      lanes: ${{ steps.select.outputs.lanes }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Select lanes
        id: select
        env:
          EVENT: ${{ github.event_name }}
          LANE_INPUT: ${{ inputs.lane }}
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
        run: echo "lanes=$(scripts/update-select-lanes.sh)" >> "$GITHUB_OUTPUT"

  lane:
    needs: select
    if: needs.select.outputs.lanes != '[]'
    strategy:
      fail-fast: false
      matrix:
        lane: ${{ fromJSON(needs.select.outputs.lanes) }}
    # The most any job in update-lane.yml needs; each of its jobs narrows this down.
    permissions:
      contents: write
      pull-requests: write
    uses: ./.github/workflows/update-lane.yml
    with:
      lane: ${{ matrix.lane }}
```

- [ ] **Step 3: Lint the workflows**

Run: `nix shell nixpkgs#actionlint nixpkgs#shellcheck -c actionlint .github/workflows/update.yml .github/workflows/update-lane.yml .github/workflows/check.yml .github/workflows/promote.yml`
Expected: no output. actionlint runs shellcheck on every `run:` block, so fix whatever it
reports.

- [ ] **Step 4: Dry-run the lane logic locally** in a scratch clone (never in `~/.dotfiles`):

```bash
T="$CLAUDE_JOB_DIR/tmp/lane-dry"; rm -rf "$T"; git clone -q ~/.dotfiles "$T"; cd "$T"
inputs="$(nix eval --json --impure --expr 'import ./scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile ./flake.lock))' | jq -r '.desktops | join(" ")')"
nix flake update $inputs
git diff --stat
```

Expected: only `flake.lock` changes. `git diff flake.lock | grep -c nixos-raspberrypi` prints
0, because the server inputs don't move. Use `/tmp` if `CLAUDE_JOB_DIR` is unset.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/update.yml .github/workflows/update-lane.yml
git commit -m "Split the weekly update into server and desktop lane PRs"
```

---

### Task 6: Migration (only after the owner pushes `main`)

**Files:** none. These are GitHub-side steps. Do not push to make this happen: ask the owner,
who pushes.

- [ ] **Step 1: Confirm that the push landed and that `check` passed on main**

Run: `gh run list --workflow check --branch main --limit 1`
Expected: `completed success` for the pushed head.

- [ ] **Step 2: Close the old PR and delete the old branches**

```bash
n=$(gh pr list --head ci/flake-update --base main --state open --json number,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)][0].number // empty')
[ -z "$n" ] || gh pr close "$n" --comment "Replaced by the per-lane update PRs (ci/flake-update-servers, ci/flake-update-desktops)." --delete-branch
git push origin --delete ci/flake-update-staging || true
```

- [ ] **Step 3: Open both lane PRs**

Run: `gh workflow run update -f lane=both`, then `gh run watch` on that run.
Expected:
- a green run with two `lane` matrix legs;
- PRs `Update server inputs` and `Update desktop inputs` from `ci/flake-update-servers` and
  `ci/flake-update-desktops`, or one of them missing if that lane had nothing to update;
- the server PR body starts with the deploy warning;
- host lists read `servers`, `desktops`, `all` or a mix, never seven names.

- [ ] **Step 4: Rebuild a desktop and check the notifier units**

Run on a desktop: `just switch <host>`, then
`systemctl --user list-timers 'flake-update-notify-*'`.
Expected: two timers, `-servers` and `-desktops`. The old `flake-update-notify.timer` is gone.

- [ ] **Step 5: Exercise the conflict refresh, when it first happens.** No action is needed.
  The first time a merged lane leaves the other PR `CONFLICTING`, the push-triggered `update`
  run shows one `lane` leg. A clean week shows a green `select` with no `lane` legs.
