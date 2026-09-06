#!/usr/bin/env bash
# Bootstraps sops-nix recipients for one host: derives its age recipient
# from its SSH host key, generates a personal admin age key if needed,
# and patches both into .sops.yaml in place of the age1PLACEHOLDER_...
# placeholders. NEVER writes a secret value, only PUBLIC age recipients.
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
    exit 1
fi

SOPS_YAML="$REPO_ROOT/.sops.yaml"
HOST_SECRETS_FILE="$REPO_ROOT/secrets/$HOST.yaml"
HOST_SSH_PUBKEY="/etc/ssh/ssh_host_ed25519_key.pub"

# Placeholders take the form age1PLACEHOLDER_..., matched literally so a
# real recipient already in place does not match again.
HOST_UPPER=$(printf '%s' "$HOST" | tr '[:lower:]' '[:upper:]')
HOST_PLACEHOLDER="age1PLACEHOLDER_HOST_${HOST_UPPER}_REPLACE_VIA_BOOTSTRAP_SOPS_SH"
ADMIN_PLACEHOLDER="age1PLACEHOLDER_ADMIN_KRANE_REPLACE_VIA_BOOTSTRAP_SOPS_SH"

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

echo "==> Deriving age recipient for host '$HOST' from $HOST_SSH_PUBKEY"
HOST_AGE_KEY=$(ssh-to-age -i "$HOST_SSH_PUBKEY")
echo "    $HOST_AGE_KEY"

if [ -f "$PERSONAL_AGE_KEY_FILE" ]; then
    echo "==> Personal age key already exists at $PERSONAL_AGE_KEY_FILE, not regenerating"
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
   public recipients changed:

     git -C "$REPO_ROOT" diff .sops.yaml
     git -C "$REPO_ROOT" add .sops.yaml
     git -C "$REPO_ROOT" commit -m "Add $HOST sops recipient"

2. Create $HOST_SECRETS_FILE with sops. It opens \$EDITOR on a decrypted
   scratch buffer and encrypts it back to disk on save:

     sops "$HOST_SECRETS_FILE"

   Fill in this skeleton. See secrets/README.md for what each key is for:

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
