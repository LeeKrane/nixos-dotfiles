#!/usr/bin/env bash
# Usage: scripts/ani-cli-termux.sh <phone address> [ssh port, default 8022]
# Phone: Termux with openssh and sshd running, this host's key in ~/.ssh/authorized_keys, and mpv-android (is.xyz.mpv).
# Termux:Widget turns the ~/.shortcuts entries into home-screen icons; scripts/ani-cli-launcher.sh installs real app entries instead.
# One-time for playback: run `termux-setup-storage`, then add `include="/storage/emulated/0/mpv/mpv.config.mp4"` to mpv.conf
# (Settings > Advanced > Edit mpv.conf) with mpv's Videos permission granted; mpv-android takes no intent options, so ani-cli writes the referrer there.
set -euo pipefail

host="${1:?usage: $0 <phone address> [port]}"
port="${2:-8022}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
auth=/run/secrets/ani-cli/curl-auth
[ -r "$auth" ] || {
  echo "no readable $auth on this host" >&2
  exit 1
}

rev="$(grep -oP 'rev = "\K[0-9a-f]{40}' "$repo/overlays/ani-cli.nix")"
upstream="https://raw.githubusercontent.com/pystardust/ani-cli/$rev/ani-cli"

wrapper="$(
  printf '#!/data/data/com.termux/files/usr/bin/bash\nset -o errexit -o nounset -o pipefail\n'
  printf 'ANI_CLI_REAL=/data/data/com.termux/files/usr/libexec/ani-cli-real\n'
  # shellcheck disable=SC2016 # $HOME expands on the phone, not here
  printf 'ANI_SYNC_AUTH="$HOME/.config/ani-cli-sync/curl-auth"\n'
  command cat "$repo/scripts/ani-cli-sync.sh"
)"

ssh -p "$port" "$host" "
  set -e
  export DEBIAN_FRONTEND=noninteractive
  o='-o Dpkg::Options::=--force-confnew -o Dpkg::Options::=--force-confdef'
  apt-get update -q >/dev/null
  apt-get full-upgrade -y -q \$o >/dev/null
  apt-get install -y -q --no-install-recommends \$o aria2 ffmpeg fzf grep sed wget curl jq gawk diffutils >/dev/null
  mkdir -p \$PREFIX/libexec ~/.config/ani-cli-sync ~/.shortcuts
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
