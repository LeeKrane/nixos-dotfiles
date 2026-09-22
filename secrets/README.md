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
| `wireguard/wg0-private-key` | `modules/nixos/sops.nix`'s `wg0.conf` template (`PrivateKey`) | `root:0400` |
| `wireguard/address` | same template (`Address`) | `root:0400` |
| `wireguard/peer-public-key` | same template (`PublicKey`) | `root:0400` |
| `wireguard/peer-endpoint` | same template (`Endpoint`) | `root:0400` |
| `wireguard/peer-allowed-ips` | same template (`AllowedIPs`) | `root:0400` |
| `wireguard/listen-port` | same template (`ListenPort`) | `root:0400` |
| `rclone/config-seed` | `modules/home/proton-drive.nix` (seeds `~/.config/rclone/rclone.conf` if absent) | `krane:0400` |

All six wireguard values live encrypted in `secrets/<host>.yaml`; none of
them, including the address and peer identity, are cleartext anywhere in
this repo. `modules/nixos/sops.nix` renders them into a `wg0.conf` template
(fixed `PersistentKeepalive 25`), which
`modules/nixos/networking.nix` points `networking.wg-quick.interfaces.wg0.configFile`
at. The secret alone does not bring up WireGuard on a new host: add all six
keys with `sops set`, for example:

```sh
sops set secrets/<hostname>.yaml '["wireguard"]["wg0-private-key"]' '"<real private key>"'
sops set secrets/<hostname>.yaml '["wireguard"]["address"]' '"<this host tunnel address>/24"'
sops set secrets/<hostname>.yaml '["wireguard"]["peer-public-key"]' '"<peer public key>"'
sops set secrets/<hostname>.yaml '["wireguard"]["peer-endpoint"]' '"<peer host>:51820"'
sops set secrets/<hostname>.yaml '["wireguard"]["peer-allowed-ips"]' '"<peer subnet>/24"'
sops set secrets/<hostname>.yaml '["wireguard"]["listen-port"]' '"51820"'
```

Both sections are optional per host: `modules/nixos/sops.nix` only declares
a `sops.secrets` entry for a section that's actually present in
`secrets/<host>.yaml`. To disable WireGuard or the Proton Drive seed on a
host, delete that whole top-level section (`wireguard:` or `rclone:`) with
`sops secrets/<host>.yaml`. Leaving the value empty is not enough: sops
encrypts values but not key names, so Nix can read which top-level sections
exist at eval time, but it cannot read an encrypted value to tell whether
it's empty. The gate checks only the top-level section name; the leaf key
names listed above (`wg0-private-key`, `config-seed`) must match exactly or
the build still fails with `cannot be found`.

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
       address: <this host's tunnel address, e.g. 10.100.0.2/24>
       peer-public-key: <peer's WireGuard public key>
       peer-endpoint: <peer host:port, e.g. vpn.example.net:51820>
       peer-allowed-ips: <peer's subnet, e.g. 10.100.0.0/24>
       listen-port: <this host's WireGuard listen port, e.g. 51820>
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
