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

# Derived the same way install.sh derives GPU_PROFILES and FORM_FACTORS: the
# file names under templates/host/profiles/ and templates/host/form-factors/.
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
