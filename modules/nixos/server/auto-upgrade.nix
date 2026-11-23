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
