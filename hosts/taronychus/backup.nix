# taronychus' own backup: the gym-league database dumps (/srv/gymleague/dumps, written 02:30 by
# gymleague.nix) go to this host's own REST server, so they exist in a repository that
# tarritator copies offsite (the dumps themselves never leave this host otherwise).
#
# The repository is rest:...@<wg0 IP>:8000/taronychus, the same append-only server the other
# clients use, and is pruned by restic-prune.nix like the others. Secrets: restic/rest-env
# (RESTIC_REST_USERNAME=taronychus, RESTIC_REST_PASSWORD=..., matching an entry in
# restic/htpasswd) and restic/repo-password (this repository's password; restic-prune.nix
# reuses it for the prune). Needs both the restic and gymleague sections.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  inherit (import ../../lib/wireguard.nix) wg0;
in
{
  config = lib.mkIf (hostSecrets.hasSection "restic" && hostSecrets.hasSection "gymleague") {
    sops.secrets."restic/rest-env" = {
      owner = "root";
      mode = "0400";
    };
    # Declared by restic-prune.nix (owner restic, which root can read as well).

    krane.backup = {
      enable = true;
      repository = "rest:http://taronychus@${wg0.peers.taronychus.ip}:8000/taronychus";
      passwordFile = config.sops.secrets."restic/repo-password".path;
      environmentFile = config.sops.secrets."restic/rest-env".path;
      pruneOpts = [ ];
      paths = [ "/srv/gymleague/dumps" ];
      # After the 02:30 dump.
      timerConfig = {
        OnCalendar = "03:30";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };

    # The repository host listens on wg0's address; the interface has to be up first.
    systemd.services.restic-backups-default = {
      after = [ "wg-quick-wg0.service" ];
      wants = [ "wg-quick-wg0.service" ];
    };
  };
}
