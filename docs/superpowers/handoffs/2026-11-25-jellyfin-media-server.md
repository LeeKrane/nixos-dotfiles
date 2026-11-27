# Handoff: self-hosted video streaming (Jellyfin) on taragarmr

Date: 2026-11-25. The previous session was research and Q&A only. No code was written.

## Goal of the next session

1. Brainstorm the open design questions with the user.
2. Write a spec at `docs/superpowers/specs/<date>-jellyfin-media-server-design.md`.
3. Write a plan at `docs/superpowers/plans/`.
4. Implement it in the flake.

## What the user wants

- A Netflix-like streaming setup for at most 2 people.
- The user adds films and series by hand, as files on an HDD. Jellyfin must show the correct titles, posters and episode thumbnails for them.
- Backups go into the existing restic job on taragarmr.
- No request automation (Sonarr, Radarr, Jellyseerr) has been asked for. Ask before adding any of it.

## Decisions so far (agreed in chat, not yet in a spec)

- **Media server:** Jellyfin, through the NixOS module `services.jellyfin`. It was chosen over Plex because it is free and open source and needs no cloud account.
- **Host:** taragarmr. Hardware was checked over SSH on 2026-11-25, and the header of `hosts/taragarmr/default.nix` describes the host. The Radeon 680M iGPU does hardware decoding of H.264, HEVC, VP9 and AV1. It does hardware encoding of H.264 and HEVC through VAAPI. That is enough for 2 viewers. RAM was 14 of 27 GiB used, mostly by SPT. Load average was about 0.25.
- **Storage:** media goes on the existing 2 TB backup HDD (decided by the user on 2026-11-25), because streaming reads are sequential. The Jellyfin DB, metadata and image cache go on the NVMe (`/var/lib/jellyfin`, `/var/cache/jellyfin`). Transcodes go on the NVMe or a tmpfs.
- **Ingress:** Caddy (`hosts/taragarmr/caddy.nix`) is the reverse proxy if Jellyfin gets a vhost.
- **Library layout:** follow Jellyfin's naming convention, with metadata from TMDB:
  - `movies/Title (Year)/Title (Year).mkv`, with optional `[tmdbid-N]` in the folder name
  - `shows/Title (Year)/Season 01/Title S01E01.mkv`
  - Enable real-time monitoring on each library.

## Media shares the backup drive

taragarmr has a 512 GB NVMe (`disko.nix`) and one HDD, `sda`. `sda` is a 2 TB Seagate 2.5" external USB drive (ST2000LM007), mounted at `/mnt/backup` (`backup-drive.nix`). It holds the restic repository at `/mnt/backup/restic/taragarmr`. The user decided that Jellyfin's media goes on this drive too. No new disk will be bought.

What follows from that:

- **Space:** the media library and the restic repository share 2 TB. If the library fills the drive, the nightly backup fails. The spec needs a guard: a separate directory such as `/mnt/backup/media`, plus a free-space alert or a size limit (ntfy is already set up in `lib/ntfy.nix`). On 2026-11-25 `/mnt/backup` did not appear in `df` on taragarmr, so check whether it is an automount and how full the drive is.
- **Mount dependency:** jellyfin.service should use `RequiresMountsFor` on the media path, the way `restic-backups-default` already does, or the spec must say what Jellyfin does when the drive is missing. Read `backup-drive.nix` for the current mount options (`nofail`, automount).
- **Backup scope:** the media directory must stay out of restic. It sits next to the repository, so backing it up gives no protection against drive failure.
- **Drive behaviour:** the ST2000LM007 is a 5400 rpm SMR drive. Sequential reads for 2 streams are fine. Large copies onto it can slow down once its cache fills, and the nightly backup and streaming share one disk. Both are acceptable for 2 viewers, but note them in the spec.
- **Shared failure:** one drive failure loses both the media and the local backups. The user accepts this. Offsite backups to tarritator are planned separately (server migration notes).

## Open questions for brainstorming

- **Media on the backup drive:** directory layout under `/mnt/backup`, ownership and permissions next to the restic repository, the space guard, and behaviour when the drive is unplugged. See the section above.
- **Access:**
  - Option 1: a public Caddy vhost on the `krane.dev` domain. This needs a hardening review, because Jellyfin's auth history is weak.
  - Option 2: LAN and wg0 only, like the Fritzbox vhost in `caddy.nix`.
  - Ask where the second viewer is and what clients they use. For remote viewing, upload bandwidth is the limit.
- **Hardware acceleration:** `hardware.graphics`, the `jellyfin` user in the `render` and `video` groups, and the VAAPI device `/dev/dri/renderD128`. Verify on the host how HDR tone mapping works on AMD (Vulkan or OpenCL). Not checked yet.
- **Declarative vs UI-held config:** Jellyfin keeps most settings (setup wizard, libraries, users, plugins, transcoding options) in `/var/lib/jellyfin`, set through the web UI. Decide which parts are declared in Nix and which are documented as one-time manual steps.
- **Getting files onto the drive:** rsync or scp over the LAN or wg0, or a Samba share. Give the media directory a `media` group with the setgid bit, so files the user copies in stay readable by Jellyfin.
- **Plugins:** an AniDB or AniList plugin if anime will be added, and a TVDB plugin if TMDB matches badly.
- **Backup:** add `/var/lib/jellyfin` to the paths in `hosts/taragarmr/backup.nix` and exclude `/var/cache/jellyfin`. The media itself is not backed up, because it shares the drive with the repository. Jellyfin's DB is SQLite. Decide between stopping jellyfin.service during the run, as the job already does for CouchDB, and backing up live. Read the CouchDB pattern in `backup.nix` first.
- **Secrets:** probably none. If any are needed, they go in `secrets/taragarmr.yaml` through sops, following the existing sections.

## Context to read first

- `CLAUDE.md` (repo rules: commit directly on `main`, worktree only for a large subsystem).
- `hosts/taragarmr/default.nix`: module list, deploy command, firewall notes.
- `hosts/taragarmr/caddy.nix`, `backup.nix`, `backup-drive.nix`, `services.nix`.
- `modules/nixos/server/backup.nix` (the `krane.backup` options).
- `tests/server-host/default.nix` and the checks in `flake.nix`, to see what the change must keep passing.
- The user's memory notes `~/server-migration/DECISIONS.md`, but that file does not exist on tariognatha (this desktop). It may be on another machine. Ask the user if it matters.

## Environment notes

- The session runs on tariognatha. taragarmr can be reached as `ssh taragarmr`. Its login shell is fish, so wrap POSIX commands in `bash -c`. `lspci` is not installed there.
- taragarmr has no passwordless sudo. Deploys need the user to type the sudo password. The deploy command is in the header of `hosts/taragarmr/default.nix`. Leave the switch to the user.
- Build locally before asking for a deploy: `nixos-rebuild build --flake .#taragarmr`.

## Suggested skills

- `superpowers:brainstorming`: required before the spec. It works through the open questions above with the user.
- `superpowers:writing-plans`: turns the approved spec into a plan in `docs/superpowers/plans/`.
- `superpowers:test-driven-development`: write a failing check first, for example a flake check or an assertion in `tests/server-host`.
- `superpowers:subagent-driven-development` or `superpowers:executing-plans`: carry out the plan.
- `ponytail`: keep the module small and reuse `krane.backup` and the Caddy patterns.
- `superpowers:verification-before-completion`: run the build and checks before claiming the work is done.
- `/code-review`: review the finished diff.
