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
      # One function per repository: every step ends in an explicit `|| return 1`, as set -e is
      # ignored in a function called on the left of `||`. A failed repository sets rc and the
      # loop goes on with the next one, so the unit still fails at the end.
      copy_repo() {
        repo=$1
        local_repo=$2
        src=$3
        pwfile=$4
        echo "== $repo"
        if ! restic cat config --repo "$local_repo" >/dev/null 2>&1; then
          # The offsite repository gets its own password; copy needs the source chunker
          # parameters to deduplicate identically, so it is initialised from the source.
          mkdir -p "$local_repo" || return 1
          restic init --repo "$local_repo" --from-repo "$src" --from-password-file "$pwfile" \
            --copy-chunker-params || return 1
        fi
        restic copy --retry-lock 2h --repo "$local_repo" --from-repo "$src" \
          --from-password-file "$pwfile" || return 1
        # Retention is applied to the offsite copy only, never from the clients, and only
        # after the copy succeeded.
        restic forget --prune --retry-lock 2h --repo "$local_repo" ${retention} || return 1
      }
      rc=0
      ${lib.concatMapStringsSep "\n" (repo: ''
        copy_repo ${repo} ${localRepo repo} ${sourceRepo repo} ${secret "repo-password-${repo}"} || {
          echo "restic-offsite-copy: ${repo} failed" >&2
          rc=1
        }'') repos}
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
