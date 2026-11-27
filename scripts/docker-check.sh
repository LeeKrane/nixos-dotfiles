#!/usr/bin/env bash
# Usage:
#   scripts/docker-check.sh              full check, flake check plus all hosts' toplevel, --dry-run
#   scripts/docker-check.sh build HOST   real build of one host's toplevel, slow
#   scripts/docker-check.sh vm           build the tariognatha-vm QEMU/UEFI image
#   scripts/docker-check.sh eval HOST    print HOST's toplevel drvPath, eval only
#   scripts/docker-check.sh fmt          nix fmt the whole tree
#   scripts/docker-check.sh lint         scripts/lint.sh, the CI lint checks
#   scripts/docker-check.sh update       nix flake update, writes flake.lock back into the repo
#   scripts/docker-check.sh lock         nix flake lock, adds missing entries without bumping existing pins
#   scripts/docker-check.sh install-test self-test and dry-run install.sh, see justfile's install-test
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="nixos/nix:latest"
VOLUME="nixstore"

NIX_CONFIG_VALUE="experimental-features = nix-command flakes
filter-syscalls = false
max-jobs = ${NIX_MAX_JOBS:-2}
cores = ${NIX_CORES:-3}"

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

# Flakes only see tracked files: tracked edits need no staging, new files need intent-to-add (records the path without staging content).
track_new_files() {
    git ls-files -z --others --exclude-standard | xargs -0 -r git add -N --
}

run_in_container() {
    track_new_files
    docker run --rm \
        "${DOCKER_RESOURCE_ARGS[@]}" \
        -v "$REPO_ROOT:/work" -w /work \
        -v "$VOLUME:/nix" \
        -e NIX_CONFIG="$NIX_CONFIG_VALUE" \
        "$IMAGE" sh -c "
            git config --global --add safe.directory /work
            $1
        " || {
        local rc=$?
        [ "$rc" -eq 137 ] && echo "Container was OOM-killed at DOCKER_MEMORY=${DOCKER_MEMORY:-14g}; nix flake check needs about 5 GiB. Run it on a host with more free RAM." >&2
        return "$rc"
    }
}

# The host list comes from the flake (scripts/hosts.nix): x86_64-linux hosts only, as the container cannot build aarch64 toplevels.
HOSTS=()
HOSTS_PIPE=""
load_hosts() {
    local list
    list=$(run_in_container "nix eval --raw --impure .#lib.hostMeta --apply 'm: toString (import ./scripts/hosts.nix m)'")
    read -r -a HOSTS <<<"$list"
    HOSTS_PIPE=$(
        IFS='|'
        echo "${HOSTS[*]}"
    )
}

mode="${1:-check}"

host_mem_kib=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
requested_mem="${DOCKER_MEMORY:-14g}"
case "$requested_mem" in
    *g) requested_kib=$((${requested_mem%g} * 1024 * 1024)) ;;
    *m) requested_kib=$((${requested_mem%m} * 1024)) ;;
    *) requested_kib=0 ;;
esac
if [ "$requested_kib" -gt "$host_mem_kib" ]; then
    echo "DOCKER_MEMORY=$requested_mem exceeds this host's $((host_mem_kib / 1024 / 1024)) GiB RAM; the container would be OOM-killed. Set DOCKER_MEMORY lower." >&2
    exit 1
fi

seed_volume_if_missing

case "$mode" in
    check)
        load_hosts
        # shellcheck disable=SC2016 # expands inside the container's sh, not here
        run_in_container '
            set -eu
            # lua-syntax first: it realizes the applyPatches sources (IFD) that --no-build cannot build.
            nix build --no-link .#checks.x86_64-linux.lua-syntax
            nix flake check --no-build --show-trace
            for h in '"${HOSTS[*]}"'; do
                nix build .#nixosConfigurations.$h.config.system.build.toplevel --dry-run
            done
        '
        ;;
    build)
        load_hosts
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
        load_hosts
        host="${2:-}"
        if [ -z "$host" ]; then
            echo "usage: $0 eval <$HOSTS_PIPE>" >&2
            exit 1
        fi
        run_in_container "nix eval .#nixosConfigurations.$host.config.system.build.toplevel.drvPath"
        ;;
    fmt)
        run_in_container 'nix fmt'
        ;;
    lint)
        run_in_container 'bash scripts/lint.sh'
        ;;
    update)
        run_in_container 'nix flake update'
        ;;
    lock)
        run_in_container 'nix flake lock'
        ;;
    install-test)
        # install.sh has no build-time check. The --dry-run runs exit 0 without hardware via soft_fail; the git-state assertion fails if they
        # leave a staged change, a new commit or hosts/newbox/. The two existing hosts take patch_disko_file's "already patched" branch.
        track_new_files
        before_status=$(git status --porcelain | sort | md5sum)
        before_head=$(git rev-parse HEAD)
        # shellcheck disable=SC2016 # the disk lookups expand inside the container, not here
        run_in_container '
            set -eu
            nix shell nixpkgs#bash nixpkgs#gum nixpkgs#gnugrep nixpkgs#gnused nixpkgs#gawk nixpkgs#findutils nixpkgs#util-linux nixpkgs#coreutils nixpkgs#diffutils nixpkgs#git nixpkgs#btrfs-progs --command bash -c '"'"'
                set -eu
                ./install.sh --help >/dev/null
                ./install.sh --self-test
                ./install.sh --mode install --host taractias --disk "$(awk -F\" "/device = /{print \$2; exit}" hosts/taractias/disko.nix)" --yes --dry-run
                ./install.sh --mode install --host tarmantria --disk "$(awk -F\" "/device = /{print \$2; exit}" hosts/tarmantria/disko.nix)" --yes --dry-run
                ./install.sh --mode install --new-host newbox --user alice --profile intel-nvidia-prime --form-factor laptop --disk /dev/null --yes --dry-run
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
        echo "usage: $0 [check|build <host>|vm|eval <host>|fmt|lint|update|lock|install-test]" >&2
        exit 1
        ;;
esac
