# gym-league (Paul's app): Postgres 17 and the Spring backend, as docker containers on a
# dedicated network. taragarmr's Caddy proxies api-gymleague.paulbankl.dev to port 8080 here.
#
# Source: github.com/PaulBankl/GymLeague is public, so it is pinned with fetchFromGitHub
# (bump `rev` and `hash` to deploy a newer backend). A oneshot unit `docker build`s
# backend/Dockerfile from that store path into gymleague-backend:local before the container
# starts; the build downloads the Maven dependencies, so it needs network access (once per rev).
#
# Secrets: one sops env file, secret `gymleague/env` (secrets/taronychus.yaml, section
# `gymleague`), read by both containers. Variable names, from the old Coolify deployment:
#   POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD    (postgres)
#   DB_URL, DB_USERNAME, DB_PASSWORD, SPRING_PROFILES_ACTIVE (backend)
# DB_URL must point at the container name: jdbc:postgresql://gymleague-postgres:5432/<db>.
# Without the section the whole module stays off, so the host evaluates before step 8.
#
# 16K PAGE-SIZE RISK: the Pi 5 vendor kernel uses 16 KiB pages. Binaries bundling jemalloc
# built for 4 KiB pages (some postgres builds, Rust apps) may crash at startup there. The
# official postgres:17 image is Debian with glibc malloc and the backend is a JVM, so both
# are expected to be fine, but test them on taronychus first. Fallback: a 4K kernel
# (config.txt kernel=kernel8.img) or running gym-league on taragarmr.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  lan = import ../../lib/lan.nix;
  inherit (import ../../lib/wireguard.nix) wg0;
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

  # Backend clients: taragarmr's LAN address and wg0 address (Caddy runs there).
  proxyHosts = [
    lan.hosts.taragarmr
    wg0.hub.ip
  ];
  inIfaces = [
    "end0"
    "wg0"
  ];
  port = "8080";

  # Docker's published ports are DNATed and so bypass the NixOS firewall's INPUT rules; the
  # DOCKER-USER chain is the place to filter them. ctorigdstport is the port as the client
  # addressed it; only traffic arriving on the LAN and wg0 is filtered, so containers on
  # their bridge are unaffected.
  fwRules =
    action:
    let
      iptables = lib.getExe' pkgs.iptables "iptables";
      match = i: "-i ${i} -p tcp -m conntrack --ctorigdstport ${port} --ctdir ORIGINAL";
      # -I puts a rule at the top: the DROPs first, then the RETURNs above them.
      ins =
        rule:
        if action == "add" then
          "${iptables} -C DOCKER-USER ${rule} 2>/dev/null || ${iptables} -I DOCKER-USER ${rule}"
        else
          "${iptables} -D DOCKER-USER ${rule} 2>/dev/null || true";
    in
    pkgs.writeShellScript "gymleague-fw-${action}" ''
      ${lib.concatMapStringsSep "\n" (i: ins "${match i} -j DROP") inIfaces}
      ${lib.concatMapStringsSep "\n" (
        i: lib.concatMapStringsSep "\n" (s: ins "${match i} -s ${s} -j RETURN") proxyHosts
      ) inIfaces}
    '';
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
            ${docker} build --label nix-src=${src} -t ${image} ${src}/backend
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

      # Tied to the backend's lifecycle: the rules exist exactly while the published port does.
      gymleague-firewall = {
        description = "DOCKER-USER rules for the gym-league backend port";
        bindsTo = [ "docker-gymleague-backend.service" ];
        after = [ "docker-gymleague-backend.service" ];
        wantedBy = [ "docker-gymleague-backend.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = fwRules "add";
          ExecStop = fwRules "del";
        };
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
        ports = [ "0.0.0.0:${port}:8080" ];
        dependsOn = [ "gymleague-postgres" ];
        extraOptions = [ "--network=${network}" ];
      };
    };
  };
}
