#!/usr/bin/env bash
# Usage: just check-new-host. Needs local Nix with flakes; tests HEAD in a detached worktree, not uncommitted changes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILES=()
for _f in "$REPO_ROOT"/templates/host/profiles/*.nix.in; do
    PROFILES+=("$(basename "$_f" .nix.in)")
done
mapfile -t PROFILES < <(printf '%s\n' "${PROFILES[@]}" | sort)
FORM_FACTORS=()
for _f in "$REPO_ROOT"/templates/host/form-factors/*.nix.in; do
    FORM_FACTORS+=("$(basename "$_f" .nix.in)")
done
mapfile -t FORM_FACTORS < <(printf '%s\n' "${FORM_FACTORS[@]}" | sort)
unset _f
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

fail() {
    echo "FAIL $1" >&2
    if [ -n "${2:-}" ]; then
        tail -n 20 "$2" >&2
    fi
    failures=$((failures + 1))
}

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
        # CI runs `nix fmt -- --ci`, so a new host must already be formatted.
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

expect "user" "krane.user.name" "$USER_NAME"
expect "user" "users.users.$USER_NAME.home" "/home/$USER_NAME"
expect "home-manager" "home-manager.users.$USER_NAME.home.username" "$USER_NAME"
expect "git" "home-manager.users.$USER_NAME.programs.git.settings.user.name" "$GIT_NAME"
expect "git" "home-manager.users.$USER_NAME.programs.git.settings.user.email" "$GIT_EMAIL"
expect "autologin" "services.greetd.settings.initial_session.user" "$USER_NAME"
expect "hostname" "networking.hostName" "$HOST"
expect "disko" "disko.devices.disk.main.device" "$FAKE_DISK"

test -f "$WT/hosts/$HOST/illogical-impulse/.gitignore" \
    || fail "scaffold: hosts/$HOST/illogical-impulse/.gitignore is missing"
test -f "$WT/hosts/$HOST/ii-settings.json" \
    || fail "scaffold: hosts/$HOST/ii-settings.json is missing"

if [ "$failures" -ne 0 ]; then
    echo "check-new-host: $failures failures" >&2
    exit 1
fi
echo "check-new-host: all ${#PROFILES[@]}x${#FORM_FACTORS[@]} combinations evaluate"
