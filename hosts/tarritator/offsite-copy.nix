# The 2 TB USB HDD and the daily pull of taronychus' restic repositories onto it: taragarmr's
# (CouchDB, SPT) and taronychus' own (gym-league dumps), each into /mnt/backup/restic/<repo>.
# Every local copy shares the password restic/offsite-repo-password; the sources are opened
# with restic/repo-password-<repo>.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  hasRestic = hostSecrets.hasSection "restic";
  inherit (import ../../lib/wireguard.nix) wg0;

  mount = "/mnt/backup";
  repos = [
    "taragarmr"
    "taronychus"
  ];
  localRepo = repo: "${mount}/restic/${repo}";
  # The REST user and password come from the env file (RESTIC_REST_USERNAME/RESTIC_REST_PASSWORD),
  # so the URL carries no credentials.
  sourceRepo = repo: "rest:http://${wg0.peers.taronychus.ip}:8000/${repo}";
  retention = lib.concatStringsSep " " (import ../../lib/backup-retention.nix).offsite;
  secret = name: config.sops.secrets."restic/${name}".path;
in
{
  # Format the disk once with: mkfs.ext4 -L backup2tb /dev/sdX1
  # nofail + automount: the Pi boots without the disk (it is not attached yet, and may be
  # unplugged); the mount happens on first access and gives up after 5 s.
  fileSystems.${mount} = {
    device = "/dev/disk/by-label/backup2tb";
    fsType = "ext4";
    options = [
      "nofail"
      "noatime"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
    ];
  };

  sops.secrets = lib.mkIf hasRestic (
    lib.genAttrs
      (
        [
          "restic/rest-env"
          "restic/offsite-repo-password"
        ]
        ++ map (r: "restic/repo-password-${r}") repos
      )
      (_: {
        owner = "root";
        mode = "0400";
      })
  );

  systemd.services.restic-offsite-copy = lib.mkIf hasRestic {
    description = "restic copy: taronychus -> ${mount}/restic";
    # Skip cleanly (condition, not failure) while the HDD is not attached. The condition is on
    # the device node, not on the mount point or RequiresMountsFor: the automount unit is a
    # mount point even with no disk behind it, and RequiresMountsFor would turn the failed
    # mount into a failed job. The script touches the path to trigger the automount and then
    # insists on a real mount.
    unitConfig.ConditionPathExists = "/dev/disk/by-label/backup2tb";
    after = [
      "network-online.target"
      "wg-quick-wg0.service"
    ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.restic
      pkgs.util-linux
      pkgs.coreutils
    ];
    environment.RESTIC_CACHE_DIR = "/var/cache/restic-offsite";
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "restic-offsite";
      EnvironmentFile = secret "rest-env";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    script = ''
      set -eu
      ls ${mount} >/dev/null # triggers the automount
      mountpoint -q ${mount} || { echo "${mount} did not mount" >&2; exit 1; }
      export RESTIC_PASSWORD_FILE=${secret "offsite-repo-password"}
      rc=0
      ${lib.concatMapStringsSep "\n" (repo: ''
        (
          set -eu
          echo "== ${repo}"
          from="--from-repo ${sourceRepo repo} --from-password-file ${secret "repo-password-${repo}"}"
          if ! restic cat config --repo ${localRepo repo} >/dev/null 2>&1; then
            # The offsite repository gets its own password; copy needs the source chunker
            # parameters to deduplicate identically, so it is initialised from the source.
            mkdir -p ${localRepo repo}
            restic init --repo ${localRepo repo} $from --copy-chunker-params
          fi
          restic copy --retry-lock 2h --repo ${localRepo repo} $from
          # Retention is applied to the offsite copy only, never from the clients.
          restic forget --prune --retry-lock 2h --repo ${localRepo repo} ${retention}
        ) || rc=1
      '') repos}
      exit $rc
    '';
  };

  systemd.timers.restic-offsite-copy = lib.mkIf hasRestic {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "06:00";
      Persistent = true;
    };
  };
}
