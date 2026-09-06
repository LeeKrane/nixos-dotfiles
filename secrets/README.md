# secrets/

On a fresh checkout, only this file and `.gitkeep` exist here. Create each
`*.yaml` file locally, encrypt it with [sops](https://github.com/getsops/sops),
then `git add` and commit it on every host and clone that needs it.

Commit it. Flakes only see git-tracked or staged files, so an untracked
`secrets/<host>.yaml` evaluates as absent: `sops.secrets`, the wg0 tunnel and
the Proton Drive rclone seed all silently stay off, no error. `.gitignore`
only ignores `secrets/*.key`: commit a `.yaml` file like any other tracked
file. Its contents stay sops-encrypted the whole time.

Each host decrypts with an age identity derived from its own SSH host key
(`modules/nixos/sops.nix`, `sops.age.sshKeyPaths`), so a compromised host's
key exposes only that host's file, not every secret ever created.

## Files

`shared.yaml` (optional, not created by default) holds secrets any host may
need. Nothing consumes it yet, but `.sops.yaml`'s `creation_rules` already
list every host plus the admin as recipients for when one shows up, such as
an optional personal SSH key or git hosting tokens.

`<hostname>.yaml` (`tariognatha.yaml`, `tarmantria.yaml`, `taractias.yaml`)
holds per-host secrets, decryptable by that host's own key plus the admin's.
`modules/nixos/sops.nix` reads:

| Key | Read by | Owner:mode |
| --- | --- | --- |
| `wireguard/wg0-private-key` | `modules/nixos/networking.nix` (`networking.wg-quick.interfaces.wg0.privateKeyFile`) | `root:0400` |
| `rclone/config-seed` | `modules/home/proton-drive.nix` (seeds `~/.config/rclone/rclone.conf` if absent) | `krane:0400` |

The secret alone does not bring up WireGuard: also uncomment and fill in
the `address` and `peers` block in `modules/nixos/networking.nix`.

## How to create one

Every recipient in `.sops.yaml` starts as an `age1PLACEHOLDER_...` value
that decrypts nothing, until step 1 below runs.

1. Run `scripts/bootstrap-sops.sh <hostname>` on the target host, after it
   has booted at least once. It needs `/etc/ssh/ssh_host_ed25519_key.pub`,
   which `sshd-keygen` creates at first boot. The script derives the host's
   age recipient with `ssh-to-age`, generates your personal age key with
   `age-keygen` if needed, and patches both into `.sops.yaml` in place of
   the placeholders. It never writes a secret value.

   Your personal key lands at `~/.config/sops/age/keys.txt`
   (`$SOPS_AGE_KEY_FILE` if set). Back it up: lose it and every secret it
   decrypts is gone.
2. `git add .sops.yaml && git commit`.
3. Create the file with `sops`, which encrypts against the recipients
   `.sops.yaml` now lists:

   ```sh
   sops secrets/tariognatha.yaml
   ```

   This opens `$EDITOR` on a decrypted buffer and encrypts it back on save.
   Fill in real values matching this skeleton:

   ```yaml
   wireguard:
       wg0-private-key: <paste the real WireGuard private key here>
   rclone:
       config-seed: |
           [ProtonDrive]
           type = protondrive
           username = <your Proton account email>
           # rest of a working rclone.conf [ProtonDrive] stanza, copied verbatim
           # into ~/.config/rclone/rclone.conf on first activation.
   ```

4. `git add secrets/<hostname>.yaml && git commit`. Skip this and step 5
   evaluates as if the file never existed.
5. `just switch <hostname>` (or `sudo nixos-rebuild switch --flake
   .#<hostname>` on the host itself). Secrets decrypt to `/run/secrets/...`
   at activation.

## Never

- Never type a real secret value into `.sops.yaml`, a Nix file, a commit
  message, or anywhere outside a `sops`-encrypted `secrets/*.yaml`.
- Never hand-edit the `age1...` recipients in `.sops.yaml`. Let
  `scripts/bootstrap-sops.sh` do it, so the real value only ever exists on
  the machine that generated it plus whatever you copied it to yourself.
