# restic retention, one definition for every place that prunes. Each entry is a list of
# `restic forget` arguments.
{
  # Repositories on taronychus: the krane.backup default (for clients that may delete) and the
  # server-side prune of the append-only repositories (hosts/taronychus/restic-prune.nix).
  primary = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
  # Offsite copy on tarritator's HDD (hosts/tarritator/offsite-copy.nix): kept longer.
  offsite = [
    "--keep-daily 7"
    "--keep-weekly 8"
    "--keep-monthly 12"
  ];
}
