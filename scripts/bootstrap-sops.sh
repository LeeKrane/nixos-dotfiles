#!/usr/bin/env bash
# Bootstraps sops-nix recipients for one host. Each host has its own
# personal admin age key -- generated here and kept in
# $PERSONAL_AGE_KEY_FILE, never shared with any other host -- plus a host
# key derived from that host's own SSH host key. Both are patched into
# .sops.yaml in place of the age1PLACEHOLDER_... placeholders. NEVER
# writes a secret value, only PUBLIC age recipients.
#
# Usage: scripts/bootstrap-sops.sh <host>. Run this on the target host,
# after first boot, as the admin user, not root. Idempotent, safe to run
# again.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# hosts/ is the single source of truth here, same as flake.nix's hosts
# list and docker-check.sh's HOSTS.
known_hosts() {
    (
        cd "$REPO_ROOT/hosts"
        for d in */; do
            printf '%s\n' "${d%/}"
        done
    )
}

usage() {
    echo "Usage: $0 <host>" >&2
    echo "Derives sops-nix recipients for one host and patches .sops.yaml." >&2
    echo "Valid hosts: $(known_hosts | tr '\n' ' ')" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

HOST="$1"
if [ ! -d "$REPO_ROOT/hosts/$HOST" ]; then
    echo "error: unknown host '$HOST', expected one of: $(known_hosts | tr '\n' ' ')" >&2
    echo "       VM variants (e.g. tariognatha-vm) are bootstrapped under their parent" >&2
    echo "       host name -- use that, not a separate entry for the VM variant." >&2
    exit 1
fi

SOPS_YAML="$REPO_ROOT/.sops.yaml"
HOST_SECRETS_FILE="$REPO_ROOT/secrets/$HOST.yaml"
HOST_SSH_PUBKEY="/etc/ssh/ssh_host_ed25519_key.pub"

# Placeholders take the form age1PLACEHOLDER_..., matched literally so a
# real recipient already in place does not match again.
HOST_UPPER=$(printf '%s' "$HOST" | tr '[:lower:]' '[:upper:]')
HOST_PLACEHOLDER="age1PLACEHOLDER_HOST_${HOST_UPPER}_REPLACE_VIA_BOOTSTRAP_SOPS_SH"
ADMIN_PLACEHOLDER="age1PLACEHOLDER_ADMIN_${HOST_UPPER}_REPLACE_VIA_BOOTSTRAP_SOPS_SH"

# PERSONAL_AGE_KEY_FILE is sops' own SOPS_AGE_KEY_FILE default.
PERSONAL_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [ ! -f "$SOPS_YAML" ]; then
    echo "error: $SOPS_YAML not found, run this from a checkout of the repo" >&2
    exit 1
fi

if [ ! -r "$HOST_SSH_PUBKEY" ]; then
    echo "error: $HOST_SSH_PUBKEY not readable, run this on $HOST itself, after first boot" >&2
    exit 1
fi

if ! command -v ssh-to-age >/dev/null 2>&1; then
    echo "error: ssh-to-age not on PATH, run nix develop, or it is already in environment.systemPackages" >&2
    exit 1
fi

if ! command -v age-keygen >/dev/null 2>&1; then
    echo "error: age-keygen not on PATH, run nix develop, or it is already in environment.systemPackages" >&2
    exit 1
fi

# Refuses root only when it would write a new personal key into /root's
# home instead of the real admin account's.
if [ "$(id -u)" -eq 0 ] && [ ! -f "$PERSONAL_AGE_KEY_FILE" ]; then
    echo "error: running as root would create a personal age key under root's home, $PERSONAL_AGE_KEY_FILE." >&2
    echo "       Re-run as the admin user krane, or set SOPS_AGE_KEY_FILE to an" >&2
    echo "       existing key you already generated as that user." >&2
    exit 1
fi

# If this host's admin placeholder is already gone from .sops.yaml, a
# previous run of this script (or a by-hand edit) already patched in the
# real recipient for '$HOST'. Don't blindly proceed as if bootstrapping
# were still needed: verify the local personal key, if any, actually
# matches what .sops.yaml already trusts for this host.
if ! grep -qF "$ADMIN_PLACEHOLDER" "$SOPS_YAML"; then
    SOPS_ADMIN_LINE=$(grep -E "&admin_${HOST}[[:space:]]" "$SOPS_YAML" || true)
    if [ -z "$SOPS_ADMIN_LINE" ]; then
        echo "error: $ADMIN_PLACEHOLDER is not in $SOPS_YAML, and no &admin_${HOST}" >&2
        echo "       anchor line was found either. .sops.yaml is in an unexpected state" >&2
        echo "       for host '$HOST' -- fix it by hand before re-running." >&2
        exit 1
    fi

    SOPS_ADMIN_KEY=$(printf '%s\n' "$SOPS_ADMIN_LINE" | grep -oE 'age1[0-9a-z]+' || true)
    if [ -z "$SOPS_ADMIN_KEY" ]; then
        echo "error: could not find an age1... recipient on the &admin_${HOST} line in" >&2
        echo "       $SOPS_YAML:" >&2
        echo "       $SOPS_ADMIN_LINE" >&2
        exit 1
    fi

    if [ -f "$PERSONAL_AGE_KEY_FILE" ]; then
        LOCAL_ADMIN_KEY=$(age-keygen -y "$PERSONAL_AGE_KEY_FILE" 2>/dev/null || true)
        if [ -z "$LOCAL_ADMIN_KEY" ]; then
            echo "error: could not read a public key from $PERSONAL_AGE_KEY_FILE" >&2
            exit 1
        fi
        if [ "$LOCAL_ADMIN_KEY" != "$SOPS_ADMIN_KEY" ]; then
            echo "error: $PERSONAL_AGE_KEY_FILE is not this host's registered admin" >&2
            echo "       recipient in .sops.yaml." >&2
            echo "       local key's public value:   $LOCAL_ADMIN_KEY" >&2
            echo "       .sops.yaml's admin_${HOST}:  $SOPS_ADMIN_KEY" >&2
            echo "       Restore the correct $PERSONAL_AGE_KEY_FILE for this host, or re-add" >&2
            echo "       $ADMIN_PLACEHOLDER to .sops.yaml and re-run." >&2
            exit 1
        fi
        echo "==> Personal age key at $PERSONAL_AGE_KEY_FILE already matches .sops.yaml's admin_${HOST} recipient"
    else
        echo "error: $ADMIN_PLACEHOLDER is already gone from $SOPS_YAML, but" >&2
        echo "       $PERSONAL_AGE_KEY_FILE does not exist. Refusing to generate a brand" >&2
        echo "       new personal key here: .sops.yaml already trusts $SOPS_ADMIN_KEY for" >&2
        echo "       host '$HOST', and a fresh key would just be an orphan nobody added as" >&2
        echo "       a recipient." >&2
        echo "       Restore the correct $PERSONAL_AGE_KEY_FILE for this host, or re-add" >&2
        echo "       $ADMIN_PLACEHOLDER to .sops.yaml and re-run." >&2
        exit 1
    fi
fi

echo "==> Deriving age recipient for host '$HOST' from $HOST_SSH_PUBKEY"
HOST_AGE_KEY=$(ssh-to-age -i "$HOST_SSH_PUBKEY")
echo "    $HOST_AGE_KEY"

if [ -f "$PERSONAL_AGE_KEY_FILE" ]; then
    echo "==> Personal age key already exists at $PERSONAL_AGE_KEY_FILE, not regenerating"
    if grep -qF "$ADMIN_PLACEHOLDER" "$SOPS_YAML"; then
        # About to register this existing key as $HOST's admin_$HOST
        # recipient below. Refuse if it's already registered as some
        # OTHER host's personal key -- two hosts sharing one personal
        # admin key defeats the point of per-host keys.
        if [ -z "${LOCAL_ADMIN_KEY:-}" ]; then
            LOCAL_ADMIN_KEY=$(age-keygen -y "$PERSONAL_AGE_KEY_FILE" 2>/dev/null || true)
            if [ -z "$LOCAL_ADMIN_KEY" ]; then
                echo "error: could not read a public key from $PERSONAL_AGE_KEY_FILE" >&2
                exit 1
            fi
        fi
        OTHER_ADMIN_LINES=$(grep -E "^[[:space:]]*- &admin_" "$SOPS_YAML" | grep -v "&admin_${HOST}[[:space:]]" || true)
        if printf '%s\n' "$OTHER_ADMIN_LINES" | grep -qF "$LOCAL_ADMIN_KEY"; then
            echo "error: $PERSONAL_AGE_KEY_FILE's public key is already registered as another" >&2
            echo "       host's personal admin key in $SOPS_YAML. Each host needs its own" >&2
            echo "       personal key -- generate a fresh one with:" >&2
            echo "         age-keygen -o $PERSONAL_AGE_KEY_FILE" >&2
            echo "       or set SOPS_AGE_KEY_FILE to point at a different, unused key file." >&2
            exit 1
        fi
    fi
else
    echo "==> Generating a new personal age key at $PERSONAL_AGE_KEY_FILE"
    mkdir -p "$(dirname "$PERSONAL_AGE_KEY_FILE")"
    age-keygen -o "$PERSONAL_AGE_KEY_FILE"
    chmod 600 "$PERSONAL_AGE_KEY_FILE"
fi

PERSONAL_AGE_KEY=$(age-keygen -y "$PERSONAL_AGE_KEY_FILE")
echo "    $PERSONAL_AGE_KEY"

echo "==> Patching $SOPS_YAML"
sed -i "s#${HOST_PLACEHOLDER}#${HOST_AGE_KEY}#" "$SOPS_YAML"
sed -i "s#${ADMIN_PLACEHOLDER}#${PERSONAL_AGE_KEY}#" "$SOPS_YAML"

if grep -q "age1PLACEHOLDER_" "$SOPS_YAML"; then
    echo "    other hosts' placeholders are untouched, run this script again on them"
else
    echo "    all placeholders replaced"
fi

cat <<EOF

==> Next steps

1. Review the diff, then commit it. Still zero secret values, only
   public recipients changed -- this host's own personal admin key (from
   $PERSONAL_AGE_KEY_FILE) plus its host key, both unique to '$HOST':

     git -C "$REPO_ROOT" diff .sops.yaml
     git -C "$REPO_ROOT" add .sops.yaml
     git -C "$REPO_ROOT" commit -m "Add $HOST sops recipient"

2. Create $HOST_SECRETS_FILE with sops. It opens \$EDITOR on a decrypted
   scratch buffer and encrypts it back to disk on save:

     sops "$HOST_SECRETS_FILE"

   Fill in this skeleton. See secrets/README.md for what each key is for.
   Both sections are optional: delete a whole section below to disable
   that feature on this host.

     wireguard:
         wg0-private-key: <real WireGuard private key>
     rclone:
         config-seed: |
             [ProtonDrive]
             type = protondrive
             username = <your Proton account email>
             # ... rest of a working rclone.conf [ProtonDrive] stanza (password, 2fa)

3. Commit that the file now exists. Its contents are encrypted, sops
   itself refuses to write plaintext to disk:

     git -C "$REPO_ROOT" add "$HOST_SECRETS_FILE"
     git -C "$REPO_ROOT" commit -m "Add $HOST secrets"

4. Rebuild so the secrets actually decrypt to /run/secrets:

     sudo nixos-rebuild switch --flake "$REPO_ROOT#$HOST"
EOF
