#!/usr/bin/env bash
# install.sh installs krane's NixOS + Hyprland flake on tariognatha,
# tarmantria and taractias. Two modes, auto-detected, override with
# --mode. Install mode runs from a live ISO and erases the target disk
# while partitioning it with disko. Setup mode runs after first boot and
# drives the second switch. Logs each run to
# /tmp/krane-install-TIMESTAMP-PID.log.

# -E makes the ERR trap fire inside functions, not just at the top level.
set -Eeuo pipefail

# Re-execs through nix shell when gum is missing, since the live ISO
# lacks it. KRANE_INSTALL_REEXEC stops this from looping.
if ! command -v gum >/dev/null 2>&1 && [ -z "${KRANE_INSTALL_REEXEC:-}" ]; then
    export KRANE_INSTALL_REEXEC=1
    exec nix --extra-experimental-features 'nix-command flakes' shell \
        nixpkgs#gum nixpkgs#git nixpkgs#dmidecode nixpkgs#pciutils \
        --command bash "$0" "$@"
fi

# The minimal live ISO ships nix without flakes; the installed system
# enables them via modules/nixos/nix-settings.nix. extra- merges with
# any existing setting instead of replacing it.
export NIX_CONFIG="extra-experimental-features = nix-command flakes"

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
# Suppresses on_exit's own reminder, since die/usage already explained the failure.
HANDLED_EXIT=false
USAGE_EXIT=false

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

log_info() { gum log --time=rfc3339 --level info --structured "$1" >&2; }
log_ok() { gum log --time=rfc3339 --level info --structured "$1" status ok >&2; }
log_warn() { gum log --time=rfc3339 --level warn --structured "$1" >&2; }
log_error() { gum log --time=rfc3339 --level error --structured "$1" >&2; }

print_fail_box() {
    HANDLED_EXIT=true
    local lines=("install.sh failed" "" "$1")
    if $LOG_WRITABLE; then
        lines+=("" "Log: $LOG")
    fi
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "${lines[@]}" >&2
}

die() {
    log_error "$*"
    print_fail_box "$*"
    exit 1
}

err_trap() {
    local msg="unexpected failure at line $1"
    log_error "$msg"
    if $LOG_WRITABLE; then
        msg="$msg, see $LOG"
    fi
    print_fail_box "$msg"
}
trap 'err_trap $LINENO' ERR

on_exit() {
    local rc=$?
    if [ "$rc" -ne 0 ] && ! $HANDLED_EXIT && ! $USAGE_EXIT; then
        if $LOG_WRITABLE; then
            gum style --foreground 244 "See $LOG for the full transcript, exit $rc." >&2
        else
            gum style --foreground 244 "exit $rc, no log file was writable this run." >&2
        fi
    fi
}
trap on_exit EXIT

run() {
    if $DRY_RUN; then
        printf '+ %s\n' "$(printf '%q ' "$@")" >&2
        return 0
    fi
    "$@"
}

# -o pipefail matters the moment a run_sh string pipes commands, so a
# failing command on the left cannot look like a success.
run_sh() {
    if $DRY_RUN; then
        printf '+ %s\n' "$1" >&2
        return 0
    fi
    bash -o pipefail -c "$1"
}

capture() {
    if $DRY_RUN; then
        printf '+ %s\n' "$(printf '%q ' "$@")" >&2
        printf '%s\n' "/dry-run/placeholder"
        return 0
    fi
    "$@"
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
    gum confirm "$1"
}

# Never reached under --yes or --dry-run: callers require --host or --disk first.
choose_one() {
    local prompt="$1" selected="$2"
    shift 2
    log_info "$prompt"
    if [ "$#" -eq 0 ]; then
        die "choose_one: no candidates for '$prompt'"
    fi
    if [ -n "$selected" ]; then
        gum choose --selected "$selected" "$@"
    else
        gum choose "$@"
    fi
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
    require nixos-install nixos-generate-config nixos-enter git nix sed lsblk
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
    gum style \
        --border double --border-foreground 196 --foreground 196 --bold \
        --padding "1 3" --margin "1 0" \
        "This will ERASE ALL DATA on:" "" "  $DISK" "" "Host: $HOST" >&2
    if $YES; then
        log_warn "auto-confirmed wipe of $DISK via --yes"
        return
    fi
    local typed
    typed=$(gum input --placeholder "$DISK" --prompt "Type the disk path to confirm: ")
    [ "$typed" = "$DISK" ] || die "typed path did not match $DISK, aborting"
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
    run_sh "\"$disko_script\" 2>&1" || die "disko run failed for $HOST, see $LOG"
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

run_nixos_install() {
    log_step "Running nixos-install for $HOST"
    run_sh "nixos-install --flake \"$REPO_ROOT#$HOST\" --no-root-passwd --accept-flake-config 2>&1" \
        || die "nixos-install failed for $HOST, see $LOG"
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
    choose_disk
    validate_disk_is_physical

    confirm_wipe_target
    patch_disko
    run git -C "$REPO_ROOT" add -A
    run_disko
    generate_hardware_config
    patch_prime
    commit_hardware_config
    run_nixos_install
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

run_bootstrap_sops() {
    log_step "Bootstrapping sops-nix recipients for $HOST"
    run_sh "\"$REPO_ROOT/scripts/bootstrap-sops.sh\" \"$HOST\""
    if confirm "Commit .sops.yaml now?"; then
        run git -C "$REPO_ROOT" add .sops.yaml
        run git -C "$REPO_ROOT" commit -m "Add $HOST sops recipient"
    fi
}

edit_host_secrets() {
    local secrets_file="$REPO_ROOT/secrets/$HOST.yaml"
    if $YES; then
        log_info "skipping interactive secrets edit under --yes, run 'sops $secrets_file' later"
        return
    fi
    if confirm "Edit $secrets_file with sops now?"; then
        run_sh "sops \"$secrets_file\""
        log_warn "uncommitted secrets evaluate as ABSENT to sops-nix, commit $secrets_file before rebuilding"
        if confirm "Commit $secrets_file now?"; then
            run git -C "$REPO_ROOT" add "$secrets_file"
            run git -C "$REPO_ROOT" commit -m "Add $HOST secrets"
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
        verify_check "systemd-boot entries present" bootctl list
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
    if confirm "Run 'sudo nixos-rebuild switch --flake $REPO_ROOT#$HOST' now?"; then
        run_sh "sudo nixos-rebuild switch --flake \"$REPO_ROOT#$HOST\" --accept-flake-config 2>&1" \
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

    echo "== self-test: ERR trap fires inside a function ==" >&2
    # A separate bash "$0" process, not a subshell, so the real ERR trap fires.
    local out rc2=0
    out=$(bash "$0" --self-test-trigger-err 2>&1) || rc2=$?
    if [ "$rc2" -ne 0 ] && printf '%s' "$out" | grep -q "unexpected failure at line"; then
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
