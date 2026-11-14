# restic retention, one definition for every place that prunes. Each entry is a list of
# `restic forget` arguments.
{
  # The krane.backup default.
  primary = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
}
