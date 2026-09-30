#!/usr/bin/env bash
# Tests scripts/claude/agents.sh in a dots-hyprland checkout against a fake
# `claude`. Usage: bash test-agents-sh.sh [<ii root>]   (default: the krane clone)
set -euo pipefail
ii=${1:-$HOME/src/dots-hyprland/dots/.config/quickshell/ii}
script="$ii/scripts/claude/agents.sh"
work=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")
trap 'rm -rf "$work"' EXIT
fail=0
check() { # name, expected, actual
    if [[ $2 == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$2], got [$3]"; fail=1; fi
}

mkdir -p "$work/bin" "$work/home/.claude/projects/-home-x-repo"
touch -d @1790000000 "$work/home/.claude/projects/-home-x-repo/s-int.jsonl"
# $$ is this test shell: a live pid whose ancestry ends at init.
command cat > "$work/bin/claude" <<FAKE
#!/usr/bin/env bash
[[ \$1 == agents && \$2 == --json ]] || exit 9
printf '%s' '[{"kind":"interactive","sessionId":"s-int","pid":$$,"name":"a","status":"idle","cwd":"/home/x/repo"},{"kind":"background","sessionId":"s-bg","pid":$$,"id":"ab12cd34","name":"b","state":"working","cwd":"/home/x/other"}]'
FAKE
chmod +x "$work/bin/claude"
# Only the tools agents.sh needs, so a claude installed on the host stays invisible.
mkdir -p "$work/tools"
for t in jq stat bash timeout mktemp rm; do ln -s "$(command -v "$t")" "$work/tools/$t"; done
base_path="$work/tools"

out=$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script")
check "prints an array of both sessions" 2 "$(jq length <<<"$out")"
check "keeps upstream fields" "ab12cd34" "$(jq -r '.[1].id' <<<"$out")"
check "interactive ancestors start at the session pid" "$$" "$(jq -r '.[0].ancestors[0]' <<<"$out")"
check "interactive ancestors stop before init" "false" "$(jq '.[0].ancestors | any(. == 1)' <<<"$out")"
check "interactive ancestors are numbers" "number" "$(jq -r '.[0].ancestors[0] | type' <<<"$out")"
check "background ancestors are empty" "[]" "$(jq -c '.[1].ancestors' <<<"$out")"
check "lastActivity is the transcript mtime" "1790000000" "$(jq '.[0].lastActivity' <<<"$out")"
check "missing transcript gives null" "null" "$(jq '.[1].lastActivity' <<<"$out")"

printf '#!/usr/bin/env bash\necho "[]"\n' > "$work/bin/claude"
check "no sessions prints []" "[]" "$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script")"

printf '#!/usr/bin/env bash\necho "{}"\n' > "$work/bin/claude"
set +e
HOME="$work/home" PATH="$work/bin:$base_path" bash "$script" >/dev/null 2>&1; rc=$?
set -e
check "non-array output fails" 2 "$rc"

printf '#!/usr/bin/env bash\nexit 127\n' > "$work/bin/claude"
chmod +x "$work/bin/claude"
set +e
HOME="$work/home" PATH="$work/bin:$base_path" bash "$script" >/dev/null 2>&1; rc=$?
set -e
check "claude's own exit 127 passes through, distinct from the exit-3 guard" 127 "$rc"

command cat > "$work/bin/claude" <<'FAKE'
#!/usr/bin/env bash
[[ $1 == agents && $2 == --json ]] || exit 9
sleep 30
FAKE
chmod +x "$work/bin/claude"
set +e
start=$(date +%s)
HOME="$work/home" PATH="$work/bin:$base_path" bash "$script" >/dev/null 2>&1; rc=$?
elapsed=$(( $(date +%s) - start ))
set -e
check "a hung claude is killed by the script's own timeout" true "$([[ $elapsed -lt 30 ]] && echo true || echo false)"
check "a timeout is an ordinary failure, not the missing-claude code" true "$([[ $rc -ne 0 && $rc -ne 3 ]] && echo true || echo false)"

rm "$work/bin/claude"
set +e
err=$(HOME="$work/home" PATH="$work/bin:$base_path" bash "$script" 2>&1 >/dev/null); rc=$?
set -e
check "missing claude exits 3" 3 "$rc"
check "missing claude says so on stderr" "claude not found on PATH" "$err"

exit $fail
