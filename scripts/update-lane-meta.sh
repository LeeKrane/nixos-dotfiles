#!/usr/bin/env bash
# The one table of per-lane strings for the weekly update lanes
# (docs/superpowers/specs/2026-11-23-update-lanes-design.md). Prints key=value lines, ready for
# $GITHUB_OUTPUT. Which inputs a lane bumps lives in scripts/update-lanes.nix.
#   update-lane-meta.sh LANE
set -euo pipefail

case "${1:?usage: update-lane-meta.sh LANE}" in
    servers)
        # pkgs/claude-code is installed on servers too, so it rides the server lane.
        claude_code=true
        title='Update server inputs'
        commit='Update server inputs and claude-code'
        switch_host=taragarmr
        ;;
    desktops)
        claude_code=false
        title='Update desktop inputs'
        commit='Update desktop inputs'
        switch_host='<host>'
        ;;
    *)
        echo "unknown lane: $1" >&2
        exit 1
        ;;
esac
printf 'claude_code=%s\ntitle=%s\ncommit=%s\nswitch_host=%s\n' "$claude_code" "$title" "$commit" "$switch_host"
