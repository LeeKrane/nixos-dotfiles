# billion-context (`bili`), its config, and the MITM proxy service the `claude` fish function in
# modules/nixos/common/claude.nix points HTTPS_PROXY at. ~/.config/billion-context is not in
# ii's wipe set.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  port = "28787"; # bili launcher lanes use the 18787+ zone
  settings = {
    compress = {
      # Hard cap: the window bili budgets against, even if the model declares more.
      modelContextLimit = 400000;
      # Forced compression above 75% of 400K, the 300K soft target.
      maxContextLimit = "75%";
      # Emergency compression above 95%, last resort before the hard cap.
      emergencyThresholdPercent = "95%";
      # Few but deep compressions: wait for 300K of growth between nudges, and skip a
      # compression that would free less than 150K.
      nudgeGrowthTokens = 300000;
      minPressureBenefitTokens = 150000;
      # Only compress when the model was nudged, never unprompted.
      requireNudge = true;
    };
    # cacheKeepalive deliberately absent: no synthetic cache pings.

    # MITM only for Anthropic: Claude Code reaches the service via HTTPS_PROXY.
    mitm = {
      enabled = true;
      domains = [ "api.anthropic.com" ];
    };
    # Upstream leg: CONNECT through teamclaude (its MITM injects the seat auth), trusting its
    # CA for the TLS to api.anthropic.com. A per-URL proxy tops bili's proxy resolution order.
    providers."mitm://api.anthropic.com".proxy = "http://127.0.0.1:3456";
    network.caFile = "${config.xdg.configHome}/teamclaude-ca.pem";
  };
  configFile = pkgs.writeText "billion-context.json" (builtins.toJSON settings);
in
{
  home.packages = [ pkgs.billion-context ];

  # Copied, not a home.file symlink: the bili Web UI writes its settings (proxy, ...) to this
  # file, and a read-only store symlink would break that. Each activation resets it to the
  # declared values, so UI edits last until the next switch. Config path and plain-JSON
  # format per the package's docs/configuration.md. Before reloadSystemd, so the restart the
  # unit's X-Restart-Triggers causes reads the new file.
  home.activation.billionContextConfig =
    lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 ${configFile} "$HOME/.config/billion-context/billion-context.json"
      '';

  # Loopback only (no --host), foreground. Starts after teamclaude, which it chains to; like
  # teamclaude.nix, no network ordering and default.target. `start` creates the root CA claude
  # trusts (~/.local/share/billion-context/ca/root-ca.pem) at startup. teamclaude only creates
  # teamclaude-ca.pem (network.caFile above) on its first MITM CONNECT, so ExecStartPre makes
  # one: teamclaude answers its built-in www.example.org test host itself, with no credentials
  # and no upstream request (-k: that CA is not trusted yet). The grep for the PEM end marker
  # then makes the CA a hard precondition (teamclaude writes the cert-only file atomically,
  # tmp + rename in its mitm.js, so the marker means a complete file):
  # without it bili would start but fail every upstream TLS handshake, so
  # the unit fails instead and Restart=always retries until teamclaude is up. The restart
  # trigger restarts the service on a switch that changes the copied config, which its unit
  # text would not otherwise reflect.
  systemd.user.services.billion-context = {
    Unit = {
      Description = "billion-context MITM compression proxy for Claude Code";
      After = [ "teamclaude.service" ];
      Wants = [ "teamclaude.service" ];
      X-Restart-Triggers = [ "${configFile}" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStartPre = [
        "-${pkgs.curl}/bin/curl -sk -o /dev/null -m 10 --retry 5 --retry-connrefused --proxy http://127.0.0.1:3456 https://www.example.org/"
        "${pkgs.gnugrep}/bin/grep -q -e '-----END CERTIFICATE-----' ${settings.network.caFile}"
      ];
      ExecStart = "${pkgs.billion-context}/bin/bili-mitm-proxy start --port ${port}";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
