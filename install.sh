#!/usr/bin/env bash
# install.sh installs krane's NixOS + Hyprland flake on tariognatha,
# tarmantria and taractias. Two modes, auto-detected, override with
# --mode. Install mode runs from a live ISO and erases the target disk
# while partitioning it with disko. Setup mode runs after first boot and
# drives the second switch. Logs each run to
# /tmp/krane-install-TIMESTAMP-PID.log.

# -E makes the ERR trap fire inside functions, not just at the top level.
set -Eeuo pipefail

# Every nix call below, including the ones nixos-install and nixos-rebuild make, needs flakes.
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}experimental-features = nix-command flakes"

# Re-execs through nix shell when gum is missing, since the live ISO
# lacks it. KRANE_INSTALL_REEXEC stops this from looping.
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

# CLICOLOR_FORCE keeps gum colour even though tee below makes stdout a
# pipe. Only set when this script's own stdout is a real terminal.
if [ -t 1 ]; then
    export CLICOLOR_FORCE=1
fi

# Copies all output to $LOG from here on. tee still shows it live too.
if $LOG_WRITABLE; then
    exec > >(tee -a "$LOG") 2>&1
fi

# stderr is now a pipe to tee, which breaks gum's interactive TUI (drawn on
# stderr): the prompt line duplicates and typed input echoes late. gum_tty
# redirects interactive gum calls to /dev/tty instead, falling back to
# stderr when no real tty is available, such as container dry-runs.
HAVE_TTY=false
{ : >/dev/tty; } 2>/dev/null && HAVE_TTY=true

gum_tty() {
    if $HAVE_TTY; then
        gum "$@" 2>/dev/tty
    else
        gum "$@"
    fi
}

# hosts/ is the single source of truth here, same as flake.nix's hosts,
# known_hosts() and docker-check.sh's HOSTS.
AVAILABLE_HOSTS=()
for _d in "$REPO_ROOT"/hosts/*/; do
    AVAILABLE_HOSTS+=("$(basename "$_d")")
done
unset _d

MODE=""
# Not "${HOST:-}", so an ambient $HOST in the shell never picks the target.
HOST=""
DISK=""
YES=false
DRY_RUN=false
CONFIRM_WIPE=false
SELF_TEST=false
SELF_TEST_TRIGGER_ERR=false
SELF_TEST_CHECK_DISKO_SED=false
SELF_TEST_CHECK_PRIME_SED=false
SELF_TEST_FAILURES=0
# The most recent command run/run_sh/capture executed, so err_trap can show
# the real failing command instead of just a line number. Cleared to ""
# only when that command succeeds.
LAST_CMD=""
# Suppresses on_exit's own reminder, since die/usage already explained the failure.
HANDLED_EXIT=false
USAGE_EXIT=false
# Tracks whether setup_install_swap created /mnt/swapfile, so teardown_install_swap
# and on_exit know whether there is anything to remove.
INSTALL_SWAP_ACTIVE=false
INSTALL_SWAP_ON=false

# Runs from run_install_mode after a successful install and from on_exit, so
# an aborted run never leaves the swapfile inside the new root. Warns
# instead of dying on failure, so cleanup never trips the ERR trap. Defined
# early since on_exit can call it before arg parsing reaches --help or an
# unknown flag.
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

# LC_ALL=C keeps [@-~] a byte range: under a UTF-8 locale sed's collation
# silently drops that range and the strip never matches. Shared by err_trap
# and run_nixos_install's retry loop.
clean_log_lines() {
    LC_ALL=C sed -E $'s/\x1b\\[[0-9;?]*[ -\\/]*[@-~]//g' | LC_ALL=C tr -d '\000-\010\013-\037\177' | cut -c1-100
}

clean_log_tail() {
    tail -n "$1" "$LOG" | clean_log_lines
}

# FUNCNAME[0]/BASH_LINENO[0] here are err_trap's own frame. When the failure
# happened directly inside run/run_sh/capture, FUNCNAME[1] just names that
# generic helper, so this shifts one frame further out to the user-level
# function that called it, such as run_disko, and BASH_LINENO[1] for the
# line in that function where the helper was called.
err_trap() {
    # A failure inside a $(...) or (...) subshell runs err_trap in a child
    # process. Returning early there leaves the box to the parent shell,
    # which sees the same failure, instead of printing one box per level.
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

# For a run whose failure is tolerated (caller has its own || handler and
# keeps going): clears LAST_CMD even on failure, so a later, unrelated
# failure in the same function never has err_trap blame this one instead.
run_soft() { run "$@" || { local rc=$?; LAST_CMD=""; return "$rc"; }; }

# -o pipefail matters the moment a run_sh string pipes commands, so a
# failing command on the left cannot look like a success.
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

# Like run_sh, but for full-screen interactive programs (sops's $EDITOR)
# that get confused by output going through the tee pipe set up on stdout
# and stderr near the top of the script. When a real tty is available,
# runs straight against /dev/tty instead; otherwise falls back to run_sh's
# own behaviour.
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

# Never reached under --yes or --dry-run: callers require --host or --disk first.
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

# Under --dry-run this only warns, so container tests without real tools
# like nixos-install and sops still exercise every code path.
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
  --disk DISK              Target block device, install mode only.
  -y, --yes               Assume yes and auto-confirm every prompt. Live
                            install also requires --confirm-wipe unless
                            --dry-run is given too. Never skips setting
                            krane's password.
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

# Avoids an unbound-variable error under set -u when a flag has no value.
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

# True only when $HOST's own default.nix imports the NVIDIA desktop GPU
# module, confirmed with `git grep -n nvidia-desktop hosts/`: tariognatha
# only. Empty $HOST (interactive host choice not made yet) reads as false.
host_uses_cuda() {
    grep -q 'gpu/nvidia-desktop' "$REPO_ROOT/hosts/$HOST/default.nix" 2>/dev/null
}

# Prints the --option accept-flake-config flag nix/nixos-rebuild take.
# True trusts flake.nix's nixConfig, which is only worth it on the host
# that actually pulls packages from the CUDA cache.
flake_config_opt() {
    if host_uses_cuda; then
        printf -- '--option accept-flake-config true'
    else
        printf -- '--option accept-flake-config false'
    fi
}

# Read-only DNS probe, not routed through run: a lookup here changes
# nothing. cache.nixos-cuda.org is only checked on the CUDA host, since a
# non-CUDA install never queries it. Seen on taractias: the live ISO's
# inherited DNS server timed out on cache.nixos-cuda.org while
# cache.nixos.org resolved fine, and nix gave up waiting on the stalled
# lookup instead of just skipping that substituter.
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
    if [ -n "$HOST" ]; then
        return
    fi
    if $YES; then
        die "--host is required together with --yes or --dry-run, no interactive prompts under --yes"
    fi
    local suggestion
    suggestion=$(suggest_host)
    HOST=$(choose_one "Select the target host" "$suggestion" "${AVAILABLE_HOSTS[@]}")
}

# Excludes zram, device-mapper, MD-RAID and loop devices by name, since
# lsblk's own TYPE==disk filter below does not catch zram.
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
        # Excludes the disk the live ISO itself booted from.
        if [ -n "$iso_disk" ] && [ "$base" = "$iso_disk" ]; then
            continue
        fi
        candidates+=("$line")
    done < <(lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$NF == "disk"')

    [ "${#candidates[@]}" -gt 0 ] || die "no candidate disks found, lsblk found nothing besides the ISO device"

    local chosen
    chosen=$(choose_one "Select the target disk. THIS WILL BE ERASED." "" "${candidates[@]}")
    DISK=$(printf '%s' "$chosen" | awk '{print $1}')

    # Prefers a stable /dev/disk/by-id path, which survives disk
    # reordering across reboots.
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

# Blocks $DISK values that could break out of patch_disko's sed expression.
validate_disk_charset() {
    case "$DISK" in
        *[!A-Za-z0-9/_.:-]*)
            die "disk path contains characters unsafe for this script's sed use: $DISK"
            ;;
    esac
}

# The -b check guards against a non-block-device $DISK before anything
# destructive runs. Warns instead of dying under --dry-run, for
# placeholder paths like /dev/null in container tests.
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
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "This will ERASE ALL DATA on:" "" "  $DISK" "  resolves to /dev/$kernel_hl" "" "Host: $HOST" >&2
    if $YES; then
        log_warn "auto-confirmed wipe of $DISK via --yes"
        return
    fi
    local typed
    typed=$(gum_tty input --placeholder "$kernel" --prompt "Type $kernel_hl to confirm: ")
    [ "$typed" = "$kernel" ] || die "typed name did not match $kernel (device $DISK), aborting"
    log_info "wipe confirmed for /dev/$kernel"
}

# grep -qF verifies the sed actually landed, factored out so --self-test
# can exercise it for real against a throwaway copy.
patch_disko_file() {
    local disko_file="$1" disk="$2"
    if grep -qF "device = \"$disk\";" "$disko_file"; then
        log_info "disko.nix already patched for $disk"
        return 0
    fi
    if ! grep -qF 'device = "/dev/CHANGE-ME";' "$disko_file"; then
        die "$disko_file has neither the CHANGE-ME placeholder nor $disk already patched in, check it by hand"
    fi
    run sed -i "s#device = \"/dev/CHANGE-ME\";#device = \"$disk\";#" "$disko_file"
    if ! $DRY_RUN; then
        grep -qF "device = \"$disk\";" "$disko_file" || die "post-sed verification failed: $disko_file"
    fi
}

patch_disko() {
    log_step "Patching hosts/$HOST/disko.nix for $DISK"
    validate_disk_charset
    patch_disko_file "$REPO_ROOT/hosts/$HOST/disko.nix" "$DISK"
}

run_disko() {
    log_step "Running disko for $HOST (formats $DISK)"
    local disko_script
    disko_script=$(capture_with_spin "Evaluating disko script for $HOST" \
        nix build --no-link --print-out-paths --accept-flake-config \
        "$REPO_ROOT#nixosConfigurations.$HOST.config.system.build.diskoScript")
    # No spinner or extra tee here, both need to stream live output directly.
    run_sh "\"$disko_script\" 2>&1" || { LAST_CMD=""; die "disko run failed for $HOST, see $LOG"; }
}

# Under 12 GiB, since the nix build needs about 4 GB and the live ISO has no swap.
install_swap_needed() { [ "$1" -lt 12582912 ]; }

# The live ISO keeps /tmp and ~/.cache/nix in RAM with no swap backing it, so
# nixos-install's nix build can OOM on a low-RAM machine. /mnt exists by now.
# Swap is an optimisation here, never abort the install over it: a failed
# mkswapfile or swapon just warns and continues without one.
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
        log_info "RAM is $mem_gib GiB, creating an 8 GiB swapfile on /mnt for the install"
        INSTALL_SWAP_ACTIVE=true
        run_soft btrfs filesystem mkswapfile --size 8g /mnt/swapfile \
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

# lspci -D prints DDDD:bb:dd.f in hex. krane.prime.*BusId wants
# PCI:bus:device:function in decimal, so this converts hex to decimal.
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
    # Uses | as the sed delimiter, not #, since the replacement text
    # itself contains a literal # in its trailing comment.
    run sed -i -E "s|(krane\.prime\.${key}[[:space:]]*=[[:space:]]*)\"[^\"]*\"[[:space:]]*;.*|\\1\"${value}\"; # set by install.sh|" "$file"
    if ! $DRY_RUN; then
        grep -qF "$target" "$file" || die "post-sed verification failed for $key in $file"
    fi
}

patch_prime() {
    local default_nix="$REPO_ROOT/hosts/$HOST/default.nix"
    if ! grep -qE '^[[:space:]]*krane\.prime\.(intelBusId|nvidiaBusId)[[:space:]]*=[[:space:]]*"' "$default_nix"; then
        return 0
    fi

    log_step "Detecting PRIME PCI bus IDs for $HOST"
    if ! command -v lspci >/dev/null 2>&1; then
        soft_fail "lspci not found, cannot auto-detect PRIME bus IDs, edit $default_nix by hand"
        return 0
    fi

    local lspci_out intel_addr nvidia_addr
    # || true, since a non-zero lspci exit here must fall through to
    # soft_fail, not abort after the disk is already wiped.
    lspci_out=$(lspci -D) || true
    # || true, since under set -o pipefail an empty grep match must not
    # abort the script here.
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

# Commits before nixos-install so the copied repo starts with a clean
# history instead of the disko/PRIME patches left as a local diff.
commit_hardware_config() {
    log_step "Committing local hardware config for $HOST"
    run git -C "$REPO_ROOT" add -A
    if ! $DRY_RUN && git -C "$REPO_ROOT" diff --cached --quiet; then
        log_info "nothing new to commit for $HOST hardware config"
        return 0
    fi
    local id_args=()
    # Commit identity is overridden only when none is configured.
    if [ -z "$(git -C "$REPO_ROOT" config user.email 2>/dev/null || true)" ]; then
        id_args=(-c user.name=krane -c user.email=krane@localhost)
    fi
    run git -C "$REPO_ROOT" "${id_args[@]}" commit -m "Configure $HOST hardware" --quiet
}

# disko's own nix build already ran before /mnt existed, so it used the
# ISO's own tmp. TMPDIR/XDG_CACHE_HOME are scoped to this one command, not
# exported, so --dry-run never touches the real environment.
#
# Retries up to 3 times: nixos-install resumes from paths nix already
# copied, so a transient network failure only costs the 10 s wait between
# attempts, not the whole download. mkdir/rm around the loop run once,
# not per attempt, and each run_sh stays paired with its own handler so a
# failure here never trips the ERR trap.
run_nixos_install() {
    log_step "Running nixos-install for $HOST"
    if host_uses_cuda; then
        log_info "$HOST has CUDA packages, accept-flake-config true"
    else
        log_info "host has no CUDA packages, CUDA cache disabled for this install"
    fi
    local flake_opt
    flake_opt=$(flake_config_opt)
    run mkdir -p /mnt/var/cache/installer/tmp
    local attempt
    for attempt in 1 2 3; do
        local log_mark
        log_mark=$(wc -l < "$LOG" 2>/dev/null || echo 0)
        run_sh "TMPDIR=/mnt/var/cache/installer/tmp XDG_CACHE_HOME=/mnt/var/cache/installer nixos-install --flake \"$REPO_ROOT#$HOST\" --no-root-passwd $flake_opt 2>&1" \
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

# Always runs for real outside --dry-run: --yes must never leave a fresh
# install with no login. Retries a few times for a mistyped password.
set_krane_password() {
    log_step "Set krane's password on the new install"

    if ! $DRY_RUN && [ ! -t 0 ]; then
        print_no_password_box
        PASSWORD_SET=false
        return 0
    fi

    local attempt=1
    while [ "$attempt" -le 3 ]; do
        if run nixos-enter --root /mnt -- passwd krane; then
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
        "  nixos-enter --root /mnt -- passwd krane" >&2
}

finish_install() {
    log_step "Copying repo to /mnt/home/krane/.dotfiles"
    run mkdir -p /mnt/home/krane/.dotfiles
    run_sh "cp -a \"$REPO_ROOT/.\" /mnt/home/krane/.dotfiles/"
    run nixos-enter --root /mnt -- chown -R krane:users /home/krane/.dotfiles
    run_sh "test -f /mnt/home/krane/.dotfiles/flake.nix" \
        || die "repo copy to /mnt/home/krane/.dotfiles is missing flake.nix, see $LOG"

    PASSWORD_SET=true
    set_krane_password

    banner "Install complete" \
        "Next steps:" \
        "  1. reboot" \
        "  2. ~/.dotfiles/install.sh --mode setup" \
        "  3. second switch, setup mode drives this"

    if $PASSWORD_SET; then
        if confirm "Reboot now?"; then
            run reboot
        fi
    else
        log_warn "not offering to reboot, set krane's password first"
    fi
}

run_install_mode() {
    preflight_live
    choose_host
    check_dns
    choose_disk
    validate_disk_is_physical

    confirm_wipe_target
    patch_disko
    run git -C "$REPO_ROOT" add -A
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
    if [ ! -d "$REPO_ROOT/hosts/$HOST" ]; then
        soft_fail "unknown host '$HOST', expected one of: ${AVAILABLE_HOSTS[*]}"
    fi
    if [ "$REPO_ROOT" != "$HOME/.dotfiles" ]; then
        log_warn "checked out at $REPO_ROOT, not \$HOME/.dotfiles. The docs assume the latter"
    fi
}

# True when $1 (a .sops.yaml path) still contains $2's unreplaced
# bootstrap-sops.sh placeholder recipient. Mirrors the placeholder shape
# scripts/bootstrap-sops.sh derives from HOST (see its HOST_PLACEHOLDER). A
# missing .sops.yaml counts as "placeholder present" too, i.e. not yet
# bootstrapped: bootstrap-sops.sh must still run, and hits its own "not
# found" guard if it has nothing to work from.
sops_placeholder_present() {
    local sops_yaml="$1" host="$2" host_upper placeholder
    [ -f "$sops_yaml" ] || return 0
    host_upper=$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')
    placeholder="age1PLACEHOLDER_HOST_${host_upper}_REPLACE_VIA_BOOTSTRAP_SOPS_SH"
    grep -qF "$placeholder" "$sops_yaml" 2>/dev/null
}

# True when $2, in the worktree of the git repo at $1, has no uncommitted
# change at all -- modified, untracked, staged, or deleted. Reads the
# worktree/index via `git status --porcelain` so callers can decide whether
# there is anything to commit BEFORE staging: `git add` only runs once the
# user has confirmed the commit, so a declined confirm leaves nothing
# staged. Works with no HEAD too (an unborn branch still reports an
# untracked path via `??`), unlike an index-vs-HEAD diff.
git_path_clean() {
    local repo="$1" path="$2"
    [ -z "$(git -C "$repo" status --porcelain -- "$path" 2>/dev/null)" ]
}

# Setup mode must be safely re-runnable: a prior run may have already
# patched .sops.yaml and committed it, in which case bootstrap-sops.sh has
# nothing left to do and `git commit` on a clean tree would exit 1 and
# abort the rest of setup (edit_host_secrets, setup_rust, ...).
run_bootstrap_sops() {
    log_step "Bootstrapping sops-nix recipients for $HOST"
    local key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if sops_placeholder_present "$REPO_ROOT/.sops.yaml" "$HOST"; then
        run_sh "\"$REPO_ROOT/scripts/bootstrap-sops.sh\" \"$HOST\""
    elif [ -f "$key_file" ]; then
        if $DRY_RUN; then
            log_info "would skip bootstrap: sops already bootstrapped for $HOST"
        else
            log_info "sops already bootstrapped for $HOST, skipping"
        fi
    else
        # The host placeholder is gone but the admin key that decrypts
        # existing secrets is missing. Re-running bootstrap-sops.sh here
        # would generate a fresh admin key that never becomes a recipient
        # (the admin placeholder is already replaced too), silently
        # locking secrets out from under the new key. Fail loudly instead.
        local msg="sops already bootstrapped for $HOST but admin key $key_file is missing; restore it from your backup (see secrets/README.md) or re-add the age1PLACEHOLDER_ADMIN_KRANE_REPLACE_VIA_BOOTSTRAP_SOPS_SH placeholder to .sops.yaml and rerun"
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
            # sops exits 200 "File has not changed, exiting." when the user
            # quits without editing; tolerate only that. Anything else
            # (e.g. 128 on an undecryptable file with sops 3.13.3) is a
            # real failure and must abort setup rather than be silently
            # skipped. Clear LAST_CMD ourselves, same as run_soft, so a
            # later unrelated failure in this function is never blamed on
            # this handled one; die() itself never re-triggers the ERR
            # trap since it's reached via `||`, exempting it, and die only
            # runs log_error/print_fail_box/exit from there.
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

# One entry per docs/VERIFY.md checklist item. Never dies, reports
# OK/WARN/SKIP instead.
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
    # SC2016: these bash -c strings expand $HOME inside the spawned bash, not here.
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
        verify_check "Hyprland config has no errors" hyprctl configerrors
        # shellcheck disable=SC2016
        verify_check "Monitor layout is queryable" bash -c 'hyprctl monitors -j >/dev/null'
    else
        verify_skip "Hyprland config has no errors" "not running inside a Hyprland session"
        verify_skip "Monitor layout is queryable" "not running inside a Hyprland session"
    fi

    if command -v bootctl >/dev/null 2>&1; then
        # bootctl list needs root: the ESP is mounted umask=0077 (hosts/*/disko.nix).
        # Cache the credential first; sudo reads the password straight from
        # /dev/tty, so it works despite the tee pipe on stdout/stderr. run_tty
        # no-ops under --dry-run and fails fast with no tty, in which case the
        # `sudo -n` below just WARNs instead of stalling the checklist.
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
        log_info "$HOST has CUDA packages, accept-flake-config true"
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

    if [ -n "$HOST" ]; then
        local known=false h
        for h in "${AVAILABLE_HOSTS[@]}"; do
            [ "$h" = "$HOST" ] && known=true
        done
        $known || die "unknown host '$HOST', expected one of: ${AVAILABLE_HOSTS[*]}"
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

# Self-test: a maintainer or CI hook, dispatched before main runs.

# Spawns a separate bash "$0" so the real -E and ERR trap fire, unlike an
# in-process subshell. self_test() greps its output for the failure box.
if $SELF_TEST_TRIGGER_ERR; then
    self_test_trigger_err_fn() { false; }
    self_test_trigger_err_fn
    # Unreachable: false fails under set -e, this guards a silent regression.
    echo "self-test-trigger-err: unreachable line ran, ERR trap did not abort the script" >&2
    exit 1
fi

# Each builds a throwaway fixture and runs the real (non-dry-run) sed and
# verify helper against it, since a --dry-run test never exercises real sed.
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

    echo "== self-test: install swap RAM threshold ==" >&2
    if install_swap_needed 7025000 && ! install_swap_needed 33554432; then
        echo "OK: install_swap_needed true at 6.7 GiB, false at 32 GiB" >&2
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
    [ "$got" = "--option accept-flake-config true" ] \
        || { echo "FAIL: flake_config_opt for tariognatha was '$got'" >&2; opt_ok=false; }
    HOST=taractias
    got=$(flake_config_opt)
    [ "$got" = "--option accept-flake-config false" ] \
        || { echo "FAIL: flake_config_opt for taractias was '$got'" >&2; opt_ok=false; }
    HOST="$saved_host"
    if $opt_ok; then
        echo "OK: flake_config_opt true only for tariognatha" >&2
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
    # Committed, worktree matches HEAD, nothing staged: clean.
    if git_path_clean "$git_tmp" tracked.yaml; then
        echo "OK: a clean committed file reads as nothing to commit" >&2
    else
        echo "FAIL: a clean committed file did not read as clean" >&2
        clean_ok=false
    fi
    # Modified in the worktree, not staged: dirty.
    echo modified >"$git_tmp/tracked.yaml"
    if ! git_path_clean "$git_tmp" tracked.yaml; then
        echo "OK: a modified, unstaged file reads as dirty" >&2
    else
        echo "FAIL: a modified, unstaged file read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" checkout -q -- tracked.yaml
    # Untracked, not staged: dirty.
    echo new >"$git_tmp/untracked.yaml"
    if ! git_path_clean "$git_tmp" untracked.yaml; then
        echo "OK: an untracked file reads as dirty" >&2
    else
        echo "FAIL: an untracked file read as clean" >&2
        clean_ok=false
    fi
    # Staged new file: dirty.
    git -C "$git_tmp" add -- untracked.yaml
    if ! git_path_clean "$git_tmp" untracked.yaml; then
        echo "OK: a staged new file reads as dirty" >&2
    else
        echo "FAIL: a staged new file read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m add-untracked
    # Staged deletion (`git rm --cached`) with the worktree copy left
    # identical to HEAD: still dirty, because the index no longer matches
    # HEAD -- `git status --porcelain` reports both the index-level D and
    # an untracked ?? for the same path. A real run would then `git add`
    # (restoring the index to match HEAD and the worktree) before
    # committing; the caller re-checks `git diff --cached --quiet HEAD`
    # after that `add` and, finding nothing staged, skips the commit
    # instead of running it and hitting exit 1 "nothing to commit".
    git -C "$git_tmp" rm -q --cached tracked.yaml
    if ! git_path_clean "$git_tmp" tracked.yaml; then
        echo "OK: a staged deletion with worktree identical to HEAD reads as dirty" >&2
    else
        echo "FAIL: a staged deletion with worktree identical to HEAD read as clean" >&2
        clean_ok=false
    fi
    git -C "$git_tmp" add -- tracked.yaml
    # No HEAD at all (unborn branch) with an untracked file: dirty, not an
    # error -- `git status --porcelain` needs no HEAD to report `??`.
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
