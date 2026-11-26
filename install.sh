#!/usr/bin/env bash
# Installs the krane flake on tariognatha, tarmantria and taractias.
# Install mode (live ISO) partitions with disko; setup mode (after first boot) runs the second switch.
# Mode is auto-detected, --mode overrides. Logs to /tmp/krane-install-TIMESTAMP-PID.log.

set -Eeuo pipefail

# nix calls, including nixos-install and nixos-rebuild, need flakes.
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}experimental-features = nix-command flakes"

# Re-exec via nix shell: the live ISO lacks gum.
if ! command -v gum >/dev/null 2>&1 && [ -z "${KRANE_INSTALL_REEXEC:-}" ]; then
    export KRANE_INSTALL_REEXEC=1
    exec nix --extra-experimental-features 'nix-command flakes' shell \
        nixpkgs#gum nixpkgs#git nixpkgs#dmidecode nixpkgs#pciutils \
        --command bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/tmp/krane-install-$(date +%Y%m%d-%H%M%S)-$$.log"
LOG_WRITABLE=true
if ! : >"$LOG" 2>/dev/null; then
    LOG_WRITABLE=false
    echo "warning: cannot write to $LOG, continuing without a log file" >&2
fi

# CLICOLOR_FORCE keeps gum colour although tee makes stdout a pipe.
if [ -t 1 ]; then
    export CLICOLOR_FORCE=1
fi

if $LOG_WRITABLE; then
    exec > >(tee -a "$LOG") 2>&1
fi

# stderr is a pipe to tee, which breaks gum's TUI (drawn on stderr). gum_tty uses /dev/tty,
# falling back to stderr without a tty (container dry-runs).
HAVE_TTY=false
{ : >/dev/tty; } 2>/dev/null && HAVE_TTY=true

gum_tty() {
    if $HAVE_TTY; then
        gum "$@" 2>/dev/tty
    else
        gum "$@"
    fi
}

AVAILABLE_HOSTS=()
for _d in "$REPO_ROOT"/hosts/*/; do
    AVAILABLE_HOSTS+=("$(basename "$_d")")
done
unset _d

TEMPLATE_DIR="$REPO_ROOT/templates/host"
GPU_PROFILES=()
for _f in "$TEMPLATE_DIR"/profiles/*.nix.in; do
    GPU_PROFILES+=("$(basename "$_f" .nix.in)")
done
mapfile -t GPU_PROFILES < <(printf '%s\n' "${GPU_PROFILES[@]}" | sort)
FORM_FACTORS=()
for _f in "$TEMPLATE_DIR"/form-factors/*.nix.in; do
    FORM_FACTORS+=("$(basename "$_f" .nix.in)")
done
mapfile -t FORM_FACTORS < <(printf '%s\n' "${FORM_FACTORS[@]}" | sort)
unset _f
DEFAULT_INSTALL_USER=krane
DEFAULT_GIT_EMAIL=chris@krane.dev
# shellcheck disable=SC2209 # "at" is the keyboard layout, not the job-scheduling command.
DEFAULT_KB_LAYOUT="at"
DEFAULT_KB_VARIANT=nodeadkeys

MODE=""
# Not "${HOST:-}": an ambient $HOST must not pick the target.
HOST=""
DISK=""
YES=false
DRY_RUN=false
CONFIRM_WIPE=false
SELF_TEST=false
SELF_TEST_TRIGGER_ERR=false
SELF_TEST_CHECK_DISKO_SED=false
SELF_TEST_CHECK_PRIME_SED=false
SELF_TEST_CHECK_SCAFFOLD=false
SELF_TEST_FAILURES=0
LAST_CMD=""
HANDLED_EXIT=false
USAGE_EXIT=false
INSTALL_SWAP_ACTIVE=false
INSTALL_SWAP_ON=false

NEW_HOST_MODE=false
NEW_HOST=""
NEW_USER=""
NEW_GIT_NAME=""
NEW_GIT_EMAIL=""
NEW_PROFILE=""
NEW_FORM_FACTOR=""
NEW_KB_LAYOUT=""
NEW_KB_VARIANT=""
# --kb-variant "" is a real answer, so it needs its own flag.
NEW_KB_VARIANT_SET=false
SYSTEM_ACCOUNT_NAMES=(root nobody daemon bin sys sync games man lp mail news uucp proxy backup operator
    sshd messagebus polkituser rtkit avahi geoclue nscd dhcpcd greeter flatpak ollama pipewire colord
    cups usbmux qemu-libvirtd nm-openvpn nm-iodine fwupd-refresh)

SELF_TEST_SCAFFOLD=false
NEW_HOST_MENU_ENTRY="+ new host"
SCAFFOLD_STAGING=""
SCAFFOLD_PREVIEW_DIR=""
SCAFFOLD_PENDING=false
SCAFFOLD_SOPS_SNAPSHOT=""

INSTALL_USER=""

# Defined early: on_exit can call it before arg parsing finishes.
teardown_install_swap() {
    if ! $INSTALL_SWAP_ACTIVE; then
        return
    fi
    if $INSTALL_SWAP_ON; then
        run_soft swapoff /mnt/swapfile || log_warn "swapoff /mnt/swapfile failed, remove /swapfile after first boot"
        INSTALL_SWAP_ON=false
    fi
    run_soft rm -f /mnt/swapfile || log_warn "could not remove /mnt/swapfile"
    INSTALL_SWAP_ACTIVE=false
}

# Undoes an unfinished scaffold_host: removes hosts/$HOST and restores .sops.yaml from
# SCAFFOLD_SOPS_SNAPSHOT, not git, which would drop uncommitted edits.
rollback_scaffold() {
    if ! $SCAFFOLD_PENDING || [ -z "$HOST" ]; then
        return 0
    fi
    SCAFFOLD_PENDING=false
    log_warn "rolling back the partial hosts/$HOST scaffold"
    rm -rf "${REPO_ROOT:?}/hosts/$HOST" || log_warn "could not remove hosts/$HOST, delete it by hand"
    if [ -n "$SCAFFOLD_SOPS_SNAPSHOT" ] && [ -f "$SCAFFOLD_SOPS_SNAPSHOT" ]; then
        cat "$SCAFFOLD_SOPS_SNAPSHOT" >"$REPO_ROOT/.sops.yaml" \
            || log_warn "could not restore .sops.yaml, its snapshot is at $SCAFFOLD_SOPS_SNAPSHOT"
    else
        log_warn "no .sops.yaml snapshot to restore from, check .sops.yaml by hand"
    fi
}

banner() {
    gum style \
        --border double --border-foreground 212 --foreground 212 --bold \
        --padding "1 4" --margin "1 0" --align center \
        "$@"
}

log_step() {
    printf '\n' >&2
    gum style --foreground 99 --bold "── $1 ──" >&2
}

log_info() { gum log --time=rfc3339 --level info --structured -- "$1" >&2; }
log_ok() { gum log --time=rfc3339 --level info --structured -- "$1" status ok >&2; }
log_warn() { gum log --time=rfc3339 --level warn --structured -- "$1" >&2; }
log_error() { gum log --time=rfc3339 --level error --structured -- "$1" >&2; }

print_fail_box() {
    HANDLED_EXIT=true
    local lines=("install.sh failed" "" "$@")
    if $LOG_WRITABLE; then
        lines+=("" "Log: $LOG")
    fi
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        -- "${lines[@]}" >&2 || true
}

die() {
    log_error "$*"
    print_fail_box "$*"
    exit 1
}

clean_log_lines() {
    LC_ALL=C sed -E $'s/\x1b\\[[0-9;?]*[ -\\/]*[@-~]//g' | LC_ALL=C tr -d '\000-\010\013-\037\177' | cut -c1-100
}

clean_log_tail() {
    tail -n "$1" "$LOG" | clean_log_lines
}

err_trap() {
    # In a subshell the parent sees the same failure; return to print one box.
    [ "${BASHPID:-$$}" = "$$" ] || return 0
    local rc="$1" line="$2"
    local fn="${FUNCNAME[1]:-main}" fn_line="${BASH_LINENO[0]:-$line}"
    case "$fn" in
        run | run_sh | capture)
            fn="${FUNCNAME[2]:-main}"
            fn_line="${BASH_LINENO[1]:-$line}"
            ;;
    esac
    local cmd="${LAST_CMD:-$BASH_COMMAND}"
    local lines=("command failed (exit $rc):" "  $cmd" "in $fn (install.sh line $fn_line)")
    if $LOG_WRITABLE; then
        lines+=("" "last log lines:")
        local logline
        while IFS= read -r logline; do
            lines+=("$logline")
        done < <(clean_log_tail 10)
    fi
    log_error "command failed (exit $rc): $cmd, in $fn (install.sh line $fn_line)"
    print_fail_box "${lines[@]}"
    LAST_CMD=""
}
trap 'err_trap $? $LINENO' ERR

on_exit() {
    local rc=$?
    if [ "$rc" -ne 0 ] && ! $HANDLED_EXIT && ! $USAGE_EXIT; then
        if $LOG_WRITABLE; then
            gum style --foreground 244 "See $LOG for the full transcript, exit $rc." >&2
        else
            gum style --foreground 244 "exit $rc, no log file was writable this run." >&2
        fi
    fi
    teardown_install_swap
    rollback_scaffold
    if [ -n "$SCAFFOLD_STAGING" ]; then
        rm -rf "$SCAFFOLD_STAGING"
    fi
    if [ -n "$SCAFFOLD_SOPS_SNAPSHOT" ]; then
        rm -f "$SCAFFOLD_SOPS_SNAPSHOT"
    fi
}
trap on_exit EXIT

run() {
    if $DRY_RUN; then
        printf '+ %s\n' "$(printf '%q ' "$@")" >&2
        return 0
    fi
    LAST_CMD=$(printf '%q ' "$@")
    "$@"
    local rc=$?
    [ "$rc" -eq 0 ] && LAST_CMD=""
    return "$rc"
}

# Tolerated failure: clears LAST_CMD even on failure so err_trap never blames it later.
run_soft() { run "$@" || { local rc=$?; LAST_CMD=""; return "$rc"; }; }

run_sh() {
    if $DRY_RUN; then
        printf '+ %s\n' "$1" >&2
        return 0
    fi
    LAST_CMD="$1"
    bash -o pipefail -c "$1"
    local rc=$?
    [ "$rc" -eq 0 ] && LAST_CMD=""
    return "$rc"
}

# Like run_sh for full-screen programs (sops $EDITOR) that break under the tee pipe;
# runs against /dev/tty when available.
run_tty() {
    if $DRY_RUN; then
        printf '+ %s\n' "$1" >&2
        return 0
    fi
    LAST_CMD="$1"
    if $HAVE_TTY; then
        bash -o pipefail -c "$1" </dev/tty >/dev/tty 2>&1
    else
        bash -o pipefail -c "$1"
    fi
    local rc=$?
    [ "$rc" -eq 0 ] && LAST_CMD=""
    return "$rc"
}

capture() {
    if $DRY_RUN; then
        printf '+ %s\n' "$(printf '%q ' "$@")" >&2
        printf '%s\n' "/dry-run/placeholder"
        return 0
    fi
    LAST_CMD=$(printf '%q ' "$@")
    "$@"
    local rc=$?
    [ "$rc" -eq 0 ] && LAST_CMD=""
    return "$rc"
}

capture_with_spin() {
    local title="$1"
    shift
    if $DRY_RUN; then
        capture "$@"
        return
    fi
    gum spin --title "$title" --show-output -- "$@"
}

confirm() {
    if $YES; then
        log_info "auto-confirm: $1"
        return 0
    fi
    if gum_tty confirm "$1"; then
        log_info "confirmed: $1"
        return 0
    fi
    log_info "declined: $1"
    return 1
}

choose_one() {
    local prompt="$1" selected="$2"
    shift 2
    log_info "$prompt"
    if [ "$#" -eq 0 ]; then
        die "choose_one: no candidates for '$prompt'"
    fi
    local result
    if [ -n "$selected" ]; then
        result=$(gum_tty choose --selected "$selected" "$@")
    else
        result=$(gum_tty choose "$@")
    fi
    log_info "selected: $result"
    printf '%s\n' "$result"
}

# Under --dry-run this only warns, so container tests without real tools still run every path.
require() {
    for bin in "$@"; do
        command -v "$bin" >/dev/null 2>&1 || soft_fail "required command not found: $bin"
    done
}

soft_fail() {
    if $DRY_RUN; then
        log_warn "$1, continuing under --dry-run"
        return 0
    fi
    die "$1"
}

usage() {
    cat <<EOF
Usage: install.sh [options]

  --mode install|setup   Force a mode instead of auto-detecting it.
  --host HOST             One of: ${AVAILABLE_HOSTS[*]}
  --new-host NAME         Install mode only: create hosts/NAME from
                            templates/host/ instead of using an existing
                            host. Asks for the settings below unless given.
  --user NAME             New host's login user (default $DEFAULT_INSTALL_USER).
  --git-name NAME         New host's git user.name (default: the login user).
  --git-email EMAIL       New host's git user.email (default $DEFAULT_GIT_EMAIL).
  --profile PROFILE       New host's GPU profile: ${GPU_PROFILES[*]}
  --form-factor FF        New host's form factor: ${FORM_FACTORS[*]}
  --kb-layout LAYOUT      New host's keyboard layout (default $DEFAULT_KB_LAYOUT).
  --kb-variant VARIANT    New host's keyboard variant (default
                            $DEFAULT_KB_VARIANT for --kb-layout $DEFAULT_KB_LAYOUT,
                            otherwise empty). --yes --new-host also requires
                            --user, --profile and --form-factor.
  --disk DISK              Target block device, install mode only.
  -y, --yes               Assume yes and auto-confirm every prompt. Live
                            install also requires --confirm-wipe unless
                            --dry-run is given too. Never skips setting
                            the login user's password.
  -n, --dry-run           Print every mutating command instead of running
                            it. Implies --yes. Safe anywhere, any time.
  --confirm-wipe          Required alongside a live, non-dry-run --yes
                            install. Acknowledges the target disk will be
                            erased without an interactive prompt.
  -h, --help              Show this help and exit.
EOF
}

usage_die() {
    echo "error: $1" >&2
    usage
    USAGE_EXIT=true
    exit 1
}

require_arg() {
    if [ "$#" -lt 2 ]; then
        usage_die "$1 requires a value"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            require_arg "$@"
            MODE="$2"
            shift 2
            ;;
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --host)
            require_arg "$@"
            HOST="$2"
            shift 2
            ;;
        --host=*)
            HOST="${1#*=}"
            shift
            ;;
        --disk)
            require_arg "$@"
            DISK="$2"
            shift 2
            ;;
        --disk=*)
            DISK="${1#*=}"
            shift
            ;;
        --new-host)
            require_arg "$@"
            NEW_HOST_MODE=true
            NEW_HOST="$2"
            shift 2
            ;;
        --new-host=*)
            NEW_HOST_MODE=true
            NEW_HOST="${1#*=}"
            shift
            ;;
        --user)
            require_arg "$@"
            NEW_USER="$2"
            shift 2
            ;;
        --user=*)
            NEW_USER="${1#*=}"
            shift
            ;;
        --git-name)
            require_arg "$@"
            NEW_GIT_NAME="$2"
            shift 2
            ;;
        --git-name=*)
            NEW_GIT_NAME="${1#*=}"
            shift
            ;;
        --git-email)
            require_arg "$@"
            NEW_GIT_EMAIL="$2"
            shift 2
            ;;
        --git-email=*)
            NEW_GIT_EMAIL="${1#*=}"
            shift
            ;;
        --profile)
            require_arg "$@"
            NEW_PROFILE="$2"
            shift 2
            ;;
        --profile=*)
            NEW_PROFILE="${1#*=}"
            shift
            ;;
        --form-factor)
            require_arg "$@"
            NEW_FORM_FACTOR="$2"
            shift 2
            ;;
        --form-factor=*)
            NEW_FORM_FACTOR="${1#*=}"
            shift
            ;;
        --kb-layout)
            require_arg "$@"
            NEW_KB_LAYOUT="$2"
            shift 2
            ;;
        --kb-layout=*)
            NEW_KB_LAYOUT="${1#*=}"
            shift
            ;;
        --kb-variant)
            require_arg "$@"
            NEW_KB_VARIANT="$2"
            NEW_KB_VARIANT_SET=true
            shift 2
            ;;
        --kb-variant=*)
            NEW_KB_VARIANT="${1#*=}"
            NEW_KB_VARIANT_SET=true
            shift
            ;;
        -y | --yes)
            YES=true
            shift
            ;;
        -n | --dry-run)
            DRY_RUN=true
            YES=true
            shift
            ;;
        --confirm-wipe)
            CONFIRM_WIPE=true
            shift
            ;;
        --self-test)
            SELF_TEST=true
            shift
            ;;
        --self-test-trigger-err)
            SELF_TEST_TRIGGER_ERR=true
            shift
            ;;
        --self-test-check-disko-sed)
            SELF_TEST_CHECK_DISKO_SED=true
            shift
            ;;
        --self-test-check-prime-sed)
            SELF_TEST_CHECK_PRIME_SED=true
            shift
            ;;
        --self-test-check-scaffold)
            SELF_TEST_CHECK_SCAFFOLD=true
            shift
            ;;
        --self-test-scaffold)
            SELF_TEST_SCAFFOLD=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage_die "unknown argument: $1"
            ;;
    esac
done

detect_mode() {
    if [ -d /iso ] || [ ! -e /etc/NIXOS ]; then
        echo install
        return
    fi
    if command -v findmnt >/dev/null 2>&1; then
        local fstype
        fstype=$(findmnt -no FSTYPE / 2>/dev/null || true)
        if [ "$fstype" = "overlay" ]; then
            echo install
            return
        fi
    fi
    echo setup
}

# New hosts are not written until after check_dns, so they answer from their chosen GPU profile.
host_uses_cuda() {
    if $NEW_HOST_MODE && [ -n "$NEW_PROFILE" ]; then
        [ "$NEW_PROFILE" = nvidia-desktop ]
        return
    fi
    grep -q 'gpu/nvidia-desktop' "$REPO_ROOT/hosts/$HOST/default.nix" 2>/dev/null
}

host_dir() {
    if [ -n "$SCAFFOLD_PREVIEW_DIR" ]; then
        printf '%s\n' "$SCAFFOLD_PREVIEW_DIR"
    else
        printf '%s\n' "$REPO_ROOT/hosts/$HOST"
    fi
}

# --option flags adding the CUDA cache substituter. flake.nix has no nixConfig, so only the CUDA host gets it here.
flake_config_opt() {
    if host_uses_cuda; then
        printf -- '--option extra-substituters https://cache.nixos-cuda.org --option extra-trusted-public-keys cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M='
    fi
}

check_dns() {
    local names=(cache.nixos.org)
    host_uses_cuda && names+=(cache.nixos-cuda.org)

    local name start_ns elapsed_ms trouble=false
    for name in "${names[@]}"; do
        start_ns=$(date +%s%N)
        if timeout 5 getent hosts "$name" >/dev/null 2>&1; then
            elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
            if [ "$elapsed_ms" -gt 3000 ]; then
                log_warn "DNS lookup for $name took ${elapsed_ms} ms"
                trouble=true
            else
                log_ok "DNS ok: $name in ${elapsed_ms} ms"
            fi
        else
            elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
            log_warn "DNS lookup for $name failed after ${elapsed_ms} ms"
            trouble=true
        fi
    done
    $trouble || return 0

    if ! command -v nmcli >/dev/null 2>&1; then
        log_warn "nmcli not found, cannot offer to pin DNS, fix DNS by hand if lookups keep failing"
        return 0
    fi
    local conn
    conn=$(nmcli -t -f TYPE,NAME con show --active 2>/dev/null | grep -v '^loopback:' | head -1 | cut -d: -f2- | sed 's/\\:/:/g' || true)
    if [ -z "$conn" ]; then
        log_warn "no active NetworkManager connection found, cannot offer to pin DNS"
        return 0
    fi

    if confirm "Pin public DNS (1.1.1.1, 9.9.9.9) on connection '$conn'?"; then
        run_soft nmcli con mod "$conn" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes \
            || log_warn "could not modify '$conn', pin DNS by hand"
        run_soft nmcli con up "$conn" \
            || log_warn "could not reactivate '$conn', check the connection by hand"
        start_ns=$(date +%s%N)
        if timeout 5 getent hosts cache.nixos.org >/dev/null 2>&1; then
            elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
            log_ok "DNS ok after pinning: cache.nixos.org in ${elapsed_ms} ms"
        else
            log_warn "cache.nixos.org still fails to resolve after pinning DNS on '$conn'"
        fi
    fi
}

preflight_live() {
    log_step "Preflight (live install)"
    [ "$(id -u)" -eq 0 ] || soft_fail "must run as root, this is a live installer"
    [ -d /sys/firmware/efi ] || soft_fail "not booted in UEFI mode, this installer only supports UEFI/GPT"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 5 -o /dev/null https://cache.nixos.org \
            || soft_fail "no network reachable at cache.nixos.org, the live ISO needs network for this installer"
    else
        log_warn "curl not found, skipping network reachability check"
    fi
    require nixos-install nixos-generate-config nixos-enter git nix sed lsblk btrfs swapon timeout
    for bin in dmidecode lspci; do
        command -v "$bin" >/dev/null 2>&1 \
            || log_warn "$bin not found, host suggestion and PRIME bus-ID auto-detection will be skipped"
    done
}

suggest_host() {
    local model="" chassis="" gpu_info=""
    if command -v dmidecode >/dev/null 2>&1; then
        model=$(dmidecode -s system-product-name 2>/dev/null || true)
        chassis=$(dmidecode -s chassis-type 2>/dev/null || true)
    fi
    if command -v lspci >/dev/null 2>&1; then
        gpu_info=$(lspci 2>/dev/null | grep -iE 'vga|3d controller' || true)
    fi

    if printf '%s' "$model" | grep -qiE '330S|IdeaPad'; then
        echo taractias
        return
    fi
    if printf '%s' "$gpu_info" | grep -qi nvidia && printf '%s' "$gpu_info" | grep -qi intel; then
        echo tarmantria
        return
    fi
    if printf '%s' "$gpu_info" | grep -qi nvidia && printf '%s' "$chassis" | grep -qiE 'desktop|tower'; then
        echo tariognatha
        return
    fi
    if printf '%s' "$gpu_info" | grep -qi amd && printf '%s' "$chassis" | grep -qiE 'laptop|notebook'; then
        echo taractias
        return
    fi
    echo ""
}

choose_host() {
    if $NEW_HOST_MODE; then
        prompt_new_host
        return
    fi
    if [ -n "$HOST" ]; then
        return
    fi
    if $YES; then
        die "--host or --new-host is required together with --yes or --dry-run, no interactive prompts under --yes"
    fi
    local suggestion
    suggestion=$(suggest_host)
    HOST=$(choose_one "Select the target host" "$suggestion" "${AVAILABLE_HOSTS[@]}" "$NEW_HOST_MENU_ENTRY")
    if [ "$HOST" = "$NEW_HOST_MENU_ENTRY" ]; then
        HOST=""
        NEW_HOST_MODE=true
        prompt_new_host
    fi
}

nix_string_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//\$\{/\\\$\{}
    printf '%s' "$s"
}

sed_replacement_escape() {
    printf '%s' "$1" | sed -e 's/[\/&\\]/\\&/g'
}

template_section() {
    awk -v want="$2" '/^#== / { cur = $2; next } cur == want' "$1"
}

# $3 goes through ENVIRON, not -v, which would rewrite its backslashes.
replace_block_token() {
    local file="$1" token="@$2@" tmp
    tmp=$(mktemp "$file.XXXXXX")
    BLOCK="$3" awk -v tok="$token" '
        { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t) }
        t == tok { if (ENVIRON["BLOCK"] != "") print ENVIRON["BLOCK"]; next }
        { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
}

render_host_templates() {
    local dest="$1" host="$2" user="$3" git_name="$4" git_email="$5"
    local profile="$6" form_factor="$7" kb_layout="$8" kb_variant="$9"
    local profile_file="$TEMPLATE_DIR/profiles/$profile.nix.in"
    local ff_file="$TEMPLATE_DIR/form-factors/$form_factor.nix.in"
    [ -f "$profile_file" ] || die "unknown GPU profile '$profile', expected one of: ${GPU_PROFILES[*]}"
    [ -f "$ff_file" ] || die "unknown form factor '$form_factor', expected one of: ${FORM_FACTORS[*]}"
    mkdir -p "$dest"
    local name
    for name in default.nix disko.nix display.nix hardware-configuration.nix; do
        cp "$TEMPLATE_DIR/$name.in" "$dest/$name"
    done
    mkdir -p "$dest/illogical-impulse"
    cp "$TEMPLATE_DIR/illogical-impulse/.gitignore" "$dest/illogical-impulse/.gitignore"
    cp "$TEMPLATE_DIR/ii-settings.json" "$dest/ii-settings.json"
    replace_block_token "$dest/default.nix" PROFILE_IMPORTS "$(template_section "$profile_file" imports)"
    replace_block_token "$dest/default.nix" FORM_FACTOR_IMPORTS "$(template_section "$ff_file" imports)"
    replace_block_token "$dest/default.nix" PROFILE "$(template_section "$profile_file" body)"
    replace_block_token "$dest/display.nix" TOUCHPAD "$(template_section "$ff_file" touchpad)"
    # One sed pass cannot protect GIT_NAME: a name containing "@GIT_EMAIL@" would be rewritten again
    # by GIT_EMAIL's expression, so a git name containing @ is refused.
    case "$git_name" in
        *@*) die "git name '$git_name' contains '@', refusing to render: it could be rewritten by a later sed expression" ;;
    esac
    local sed_args=() pair key value
    for pair in "HOST=$host" "USERNAME=$user" "PROFILE_NAME=$profile" "FORM_FACTOR=$form_factor" \
        "KB_LAYOUT=$kb_layout" "KB_VARIANT=$kb_variant" "GIT_NAME=$git_name" "GIT_EMAIL=$git_email"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        sed_args+=(-e "s/@${key}@/$(sed_replacement_escape "$(nix_string_escape "$value")")/g")
    done
    for name in default.nix disko.nix display.nix hardware-configuration.nix; do
        sed -i "${sed_args[@]}" "$dest/$name"
    done
    if grep -nE '@(HOST|USERNAME|GIT_NAME|GIT_EMAIL|PROFILE_NAME|FORM_FACTOR|KB_LAYOUT|KB_VARIANT|PROFILE_IMPORTS|FORM_FACTOR_IMPORTS|PROFILE|TOUCHPAD)@' "$dest"/*.nix >&2; then
        die "unrendered @TOKEN@ left in $dest, see the lines above"
    fi
}

parse_check_nix_dir() {
    local file
    for file in "$1"/*.nix; do
        nix-instantiate --parse "$file" >/dev/null \
            || die "rendered $(basename "$file") does not parse as Nix, see the error above"
    done
}

host_known() {
    local h
    for h in "${AVAILABLE_HOSTS[@]}"; do
        [ "$h" = "$1" ] && return 0
    done
    return 1
}

# No trailing -: networking.hostName rejects it, surfacing only in nixos-install after the wipe.
# tariognatha-vm is flake.nix's VM check target, not a hosts/ dir.
check_new_hostname() {
    local name="$1"
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
        echo "hostname '$name' must start with a lowercase letter and use only a-z, 0-9 and -, at most 63 characters"
        return 1
    fi
    if [[ "$name" == *- ]]; then
        echo "hostname '$name' must not end in -, NixOS's networking.hostName rejects that"
        return 1
    fi
    if [ "$name" = tariognatha-vm ]; then
        echo "hostname 'tariognatha-vm' is taken by flake.nix's VM check target"
        return 1
    fi
    if host_known "$name"; then
        echo "hosts/$name already exists, pick it from the host list instead"
        return 1
    fi
    if [ -e "$REPO_ROOT/hosts/$name" ] || [ -L "$REPO_ROOT/hosts/$name" ]; then
        echo "hosts/$name already exists"
        return 1
    fi
    return 0
}

check_new_username() {
    local name="$1" sys
    if ! [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "username '$name' must start with a-z or _ and use only a-z, 0-9, _ and -, at most 32 characters"
        return 1
    fi
    case "$name" in
        nixbld* | systemd-*)
            echo "username '$name' is reserved for a NixOS system account"
            return 1
            ;;
    esac
    for sys in "${SYSTEM_ACCOUNT_NAMES[@]}"; do
        if [ "$sys" = "$name" ]; then
            echo "username '$name' is a system account name"
            return 1
        fi
    done
    return 0
}

# No @: keeps the leftover-@TOKEN@ check in render_host_templates unambiguous.
check_git_name() {
    if [ -z "$1" ]; then
        echo "git name must not be empty"
        return 1
    fi
    if [[ "$1" == *@* || "$1" == *[[:cntrl:]]* ]]; then
        echo "git name must not contain @ or control characters"
        return 1
    fi
    return 0
}

check_git_email() {
    if ! [[ "$1" =~ ^[^@[:space:][:cntrl:]]+@[^@[:space:][:cntrl:]]+$ ]]; then
        echo "git email '$1' must look like name@domain, with one @ and no spaces"
        return 1
    fi
    return 0
}

check_kb_layout() {
    if ! [[ "$1" =~ ^[a-z0-9_]+(,[a-z0-9_]+)*$ ]]; then
        echo "keyboard layout '$1' must be an XKB layout such as at or de,us"
        return 1
    fi
    return 0
}

check_kb_variant() {
    if ! [[ "$1" =~ ^[a-z0-9_,-]*$ ]]; then
        echo "keyboard variant '$1' must be an XKB variant such as nodeadkeys, or empty"
        return 1
    fi
    return 0
}

check_profile() {
    local p
    for p in "${GPU_PROFILES[@]}"; do
        [ "$p" != "$1" ] || return 0
    done
    echo "unknown GPU profile '$1', expected one of: ${GPU_PROFILES[*]}"
    return 1
}

check_form_factor() {
    local f
    for f in "${FORM_FACTORS[@]}"; do
        [ "$f" != "$1" ] || return 0
    done
    echo "unknown form factor '$1', expected one of: ${FORM_FACTORS[*]}"
    return 1
}

# Prints "<gpu-profile> <form-factor>" with one space, so an empty field stays empty.
# AMD+NVIDIA PRIME is unsupported: NVIDIA without Intel suggests nvidia-desktop.
suggest_profile() {
    local chassis="" gpu_info="" profile="" form_factor=""
    if command -v dmidecode >/dev/null 2>&1; then
        chassis=$(dmidecode -s chassis-type 2>/dev/null || true)
    fi
    if command -v lspci >/dev/null 2>&1; then
        gpu_info=$(lspci 2>/dev/null | grep -iE 'vga|3d controller' || true)
    fi
    if printf '%s' "$chassis" | grep -qiE 'laptop|notebook|portable|convertible|detachable'; then
        form_factor=laptop
    elif printf '%s' "$chassis" | grep -qiE 'desktop|tower|mini pc|all in one'; then
        form_factor=desktop
    fi
    if printf '%s' "$gpu_info" | grep -qi nvidia; then
        if printf '%s' "$gpu_info" | grep -qi intel; then
            # intel-nvidia-prime switches iGPU/NVIDIA to save battery, which only matters on a laptop.
            if [ "$form_factor" = desktop ]; then
                profile=nvidia-desktop
            else
                profile=intel-nvidia-prime
            fi
        else
            profile=nvidia-desktop
        fi
    elif printf '%s' "$gpu_info" | grep -qiE 'amd|advanced micro devices'; then
        profile=amd-igpu
    elif printf '%s' "$gpu_info" | grep -qi intel; then
        profile=intel-igpu
    fi
    printf '%s %s\n' "$profile" "$form_factor"
}

validate_new_host_flags() {
    local given=() reason
    [ -z "$NEW_USER" ] || given+=(--user)
    [ -z "$NEW_GIT_NAME" ] || given+=(--git-name)
    [ -z "$NEW_GIT_EMAIL" ] || given+=(--git-email)
    [ -z "$NEW_PROFILE" ] || given+=(--profile)
    [ -z "$NEW_FORM_FACTOR" ] || given+=(--form-factor)
    [ -z "$NEW_KB_LAYOUT" ] || given+=(--kb-layout)
    if $NEW_KB_VARIANT_SET; then
        given+=(--kb-variant)
    fi
    if ! $NEW_HOST_MODE; then
        [ "${#given[@]}" -eq 0 ] || usage_die "${given[*]} only apply together with --new-host"
        return 0
    fi
    [ "$MODE" = install ] || usage_die "--new-host only works in install mode, setup mode runs on a host already in hosts/"
    [ -z "$HOST" ] || usage_die "--host and --new-host are mutually exclusive"
    reason=$(check_new_hostname "$NEW_HOST") || usage_die "--new-host: $reason"
    if $YES; then
        local missing=()
        [ -n "$NEW_USER" ] || missing+=(--user)
        [ -n "$NEW_PROFILE" ] || missing+=(--profile)
        [ -n "$NEW_FORM_FACTOR" ] || missing+=(--form-factor)
        [ "${#missing[@]}" -eq 0 ] || usage_die "--yes --new-host also requires ${missing[*]}"
    fi
    if [ -n "$NEW_USER" ]; then
        reason=$(check_new_username "$NEW_USER") || usage_die "--user: $reason"
    fi
    if [ -n "$NEW_GIT_NAME" ]; then
        reason=$(check_git_name "$NEW_GIT_NAME") || usage_die "--git-name: $reason"
    fi
    if [ -n "$NEW_GIT_EMAIL" ]; then
        reason=$(check_git_email "$NEW_GIT_EMAIL") || usage_die "--git-email: $reason"
    fi
    if [ -n "$NEW_PROFILE" ]; then
        reason=$(check_profile "$NEW_PROFILE") || usage_die "--profile: $reason"
    fi
    if [ -n "$NEW_FORM_FACTOR" ]; then
        reason=$(check_form_factor "$NEW_FORM_FACTOR") || usage_die "--form-factor: $reason"
    fi
    if [ -n "$NEW_KB_LAYOUT" ]; then
        reason=$(check_kb_layout "$NEW_KB_LAYOUT") || usage_die "--kb-layout: $reason"
    fi
    if $NEW_KB_VARIANT_SET; then
        reason=$(check_kb_variant "$NEW_KB_VARIANT") || usage_die "--kb-variant: $reason"
    fi
}

prompt_validated() {
    local prompt="$1" default="$2" validator="$3" answer reason
    while true; do
        answer=$(gum_tty input --prompt "$prompt: " --value "$default" --placeholder "$default")
        if reason=$("$validator" "$answer"); then
            log_info "$prompt: $answer"
            printf '%s\n' "$answer"
            return 0
        fi
        log_warn "$reason"
    done
}

prompt_new_host() {
    log_step "New host"
    if [ -z "$NEW_HOST" ]; then
        NEW_HOST=$(prompt_validated "Hostname" "" check_new_hostname)
    fi
    if [ -z "$NEW_USER" ]; then
        NEW_USER=$(prompt_validated "Login username" "$DEFAULT_INSTALL_USER" check_new_username)
    fi
    if [ -z "$NEW_GIT_NAME" ]; then
        if $YES; then
            NEW_GIT_NAME="$NEW_USER"
        else
            NEW_GIT_NAME=$(prompt_validated "git user.name" "$NEW_USER" check_git_name)
        fi
    fi
    if [ -z "$NEW_GIT_EMAIL" ]; then
        if $YES; then
            NEW_GIT_EMAIL="$DEFAULT_GIT_EMAIL"
        else
            NEW_GIT_EMAIL=$(prompt_validated "git user.email" "$DEFAULT_GIT_EMAIL" check_git_email)
        fi
    fi
    if [ -z "$NEW_PROFILE" ] || [ -z "$NEW_FORM_FACTOR" ]; then
        local suggestion
        suggestion=$(suggest_profile)
        if [ -z "$NEW_PROFILE" ]; then
            NEW_PROFILE=$(choose_one "GPU profile for $NEW_HOST" "${suggestion%% *}" "${GPU_PROFILES[@]}")
        fi
        if [ -z "$NEW_FORM_FACTOR" ]; then
            NEW_FORM_FACTOR=$(choose_one "Form factor for $NEW_HOST" "${suggestion#* }" "${FORM_FACTORS[@]}")
        fi
    fi
    if [ -z "$NEW_KB_LAYOUT" ]; then
        if $YES; then
            NEW_KB_LAYOUT="$DEFAULT_KB_LAYOUT"
        else
            NEW_KB_LAYOUT=$(prompt_validated "Keyboard layout" "$DEFAULT_KB_LAYOUT" check_kb_layout)
        fi
    fi
    if ! $NEW_KB_VARIANT_SET; then
        # nodeadkeys only fits the at layout; other layouts get no variant.
        local default_kb_variant=""
        if [ "$NEW_KB_LAYOUT" = "$DEFAULT_KB_LAYOUT" ]; then
            default_kb_variant="$DEFAULT_KB_VARIANT"
        fi
        if $YES; then
            NEW_KB_VARIANT="$default_kb_variant"
        else
            NEW_KB_VARIANT=$(prompt_validated "Keyboard variant (may be empty)" "$default_kb_variant" check_kb_variant)
        fi
        NEW_KB_VARIANT_SET=true
    fi
    HOST="$NEW_HOST"
    log_info "new host $HOST: user $NEW_USER, git $NEW_GIT_NAME <$NEW_GIT_EMAIL>, $NEW_PROFILE, $NEW_FORM_FACTOR, keyboard $NEW_KB_LAYOUT/${NEW_KB_VARIANT:-<none>}"
}

# Excludes zram, device-mapper, MD-RAID and loop by name; lsblk's TYPE filter misses zram.
is_excluded_disk_name() {
    case "$1" in
        zram* | dm-* | md* | loop*) return 0 ;;
        *) return 1 ;;
    esac
}

choose_disk() {
    if [ -n "$DISK" ]; then
        return
    fi
    if $YES; then
        die "--disk is required together with --yes or --dry-run, no interactive prompts under --yes"
    fi

    local iso_disk=""
    if command -v findmnt >/dev/null 2>&1; then
        iso_disk=$(findmnt -no PKNAME /iso 2>/dev/null || true)
    fi

    local candidates=() line base
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        base=$(basename "${line%% *}")
        if is_excluded_disk_name "$base"; then
            continue
        fi
        if [ -n "$iso_disk" ] && [ "$base" = "$iso_disk" ]; then
            continue
        fi
        candidates+=("$line")
    done < <(lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$NF == "disk"')

    [ "${#candidates[@]}" -gt 0 ] || die "no candidate disks found, lsblk found nothing besides the ISO device"

    local chosen
    chosen=$(choose_one "Select the target disk. THIS WILL BE ERASED." "" "${candidates[@]}")
    DISK=$(printf '%s' "$chosen" | awk '{print $1}')

    local by_id="" candidate
    while IFS= read -r candidate; do
        case "$candidate" in
            *-part*) continue ;;
        esac
        case "$(basename "$candidate")" in
            wwn-*)
                [ -n "$by_id" ] || by_id="$candidate"
                ;;
            *)
                by_id="$candidate"
                break
                ;;
        esac
    done < <(find -L /dev/disk/by-id -maxdepth 1 -samefile "$DISK" 2>/dev/null)

    if [ -n "$by_id" ] && confirm "Use the stable path $by_id instead of $DISK?"; then
        DISK="$by_id"
    fi
}

validate_disk_charset() {
    case "$DISK" in
        *[!A-Za-z0-9/_.:-]*)
            die "disk path contains characters unsafe for this script's sed use: $DISK"
            ;;
    esac
}

# Under --dry-run only warns, for placeholder paths like /dev/null in container tests.
validate_disk_is_physical() {
    if [ -b "$DISK" ]; then
        :
    else
        soft_fail "not a block device: $DISK"
    fi
    local disk_type
    disk_type=$(lsblk -dno TYPE "$DISK" 2>/dev/null || true)
    if [ "$disk_type" = "disk" ]; then
        :
    else
        soft_fail "lsblk does not report $DISK as TYPE=disk, got '${disk_type:-<none>}'"
    fi
}

confirm_wipe_target() {
    local kernel
    kernel=$(basename "$(readlink -f "$DISK")")
    local kernel_hl
    kernel_hl=$(gum style --foreground 226 --bold "$kernel")
    local host_label="$HOST"
    if $NEW_HOST_MODE; then
        host_label="$HOST (new: hosts/$HOST is written after this confirmation)"
    fi
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "This will ERASE ALL DATA on:" "" "  $DISK" "  resolves to /dev/$kernel_hl" "" "Host: $host_label" >&2
    if $YES; then
        log_warn "auto-confirmed wipe of $DISK via --yes"
        return
    fi
    local typed
    typed=$(gum_tty input --placeholder "$kernel" --prompt "Type $kernel_hl to confirm: ")
    [ "$typed" = "$kernel" ] || die "typed name did not match $kernel (device $DISK), aborting"
    log_info "wipe confirmed for /dev/$kernel"
}

# Runs only after the wipe is confirmed, so an earlier abort leaves the repo untouched.
# A later failure leaves the host in place; a rerun picks it from the menu.
scaffold_host() {
    log_step "Scaffolding hosts/$HOST ($NEW_PROFILE, $NEW_FORM_FACTOR, user $NEW_USER)"
    require nix-instantiate awk
    local dest="$REPO_ROOT/hosts/$HOST"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        die "$dest already exists, rerun and pick $HOST from the host list instead"
    fi
    SCAFFOLD_STAGING=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-scaffold.XXXXXX")
    render_host_templates "$SCAFFOLD_STAGING" "$HOST" "$NEW_USER" "$NEW_GIT_NAME" "$NEW_GIT_EMAIL" \
        "$NEW_PROFILE" "$NEW_FORM_FACTOR" "$NEW_KB_LAYOUT" "$NEW_KB_VARIANT"
    parse_check_nix_dir "$SCAFFOLD_STAGING"
    log_ok "rendered and parse-checked hosts/$HOST in $SCAFFOLD_STAGING"
    if $DRY_RUN; then
        SCAFFOLD_PREVIEW_DIR="$SCAFFOLD_STAGING"
    else
        # Check .sops.yaml is readable first so rollback never fabricates an empty one.
        [ -f "$REPO_ROOT/.sops.yaml" ] || die "$REPO_ROOT/.sops.yaml not found, cannot register sops placeholders for $HOST"
        # Snapshot .sops.yaml (uncommitted edits included) in TMPDIR, outside SCAFFOLD_STAGING, which is copied to hosts/$HOST/.
        SCAFFOLD_SOPS_SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/krane-install-sops-snapshot.XXXXXX")
        cp -p "$REPO_ROOT/.sops.yaml" "$SCAFFOLD_SOPS_SNAPSHOT"
        SCAFFOLD_PENDING=true
    fi
    run mkdir -p "$dest"
    run cp -a "$SCAFFOLD_STAGING/." "$dest/"
    run chmod -R u+rwX,go+rX,go-w "$dest"
    run register_sops_host "$REPO_ROOT/.sops.yaml" "$HOST"
    SCAFFOLD_PENDING=false
    if [ -n "$SCAFFOLD_SOPS_SNAPSHOT" ]; then
        rm -f "$SCAFFOLD_SOPS_SNAPSHOT"
        SCAFFOLD_SOPS_SNAPSHOT=""
    fi
}

patch_disko_file() {
    local disko_file="$1" disk="$2"
    if grep -qF "device = \"$disk\";" "$disko_file"; then
        log_info "disko.nix already patched for $disk"
        return 0
    fi
    # A committed disk that differs from the chosen one is a hard stop: the by-id path in git is the
    # only disk-choice check outside this prompt flow. Record the new disk in git first.
    if ! grep -qF 'device = "/dev/CHANGE-ME";' "$disko_file"; then
        local committed
        committed=$(sed -n 's/^[[:space:]]*device = "\(.*\)";.*/\1/p' "$disko_file" | head -n 1)
        die "$disko_file is set up for ${committed:-another disk}, not $disk. To install onto $disk (e.g. after replacing the disk), set its device line to \"$disk\" or \"/dev/CHANGE-ME\", commit, and rerun"
    fi
    run sed -i "s#device = \"/dev/CHANGE-ME\";#device = \"$disk\";#" "$disko_file"
    if ! $DRY_RUN; then
        grep -qF "device = \"$disk\";" "$disko_file" || die "post-sed verification failed: $disko_file"
    fi
}

patch_disko() {
    log_step "Patching hosts/$HOST/disko.nix for $DISK"
    validate_disk_charset
    patch_disko_file "$(host_dir)/disko.nix" "$DISK"
}

# Runs after patch_disko's `git add -A`: a new host's files are invisible to the flake until staged.
# Under --dry-run a new host is never staged, so the prompted username stands in.
resolve_install_user() {
    if $NEW_HOST_MODE && $DRY_RUN; then
        INSTALL_USER="$NEW_USER"
        log_info "login user for $HOST: $INSTALL_USER (prompted, a new host is not evaluated under --dry-run)"
        return 0
    fi
    local user=""
    user=$(nix eval --raw "$REPO_ROOT#nixosConfigurations.$HOST.config.krane.user.name") || user=""
    if [ -z "$user" ]; then
        soft_fail "could not evaluate nixosConfigurations.$HOST.config.krane.user.name"
        user="${NEW_USER:-$DEFAULT_INSTALL_USER}"
    fi
    if $NEW_HOST_MODE && [ "$user" != "$NEW_USER" ]; then
        die "hosts/$HOST evaluates to login user '$user', but '$NEW_USER' was entered, check hosts/$HOST/default.nix"
    fi
    INSTALL_USER="$user"
    log_info "login user for $HOST: $INSTALL_USER"
}

run_disko() {
    log_step "Running disko for $HOST (formats $DISK)"
    local disko_script
    # shellcheck disable=SC2046 # flake_config_opt's words must split into separate --option args.
    disko_script=$(capture_with_spin "Evaluating disko script for $HOST" \
        nix build --no-link --print-out-paths $(flake_config_opt) \
        "$REPO_ROOT#nixosConfigurations.$HOST.config.system.build.diskoScript")
    # No spinner or extra tee: output must stream live.
    run_sh "\"$disko_script\" 2>&1" || { LAST_CMD=""; die "disko run failed for $HOST, see $LOG"; }
}

install_swap_needed() { [ "$1" -lt 25165824 ]; }

# The live ISO has no swap backing RAM, so nixos-install's nix build can OOM on low-RAM machines.
# Swap is best-effort: a failed mkswapfile or swapon warns and continues.
setup_install_swap() {
    log_step "Checking RAM for an install swapfile"
    local mem_kb=""
    if [ -r /proc/meminfo ]; then
        mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)
    fi
    if [ -z "$mem_kb" ]; then
        log_warn "cannot read /proc/meminfo, skipping install swapfile"
        return
    fi
    local mem_gib=$(( (mem_kb + 524288) / 1048576 ))
    if install_swap_needed "$mem_kb"; then
        log_info "RAM is $mem_gib GiB, creating a 16 GiB swapfile on /mnt for the install"
        INSTALL_SWAP_ACTIVE=true
        run_soft btrfs filesystem mkswapfile --size 16g /mnt/swapfile \
            || { log_warn "could not create the install swapfile, continuing without it"; teardown_install_swap; return; }
        run_soft swapon /mnt/swapfile \
            || { log_warn "could not enable the install swapfile, continuing without it"; teardown_install_swap; return; }
        INSTALL_SWAP_ON=true
    else
        log_info "RAM is $mem_gib GiB, no install swapfile needed"
    fi
}

generate_hardware_config() {
    log_step "Generating hosts/$HOST/hardware-configuration.nix"
    local out="$REPO_ROOT/hosts/$HOST/hardware-configuration.nix"
    run_sh "nixos-generate-config --no-filesystems --root /mnt --show-hardware-config > \"$out\""
    if ! $DRY_RUN; then
        grep -q 'availableKernelModules' "$out" || die "$out is missing availableKernelModules, nixos-generate-config may have failed"
        if grep -q 'fileSystems' "$out"; then
            die "$out unexpectedly contains fileSystems, disko manages filesystems for this flake, not nixos-generate-config"
        fi
    fi
}

# lspci -D prints hex DDDD:bb:dd.f; krane.prime.*BusId wants decimal PCI:bus:device:function.
pci_addr_to_bus_id() {
    local addr="$1" bdf bus dev fn rest
    bdf="${addr#*:}"
    bus="${bdf%%:*}"
    rest="${bdf#*:}"
    dev="${rest%%.*}"
    fn="${rest#*.}"
    printf 'PCI:%d:%d:%d' "$((16#$bus))" "$((16#$dev))" "$((16#$fn))"
}

patch_prime_line() {
    local file="$1" key="$2" value="$3"
    local target="krane.prime.${key} = \"${value}\"; # set by install.sh"
    if grep -qF "$target" "$file"; then
        log_info "$key already patched to $value"
        return 0
    fi
    if ! grep -qE "^[[:space:]]*krane\.prime\.${key}[[:space:]]*=[[:space:]]*\"" "$file"; then
        die "$file has no krane.prime.${key} assignment to patch"
    fi
    # | as sed delimiter: the replacement contains a literal #.
    run sed -i -E "s|(krane\.prime\.${key}[[:space:]]*=[[:space:]]*)\"[^\"]*\"[[:space:]]*;.*|\\1\"${value}\"; # set by install.sh|" "$file"
    if ! $DRY_RUN; then
        grep -qF "$target" "$file" || die "post-sed verification failed for $key in $file"
    fi
}

patch_prime() {
    local default_nix
    default_nix="$(host_dir)/default.nix"
    if ! grep -qE '^[[:space:]]*krane\.prime\.(intelBusId|nvidiaBusId)[[:space:]]*=[[:space:]]*"' "$default_nix"; then
        return 0
    fi

    log_step "Detecting PRIME PCI bus IDs for $HOST"
    if ! command -v lspci >/dev/null 2>&1; then
        soft_fail "lspci not found, cannot auto-detect PRIME bus IDs, edit $default_nix by hand"
        return 0
    fi

    local lspci_out intel_addr nvidia_addr
    # || true: a non-zero lspci must fall through to soft_fail.
    lspci_out=$(lspci -D) || true
    # || true: an empty grep match must not abort under pipefail.
    intel_addr=$(printf '%s\n' "$lspci_out" | grep -i vga | grep -i intel | head -1 | awk '{print $1}' || true)
    nvidia_addr=$(printf '%s\n' "$lspci_out" | grep -iE '3d controller|vga' | grep -i nvidia | head -1 | awk '{print $1}' || true)
    if [ -z "$intel_addr" ] || [ -z "$nvidia_addr" ]; then
        soft_fail "could not find both an Intel and an NVIDIA PCI device via 'lspci -D'; edit $default_nix by hand"
        return 0
    fi

    local intel_bus nvidia_bus
    intel_bus=$(pci_addr_to_bus_id "$intel_addr")
    nvidia_bus=$(pci_addr_to_bus_id "$nvidia_addr")
    log_info "Intel $intel_addr -> $intel_bus"
    log_info "NVIDIA $nvidia_addr -> $nvidia_bus"

    patch_prime_line "$default_nix" "intelBusId" "$intel_bus"
    patch_prime_line "$default_nix" "nvidiaBusId" "$nvidia_bus"
}

# Commit before nixos-install so the copied repo starts clean; the new host's files, .sops.yaml
# placeholders and hardware config land in this one commit.
commit_hardware_config() {
    log_step "Committing local hardware config for $HOST"
    run git -C "$REPO_ROOT" add -A
    if ! $DRY_RUN && git -C "$REPO_ROOT" diff --cached --quiet; then
        log_info "nothing new to commit for $HOST hardware config"
        return 0
    fi
    local id_args=()
    if [ -z "$(git -C "$REPO_ROOT" config user.email 2>/dev/null || true)" ]; then
        id_args=(-c "user.name=$INSTALL_USER" -c "user.email=$INSTALL_USER@localhost")
    fi
    local message="Configure $HOST hardware"
    if $NEW_HOST_MODE; then
        message="Add $HOST host"
    fi
    run git -C "$REPO_ROOT" "${id_args[@]}" commit -m "$message" --quiet
}

run_nixos_install() {
    log_step "Running nixos-install for $HOST"
    if host_uses_cuda; then
        log_info "$HOST has CUDA packages, passing cache.nixos-cuda.org substituter options"
    else
        log_info "host has no CUDA packages, CUDA cache disabled for this install"
    fi
    local flake_opt
    flake_opt=$(flake_config_opt)
    local install_cores
    install_cores=$(( $(command -v nproc >/dev/null 2>&1 && nproc || echo 1) / 2 ))
    [ "$install_cores" -ge 1 ] || install_cores=1
    log_info "Limiting nixos-install to max-jobs 1, cores $install_cores to avoid OOM on the live ISO"
    local install_nix_config="$NIX_CONFIG"$'\n'"max-jobs = 1"$'\n'"cores = $install_cores"
    run mkdir -p /mnt/var/cache/installer/tmp
    local attempt
    for attempt in 1 2 3; do
        local log_mark
        log_mark=$(wc -l < "$LOG" 2>/dev/null || echo 0)
        run_sh "NIX_CONFIG=$(printf '%q' "$install_nix_config") TMPDIR=/mnt/var/cache/installer/tmp XDG_CACHE_HOME=/mnt/var/cache/installer nixos-install --flake \"$REPO_ROOT#$HOST\" --no-root-passwd $flake_opt 2>&1" \
            && break
        LAST_CMD=""
        if [ "$attempt" -eq 3 ]; then
            die "nixos-install failed 3 times for $HOST, see $LOG"
        fi
        local logline tail_lines=()
        if $LOG_WRITABLE; then
            while IFS= read -r logline; do
                tail_lines+=("$logline")
            done < <(tail -n "+$((log_mark + 1))" "$LOG" | clean_log_lines | tail -n 5)
        fi
        log_warn "nixos-install failed (attempt $attempt of 3)"
        for logline in "${tail_lines[@]}"; do
            log_warn "$logline"
        done
        confirm "Retry nixos-install? (already copied paths are kept)" \
            || die "not retrying nixos-install for $HOST, declined after attempt $attempt"
        sleep 10
    done
    run rm -rf /mnt/var/cache/installer
}

# Not skipped under --yes: a fresh install needs a login.
set_user_password() {
    log_step "Set $INSTALL_USER's password on the new install"

    if ! $DRY_RUN && [ ! -t 0 ]; then
        print_no_password_box
        PASSWORD_SET=false
        return 0
    fi

    local attempt=1
    while [ "$attempt" -le 3 ]; do
        if run nixos-enter --root /mnt -- passwd "$INSTALL_USER"; then
            PASSWORD_SET=true
            return 0
        fi
        log_warn "passwd failed (attempt $attempt/3)"
        attempt=$((attempt + 1))
    done
    print_no_password_box
    PASSWORD_SET=false
}

print_no_password_box() {
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "NO PASSWORD SET" "" \
        "Run this yourself before rebooting:" "" \
        "  nixos-enter --root /mnt -- passwd $INSTALL_USER" >&2
}

finish_install() {
    [ -n "$INSTALL_USER" ] || die "INSTALL_USER is unset, resolve_install_user did not run"
    local home_dir="/home/$INSTALL_USER"
    log_step "Copying repo to /mnt$home_dir/.dotfiles"
    run mkdir -p "/mnt$home_dir/.dotfiles"
    run_sh "cp -a \"$REPO_ROOT/.\" \"/mnt$home_dir/.dotfiles/\""
    run nixos-enter --root /mnt -- chown -R "$INSTALL_USER:users" "$home_dir/.dotfiles"
    run_sh "test -f \"/mnt$home_dir/.dotfiles/flake.nix\"" \
        || die "repo copy to /mnt$home_dir/.dotfiles is missing flake.nix, see $LOG"

    PASSWORD_SET=true
    set_user_password

    banner "Install complete" \
        "Next steps:" \
        "  1. reboot" \
        "  2. ~/.dotfiles/install.sh --mode setup" \
        "  3. second switch, setup mode drives this"

    # The live ISO checkout is lost at reboot; the only other copy is on the target disk.
    if $NEW_HOST_MODE; then
        gum style \
            --border double --border-foreground 226 --foreground 226 --bold \
            --padding "1 3" --margin "1 0" \
            "hosts/$HOST is new and not pushed anywhere" "" \
            "It exists only as a local commit in $home_dir/.dotfiles on the new install." \
            "Push it from there after first boot, or it is lost with this disk." >&2
    fi

    if $PASSWORD_SET; then
        if confirm "Reboot now?"; then
            run reboot
        fi
    else
        log_warn "not offering to reboot, set $INSTALL_USER's password first"
    fi
}

run_install_mode() {
    preflight_live
    choose_host
    check_dns
    choose_disk
    validate_disk_is_physical

    confirm_wipe_target
    if $NEW_HOST_MODE; then
        scaffold_host
    fi
    patch_disko
    run git -C "$REPO_ROOT" add -A
    resolve_install_user
    run_disko
    setup_install_swap
    generate_hardware_config
    patch_prime
    commit_hardware_config
    run_nixos_install
    teardown_install_swap
    finish_install
}

preflight_setup() {
    log_step "Preflight (setup mode)"
    if [ "$(id -u)" -eq 0 ]; then
        soft_fail "setup mode must not run as root, bootstrap-sops.sh needs to write your personal age key under \$HOME"
    fi
    require git just sops age ssh-to-age
    HOST="${HOST:-$(hostname)}"
    # Setup mode needs an installed host config; new hosts are created only in install mode.
    host_known "$HOST" || die "host '$HOST' not in hosts/ — install it via install mode, or pass --host"
    if [ "$REPO_ROOT" != "$HOME/.dotfiles" ]; then
        log_warn "checked out at $REPO_ROOT, not \$HOME/.dotfiles. The docs assume the latter"
    fi
}

# True when $1 (.sops.yaml) still has either of $2's age1PLACEHOLDER_HOST_/ADMIN_ recipients
# (see scripts/bootstrap-sops.sh), or is missing.
sops_placeholder_present() {
    local sops_yaml="$1" host="$2" host_upper host_placeholder admin_placeholder
    [ -f "$sops_yaml" ] || return 0
    host_upper=$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')
    host_placeholder="age1PLACEHOLDER_HOST_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH"
    admin_placeholder="age1PLACEHOLDER_ADMIN_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH"
    grep -qF "$host_placeholder" "$sops_yaml" 2>/dev/null \
        || grep -qF "$admin_placeholder" "$sops_yaml" 2>/dev/null
}

# Adds host $2's two age1PLACEHOLDER_* recipients to $1 as the last `keys:` entries plus a creation rule
# for secrets/$2.yaml, the shape bootstrap-sops.sh expects. No-op when an anchor exists, matched whole so
# `tar` never hits `&admin_taractias`.
register_sops_host() {
    local sops_yaml="$1" host="$2" host_upper tmp
    [ -f "$sops_yaml" ] || die "$sops_yaml not found, cannot register sops placeholders for $host"
    if grep -qE "&(admin|host)_${host}([[:space:]]|\$)" "$sops_yaml"; then
        log_info "$sops_yaml already has anchors for $host, leaving it as is"
        return 0
    fi
    grep -q '^creation_rules:' "$sops_yaml" \
        || die "$sops_yaml has no top-level creation_rules:, cannot place $host's recipients"
    host_upper=$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')
    tmp=$(mktemp "${TMPDIR:-/tmp}/krane-install-sops.XXXXXX")
    # Blank lines are held until the next non-blank, so new keys land after the last keys: entry, before creation_rules:.
    awk -v host="$host" -v upper="$host_upper" '
        /^creation_rules:/ && !done {
            printf "  - &admin_%s age1PLACEHOLDER_ADMIN_%s_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n", host, upper
            printf "  - &host_%s age1PLACEHOLDER_HOST_%s_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n", host, upper
            printf "%s", gap
            gap = ""
            done = 1
            print
            next
        }
        /^[[:space:]]*$/ && !done { gap = gap $0 "\n"; next }
        { printf "%s", gap; gap = ""; print }
        END {
            printf "%s", gap
            printf "\n  - path_regex: secrets/%s\\.yaml$\n", host
            printf "    key_groups:\n      - age:\n          - *admin_%s\n          - *host_%s\n", host, host
        }
    ' "$sops_yaml" >"$tmp"
    if ! grep -qF "&admin_${host} age1PLACEHOLDER_ADMIN_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH" "$tmp" \
        || ! grep -qF "&host_${host} age1PLACEHOLDER_HOST_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH" "$tmp"; then
        rm -f "$tmp"
        die "post-awk verification failed for $host in $sops_yaml"
    fi
    # cat into the original, not mv, to keep its mode and owner.
    cat "$tmp" >"$sops_yaml"
    rm -f "$tmp"
}

# True when $2 in repo $1 has no uncommitted change (modified, untracked, staged or deleted).
# Checked before staging so a declined confirm stages nothing; works on an unborn branch.
git_path_clean() {
    local repo="$1" path="$2"
    [ -z "$(git -C "$repo" status --porcelain -- "$path" 2>/dev/null)" ]
}

# Re-runnable: a prior run may have committed the patched .sops.yaml, and `git commit` on a clean tree exits 1.
run_bootstrap_sops() {
    log_step "Bootstrapping sops-nix recipients for $HOST"
    local key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if sops_placeholder_present "$REPO_ROOT/.sops.yaml" "$HOST"; then
        run_sh "\"$REPO_ROOT/scripts/bootstrap-sops.sh\" \"$HOST\""
    elif [ -f "$key_file" ]; then
        # A mismatch with the registered admin_$HOST recipient usually means the key came from another host
        # or was regenerated, so secrets would fail to decrypt.
        if command -v age-keygen >/dev/null 2>&1; then
            local local_pub registered_pub
            local_pub=$(age-keygen -y "$key_file" 2>/dev/null || true)
            registered_pub=$(command grep -F "&admin_${HOST}" "$REPO_ROOT/.sops.yaml" 2>/dev/null | command grep -oE 'age1[0-9a-z]+' | head -n1 || true)
            if [ -n "$local_pub" ] && [ -n "$registered_pub" ] && [ "$local_pub" != "$registered_pub" ]; then
                local mismatch_msg="local personal age key $key_file (public key $local_pub) does not match this host's admin_$HOST recipient registered in .sops.yaml ($registered_pub); restore the matching key from your backup (see secrets/README.md) or re-run scripts/bootstrap-sops.sh $HOST to register this key instead"
                if $DRY_RUN; then
                    log_warn "$mismatch_msg"
                else
                    die "$mismatch_msg"
                fi
            fi
        else
            log_warn "age-keygen not found, skipping verification that $key_file matches the admin_$HOST recipient in .sops.yaml"
        fi
        if $DRY_RUN; then
            log_info "would skip bootstrap: sops already bootstrapped for $HOST"
        else
            log_info "sops already bootstrapped for $HOST, skipping"
        fi
    else
        # Re-running bootstrap-sops.sh would generate a personal key that never becomes a recipient,
        # locking secrets out. Fail instead.
        local host_upper
        host_upper=$(printf '%s' "$HOST" | tr '[:lower:]' '[:upper:]')
        local msg="sops already bootstrapped for $HOST but personal key $key_file is missing; restore it from your backup (see secrets/README.md) or re-add the age1PLACEHOLDER_ADMIN_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH placeholder to .sops.yaml and rerun"
        if $DRY_RUN; then
            log_warn "$msg"
        else
            die "$msg"
        fi
    fi
    if git_path_clean "$REPO_ROOT" .sops.yaml; then
        if $DRY_RUN; then
            log_info "would skip: nothing to commit for .sops.yaml"
        else
            log_info "nothing to commit for .sops.yaml"
        fi
        return 0
    fi
    if confirm "Commit .sops.yaml now?"; then
        run git -C "$REPO_ROOT" add -- .sops.yaml
        if git -C "$REPO_ROOT" diff --cached --quiet HEAD -- .sops.yaml 2>/dev/null; then
            log_info "nothing to commit for .sops.yaml after staging"
        else
            run git -C "$REPO_ROOT" commit -m "Add $HOST sops recipient"
        fi
    fi
}

edit_host_secrets() {
    local secrets_file="$REPO_ROOT/secrets/$HOST.yaml"
    if $YES; then
        log_info "skipping interactive secrets edit under --yes, run 'sops $secrets_file' later"
        return
    fi
    if confirm "Edit $secrets_file with sops now?"; then
        log_info "opening sops editor for secrets/$HOST.yaml (output goes to the terminal, not the log)"
        run_tty "sops \"$secrets_file\"" || {
            local rc=$?
            LAST_CMD=""
            [ "$rc" -eq 200 ] || die "sops failed on $secrets_file (exit $rc)"
            log_warn "sops left $secrets_file unchanged, skipping commit"
            return 0
        }
        log_warn "uncommitted secrets evaluate as ABSENT to sops-nix, commit $secrets_file before rebuilding"
        [ -f "$secrets_file" ] || { log_info "no $secrets_file to commit"; return 0; }
        if git_path_clean "$REPO_ROOT" "secrets/$HOST.yaml"; then
            log_info "nothing to commit for $HOST secrets"
            return
        fi
        if confirm "Commit $secrets_file now?"; then
            run git -C "$REPO_ROOT" add -- "secrets/$HOST.yaml"
            if git -C "$REPO_ROOT" diff --cached --quiet HEAD -- "secrets/$HOST.yaml" 2>/dev/null; then
                log_info "nothing to commit for secrets/$HOST.yaml after staging"
            else
                run git -C "$REPO_ROOT" commit -m "Add $HOST secrets"
            fi
        fi
    fi
}

setup_rust() {
    log_step "Rust toolchain (rustup)"
    if ! command -v rustup >/dev/null 2>&1; then
        log_warn "rustup not found, skipping"
        return
    fi
    if confirm "Run 'rustup default stable' and add rust-analyzer + rust-src?"; then
        run rustup default stable
        run rustup component add rust-analyzer rust-src
    fi
}

check_flathub() {
    log_step "Checking the flathub flatpak remote"
    if ! command -v flatpak >/dev/null 2>&1; then
        log_warn "flatpak not found, skipping flathub remote check"
        return
    fi
    if flatpak remote-list 2>/dev/null | grep -qi flathub; then
        log_ok "flathub remote already registered"
        return
    fi
    if confirm "flathub remote missing, add it now?"; then
        run_sh "flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    fi
}

verify_check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        log_ok "$desc"
    else
        log_warn "$desc, see docs/VERIFY.md"
    fi
}

verify_skip() {
    log_info "[SKIP] $1, $2"
}

verify_checks() {
    log_step "VERIFY checklist (docs/VERIFY.md section 2)"
    # shellcheck disable=SC2016
    verify_check "keybinds.lua has the GENERATED header" \
        bash -c 'head -4 "$HOME/.config/hypr/custom/keybinds.lua" | grep -q "GENERATED FILE"'
    # shellcheck disable=SC2016
    verify_check "env.lua override sentinel appears exactly once" \
        bash -c '[ "$(grep -c -- "-- >>> krane overrides >>>" "$HOME/.config/hypr/custom/env.lua" 2>/dev/null || echo 0)" = 1 ]'
    # shellcheck disable=SC2016
    verify_check "general.lua override sentinel appears exactly once" \
        bash -c '[ "$(grep -c -- "-- >>> krane overrides >>>" "$HOME/.config/hypr/custom/general.lua" 2>/dev/null || echo 0)" = 1 ]'

    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        # shellcheck disable=SC2016
        verify_check "Hyprland config has no errors" bash -c 'out=$(hyprctl configerrors 2>&1) && [ -z "$out" ]'
        # shellcheck disable=SC2016
        verify_check "Monitor layout is queryable" bash -c 'hyprctl monitors -j >/dev/null'
    else
        verify_skip "Hyprland config has no errors" "not running inside a Hyprland session"
        verify_skip "Monitor layout is queryable" "not running inside a Hyprland session"
    fi

    if command -v bootctl >/dev/null 2>&1; then
        # bootctl list needs root (ESP is umask=0077). Cache the credential first: sudo prompts on /dev/tty,
        # so it works despite the tee pipe. With no tty `sudo -n` below WARNs instead of stalling.
        log_info "caching sudo credential for on-target checks"
        run_tty "sudo -v" || LAST_CMD=""
        verify_check "systemd-boot entries present" sudo -n bootctl list
    else
        verify_skip "systemd-boot entries present" "bootctl not found"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        verify_check "Proton Drive mount unit active" systemctl --user status proton-drive-mount
    else
        verify_skip "Proton Drive mount unit active" "systemctl not found"
    fi
    if [ "$HOST" = tarmantria ]; then
        # shellcheck disable=SC2016
        verify_check "PRIME offload reaches the dGPU" bash -c 'nvidia-offload glxinfo | grep -i vendor'
    fi
    if [ "$HOST" = tarmantria ] || [ "$HOST" = taractias ]; then
        # shellcheck disable=SC2016
        verify_check "Wi-Fi device present" bash -c 'nmcli device status | grep -i wifi'
        # shellcheck disable=SC2016
        verify_check "Bluetooth powered" bash -c 'bluetoothctl show | grep -i powered'
    fi
}

second_switch() {
    log_step "Second nixos-rebuild switch"
    if host_uses_cuda; then
        log_info "$HOST has CUDA packages, passing cache.nixos-cuda.org substituter options"
    else
        log_info "host has no CUDA packages, CUDA cache disabled for this switch"
    fi
    local flake_opt
    flake_opt=$(flake_config_opt)
    if confirm "Run 'sudo nixos-rebuild switch --flake $REPO_ROOT#$HOST' now?"; then
        run_sh "sudo nixos-rebuild switch --flake \"$REPO_ROOT#$HOST\" $flake_opt 2>&1" \
            || die "nixos-rebuild switch failed for $HOST, see $LOG"
        verify_checks
    fi
}

run_setup_mode() {
    preflight_setup
    run_bootstrap_sops
    edit_host_secrets
    setup_rust
    check_flathub
    verify_checks
    second_switch

    banner "Setup complete" \
        "Next steps:" \
        "  - fill in WireGuard / rclone values in secrets/$HOST.yaml" \
        "  - just check"
}

main() {
    if [ -z "$MODE" ]; then
        MODE="$(detect_mode)"
    fi
    case "$MODE" in
        install | setup) ;;
        *) die "invalid --mode '$MODE', expected install or setup" ;;
    esac

    validate_new_host_flags

    if [ -n "$HOST" ]; then
        host_known "$HOST" || die "unknown host '$HOST', expected one of: ${AVAILABLE_HOSTS[*]}"
    fi

    if [ "$MODE" = install ] && $YES && ! $DRY_RUN && ! $CONFIRM_WIPE; then
        die "live install with --yes, without --dry-run, also requires --confirm-wipe"
    fi

    banner "krane's NixOS installer" "mode: $MODE" "dry-run: $DRY_RUN"
    if $LOG_WRITABLE; then
        gum style --foreground 244 "Log: $LOG" >&2
    fi

    if [ "$MODE" = install ]; then
        run_install_mode
    else
        run_setup_mode
    fi

    if $LOG_WRITABLE; then
        log_info "Full log: $LOG"
    fi
}

# Spawns a separate bash "$0" so the real ERR trap fires.
if $SELF_TEST_TRIGGER_ERR; then
    self_test_trigger_err_fn() { false; }
    self_test_trigger_err_fn
    # Unreachable unless the ERR trap regresses.
    echo "self-test-trigger-err: unreachable line ran, ERR trap did not abort the script" >&2
    exit 1
fi

if $SELF_TEST_CHECK_DISKO_SED; then
    self_test_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest.XXXXXX")
    trap 'rc=$?; rm -rf "$self_test_tmpdir"; (exit $rc); on_exit' EXIT
    printf '{ disko.devices.disk.main = {\n    device = "/dev/CHANGE-ME";\n}; }\n' \
        >"$self_test_tmpdir/disko.nix"
    DRY_RUN=false
    patch_disko_file "$self_test_tmpdir/disko.nix" "/dev/self-test-disk"
    grep -qF 'device = "/dev/self-test-disk";' "$self_test_tmpdir/disko.nix" \
        || die "patch_disko_file did not produce the expected device line"
    echo "self-test-check-disko-sed: OK"
    exit 0
fi

if $SELF_TEST_CHECK_PRIME_SED; then
    self_test_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest.XXXXXX")
    trap 'rc=$?; rm -rf "$self_test_tmpdir"; (exit $rc); on_exit' EXIT
    cp "$REPO_ROOT/hosts/tarmantria/default.nix" "$self_test_tmpdir/default.nix"
    DRY_RUN=false
    patch_prime_line "$self_test_tmpdir/default.nix" "intelBusId" "PCI:9:9:9"
    grep -qF 'krane.prime.intelBusId = "PCI:9:9:9"; # set by install.sh' "$self_test_tmpdir/default.nix" \
        || die "patch_prime_line did not produce the expected assignment line"
    echo "self-test-check-prime-sed: OK"
    exit 0
fi

if $SELF_TEST_CHECK_SCAFFOLD; then
    self_test_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest.XXXXXX")
    trap 'rc=$?; rm -rf "$self_test_tmpdir"; (exit $rc); on_exit' EXIT
    DRY_RUN=false
    command -v nix-instantiate >/dev/null 2>&1 || die "nix-instantiate not found, cannot parse-check the templates"
    for st_profile in "${GPU_PROFILES[@]}"; do
        for st_ff in "${FORM_FACTORS[@]}"; do
            st_dir="$self_test_tmpdir/$st_profile-$st_ff"
            render_host_templates "$st_dir" testhost tester "Test Er" tester@example.invalid \
                "$st_profile" "$st_ff" at nodeadkeys
            parse_check_nix_dir "$st_dir"
            for st_file in default.nix disko.nix display.nix hardware-configuration.nix; do
                [ -f "$st_dir/$st_file" ] || die "$st_profile/$st_ff: $st_file was not rendered"
            done
            [ -f "$st_dir/illogical-impulse/.gitignore" ] \
                || die "$st_profile/$st_ff: illogical-impulse/.gitignore was not copied"
            grep -qx '{}' "$st_dir/ii-settings.json" \
                || die "$st_profile/$st_ff: ii-settings.json was not copied as {}"
            grep -qF 'name = "tester";' "$st_dir/default.nix" \
                || die "$st_profile/$st_ff: default.nix has no krane.user name line"
            grep -qF 'system.stateVersion = "26.05";' "$st_dir/default.nix" \
                || die "$st_profile/$st_ff: default.nix has no stateVersion 26.05"
            grep -qF 'device = "/dev/CHANGE-ME";' "$st_dir/disko.nix" \
                || die "$st_profile/$st_ff: disko.nix lost the CHANGE-ME placeholder patch_disko needs"
            grep -qF 'layout = "at";' "$st_dir/default.nix" \
                || die "$st_profile/$st_ff: default.nix has no krane.keyboard layout line"
            grep -qF 'kb_layout = osConfig.krane.keyboard.layout;' "$st_dir/display.nix" \
                || die "$st_profile/$st_ff: display.nix does not read osConfig.krane.keyboard.layout"
            if [ "$st_ff" = laptop ]; then
                grep -qF 'tap_to_click = true;' "$st_dir/display.nix" \
                    || die "$st_profile/$st_ff: laptop display.nix has no touchpad block"
            else
                ! grep -qF 'touchpad' "$st_dir/display.nix" \
                    || die "$st_profile/$st_ff: desktop display.nix has a touchpad block"
            fi
            # host_uses_cuda keys on this import.
            if [ "$st_profile" = nvidia-desktop ]; then
                grep -q 'gpu/nvidia-desktop' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: default.nix does not import gpu/nvidia-desktop.nix"
            else
                ! grep -q 'gpu/nvidia-desktop' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: default.nix imports gpu/nvidia-desktop.nix"
            fi
            # patch_prime keys on these two lines, with its own regex.
            if [ "$st_profile" = intel-nvidia-prime ]; then
                grep -qE '^[[:space:]]*krane\.prime\.intelBusId[[:space:]]*=[[:space:]]*"' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: no intelBusId line in the form patch_prime expects"
                grep -qE '^[[:space:]]*krane\.prime\.nvidiaBusId[[:space:]]*=[[:space:]]*"' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: no nvidiaBusId line in the form patch_prime expects"
                patch_prime_line "$st_dir/default.nix" intelBusId PCI:9:9:9
                patch_prime_line "$st_dir/default.nix" nvidiaBusId PCI:8:8:8
                parse_check_nix_dir "$st_dir"
            else
                ! grep -qE '^[[:space:]]*krane\.prime\.' "$st_dir/default.nix" \
                    || die "$st_profile/$st_ff: non-PRIME profile has krane.prime lines"
            fi
        done
    done
    # A git name with @ could be rewritten by GIT_EMAIL's sed expression (see render_host_templates), so it is
    # refused. The $(...) subshell absorbs render_host_templates' die.
    st_dir="$self_test_tmpdir/refuse-at-in-git-name"
    st_out8=$(render_host_templates "$st_dir" testhost tester 'Bad@Name' tester@example.invalid \
        amd-igpu laptop at nodeadkeys 2>&1) && st_rc8=0 || st_rc8=$?
    if [ "$st_rc8" -eq 0 ]; then
        die "render_host_templates accepted a git name containing '@', expected it to refuse"
    fi
    printf '%s' "$st_out8" | grep -qF "contains '@'" \
        || die "render_host_templates refused the @ git name for the wrong reason: $st_out8"
    st_dir="$self_test_tmpdir/escaping"
    # shellcheck disable=SC2016 # the literal ${x} is the point of this value.
    render_host_templates "$st_dir" testhost tester 'A/B & C\D "q" ${x}' 'a&b/c\d@example.invalid' \
        amd-igpu laptop at nodeadkeys
    parse_check_nix_dir "$st_dir"
    # shellcheck disable=SC2016 # matches the escaped Nix text literally.
    grep -qF 'gitName = "A/B & C\\D \"q\" \${x}";' "$st_dir/default.nix" \
        || die "git name with / & \\ \" \${ was not escaped for Nix and sed"
    grep -qF 'gitEmail = "a&b/c\\d@example.invalid";' "$st_dir/default.nix" \
        || die "git email with & / \\ was not escaped for Nix and sed"
    st_dir="$self_test_tmpdir/empty-kb-variant"
    render_host_templates "$st_dir" testhost tester "Test Er" tester@example.invalid \
        amd-igpu laptop us ""
    parse_check_nix_dir "$st_dir"
    grep -qF 'layout = "us";' "$st_dir/default.nix" \
        || die "non-at keyboard layout did not render into krane.keyboard.layout"
    grep -qF 'variant = "";' "$st_dir/default.nix" \
        || die "empty keyboard variant did not render as variant = \"\";"
    st_sops="$self_test_tmpdir/sops.yaml"
    cp "$REPO_ROOT/.sops.yaml" "$st_sops"
    register_sops_host "$st_sops" testhost
    sops_placeholder_present "$st_sops" testhost \
        || die "sops_placeholder_present missed testhost's new placeholders"
    ! sops_placeholder_present "$st_sops" taractias \
        || die "registering testhost made taractias read as not bootstrapped"
    [ "$(grep -c '&admin_testhost ' "$st_sops")" = 1 ] || die "&admin_testhost is not in .sops.yaml exactly once"
    st_rules_line=$(grep -n '^creation_rules:' "$st_sops" | cut -d: -f1)
    st_key_line=$(grep -n '&host_testhost ' "$st_sops" | cut -d: -f1)
    [ "$st_key_line" -lt "$st_rules_line" ] || die "&host_testhost landed after creation_rules:"
    grep -qF 'path_regex: secrets/testhost\.yaml$' "$st_sops" || die "no creation rule for secrets/testhost.yaml"
    if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q mikefarah; then
        [ "$(yq 'explode(.) | .creation_rules[-1].key_groups[0].age[1]' "$st_sops")" = age1PLACEHOLDER_HOST_TESTHOST_REPLACE_VIA_BOOTSTRAP_SOPS_SH ] \
            || die "yq does not resolve testhost's creation rule to its host placeholder"
    else
        log_warn "mikefarah yq not found, skipping the YAML structure check"
    fi
    cp "$st_sops" "$st_sops.once"
    register_sops_host "$st_sops" testhost
    cmp -s "$st_sops" "$st_sops.once" || die "a second register_sops_host testhost changed .sops.yaml"
    register_sops_host "$st_sops" tar
    grep -qF '&admin_tar age1PLACEHOLDER_ADMIN_TAR_REPLACE_VIA_BOOTSTRAP_SOPS_SH' "$st_sops" \
        || die "host 'tar' was treated as already registered because of &admin_taractias"
    register_sops_host "$st_sops" my-box
    sops_placeholder_present "$st_sops" my-box \
        || die "sops_placeholder_present missed a dashed host's placeholders"
    echo "self-test-check-scaffold: OK"
    exit 0
fi

# Scaffolds the --new-host host for real into this checkout's hosts/ and .sops.yaml, patches disko.nix
# with a fake disk, then exits. Used by check-new-host.sh and self_test from a throwaway repo copy.
if $SELF_TEST_SCAFFOLD; then
    [ "${KRANE_ALLOW_SCAFFOLD_HOOK:-}" = 1 ] \
        || die "--self-test-scaffold writes hosts/ and .sops.yaml for real, it only runs with KRANE_ALLOW_SCAFFOLD_HOOK=1 from a throwaway copy of the repo"
    YES=true
    DRY_RUN=false
    MODE=install
    validate_new_host_flags
    $NEW_HOST_MODE || usage_die "--self-test-scaffold needs --new-host"
    prompt_new_host
    scaffold_host
    patch_disko_file "$REPO_ROOT/hosts/$HOST/disko.nix" /dev/disk/by-id/check-new-host-fake-disk
    echo "self-test-scaffold: OK $HOST"
    exit 0
fi

self_test_validator() {
    local want="$1" validator="$2" value rc=0
    shift 2
    for value in "$@"; do
        if "$validator" "$value" >/dev/null; then
            [ "$want" = valid ] || { echo "FAIL: $validator accepted '$value'" >&2; rc=1; }
        else
            [ "$want" = invalid ] || { echo "FAIL: $validator rejected '$value'" >&2; rc=1; }
        fi
    done
    return "$rc"
}

self_test() {
    echo "== self-test: run_sh honours pipefail ==" >&2
    local saved_dry_run="$DRY_RUN" rc=0
    DRY_RUN=false
    run_sh 'false | true' || rc=$?
    DRY_RUN="$saved_dry_run"
    if [ "$rc" -ne 0 ]; then
        echo "OK: run_sh 'false | true' failed as expected (rc=$rc)" >&2
    else
        echo "FAIL: run_sh 'false | true' returned success, pipefail not honoured" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: run_tty ==" >&2
    local saved_dry_run2="$DRY_RUN" rc5=0 out5
    DRY_RUN=true
    out5=$(run_tty 'false' 2>&1)
    rc5=$?
    DRY_RUN="$saved_dry_run2"
    if [ "$rc5" -eq 0 ] && printf '%s' "$out5" | grep -qF '+ false'; then
        echo "OK: run_tty 'false' under DRY_RUN=true returned 0 and printed '+ false'" >&2
    else
        echo "FAIL: run_tty 'false' under DRY_RUN=true was rc=$rc5 out=$out5" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi
    if { : </dev/tty; } 2>/dev/null; then
        local saved_have_tty="$HAVE_TTY" rc6=0 tty_out_file
        HAVE_TTY=true
        tty_out_file=$(mktemp "${TMPDIR:-/tmp}/krane-install-selftest-tty.XXXXXX")
        run_tty '[ -t 1 ] && [ -t 0 ]' >"$tty_out_file" 2>&1 || rc6=$?
        HAVE_TTY="$saved_have_tty"
        rm -f "$tty_out_file"
        if [ "$rc6" -eq 0 ]; then
            echo "OK: run_tty ran the stub against a real /dev/tty (rc=0)" >&2
        else
            echo "FAIL: run_tty against a real /dev/tty returned rc=$rc6" >&2
            SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
        fi
    else
        echo "OK: skipped (no tty)" >&2
    fi

    echo "== self-test: ERR trap fires inside a function ==" >&2
    # A separate bash "$0" process, not a subshell, so the real ERR trap fires.
    local out rc2=0
    out=$(bash "$0" --self-test-trigger-err 2>&1) || rc2=$?
    if [ "$rc2" -ne 0 ] && printf '%s' "$out" | grep -q "false" \
        && printf '%s' "$out" | grep -q "exit 1" \
        && printf '%s' "$out" | grep -q "in self_test_trigger_err_fn"; then
        echo "OK: ERR trap fired for a failure inside a function (rc=$rc2)" >&2
    else
        echo "FAIL: ERR trap did not fire for a failure inside a function (rc=$rc2)" >&2
        echo "  captured output: $out" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: patch_disko_file sed (real, non-dry-run) ==" >&2
    local out3 rc3=0
    out3=$(bash "$0" --self-test-check-disko-sed 2>&1) || rc3=$?
    if [ "$rc3" -eq 0 ] && printf '%s' "$out3" | grep -q "self-test-check-disko-sed: OK"; then
        echo "OK: patch_disko_file produced the expected device line" >&2
    else
        echo "FAIL: patch_disko_file sed check failed (rc=$rc3)" >&2
        echo "  captured output: $out3" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: patch_prime_line sed (real, non-dry-run) ==" >&2
    local out4 rc4=0
    out4=$(bash "$0" --self-test-check-prime-sed 2>&1) || rc4=$?
    if [ "$rc4" -eq 0 ] && printf '%s' "$out4" | grep -q "self-test-check-prime-sed: OK"; then
        echo "OK: patch_prime_line produced the expected assignment line" >&2
    else
        echo "FAIL: patch_prime_line sed check failed (rc=$rc4)" >&2
        echo "  captured output: $out4" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: new-host templates render and parse (real, non-dry-run) ==" >&2
    local out7 rc7=0
    out7=$(bash "$0" --self-test-check-scaffold 2>&1) || rc7=$?
    if [ "$rc7" -eq 0 ] && printf '%s' "$out7" | grep -q "self-test-check-scaffold: OK"; then
        echo "OK: every GPU profile x form factor renders, parses and keeps its install.sh hooks" >&2
    else
        echo "FAIL: new-host template check failed (rc=$rc7)" >&2
        echo "  captured output: $out7" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: install swap RAM threshold ==" >&2
    if install_swap_needed 15728640 && ! install_swap_needed 33554432; then
        echo "OK: install_swap_needed true at 15 GiB, false at 32 GiB" >&2
    else
        echo "FAIL: install_swap_needed threshold wrong" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: host_uses_cuda is true only for tariognatha ==" >&2
    local saved_host="$HOST" h cuda_ok=true
    for h in "${AVAILABLE_HOSTS[@]}"; do
        HOST="$h"
        if [ "$h" = tariognatha ]; then
            host_uses_cuda || { echo "FAIL: host_uses_cuda false for $h, expected true" >&2; cuda_ok=false; }
        else
            ! host_uses_cuda || { echo "FAIL: host_uses_cuda true for $h, expected false" >&2; cuda_ok=false; }
        fi
    done
    HOST="$saved_host"
    if $cuda_ok; then
        echo "OK: host_uses_cuda true only for tariognatha" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: flake_config_opt follows host_uses_cuda ==" >&2
    local opt_ok=true got
    HOST=tariognatha
    got=$(flake_config_opt)
    expected="--option extra-substituters https://cache.nixos-cuda.org --option extra-trusted-public-keys cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    [ "$got" = "$expected" ] \
        || { echo "FAIL: flake_config_opt for tariognatha was '$got'" >&2; opt_ok=false; }
    HOST=taractias
    got=$(flake_config_opt)
    [ -z "$got" ] \
        || { echo "FAIL: flake_config_opt for taractias was '$got'" >&2; opt_ok=false; }
    HOST="$saved_host"
    if $opt_ok; then
        echo "OK: flake_config_opt matches expected substituter options" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: sops_placeholder_present detects an unreplaced placeholder ==" >&2
    local ph_tmp ph_ok=true
    ph_tmp=$(mktemp "${TMPDIR:-/tmp}/krane-install-selftest-sops.XXXXXX")
    printf 'age1PLACEHOLDER_HOST_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n' >"$ph_tmp"
    sops_placeholder_present "$ph_tmp" taractias \
        || { echo "FAIL: placeholder present was not detected" >&2; ph_ok=false; }
    printf 'age18ln7hrxrhx59dk5cn4p8d9gndnftkcpyauvfkhttfhphu6kg3adq8q8wsf\n' >"$ph_tmp"
    ! sops_placeholder_present "$ph_tmp" taractias \
        || { echo "FAIL: a real recipient was misread as the placeholder" >&2; ph_ok=false; }
    rm -f "$ph_tmp"
    if $ph_ok; then
        echo "OK: sops_placeholder_present distinguishes placeholder from real recipient" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: git_path_clean decides commit vs skip from the worktree ==" >&2
    local git_tmp clean_ok=true
    git_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-git.XXXXXX")
    (
        cd "$git_tmp"
        git init -q
        git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
        echo one >tracked.yaml
        git add tracked.yaml
        git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m add
    )
    if git_path_clean "$git_tmp" tracked.yaml; then
        echo "OK: a clean committed file reads as nothing to commit" >&2
    else
        echo "FAIL: a clean committed file did not read as clean" >&2
        clean_ok=false
    fi
    echo modified >"$git_tmp/tracked.yaml"
    if ! git_path_clean "$git_tmp" tracked.yaml; then
        echo "OK: a modified, unstaged file reads as dirty" >&2
    else
        echo "FAIL: a modified, unstaged file read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" checkout -q -- tracked.yaml
    echo new >"$git_tmp/untracked.yaml"
    if ! git_path_clean "$git_tmp" untracked.yaml; then
        echo "OK: an untracked file reads as dirty" >&2
    else
        echo "FAIL: an untracked file read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" add -- untracked.yaml
    if ! git_path_clean "$git_tmp" untracked.yaml; then
        echo "OK: a staged new file reads as dirty" >&2
    else
        echo "FAIL: a staged new file read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m add-untracked
    # Staged deletion with the worktree identical to HEAD is still dirty: the index no longer matches HEAD.
    # A real run re-adds, finds nothing staged and skips the commit.
    git -C "$git_tmp" rm -q --cached tracked.yaml
    if ! git_path_clean "$git_tmp" tracked.yaml; then
        echo "OK: a staged deletion with worktree identical to HEAD reads as dirty" >&2
    else
        echo "FAIL: a staged deletion with worktree identical to HEAD read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" add -- tracked.yaml
    local no_head_tmp
    no_head_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-git-nohead.XXXXXX")
    (
        cd "$no_head_tmp"
        git init -q
        echo one >staged.yaml
    )
    if ! git_path_clean "$no_head_tmp" staged.yaml; then
        echo "OK: a repo with no HEAD and an untracked file reads as dirty" >&2
    else
        echo "FAIL: a repo with no HEAD and an untracked file read as clean" >&2
        clean_ok=false
    fi
    rm -rf "$git_tmp" "$no_head_tmp"
    if $clean_ok; then
        echo "OK: git_path_clean covers committed/modified/untracked/staged/deleted/no-HEAD" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: new-host input validators ==" >&2
    local vd_ok=true long63 long64 long32 long33
    long63=$(printf 'a%.0s' {1..63})
    long64=$(printf 'a%.0s' {1..64})
    long32=$(printf 'u%.0s' {1..32})
    long33=$(printf 'u%.0s' {1..33})
    self_test_validator valid check_new_hostname newbox a b2 my-box "$long63" || vd_ok=false
    # box- passes the bare regex but networking.hostName rejects it.
    self_test_validator invalid check_new_hostname "" 9box Box -box box- my_box my.box "my box" \
        tariognatha-vm "${AVAILABLE_HOSTS[@]}" "$long64" || vd_ok=false
    self_test_validator valid check_new_username krane alice _svc a-b a_b "$long32" || vd_ok=false
    self_test_validator invalid check_new_username "" root nobody daemon sshd greeter nixbld nixbld1 \
        systemd-network Alice 1abc "a b" a.b "$long33" || vd_ok=false
    # shellcheck disable=SC2016 # the literal ${x} is the point of this value.
    self_test_validator valid check_git_name krane "Test Er" "Zoë O'Brien" 'A/B & C\D "q" ${x}' || vd_ok=false
    self_test_validator invalid check_git_name "" "a@b" "$(printf 'a\nb')" || vd_ok=false
    self_test_validator valid check_git_email chris@krane.dev a+b@x.y root@localhost || vd_ok=false
    self_test_validator invalid check_git_email "" nodomain a@b@c "a b@c.d" a@ @b || vd_ok=false
    self_test_validator valid check_kb_layout at us de,us || vd_ok=false
    self_test_validator invalid check_kb_layout "" AT "at;rm" "at us" || vd_ok=false
    self_test_validator valid check_kb_variant "" nodeadkeys altgr-intl || vd_ok=false
    self_test_validator invalid check_kb_variant "no dead" 'x"y' || vd_ok=false
    self_test_validator valid check_profile "${GPU_PROFILES[@]}" || vd_ok=false
    self_test_validator invalid check_profile "" amd-nvidia-prime || vd_ok=false
    self_test_validator valid check_form_factor "${FORM_FACTORS[@]}" || vd_ok=false
    self_test_validator invalid check_form_factor "" tablet || vd_ok=false
    if $vd_ok; then
        echo "OK: hostname, username, git, keyboard, profile and form-factor validators" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: prompt_new_host defaults kb-variant off DEFAULT_KB_LAYOUT only ==" >&2
    local kv_ok=true
    local saved_yes="$YES" saved_new_host_mode="$NEW_HOST_MODE" saved_new_host="$NEW_HOST" \
        saved_new_user="$NEW_USER" saved_new_git_name="$NEW_GIT_NAME" saved_new_git_email="$NEW_GIT_EMAIL" \
        saved_new_profile="$NEW_PROFILE" saved_new_form_factor="$NEW_FORM_FACTOR" \
        saved_new_kb_layout="$NEW_KB_LAYOUT" saved_new_kb_variant="$NEW_KB_VARIANT" \
        saved_new_kb_variant_set="$NEW_KB_VARIANT_SET" saved_host3="$HOST"
    YES=true
    NEW_HOST_MODE=true
    NEW_HOST=kvtest
    NEW_USER=tester
    NEW_GIT_NAME="Test Er"
    NEW_GIT_EMAIL=tester@example.invalid
    NEW_PROFILE=amd-igpu
    NEW_FORM_FACTOR=laptop
    NEW_KB_LAYOUT="$DEFAULT_KB_LAYOUT"
    NEW_KB_VARIANT=""
    NEW_KB_VARIANT_SET=false
    prompt_new_host >/dev/null
    [ "$NEW_KB_VARIANT" = "$DEFAULT_KB_VARIANT" ] \
        || { echo "FAIL: --kb-layout $DEFAULT_KB_LAYOUT defaulted kb-variant to '$NEW_KB_VARIANT', expected '$DEFAULT_KB_VARIANT'" >&2; kv_ok=false; }
    NEW_KB_LAYOUT=us
    NEW_KB_VARIANT=""
    NEW_KB_VARIANT_SET=false
    prompt_new_host >/dev/null
    [ "$NEW_KB_VARIANT" = "" ] \
        || { echo "FAIL: --kb-layout us defaulted kb-variant to '$NEW_KB_VARIANT', expected empty" >&2; kv_ok=false; }
    YES="$saved_yes"
    NEW_HOST_MODE="$saved_new_host_mode"
    NEW_HOST="$saved_new_host"
    NEW_USER="$saved_new_user"
    NEW_GIT_NAME="$saved_new_git_name"
    NEW_GIT_EMAIL="$saved_new_git_email"
    NEW_PROFILE="$saved_new_profile"
    NEW_FORM_FACTOR="$saved_new_form_factor"
    NEW_KB_LAYOUT="$saved_new_kb_layout"
    NEW_KB_VARIANT="$saved_new_kb_variant"
    NEW_KB_VARIANT_SET="$saved_new_kb_variant_set"
    HOST="$saved_host3"
    if $kv_ok; then
        echo "OK: kb-variant defaults to nodeadkeys only for layout at, else empty" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: suggest_profile keeps each field in its slot ==" >&2
    local sp_ok=true sp_got
    sp_got=$(
        lspci() { printf '00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Notebook; }
        suggest_profile
    )
    [ "$sp_got" = "intel-igpu laptop" ] || { echo "FAIL: Intel-only notebook suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '00:02.0 VGA compatible controller: Intel Corporation UHD\n01:00.0 3D controller: NVIDIA Corporation GA107M\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Laptop; }
        suggest_profile
    )
    [ "$sp_got" = "intel-nvidia-prime laptop" ] || { echo "FAIL: Intel+NVIDIA laptop suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '00:02.0 VGA compatible controller: Intel Corporation UHD\n01:00.0 3D controller: NVIDIA Corporation GA104\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Desktop; }
        suggest_profile
    )
    [ "$sp_got" = "nvidia-desktop desktop" ] || { echo "FAIL: Intel+NVIDIA desktop suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '0a:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Raphael\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Desktop; }
        suggest_profile
    )
    [ "$sp_got" = "amd-igpu desktop" ] || { echo "FAIL: AMD desktop suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { printf '01:00.0 VGA compatible controller: NVIDIA Corporation AD104 [GeForce RTX 4070 Ti]\n'; }
        dmidecode() { [ "$2" = chassis-type ] && echo Tower; }
        suggest_profile
    )
    [ "$sp_got" = "nvidia-desktop desktop" ] || { echo "FAIL: NVIDIA tower suggested '$sp_got'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { :; }
        dmidecode() { [ "$2" = chassis-type ] && echo Notebook; }
        suggest_profile
    )
    [ "${sp_got%% *}" = "" ] && [ "${sp_got#* }" = laptop ] \
        || { echo "FAIL: unknown GPU on a notebook split as profile='${sp_got%% *}' form='${sp_got#* }'" >&2; sp_ok=false; }
    sp_got=$(
        lspci() { return 1; }
        dmidecode() { return 1; }
        suggest_profile
    )
    [ "$sp_got" = " " ] || { echo "FAIL: failed probes suggested '$sp_got'" >&2; sp_ok=false; }
    if $sp_ok; then
        echo "OK: suggest_profile maps lspci/dmidecode output and never shifts fields" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: new-host flag rules are usage errors ==" >&2
    local fl_ok=true fl_want fl_case fl_out fl_rc
    while IFS='|' read -r fl_want fl_case; do
        fl_rc=0
        # shellcheck disable=SC2086 # fl_case is a flag list, split on purpose.
        fl_out=$(bash "$REPO_ROOT/install.sh" $fl_case 2>&1) || fl_rc=$?
        if [ "$fl_rc" -eq 0 ] || ! printf '%s' "$fl_out" | grep -qF -- "$fl_want"; then
            echo "FAIL: install.sh $fl_case: rc=$fl_rc, expected an error containing '$fl_want'" >&2
            fl_ok=false
        fi
    done <<'EOF'
only works in install mode|--mode setup --dry-run --new-host newbox --user alice --profile amd-igpu --form-factor laptop
only apply together with --new-host|--mode install --dry-run --host taractias --disk /dev/null --user alice
also requires --user --profile --form-factor|--mode install --dry-run --disk /dev/null --new-host newbox
mutually exclusive|--mode install --dry-run --disk /dev/null --host taractias --new-host newbox --user alice --profile amd-igpu --form-factor laptop
must start with a lowercase letter|--mode install --dry-run --disk /dev/null --new-host 9box --user alice --profile amd-igpu --form-factor laptop
already exists|--mode install --dry-run --disk /dev/null --new-host taractias --user alice --profile amd-igpu --form-factor laptop
system account|--mode install --dry-run --disk /dev/null --new-host newbox --user root --profile amd-igpu --form-factor laptop
unknown GPU profile|--mode install --dry-run --disk /dev/null --new-host newbox --user alice --profile amd-nvidia-prime --form-factor laptop
EOF
    if $fl_ok; then
        echo "OK: misused new-host flags stop with a usage error" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: a failed scaffold rolls back, a good one lands, a repeat is refused ==" >&2
    local sb_tmp sb_out sb_rc sb_ok=true
    sb_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-scaffold.XXXXXX")
    cp "$REPO_ROOT/install.sh" "$sb_tmp/install.sh"
    cp -r "$REPO_ROOT/templates" "$sb_tmp/templates"
    mkdir -p "$sb_tmp/hosts/taractias"
    cp "$REPO_ROOT/hosts/taractias/default.nix" "$sb_tmp/hosts/taractias/default.nix"
    # No creation_rules: line, so register_sops_host dies after hosts/rbhost/ is copied in; rollback_scaffold must remove it.
    printf 'keys:\n  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n' >"$sb_tmp/.sops.yaml"
    (
        cd "$sb_tmp"
        git init -q
        git add -A
        git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m init
    )
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host rbhost --user tester --profile amd-igpu --form-factor laptop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -eq 0 ] || ! printf '%s' "$sb_out" | grep -q 'no top-level creation_rules'; then
        echo "FAIL: scaffolding into a .sops.yaml without creation_rules: did not die in register_sops_host (rc=$sb_rc)" >&2
        echo "  captured output: $sb_out" >&2
        sb_ok=false
    fi
    printf '%s' "$sb_out" | grep -q 'rolling back the partial hosts/rbhost scaffold' \
        || { echo "FAIL: no rollback log line, .sops.yaml passing the diff check below would prove nothing" >&2; sb_ok=false; }
    [ ! -e "$sb_tmp/hosts/rbhost" ] || { echo "FAIL: hosts/rbhost survived the failed scaffold" >&2; sb_ok=false; }
    [ -f "$sb_tmp/hosts/taractias/default.nix" ] || { echo "FAIL: the rollback touched hosts/taractias" >&2; sb_ok=false; }
    git -C "$sb_tmp" diff --quiet -- .sops.yaml || { echo "FAIL: .sops.yaml was not restored" >&2; sb_ok=false; }
    printf 'keys:\n  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH\n\ncreation_rules:\n  - path_regex: secrets/taractias\\.yaml$\n    key_groups:\n      - age:\n          - *admin_taractias\n' >"$sb_tmp/.sops.yaml"
    git -C "$sb_tmp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -am sops
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host goodhost --user tester --profile intel-nvidia-prime --form-factor desktop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -ne 0 ] || [ ! -f "$sb_tmp/hosts/goodhost/default.nix" ] \
        || ! grep -qF '&host_goodhost age1PLACEHOLDER_HOST_GOODHOST_REPLACE_VIA_BOOTSTRAP_SOPS_SH' "$sb_tmp/.sops.yaml" \
        || ! grep -qF 'device = "/dev/disk/by-id/check-new-host-fake-disk";' "$sb_tmp/hosts/goodhost/disko.nix"; then
        echo "FAIL: a valid scaffold of goodhost did not land (rc=$sb_rc)" >&2
        echo "  captured output: $sb_out" >&2
        sb_ok=false
    fi
    # cp -a keeps mktemp -d's 0700/0600 modes; scaffold_host widens them to 0755/0644.
    [ "$(stat -c%a "$sb_tmp/hosts/goodhost")" = 755 ] \
        || { echo "FAIL: hosts/goodhost is $(stat -c%a "$sb_tmp/hosts/goodhost"), expected 755" >&2; sb_ok=false; }
    [ "$(stat -c%a "$sb_tmp/hosts/goodhost/default.nix")" = 644 ] \
        || { echo "FAIL: hosts/goodhost/default.nix is $(stat -c%a "$sb_tmp/hosts/goodhost/default.nix"), expected 644" >&2; sb_ok=false; }
    # A missing .sops.yaml must die before SCAFFOLD_PENDING is set, so rollback creates no empty one.
    rm -f "$sb_tmp/.sops.yaml"
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host nosopshost --user tester --profile amd-igpu --form-factor laptop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -eq 0 ] || ! printf '%s' "$sb_out" | grep -qF '.sops.yaml not found'; then
        echo "FAIL: scaffolding with no .sops.yaml at all did not die with the expected message (rc=$sb_rc)" >&2
        echo "  captured output: $sb_out" >&2
        sb_ok=false
    fi
    [ ! -e "$sb_tmp/hosts/nosopshost" ] || { echo "FAIL: hosts/nosopshost survived a scaffold with no .sops.yaml" >&2; sb_ok=false; }
    [ ! -e "$sb_tmp/.sops.yaml" ] \
        || { echo "FAIL: rollback fabricated a .sops.yaml where none existed before scaffolding" >&2; sb_ok=false; }
    git -C "$sb_tmp" checkout -q -- .sops.yaml
    sb_rc=0
    sb_out=$(KRANE_ALLOW_SCAFFOLD_HOOK=1 bash "$sb_tmp/install.sh" --self-test-scaffold \
        --new-host goodhost --user tester --profile amd-igpu --form-factor laptop 2>&1) || sb_rc=$?
    if [ "$sb_rc" -eq 0 ] || ! printf '%s' "$sb_out" | grep -q 'already exists'; then
        echo "FAIL: a second scaffold of goodhost was not refused (rc=$sb_rc)" >&2
        sb_ok=false
    fi
    [ -f "$sb_tmp/hosts/goodhost/default.nix" ] || { echo "FAIL: the refused repeat deleted hosts/goodhost" >&2; sb_ok=false; }
    rm -rf "$sb_tmp"
    if $sb_ok; then
        echo "OK: scaffold rolls back on failure, lands on success, refuses an existing host" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: rollback_scaffold restores .sops.yaml by content, not git checkout ==" >&2
    local rb_ok=true rb_tmp rb_committed rb_edited rb_registered rb_got
    local saved_repo_root="$REPO_ROOT" saved_host_rb="$HOST" \
        saved_pending="$SCAFFOLD_PENDING" saved_snapshot="$SCAFFOLD_SOPS_SNAPSHOT"
    rb_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-rollback.XXXXXX")
    mkdir -p "$rb_tmp/hosts/taractias" "$rb_tmp/hosts/rbhost"
    : >"$rb_tmp/hosts/taractias/default.nix"
    : >"$rb_tmp/hosts/rbhost/x.nix"
    rb_committed='keys:
  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH
'
    rb_edited='keys:
  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH
  - &uncommitted_local_edit age1UNCOMMITTED_LOCAL_EDIT_MUST_SURVIVE_ROLLBACK
'
    rb_registered='keys:
  - &admin_taractias age1PLACEHOLDER_ADMIN_TARACTIAS_REPLACE_VIA_BOOTSTRAP_SOPS_SH
  - &uncommitted_local_edit age1UNCOMMITTED_LOCAL_EDIT_MUST_SURVIVE_ROLLBACK
  - &host_rbhost age1PLACEHOLDER_HOST_RBHOST_REPLACE_VIA_BOOTSTRAP_SOPS_SH
'
    (
        cd "$rb_tmp"
        git init -q
        printf '%s' "$rb_committed" >.sops.yaml
        git add -A
        git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m init
    )
    printf '%s' "$rb_edited" >"$rb_tmp/.sops.yaml"
    SCAFFOLD_SOPS_SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/krane-install-selftest-snapshot.XXXXXX")
    printf '%s' "$rb_edited" >"$SCAFFOLD_SOPS_SNAPSHOT"
    printf '%s' "$rb_registered" >"$rb_tmp/.sops.yaml"
    REPO_ROOT="$rb_tmp"
    HOST=rbhost
    SCAFFOLD_PENDING=true
    rollback_scaffold
    [ ! -e "$rb_tmp/hosts/rbhost" ] || { echo "FAIL: hosts/rbhost survived rollback_scaffold" >&2; rb_ok=false; }
    [ -e "$rb_tmp/hosts/taractias/default.nix" ] || { echo "FAIL: rollback_scaffold touched hosts/taractias" >&2; rb_ok=false; }
    # Command substitution strips trailing newlines, so run the expected strings through it too.
    rb_got=$(command cat "$rb_tmp/.sops.yaml")
    if [ "$rb_got" != "$(printf '%s' "$rb_edited")" ]; then
        echo "FAIL: .sops.yaml after rollback_scaffold does not match the pre-registration snapshot" >&2
        if [ "$rb_got" = "$(printf '%s' "$rb_committed")" ]; then
            echo "  it matches the git-committed content instead: the uncommitted edit was discarded" >&2
        fi
        rb_ok=false
    fi
    $SCAFFOLD_PENDING && { echo "FAIL: rollback_scaffold left SCAFFOLD_PENDING=true" >&2; rb_ok=false; }
    rm -rf "$rb_tmp" "$SCAFFOLD_SOPS_SNAPSHOT"
    REPO_ROOT="$saved_repo_root"
    HOST="$saved_host_rb"
    SCAFFOLD_PENDING="$saved_pending"
    SCAFFOLD_SOPS_SNAPSHOT="$saved_snapshot"
    if $rb_ok; then
        echo "OK: rollback_scaffold restores .sops.yaml from its snapshot, keeping uncommitted edits" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: check_new_hostname refuses a dangling symlink at hosts/<name> ==" >&2
    local dl_ok=true dl_tmp saved_repo_root2="$REPO_ROOT"
    dl_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-symlink.XXXXXX")
    mkdir -p "$dl_tmp/hosts"
    ln -s "$dl_tmp/hosts/nonexistent-target" "$dl_tmp/hosts/deadlink"
    REPO_ROOT="$dl_tmp"
    if check_new_hostname deadlink >/dev/null; then
        echo "FAIL: check_new_hostname accepted a dangling symlink at hosts/deadlink" >&2
        dl_ok=false
    fi
    REPO_ROOT="$saved_repo_root2"
    rm -rf "$dl_tmp"
    if $dl_ok; then
        echo "OK: check_new_hostname refuses a dangling symlink" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    # scaffold_host's own "$dest already exists" check (-e or -L) protects a real scaffold.
    # REPO_ROOT/HOST are overridden for this command only.
    echo "== self-test: scaffold_host refuses a dangling symlink at hosts/<name> ==" >&2
    local dg_ok=true dg_tmp dg_out dg_rc=0
    dg_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-scaffold-symlink.XXXXXX")
    mkdir -p "$dg_tmp/hosts"
    ln -s "$dg_tmp/hosts/nonexistent-target" "$dg_tmp/hosts/deadlink"
    dg_out=$(REPO_ROOT="$dg_tmp" HOST=deadlink scaffold_host 2>&1) || dg_rc=$?
    if [ "$dg_rc" -eq 0 ] || ! printf '%s' "$dg_out" | grep -qF 'already exists'; then
        echo "FAIL: scaffold_host accepted a dangling symlink at hosts/deadlink (rc=$dg_rc)" >&2
        echo "  captured output: $dg_out" >&2
        dg_ok=false
    fi
    rm -rf "$dg_tmp"
    if $dg_ok; then
        echo "OK: scaffold_host's own dest guard refuses a dangling symlink" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: host_uses_cuda follows a new host's GPU profile ==" >&2
    local nc_ok=true saved_new_mode="$NEW_HOST_MODE" saved_new_profile="$NEW_PROFILE" saved_host2="$HOST"
    NEW_HOST_MODE=true
    HOST=newbox
    NEW_PROFILE=nvidia-desktop
    host_uses_cuda || { echo "FAIL: host_uses_cuda false for a new nvidia-desktop host" >&2; nc_ok=false; }
    NEW_PROFILE=intel-nvidia-prime
    ! host_uses_cuda || { echo "FAIL: host_uses_cuda true for a new intel-nvidia-prime host" >&2; nc_ok=false; }
    NEW_HOST_MODE="$saved_new_mode"
    NEW_PROFILE="$saved_new_profile"
    HOST="$saved_host2"
    if $nc_ok; then
        echo "OK: host_uses_cuda true only for a new nvidia-desktop host" >&2
    else
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    echo "== self-test: setup mode refuses a hostname that is not in hosts/ ==" >&2
    local sg_tmp sg_out sg_rc=0
    sg_tmp=$(mktemp -d "${TMPDIR:-/tmp}/krane-install-selftest-hostname.XXXXXX")
    printf '#!/bin/sh\necho bogushost\n' >"$sg_tmp/hostname"
    chmod +x "$sg_tmp/hostname"
    sg_out=$(PATH="$sg_tmp:$PATH" bash "$REPO_ROOT/install.sh" --mode setup --dry-run 2>&1) || sg_rc=$?
    rm -rf "$sg_tmp"
    if [ "$sg_rc" -ne 0 ] && printf '%s' "$sg_out" | grep -qF "host 'bogushost' not in hosts/"; then
        echo "OK: setup mode on an unknown hostname dies even under --dry-run (rc=$sg_rc)" >&2
    else
        echo "FAIL: setup mode on hostname bogushost: rc=$sg_rc, no \"not in hosts/\" error" >&2
        SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    fi

    if [ "$SELF_TEST_FAILURES" -eq 0 ]; then
        echo "self-test: all checks passed" >&2
        exit 0
    fi
    echo "self-test: $SELF_TEST_FAILURES checks failed" >&2
    exit 1
}

if $SELF_TEST; then
    self_test
fi

main "$@"
