#!/usr/bin/env bash
# Build the "ani-cli" / "ani-cli continue" launcher APK (android/ani-cli-launcher), sign it and
# put it on an Android phone running Termux, over SSH. Rerun to update; the signing key
# (~/.local/share/ani-cli-launcher/, created on first run) must stay the same for updates to
# install over the old app.
#
#   scripts/ani-cli-launcher.sh <phone address> [ssh port, default 8022]
#
# Needs Nix on this host and the phone prerequisites of scripts/ani-cli-termux.sh. The script
# sets allow-external-apps in Termux and opens the installer, it does not wait: tap Install on
# the phone. First install only: Settings > Apps > ani-cli > Permissions > Additional
# permissions > "Run commands in Termux environment" (the app also asks when first launched).
# Also needed once: Termux "Display over other apps" (Android lets it open its terminal from
# the launcher entry only with that).
set -euo pipefail

host="${1:?usage: $0 <phone address> [port]}"
port="${2:-8022}"
repo="$(cd "$(dirname "$0")/.." && pwd)"

unsigned="$(nix build --no-link --print-out-paths "$repo#ani-cli-launcher")/ani-cli-launcher-unsigned.apk"
sign="$(nix build --no-link --print-out-paths "$repo#ani-cli-launcher-sign")/bin/ani-cli-launcher-sign"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$sign" "$unsigned" "$tmp/ani-cli-launcher.apk"

# RUN_COMMAND is refused by Termux unless allow-external-apps is true.
# shellcheck disable=SC2016 # expands on the phone
ssh -n -p "$port" "$host" '
  set -e
  mkdir -p ~/.termux
  f=~/.termux/termux.properties
  touch "$f"
  if grep -q "^allow-external-apps *= *true" "$f"; then :
  else
    sed -i "/^#\? *allow-external-apps *=/d" "$f"
    echo "allow-external-apps = true" >>"$f"
  fi
  termux-reload-settings
'
# termux-open hands the file to the installer through Termux's file provider.
# shellcheck disable=SC2016
ssh -p "$port" "$host" '
  cat >~/ani-cli-launcher.apk
  termux-open --content-type application/vnd.android.package-archive ~/ani-cli-launcher.apk
' <"$tmp/ani-cli-launcher.apk"
echo "Tap Install on the phone (allow Termux to install unknown apps if asked), then grant 'Run commands in Termux environment' to ani-cli under Settings > Apps if asked."
