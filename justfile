# Common tasks for this flake. check and docker-* route Nix through the
# throwaway container in scripts/docker-check.sh, working with or
# without local Nix installed. switch, vm and sops-edit need a real
# Nix-enabled machine, the target host itself or a dev machine.
# The docker container is capped by default, 6 CPUs, 14g memory, low CPU
# shares. Override with env vars, for example:
#   DOCKER_CPUS=12 DOCKER_MEMORY=28g NIX_MAX_JOBS=4 just docker-build tariognatha

default: check

# Flake check and all hosts' toplevel, --dry-run, in docker.
check: docker-check

# Single-host eval only, no build, for iterating without waiting on the others.
eval-host HOST:
    scripts/docker-check.sh eval {{ HOST }}

# Creates and seeds the nixstore docker volume, other recipes do this too.
docker-seed:
    scripts/docker-check.sh seed

# nix flake check and all hosts' toplevel, --dry-run, in docker.
docker-check:
    scripts/docker-check.sh check

# Real build of one host's toplevel, in docker, slow, see docs/INSTALL.md.
docker-build HOST:
    scripts/docker-check.sh build {{ HOST }}

# Removes the nixstore docker volume, the only place this repo ever deletes it.
docker-clean:
    docker volume rm nixstore

# nix fmt, nixfmt-rfc-style, over the whole tree, in docker.
fmt:
    scripts/docker-check.sh fmt

# statix check and deadnix, report-only, in docker.
lint:
    scripts/docker-check.sh lint

# bash -n, shellcheck and three --dry-run runs of install.sh, in docker.
install-lint:
    scripts/docker-check.sh shellcheck

# Opens FILE in $EDITOR through sops, never routed through the docker sandbox.
sops-edit FILE:
    sops {{ FILE }}

# nix flake update, in docker, writes flake.lock back into the repo, review the diff before committing.
update:
    scripts/docker-check.sh update

# nix flake lock, in docker, only adds missing entries, never bumps pins.
lock:
    scripts/docker-check.sh lock

# Applies HOST's configuration with a real nixos-rebuild, not docker, run this on the target host itself.
switch HOST:
    sudo nixos-rebuild switch --flake .#{{ HOST }}

# Builds the tariognatha-vm QEMU/UEFI image in docker, llvmpipe only, proves wiring not real GPU or boot.
vm:
    scripts/docker-check.sh vm
