# secrets/

One [sops](https://github.com/getsops/sops)-encrypted `<hostname>.yaml` per host. There is no shared secrets file. `tariognatha-vm` shares `tariognatha.yaml` (`lib/host-secrets.nix` keys on `hostName`).

Commit each file. Flakes only see git-tracked or staged files, so an untracked `secrets/<host>.yaml` evaluates as absent: `sops.secrets`, the wg0 tunnel and the Proton Drive seed stay off with no error. Only `secrets/*.key` is gitignored.

Each host decrypts with an age identity derived from its SSH host key (`modules/nixos/common/sops.nix`, `sops.age.sshKeyPaths`), so a compromised host exposes only its own file.

## Files

Recipients are per `creation_rules` entry in `.sops.yaml`:

- Desktop (`tariognatha`, `tarmantria`, `taractias`): that host's personal admin age key (`~/.config/sops/age/keys.txt`, on that host only) and its SSH-host-derived key. A desktop's file can only be edited on that desktop: as the admin user, or as root with `SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/ssh/ssh_host_ed25519_key`. No key decrypts another desktop's file.
- Server (`taragarmr`, `taronychus`, `tarritator`, `tarronax`): its host key plus the tariognatha and tarmantria admin keys, so servers are edited from those two desktops.

Keys read by modules:

| Key | Read by | Owner:mode |
| --- | --- | --- |
| `wireguard/{wg0-private-key,address,peer-public-key,peer-endpoint,peer-allowed-ips,listen-port}` | desktops: `modules/nixos/desktop/networking.nix` renders them into a `wg0.conf` template | `root:0400` |
| `wireguard/wg0-private-key`, plus `wireguard/wg1-private-key` on the hub taragarmr | servers: `modules/nixos/server/wireguard.nix`; peers come from `lib/wireguard.nix` | `root:0400` |
| `rclone/config-seed` | `modules/home/desktop/proton-drive.nix` (seeds `~/.config/rclone/rclone.conf` if absent) | `krane:0400` |
| `ani-cli/curl-auth` | `modules/home/desktop/ani-cli.nix` (curl auth for the history sync) | `krane:0400` |
| `server-upgrade/github-token` | `modules/nixos/server/auto-upgrade.nix`; the four server files | `root:0400` |
| `ntfy/publish-token` | same module; the four server files | `root:0400` |
| `ntfy/server-env` | `hosts/taragarmr/ntfy.nix`; taragarmr only | `root:0400` |
| `ntfy/read-token` | `modules/nixos/desktop/server-upgrade-notify.nix`; the three desktop files | `krane:0400` |
| `couchdb/env` | `hosts/taragarmr/couchdb.nix`; taragarmr only | `root:0400` |
| `restic/repo-password` | `hosts/taragarmr/backup.nix`; taragarmr only | `root:0400` |

### Per-section gating

Modules declare a `sops.secrets` entry only when the host's file has that top-level section (`hasSection` in `lib/host-secrets.nix`). sops-nix then requires every leaf key the module declares: a missing leaf fails the build with `cannot be found`, so add all of a section's keys before building the code that declares them.

To turn a feature off on a host (`wireguard:`, `rclone:`, `ntfy:`, ...), delete the whole top-level section with `sops secrets/<host>.yaml`. An empty value is not enough: sops encrypts values but not key names, so Nix can read section names at eval time but not whether a value is empty.

## How to create one

A desktop's recipients in `.sops.yaml` start as `age1PLACEHOLDER_...` values (`install.sh` adds them when it scaffolds a host) that decrypt nothing until step 1. The seven existing hosts are already bootstrapped.

1. Run `scripts/bootstrap-sops.sh <hostname>` on the target host after its first boot, as the admin user, not root (it needs `/etc/ssh/ssh_host_ed25519_key.pub`). It derives the host's age recipient with `ssh-to-age`, generates a personal admin key at `~/.config/sops/age/keys.txt` (`$SOPS_AGE_KEY_FILE` if set) if needed, and patches both into that host's placeholders in `.sops.yaml`. It never writes a secret value. Back the personal key up: without it only root on that host can edit the file, via the SSH host key, until a replacement key is re-keyed in.
2. `git add .sops.yaml && git commit`.
3. `sops secrets/<hostname>.yaml` opens `$EDITOR` on a decrypted buffer and encrypts on save. Skeleton:

   ```yaml
   wireguard:
       wg0-private-key: <real WireGuard private key>
       address: <this host's tunnel address, e.g. 10.100.0.2/24>
       peer-public-key: <peer's public key>
       peer-endpoint: <peer host:port>
       peer-allowed-ips: <peer subnet, e.g. 10.100.0.0/24>
       listen-port: "<e.g. 51820, quoted so YAML keeps a string>"
   rclone:
       config-seed: |
           [ProtonDrive]
           type = protondrive
           username = <Proton account email>
           # rest of a working [ProtonDrive] stanza, copied into rclone.conf on first activation
   ```

   Single values can be set without the editor: `sops set secrets/<host>.yaml '["wireguard"]["listen-port"]' '"51820"'`.
4. `git add secrets/<hostname>.yaml && git commit` (see the top of this file for why).
5. `just switch` on the host (or `sudo nixos-rebuild switch --flake .#<hostname>`). Secrets decrypt to `/run/secrets/...` at activation.

## Servers

Servers do not use `scripts/bootstrap-sops.sh`. Their SSH host keys are generated ahead of install and kept in the password manager; their age recipients are already the `&host_<name>` entries in `.sops.yaml`. taragarmr gets its key through `nixos-anywhere --extra-files <dir>` (key under `<dir>/etc/ssh/`). The image hosts (taronychus, tarronax, tarritator) get `ssh_host_ed25519_key` (root:root 0600) and `.pub` (0644) copied into `/etc/ssh` on the flashed root partition before first boot. sshd only generates a host key when the file is missing, so the pre-placed key is kept. The login password is not in sops; it is set on site at install (see each host's header comment).

### Server upgrade secrets

`modules/nixos/server/auto-upgrade.nix` needs `server-upgrade/github-token` and `ntfy/publish-token` in every server file, plus `ntfy/server-env` on taragarmr; the desktops need `ntfy/read-token`.

`server-upgrade/github-token` is a fine-grained PAT limited to `LeeKrane/nixos-dotfiles` with Issues: read and write. To replace a lost or leaked one, run from the repo root on tariognatha or tarmantria, in bash (the login shell is fish, which cannot run the `for` loop):

```sh
for h in taragarmr taronychus tarritator tarronax; do
  sops set secrets/$h.yaml '["server-upgrade"]["github-token"]' '"<new token>"'
done
```

The three `ntfy/*` values are created together. On tariognatha or tarmantria, open `nix shell nixpkgs#ntfy-sh nixpkgs#jq nixpkgs#sops --command bash` and run the block below. `ntfy user hash` prompts for a password and prints a bcrypt hash. For `upgrade-publisher` type a random string and forget it (only its token is used). For `krane` type a password you keep in the password manager: the phone's ntfy app logs in with it.

```sh
PUB=$(ntfy token generate)
READ=$(ntfy token generate)
echo "upgrade-publisher password (random, forget it):"; PUB_HASH=$(ntfy user hash)
echo "krane password (keep it, the phone uses it):"; KRANE_HASH=$(ntfy user hash)
ENVFILE=$(printf "NTFY_AUTH_USERS='upgrade-publisher:%s:user,krane:%s:user'\nNTFY_AUTH_ACCESS='upgrade-publisher:server-upgrades:write-only,krane:server-upgrades:read-only'\nNTFY_AUTH_TOKENS='upgrade-publisher:%s:publisher,krane:%s:reader'\n" "$PUB_HASH" "$KRANE_HASH" "$PUB" "$READ")

sops set secrets/taragarmr.yaml '["ntfy"]["server-env"]' "$(jq -Rs . <<<"$ENVFILE")"
for h in taragarmr taronychus tarritator tarronax; do
  sops set secrets/$h.yaml '["ntfy"]["publish-token"]' "\"$PUB\""
done
echo "$READ"
```

Copy the printed read token and `exit` the shell so the variables are gone. Then on each of tariognatha, tarmantria and taractias (a desktop file is only editable there):

```sh
sops set secrets/$(hostname).yaml '["ntfy"]["read-token"]' '"<read token>"'
```

Commit on each machine, and pull or rebase before committing on the next.

To subscribe a phone (also needed when it is replaced), point the ntfy app at topic `server-upgrades` on `http://192.168.82.1:2586` (taragarmr's WireGuard address, `lib/ntfy.nix`; WireGuard must be on), log in as `krane` with the password kept above, and enable instant delivery. Check: on a server, `curl -H "Authorization: Bearer $(sudo cat /run/secrets/ntfy/publish-token)" -d test http://192.168.82.1:2586/server-upgrades` reaches the phone and the desktops; the same request on a desktop with `$(command cat /run/secrets/ntfy/read-token)` must be refused with HTTP 403.

The `server-upgrade` GitHub label is not created by `scripts/server-upgrade-report.sh`; create it once:

```sh
gh label create server-upgrade --repo LeeKrane/nixos-dotfiles --color D93F0B --description "Failed automatic server upgrade" --force
```

## Rotating or re-keying

After changing a host's recipients in `.sops.yaml`, the file is still encrypted for the old set. Run `sops updatekeys secrets/<host>.yaml` on that host before relying on the new key. If the old admin key is gone, only the SSH host key can still decrypt, so run it as root:

```sh
sudo env SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/ssh/ssh_host_ed25519_key sops updatekeys secrets/<host>.yaml
```

To change a desktop's admin recipient, move the old `keys.txt` aside, put that host's `age1PLACEHOLDER_ADMIN_<HOST>_REPLACE_VIA_BOOTSTRAP_SOPS_SH` line back in `.sops.yaml` in place of the old recipient, re-run `scripts/bootstrap-sops.sh <host>`, then run `updatekeys` as root as above.

Commit the re-encrypted file.

## Never

- Never put a real secret value in `.sops.yaml`, a Nix file or a commit message: the repo history is permanent. Only `sops`-encrypted `secrets/*.yaml` may hold values.
- Never hand-edit a desktop's `age1...` recipients in `.sops.yaml`: a typo plus `updatekeys` locks the host out of its file. `scripts/bootstrap-sops.sh` writes them.
