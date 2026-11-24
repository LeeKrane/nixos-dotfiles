# secrets/

This directory holds one [sops](https://github.com/getsops/sops)-encrypted
`<hostname>.yaml` per host, plus this file and `.gitkeep`. For a new host,
create its `*.yaml` file locally, encrypt it with sops, then `git add` and
commit it on every host and clone that needs it.

Commit it. Flakes only see git-tracked or staged files, so an untracked
`secrets/<host>.yaml` evaluates as absent: `sops.secrets`, the wg0 tunnel and
the Proton Drive rclone seed all silently stay off, no error. `.gitignore`
only ignores `secrets/*.key`: commit a `.yaml` file like any other tracked
file. Its contents stay sops-encrypted the whole time.

Each host decrypts with an age identity derived from its own SSH host key
(`modules/nixos/common/sops.nix`, `sops.age.sshKeyPaths`), so a compromised host's
key exposes only that host's file, not every secret ever created.

## Files

`<hostname>.yaml` (`tariognatha.yaml`, `tarmantria.yaml`, `taractias.yaml`,
`taragarmr.yaml`, `taronychus.yaml`, `tarritator.yaml`, `tarronax.yaml`)
holds per-host secrets. There is no shared secrets file. Each desktop's
`.yaml` is decryptable by two recipients only, both listed in that host's
own `creation_rules` entry in `.sops.yaml` and no other host's — that
host's personal admin age key, which lives in `~/.config/sops/age/keys.txt`
on that host and nowhere else, and that host's own SSH-host-derived age
key. Each server's file has three recipients: its own host key plus the
tariognatha and tarmantria admin keys, since servers are administered from
those two desktops. `tariognatha-vm` is the one exception, sharing
`tariognatha`'s secrets file rather than having its own.

One consequence: a desktop's `secrets/<host>.yaml` can only be edited on that
desktop itself, either as the admin user with the personal key above, or as root
there with `SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/ssh/ssh_host_ed25519_key`.
No desktop, and no single key, can decrypt or edit another desktop's file. A
server's file can be edited on tariognatha or tarmantria.

The modules below read:

| Key | Read by | Owner:mode |
| --- | --- | --- |
| `wireguard/wg0-private-key` | `modules/nixos/desktop/networking.nix`'s `wg0.conf` template (`PrivateKey`) | `root:0400` |
| `wireguard/address` | same template (`Address`) | `root:0400` |
| `wireguard/peer-public-key` | same template (`PublicKey`) | `root:0400` |
| `wireguard/peer-endpoint` | same template (`Endpoint`) | `root:0400` |
| `wireguard/peer-allowed-ips` | same template (`AllowedIPs`) | `root:0400` |
| `wireguard/listen-port` | same template (`ListenPort`) | `root:0400` |
| `rclone/config-seed` | `modules/home/desktop/proton-drive.nix` (seeds `~/.config/rclone/rclone.conf` if absent) | `krane:0400` |
| `ani-cli/curl-auth` | `modules/home/desktop/ani-cli.nix` (curl config `user = "ani-cli:<password>"` for the history sync) | `krane:0400` |
| `server-upgrade/github-token` | `modules/nixos/server/auto-upgrade.nix` (fine-grained PAT, repository `LeeKrane/nixos-dotfiles` only, Issues: read and write; the four server files) | `root:0400` |
| `ntfy/publish-token` | same module (token of ntfy user `upgrade-publisher`, write-only on `server-upgrades`; the four server files) | `root:0400` |
| `ntfy/server-env` | `hosts/taragarmr/ntfy.nix` (`NTFY_AUTH_USERS`, `NTFY_AUTH_ACCESS`, `NTFY_AUTH_TOKENS` for ntfy; taragarmr only) | `root:0400` |
| `ntfy/read-token` | `modules/nixos/desktop/server-upgrade-notify.nix` (token of ntfy user `krane`, read-only; the three desktop files) | `krane:0400` |

On the three desktops, all six wireguard values live encrypted in `secrets/<host>.yaml`; none of
them, including the address and peer identity, are cleartext anywhere in
this repo. `modules/nixos/desktop/networking.nix` renders them into a `wg0.conf` template
(fixed `PersistentKeepalive 25`) and points `networking.wg-quick.interfaces.wg0.configFile`
at it. Servers differ: `modules/nixos/server/wireguard.nix` builds their tunnels from the peer
table in `lib/wireguard.nix` and reads only `wireguard/wg0-private-key` (plus
`wireguard/wg1-private-key` on the hub, taragarmr) from their file. The secret alone does not bring up WireGuard on a new host: add all six
keys with `sops set`, for example:

```sh
sops set secrets/<hostname>.yaml '["wireguard"]["wg0-private-key"]' '"<real private key>"'
sops set secrets/<hostname>.yaml '["wireguard"]["address"]' '"<this host tunnel address>/24"'
sops set secrets/<hostname>.yaml '["wireguard"]["peer-public-key"]' '"<peer public key>"'
sops set secrets/<hostname>.yaml '["wireguard"]["peer-endpoint"]' '"<peer host>:51820"'
sops set secrets/<hostname>.yaml '["wireguard"]["peer-allowed-ips"]' '"<peer subnet>/24"'
sops set secrets/<hostname>.yaml '["wireguard"]["listen-port"]' '"51820"'
```

Both sections are optional per host: `modules/nixos/desktop/networking.nix` (wireguard) and
`modules/nixos/common/sops.nix` (rclone) only declare a `sops.secrets` entry for a section that's actually present in
`secrets/<host>.yaml`. To disable WireGuard or the Proton Drive seed on a
host, delete that whole top-level section (`wireguard:` or `rclone:`) with
`sops secrets/<host>.yaml`. Leaving the value empty is not enough: sops
encrypts values but not key names, so Nix can read which top-level sections
exist at eval time, but it cannot read an encrypted value to tell whether
it's empty. The gate checks only the top-level section name; the leaf key
names listed above (`wg0-private-key`, `config-seed`) must match exactly or
the build still fails with `cannot be found`.

## Servers (taragarmr, taronychus, tarritator, tarronax)

Servers do not use `scripts/bootstrap-sops.sh`. Their SSH host keys are generated ahead of
install, stored encrypted in the password manager, and their age recipients are already
the `&host_<name>` entries in `.sops.yaml`. taragarmr gets the key through
`nixos-anywhere --extra-files <dir>` after restoring it to `<dir>/etc/ssh/`; the image hosts
(taronychus, tarronax, tarritator) get `ssh_host_ed25519_key` (root:root 0600) and `.pub` (0644) copied
into `/etc/ssh` on the flashed root partition before first boot. sshd only generates a host
key when the file is missing, so a pre-placed key is kept. The login password is NOT in sops
(not even as a hash): it is set on site at install, see the host header comments.

### Server upgrade secrets

The automatic upgrades (`modules/nixos/server/auto-upgrade.nix`) need four secrets. Each is
declared only when its top-level section (`server-upgrade:` or `ntfy:`) exists in the host's
file, and sops-nix then requires every leaf key the module declares, so add all of a host's
keys before the code that declares them is built.

| Host file | Keys to have |
| --- | --- |
| `taragarmr` | `server-upgrade/github-token`, `ntfy/publish-token`, `ntfy/server-env` |
| `taronychus`, `tarritator`, `tarronax` | `server-upgrade/github-token`, `ntfy/publish-token` |
| `tariognatha`, `tarmantria`, `taractias` | `ntfy/read-token` |

`server-upgrade/github-token` is a fine-grained personal access token limited to the repository
`LeeKrane/nixos-dotfiles` with Issues: read and write. It is already in the four server files.
To replace a lost or leaked one, create a new token and run, on tariognatha or tarmantria,
from the repo root, in bash (the login shell is fish, which cannot run the `for` loop, so
start `bash` first and `exit` it afterwards):

```sh
for h in taragarmr taronychus tarritator tarronax; do
  sops set secrets/$h.yaml '["server-upgrade"]["github-token"]' '"<new token>"'
done
```

The three `ntfy/*` values are created together. On tariognatha or tarmantria (the admin keys
there can edit every server file), from the repo root, open a bash shell with the tools (the
login shell is fish, so bash is named explicitly):

```sh
nix shell nixpkgs#ntfy-sh nixpkgs#jq nixpkgs#sops --command bash
```

Inside it, paste the next block. It generates the two tokens and the two password hashes. `ntfy user hash` asks for a
password and prints a bcrypt hash. For `upgrade-publisher` type any random string and forget
it, since only its token is used. For `krane` type a password you keep in the password manager,
because the phone's ntfy app logs in as `krane` with it.

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

Copy the printed read token, then `exit` the nix shell so the variables are gone. A desktop's
file can only be edited on that desktop (see "Files"), so run this once on each of tariognatha,
tarmantria and taractias:

```sh
sops set secrets/$(hostname).yaml '["ntfy"]["read-token"]' '"<the read token>"'
```

Commit the changed files on each machine. The commits are made on four machines (one for the
servers, one per desktop), so push each one and pull or rebase on the next machine before
committing there, and make sure all of them are merged before step 2 of the rollout. Nothing
above writes a secret in clear text to the repo.

The `server-upgrade` GitHub label is not created by `scripts/server-upgrade-report.sh`; create
it once (the command is idempotent):

```sh
gh label create server-upgrade --repo LeeKrane/nixos-dotfiles --color D93F0B --description "Failed automatic server upgrade" --force
```

### Rollout checklist

Do these in order, by hand.

1. Add the secrets above to all seven files and commit them.
2. Merge to `main`. `.github/workflows/promote.yml` runs after `check` passes on `main` and
   creates or moves the `deploy` branch. Confirm: `git ls-remote origin refs/heads/deploy`
   shows the `main` head SHA. Servers cannot upgrade until it exists.
3. Switch each machine once, since auto-upgrade is not running yet. The servers have no
   `just`, so deploy all four from tariognatha or tarmantria (the Pi closures are aarch64 and
   only those two have binfmt emulation), from the repo root:
   `nixos-rebuild switch --flake .#<host> --target-host krane@<host> --sudo --ask-sudo-password`
   with `<host>` one of `taragarmr`, `taronychus`, `tarritator`, `tarronax`. Then
   `just switch <desktop>` on each of tariognatha, tarmantria and taractias for the
   notification subscriber. Check
   `systemctl list-timers nixos-upgrade.timer` on each server and `systemctl status ntfy-sh`
   on taragarmr.
4. Subscribe the phone's ntfy app to topic `server-upgrades` on `http://192.168.82.1:2586`
   (WireGuard must be on), logging in as `krane` with its password, with instant delivery
   enabled. On a server, run `curl -H "Authorization: Bearer $(sudo cat /run/secrets/ntfy/publish-token)" -d test
   http://192.168.82.1:2586/server-upgrades`: it must reach the phone and the desktops. On a
   desktop, the same request with `$(command cat /run/secrets/ntfy/read-token)` as the token
   must be refused (HTTP 403).
5. Failure drill on tarronax. Temporarily set `krane.autoUpgrade.healthChecks = [ "false" ];`
   in `hosts/tarronax/default.nix`, merge to `main`, wait for `deploy` to move, then run
   `sudo systemctl start nixos-upgrade` on tarronax. Expect a rollback to the previous
   generation, one ntfy push and exactly one GitHub issue with a `failed` comment. Revert the
   line, merge, wait for `deploy` to move again (started earlier, the upgrade skips the still
   failed SHA silently), then start the service again: expect a recovery push, a `recovered` comment and
   the issue closing.
6. Optional kernel drill: the first upgrade that changes a Pi's kernel waits for its reboot
   window and reboots once. Then `journalctl -u server-upgrade-health -b` on that host shows
   the boot-time health check passing.

## How to create one

For a desktop host, each of its recipients in `.sops.yaml` starts as an
`age1PLACEHOLDER_...` value that decrypts nothing, until step 1 below runs (the
install script adds those placeholders when it scaffolds a new host). The seven
existing hosts are already bootstrapped.

1. Run `scripts/bootstrap-sops.sh <hostname>` on the target host, after it
   has booted at least once. It needs `/etc/ssh/ssh_host_ed25519_key.pub`,
   which `sshd-keygen` creates at first boot. The script derives the host's
   age recipient with `ssh-to-age`, generates a personal admin age key for
   this host with `age-keygen` if needed, and patches both into
   `.sops.yaml` in place of that host's placeholders only. It never writes
   a secret value.

   The personal key lands at `~/.config/sops/age/keys.txt`
   (`$SOPS_AGE_KEY_FILE` if set) on this host, and only this host — it's
   listed in this host's `creation_rules` entry in `.sops.yaml` and no
   other's. Back it up: lose it and this host's file can still be read as
   root there via its SSH host key, but no admin-user edit is possible
   until a replacement key is generated and re-keyed in (see "Rotating or
   re-keying" below).
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
       listen-port: "<this host's WireGuard listen port, e.g. 51820, quoted so YAML keeps it a string>"
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

## Rotating or re-keying

After changing a host's recipients in `.sops.yaml` — rotating its personal
admin key, for instance — the secrets file itself is still encrypted
against the old recipient set. Run `sops updatekeys secrets/<host>.yaml`
on that host to re-encrypt it for the current recipients; do this before
relying on the new key to decrypt anything.

At that point only the old recipient or the SSH host key can still decrypt
the file, so run `updatekeys` on that host as root, via its SSH host key:

```sh
sudo env SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/ssh/ssh_host_ed25519_key sops updatekeys secrets/<host>.yaml
```

Commit the re-encrypted file afterward.

## Never

- Never type a real secret value into `.sops.yaml`, a Nix file, a commit
  message, or anywhere outside a `sops`-encrypted `secrets/*.yaml`.
- Never hand-edit the `age1...` recipients in `.sops.yaml`. Let
  `scripts/bootstrap-sops.sh` do it, so the real value only ever exists on
  the machine that generated it plus whatever you copied it to yourself.
