# gym-league (Paul's app): Postgres 17 and the Spring backend, as docker containers on a
# dedicated network. Caddy (caddy.nix) proxies api-gymleague.paulbankl.dev to 127.0.0.1:8080;
# the backend is published on loopback only, so nothing else can reach it.
#
# Source: github.com/PaulBankl/GymLeague is public, so it is pinned with fetchFromGitHub
# (bump `rev` and `hash` to deploy a newer backend). A oneshot unit `docker build`s
# backend/Dockerfile from that store path into gymleague-backend:local before the container
# starts; the build downloads the Maven dependencies, so it needs network access (once per rev).
#
# Secrets: one sops env file, secret `gymleague/env` (secrets/taragarmr.yaml, section
# `gymleague`), read by both containers. Variable names, from the old Coolify deployment:
#   POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD    (postgres)
#   DB_URL, DB_USERNAME, DB_PASSWORD, SPRING_PROFILES_ACTIVE (backend)
# DB_URL must point at the container name: jdbc:postgresql://gymleague-postgres:5432/<db>.
# Without the section the whole module stays off, so the host evaluates before it is added.
#
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  enable = hostSecrets.hasSection "gymleague";

  src = pkgs.fetchFromGitHub {
    owner = "PaulBankl";
    repo = "GymLeague";
    # main at 2026-11-12.
    rev = "e033ed4529333da591e6a66f629e2f0e64c0426b";
    hash = "sha256-LZG+zzoxg0R4J4iGA6N1OnA/4zGqI3kYJy6Dj0DLX9Y=";
  };

  network = "gymleague";
  image = "gymleague-backend:local";
  dataDir = "/srv/gymleague";
  envFile = config.sops.secrets."gymleague/env".path;
  docker = lib.getExe config.virtualisation.docker.package;

  port = "8080";
in
{
  config = lib.mkIf enable {
    sops.secrets."gymleague/env" = {
      owner = "root";
      mode = "0400";
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
      # The postgres image's entrypoint chowns its data directory itself.
      "d ${dataDir}/postgres 0755 root root -"
      "d ${dataDir}/dumps 0700 root root -"
    ];

    systemd.services = {
      gymleague-network = {
        description = "docker network ${network}";
        after = [ "docker.service" ];
        requires = [ "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "gymleague-network" ''
            ${docker} network inspect ${network} >/dev/null 2>&1 || ${docker} network create ${network}
          '';
        };
      };

      gymleague-build = {
        description = "docker build gymleague-backend from the pinned GymLeague source";
        after = [
          "docker.service"
          "network-online.target"
        ];
        requires = [ "docker.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30min";
          ExecStart = pkgs.writeShellScript "gymleague-build" ''
            set -eu
            # The store path changes with every rev/hash bump: rebuild only then.
            have=$(${docker} image inspect --format '{{ index .Config.Labels "nix-src" }}' ${image} 2>/dev/null || true)
            if [ "$have" = "${src}" ]; then
              echo "${image} is up to date"
              exit 0
            fi
            # The Maven download inside the build needs the network. A retry loop here, not
            # Restart=on-failure: the backend Requires= this unit, and a failed start job of a
            # oneshot fails the backend's start with it, whatever Restart= does afterwards.
            # Bounded (5 tries, 30 s apart, well inside TimeoutStartSec), then the unit fails.
            for attempt in 1 2 3 4 5; do
              ${docker} build --label nix-src=${src} -t ${image} ${src}/backend && exit 0
              echo "docker build failed (attempt $attempt of 5)" >&2
              [ "$attempt" = 5 ] || ${pkgs.coreutils}/bin/sleep 30
            done
            exit 1
          '';
        };
      };

      docker-gymleague-postgres = {
        requires = [ "gymleague-network.service" ];
        after = [ "gymleague-network.service" ];
      };
      docker-gymleague-backend = {
        requires = [
          "gymleague-network.service"
          "gymleague-build.service"
        ];
        after = [
          "gymleague-network.service"
          "gymleague-build.service"
          "docker-gymleague-postgres.service"
        ];
      };

      gymleague-dump = {
        description = "pg_dump of the gym-league database";
        after = [ "docker-gymleague-postgres.service" ];
        path = [
          pkgs.coreutils
          pkgs.gzip
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "gymleague-dump" ''
            set -euo pipefail
            cd ${dataDir}/dumps
            out="gymleague-$(date +%F).sql.gz"
            ${docker} exec gymleague-postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' \
              | gzip > "$out.tmp"
            mv "$out.tmp" "$out"
            # Keep the newest 7.
            ls -1t gymleague-*.sql.gz | tail -n +8 | xargs -r rm --
          '';
        };
      };
    };

    systemd.timers.gymleague-dump = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "02:30";
        Persistent = true;
      };
    };

    virtualisation.oci-containers.containers = {
      gymleague-postgres = {
        image = "postgres:17";
        environmentFiles = [ envFile ];
        volumes = [ "${dataDir}/postgres:/var/lib/postgresql/data" ];
        extraOptions = [ "--network=${network}" ];
      };
      gymleague-backend = {
        inherit image;
        # Built locally by gymleague-build.service, never pulled.
        pull = "never";
        environmentFiles = [ envFile ];
        ports = [ "127.0.0.1:${port}:8080" ];
        dependsOn = [ "gymleague-postgres" ];
        extraOptions = [ "--network=${network}" ];
      };
    };
  };
}
