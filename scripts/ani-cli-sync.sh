# Body of the ani-cli wrapper built in modules/home/desktop/ani-cli.nix: syncs ani-cli's
# watch history (ani-hsts) through the `ani-cli` database on couch.krane.dev, then runs
# the real ani-cli. The Nix side sets ANI_CLI_REAL (the real binary) and ANI_SYNC_AUTH
# (a curl config file holding `user = "ani-cli:<password>"`).
#
# Each history line is `episode<TAB>show id<TAB>title`. Sync is a three-way merge per show id
# against .ani-hsts.base, the copy last seen on the server, so an episode watched offline on
# one device and a different show watched on another both survive. The doc's _rev is
# kept in .ani-hsts.rev; a 409 on push means another device wrote first, so it re-pulls,
# re-merges and retries. Offline or a server error never blocks ani-cli: sync is skipped with
# a warning and catches up on the next run.

hist_dir="${ANI_CLI_HIST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ani-cli}"
hist="$hist_dir/ani-hsts"
base="$hist_dir/.ani-hsts.base"
rev_file="$hist_dir/.ani-hsts.rev"
url="${ANI_SYNC_URL:-https://couch.krane.dev/ani-cli/hsts}"

mkdir -p "$hist_dir"
touch "$hist" "$base"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# `|| true`: after a hangup stderr is a dead terminal, and errexit must not abort the push.
warn() { printf 'ani-cli sync: %s\n' "$*" >&2 || true; }

# Fetch the server doc into $tmp/remote and $tmp/remote-rev. A missing doc is an empty
# history with no rev. Returns non-zero when the server can't be reached.
fetch() {
  local code
  code="$(curl -sS -K "$ANI_SYNC_AUTH" -o "$tmp/resp" -w '%{http_code}' "$url")" || return 1
  case "$code" in
    200)
      jq -j '.text' "$tmp/resp" >"$tmp/remote"
      jq -r '._rev' "$tmp/resp" >"$tmp/remote-rev"
      ;;
    404)
      : >"$tmp/remote"
      : >"$tmp/remote-rev"
      ;;
    *)
      warn "GET returned HTTP $code"
      return 1
      ;;
  esac
}

# merge BASE LOCAL REMOTE: a show changed on only one side (its line differs from BASE)
# takes that side's line. Changed on both, as on a first sync with an empty BASE, the higher
# episode wins. A show missing on one side but present in BASE was deleted there and is
# dropped.
merge() {
  awk -F'\t' '
    NF < 2 { next }
    FILENAME == ARGV[1] { base[$2] = $0; next }
    FILENAME == ARGV[2] { loc[$2] = $0; lorder[++n] = $2; next }
    { rem[$2] = $0; rorder[++m] = $2 }
    END {
      for (i = 1; i <= m; i++) {
        id = rorder[i]; seen[id] = 1
        if (id in loc) {
          if (loc[id] == base[id]) print rem[id]
          else if (rem[id] == base[id]) print loc[id]
          else {
            split(loc[id], l, "\t"); split(rem[id], r, "\t")
            print ((l[1] + 0 >= r[1] + 0) ? loc[id] : rem[id])
          }
        } else if (!(id in base)) {
          print rem[id]
        }
      }
      for (i = 1; i <= n; i++) {
        id = lorder[i]
        if (!(id in seen) && loc[id] != base[id]) print loc[id]
      }
    }
  ' "$1" "$2" "$3"
}

# Pull: merge the server copy into the local file.
pull() {
  fetch || return 1
  merge "$base" "$hist" "$tmp/remote" >"$tmp/merged"
  cp "$tmp/merged" "$hist"
  cp "$tmp/remote" "$base"
  cp "$tmp/remote-rev" "$rev_file"
}

# Push: upload the local file if it differs from the server copy, retrying on conflict.
push() {
  local attempt code rev
  for attempt in 1 2 3; do
    cmp -s "$hist" "$base" && return 0
    rev="$(cat "$rev_file" 2>/dev/null || true)"
    jq -Rs --arg rev "$rev" '{text: .} + (if $rev == "" then {} else {_rev: $rev} end)' \
      "$hist" >"$tmp/body"
    code="$(curl -sS -K "$ANI_SYNC_AUTH" -X PUT -H 'Content-Type: application/json' \
      --data-binary "@$tmp/body" -o "$tmp/resp" -w '%{http_code}' "$url")" || return 1
    case "$code" in
      201 | 202)
        jq -r '.rev' "$tmp/resp" >"$rev_file"
        cp "$hist" "$base"
        return 0
        ;;
      409) pull || return 1 ;;
      *)
        warn "PUT returned HTTP $code (attempt $attempt)"
        return 1
        ;;
    esac
  done
  warn "gave up after repeated conflicts"
  return 1
}

if [ -r "$ANI_SYNC_AUTH" ]; then
  pull || warn "pull failed, using local history"
else
  warn "no credentials at $ANI_SYNC_AUTH, not syncing"
fi

finish() {
  if [ -r "$ANI_SYNC_AUTH" ]; then
    push || warn "push failed, will retry next run"
  fi
}

# Closing the terminal window (SIGHUP) or Ctrl-C kills ani-cli too; push before dying, or the
# episodes watched this run stay local until the next clean exit.
trap 'finish; exit 129' HUP
trap 'finish; exit 130' INT
trap 'finish; exit 143' TERM

status=0
"$ANI_CLI_REAL" "$@" || status=$?

trap - HUP INT TERM
finish
exit "$status"
