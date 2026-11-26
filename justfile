# "in docker" recipes run Nix in the throwaway container of scripts/docker-check.sh; the rest need local Nix.
# Container defaults: 6 CPUs, 14g memory. Override with env vars, e.g.
#   DOCKER_CPUS=12 DOCKER_MEMORY=28g NIX_MAX_JOBS=4 just docker-build tariognatha

default: check

# nix flake check and all hosts' toplevel, --dry-run, in docker.
check:
    scripts/docker-check.sh check

# Single-host eval only, no build, for iterating without waiting on the others.
eval-host HOST:
    scripts/docker-check.sh eval {{ HOST }}

# Real build of one host's toplevel, in docker, slow, see docs/INSTALL.md.
docker-build HOST:
    scripts/docker-check.sh build {{ HOST }}

# Removes the nixstore docker volume.
docker-clean:
    docker volume rm nixstore

# nix fmt over the whole tree, in docker.
fmt:
    scripts/docker-check.sh fmt

# scripts/lint.sh (nixfmt, statix, deadnix, shellcheck, actionlint, secrets guard), in docker.
lint:
    scripts/docker-check.sh lint

# Runs every scripts/tests/*-test.sh with CI's deps and lists failures at the end, needs local Nix.
test:
    #!/usr/bin/env bash
    set -u
    nix shell --inputs-from . nixpkgs#curl nixpkgs#jq nixpkgs#gawk -c bash -c 'failed=; for t in scripts/tests/*-test.sh; do bash "$t" || failed="$failed $t"; done; [ -z "$failed" ] || { echo "failed:$failed" >&2; exit 1; }'

# CI's lint job, scripts/lint.sh then just test, needs local Nix. Host evals and flake check: just check.
ci:
    scripts/lint.sh
    just test

# install.sh --self-test and four --dry-run runs of it, in docker.
install-test:
    scripts/docker-check.sh install-test

# Scaffolds a throwaway testhost per GPU profile x form factor in a temporary worktree of HEAD and evaluates each, needs local Nix, commit first.
check-new-host:
    scripts/check-new-host.sh

# Opens secrets/HOST.yaml in $EDITOR through sops; HOST defaults to this machine, a path (with /) opens that file; not in docker.
sops-edit HOST=`hostname`:
    sops {{ if HOST =~ '/' { HOST } else { "secrets/" + HOST + ".yaml" } }}

# Runs the NixVim build from this checkout without switching, from the current directory, e.g. `just nvim flake.nix`. New modules need `git add` first.
[no-cd]
[positional-arguments]
nvim *ARGS:
    nix run "{{ justfile_directory() }}#nvim" -- "$@"

# nix flake update in docker, writes flake.lock back into the repo.
update:
    scripts/docker-check.sh update

# Bumps only claude-code, newest by default or `just update-claude 2.1.278`.
update-claude VERSION="":
    scripts/update-claude-code.sh {{ VERSION }}

# nix flake lock in docker, only adds missing entries.
lock:
    scripts/docker-check.sh lock

# Applies this machine's configuration (by hostname) with nixos-rebuild; use switch-remote for other hosts.
switch:
    sudo nixos-rebuild switch --flake .#$(hostname)

# Switches HOST over ssh (servers and Pis outside auto-upgrade, e.g. the first switch); builds locally, so aarch64 Pis need binfmt or a builder.
switch-remote HOST USER="krane":
    nixos-rebuild switch --flake .#{{ HOST }} --target-host {{ USER }}@{{ HOST }} --sudo --ask-sudo-password

# Wakes tariognatha from suspend by sending a magic packet from tarronax, its neighbor on the second LAN.
wake-tariognatha:
    ssh tarronax wake-tariognatha

# Enables the pre-push lint hook (.githooks/pre-push) in this checkout.
hooks:
    git config core.hooksPath .githooks

# Like switch, but activates on next boot only, HOST defaults to this machine.
boot HOST=`hostname`:
    sudo nixos-rebuild boot --flake .#{{ HOST }}

# Like switch, but activates without making it the boot default, HOST defaults to this machine.
test-switch HOST=`hostname`:
    sudo nixos-rebuild test --flake .#{{ HOST }}

# Builds HOST's toplevel and diffs its closure against /run/current-system, HOST defaults to this machine, needs local Nix, run on the target host.
diff HOST=`hostname`:
    #!/usr/bin/env bash
    set -eu
    link=$(mktemp -u -p "${TMPDIR:-/tmp}" diff-{{ HOST }}-XXXXXX)
    trap 'rm -f "$link"' EXIT
    nix build .#nixosConfigurations.{{ HOST }}.config.system.build.toplevel --out-link "$link"
    nix store diff-closures /run/current-system "$link"

# Builds the tariognatha-vm QEMU/UEFI image in docker (llvmpipe only: proves wiring, not real GPU or boot).
vm:
    scripts/docker-check.sh vm
