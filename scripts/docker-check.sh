#!/usr/bin/env bash
# Runs nix flake check and nix build inside a throwaway nixos/nix
# container, against a persistent nixstore docker volume. Never install
# or run Nix on the host itself. Never removes the nixstore volume,
# that only happens in the docker-clean justfile recipe.
# Usage:
#   scripts/docker-check.sh              full check, flake check plus all hosts' toplevel, --dry-run
#   scripts/docker-check.sh seed         create and seed the nixstore volume, idempotent
#   scripts/docker-check.sh build HOST   real build of one host's toplevel, slow
#   scripts/docker-check.sh vm           build the tariognatha-vm QEMU/UEFI image
#   scripts/docker-check.sh eval HOST    print HOST's toplevel drvPath, eval only
#   scripts/docker-check.sh fmt          nix fmt the whole tree
#   scripts/docker-check.sh lint         statix check plus deadnix, report only
#   scripts/docker-check.sh update       nix flake update, writes flake.lock back into the repo
#   scripts/docker-check.sh lock         nix flake lock, adds missing entries without bumping existing pins
#   scripts/docker-check.sh shellcheck   lint and dry-run install.sh, see justfile's install-lint
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="nixos/nix:latest"
VOLUME="nixstore"

# hosts/ is the single source of truth here, same as flake.nix's hosts
# and bootstrap-sops.sh's known_hosts().
HOSTS=()
for d in "$REPO_ROOT"/hosts/*/; do
    HOSTS+=("$(basename "$d")")
done
HOSTS_PIPE=$(
    IFS='|'
    echo "${HOSTS[*]}"
)
# filter-syscalls=false works around seccomp restrictions on the Nix
# sandbox. max-jobs/cores match the cgroup limits below, so Nix backs off
# instead of the cgroup OOM-killing it. Override with NIX_MAX_JOBS/NIX_CORES.
NIX_CONFIG_VALUE="experimental-features = nix-command flakes
filter-syscalls = false
max-jobs = ${NIX_MAX_JOBS:-2}
cores = ${NIX_CORES:-3}"

# Caps every docker run to a fixed slice of the host. Override per
# invocation, for example DOCKER_CPUS=12 DOCKER_MEMORY=28g just docker-build tariognatha.
DOCKER_RESOURCE_ARGS=(
    --cpus "${DOCKER_CPUS:-6}"
    --cpu-shares "${DOCKER_CPU_SHARES:-256}"
    --memory "${DOCKER_MEMORY:-14g}"
    # --memory-swap equals --memory so the container is OOM-killed instead of swap-thrashing the host.
    --memory-swap "${DOCKER_MEMORY:-14g}"
)

seed_volume_if_missing() {
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        return
    fi
    echo "==> Creating and seeding docker volume '$VOLUME' (first run only)"
    docker volume create "$VOLUME" >/dev/null
    docker run --rm "${DOCKER_RESOURCE_ARGS[@]}" -v "$VOLUME:/seed" "$IMAGE" sh -c 'cp -a /nix/. /seed/'
}

run_in_container() {
    # git add -A stages every edit, since flakes only see tracked/staged files.
    git add -A
    docker run --rm \
        "${DOCKER_RESOURCE_ARGS[@]}" \
        -v "$REPO_ROOT:/work" -w /work \
        -v "$VOLUME:/nix" \
        -e NIX_CONFIG="$NIX_CONFIG_VALUE" \
        "$IMAGE" sh -c "
            # libgit2 refuses an unowned bind-mounted repo without this.
            git config --global --add safe.directory /work
            $1
        "
}

mode="${1:-check}"

seed_volume_if_missing

case "$mode" in
    seed)
        # seed_volume_if_missing above already did the work.
        ;;
    check)
        # Only the host list is spliced in here, $h expands in the container's sh.
        run_in_container '
            set -eu
            nix flake check --no-build --show-trace
            nix eval .#nixosConfigurations.tariognatha.pkgs.gnome-icon-theme.pname
            for h in '"${HOSTS[*]}"'; do
                nix build .#nixosConfigurations.$h.config.system.build.toplevel --dry-run
            done
        '
        ;;
    build)
        host="${2:-}"
        if [ -z "$host" ]; then
            echo "usage: $0 build <$HOSTS_PIPE>" >&2
            exit 1
        fi
        run_in_container "nix build .#nixosConfigurations.$host.config.system.build.toplevel"
        ;;
    vm)
        run_in_container 'nix build .#nixosConfigurations.tariognatha-vm.config.system.build.vm'
        ;;
    eval)
        host="${2:-}"
        if [ -z "$host" ]; then
            echo "usage: $0 eval <$HOSTS_PIPE>" >&2
            exit 1
        fi
        run_in_container "nix eval .#nixosConfigurations.$host.config.system.build.toplevel.drvPath"
        ;;
    fmt)
        # nix fmt with no path reads empty stdin instead of the tree, so pass "." explicitly.
        run_in_container 'nix fmt -- .'
        ;;
    lint)
        # Report-only, each check falls through to status=1 instead of aborting.
        run_in_container '
            set -eu
            status=0
            nix run nixpkgs#statix -- check . || status=1
            nix run nixpkgs#deadnix -- . || status=1
            exit "$status"
        '
        ;;
    update)
        run_in_container 'nix flake update'
        ;;
    lock)
        # Unlike update, only adds entries missing from flake.lock.
        # Writes it back host-side, root-owned, git add/chown it like any file.
        run_in_container 'nix flake lock'
        ;;
    shellcheck)
        # install.sh's equivalent of check above, since it has no
        # build-time check of its own. --self-test proves run_sh honours
        # pipefail, the ERR trap, and the disko/PRIME sed helpers. The
        # three --dry-run runs cover install mode's plain and PRIME
        # branches plus setup mode, exiting 0 with no real hardware via
        # soft_fail. Wrapped in a git-state assertion: these must not
        # leave a staged change or a new commit behind.
        git add -A
        before_status=$(git status --porcelain | sort | md5sum)
        before_head=$(git rev-parse HEAD)
        run_in_container '
            set -eu
            nix shell nixpkgs#bash nixpkgs#shellcheck nixpkgs#gum nixpkgs#gnugrep nixpkgs#gnused nixpkgs#findutils nixpkgs#util-linux nixpkgs#coreutils nixpkgs#git --command bash -c '"'"'
                set -eu
                bash -n install.sh
                shellcheck -x -S style install.sh
                ./install.sh --self-test
                ./install.sh --mode install --host taractias --disk /dev/null --yes --dry-run
                ./install.sh --mode install --host tarmantria --disk /dev/null --yes --dry-run
                ./install.sh --mode setup --host taractias --yes --dry-run
            '"'"'
        '
        after_status=$(git status --porcelain | sort | md5sum)
        after_head=$(git rev-parse HEAD)
        if [ "$before_status" != "$after_status" ] || [ "$before_head" != "$after_head" ]; then
            echo "error: git state changed while running install.sh's dry-run tests" >&2
            echo "  HEAD:   before=$before_head after=$after_head" >&2
            echo "  status: before=$before_status after=$after_status" >&2
            exit 1
        fi
        ;;
    *)
        echo "usage: $0 [seed|check|build <host>|vm|eval <host>|fmt|lint|update|lock|shellcheck]" >&2
        exit 1
        ;;
esac
