#!/usr/bin/env bash
# Install ani-cli with the history sync wrapper (scripts/ani-cli-sync.sh) on an Android phone
# running Termux, over SSH from a desktop host that has the ani-cli/curl-auth secret.
# Rerun after changing ani-cli-sync.sh or the ani-cli pin in overlays/ani-cli.nix.
#
#   scripts/ani-cli-termux.sh <phone address> [ssh port, default 8022]
#
# Phone prerequisites: Termux from GitHub or F-Droid with `pkg install openssh` and `sshd`
# running, this host's key in ~/.ssh/authorized_keys, and the mpv-android app (is.xyz.mpv),
# which ani-cli starts for playback. Termux:Widget (same source as Termux) turns the
# ~/.shortcuts entries this creates into home-screen icons; for launchers that can't use
# those (Niagara), scripts/ani-cli-launcher.sh installs real app entries instead.
#
# Playback needs two one-time manual steps, or mpv opens without playing: mpv-android takes
# no options from the intent, so ani-cli writes the stream's referrer to
# /storage/emulated/0/mpv/mpv.config.mp4. Run `termux-setup-storage` so Termux can write it,
# and add `include="/storage/emulated/0/mpv/mpv.config.mp4"` to mpv's mpv.conf (Settings >
# Advanced > Edit mpv.conf) with mpv's Videos permission granted.
set -euo pipefail

host="${1:?usage: $0 <phone address> [port]}"
port="${2:-8022}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
auth=/run/secrets/ani-cli/curl-auth
[ -r "$auth" ] || {
  echo "no readable $auth on this host" >&2
  exit 1
}

# Same ani-cli commit as the desktops: Termux's package lags behind the working provider.
rev="$(grep -oP 'rev = "\K[0-9a-f]{40}' "$repo/overlays/ani-cli.nix")"
upstream="https://raw.githubusercontent.com/pystardust/ani-cli/$rev/ani-cli"

# The wrapper body expects ANI_CLI_REAL and ANI_SYNC_AUTH set first, as the Nix wrapper does.
wrapper="$(
  printf '#!/data/data/com.termux/files/usr/bin/bash\nset -o errexit -o nounset -o pipefail\n'
  printf 'ANI_CLI_REAL=/data/data/com.termux/files/usr/libexec/ani-cli-real\n'
  # shellcheck disable=SC2016 # $HOME expands on the phone, not here
  printf 'ANI_SYNC_AUTH="$HOME/.config/ani-cli-sync/curl-auth"\n'
  command cat "$repo/scripts/ani-cli-sync.sh"
)"

# full-upgrade first: installing onto a stale Termux mixes library versions (curl then fails
# with "cannot locate symbol ... libcurl.so").
ssh -p "$port" "$host" "
  set -e
  export DEBIAN_FRONTEND=noninteractive
  o='-o Dpkg::Options::=--force-confnew -o Dpkg::Options::=--force-confdef'
  apt-get update -q >/dev/null
  apt-get full-upgrade -y -q \$o >/dev/null
  apt-get install -y -q \$o aria2 ffmpeg fzf grep sed wget curl jq gawk diffutils >/dev/null
  mkdir -p \$PREFIX/libexec ~/.config/ani-cli-sync ~/.shortcuts
  # Termux:Widget scripts, always dubbed. ~/.shortcuts feeds the widgets; dynamic_shortcuts
  # becomes app shortcuts (long-press the Termux:Widget icon, launcher search) once
  # CREATE SHORTCUTS is pressed in the Termux:Widget app.
  d=~/.termux/widget/dynamic_shortcuts
  mkdir -p \$d
  rm -f ~/.shortcuts/ani-cli* \$d/ani-cli*
  for s in 'ani-cli continue:--dub --continue' 'ani-cli:--dub'; do
    for dir in ~/.shortcuts \$d; do
      printf '#!/data/data/com.termux/files/usr/bin/bash\nexec ani-cli %s\n' \"\${s#*:}\" >\"\$dir/\${s%%:*}\"
      chmod 700 \"\$dir/\${s%%:*}\"
    done
  done
  curl -fsSL '$upstream' -o \$PREFIX/libexec/ani-cli-real
  chmod 755 \$PREFIX/libexec/ani-cli-real
  umask 077; cat >~/.config/ani-cli-sync/curl-auth
" <"$auth"
printf '%s\n' "$wrapper" | ssh -p "$port" "$host" 'cat >$PREFIX/bin/ani-cli && chmod 755 $PREFIX/bin/ani-cli'
echo "installed ani-cli $rev with history sync on $host"
