# ii settings: boot-path fixes design

Companion fix spec to [2026-09-27-ii-settings-design.md](2026-09-27-ii-settings-design.md).
Covers the pre-merge issues raised against the boot/activation path in
[2026-10-02-ii-settings-premerge.md](../handoffs/2026-10-02-ii-settings-premerge.md)
(D1, M1, M2, and the subprocess-timeout gap).

## Problem

`krane-ii-settings activate` re-renders `~/.config/hypr/custom/krane_gui.lua`
and `hypridle.conf` from the repo file at every home-manager activation, so a
GUI change made since the last `nixos-rebuild switch` survives a reboot
(`pkgs/krane-ii-settings/krane_ii_settings.py:809-839`, wired in
`modules/home/desktop/ii-settings.nix:241-243`). That activation entry still ends in
`|| true`, written on the assumption that `activate()` itself never raises.

**D1**: `activate()` enters `with locked():` before any `try`
(`krane_ii_settings.py:809-818`). `locked()` opens
`<XDG_RUNTIME_DIR>/krane-ii-settings.lock`
(`krane_ii_settings.py:327-330`), and `runtime_dir()` falls back to
`/run/user/<uid>` when `$XDG_RUNTIME_DIR` is unset
(`krane_ii_settings.py:301-302`) but never checks that the directory exists.
Before the user's systemd instance has created that directory, `open(...,
"w")` raises `FileNotFoundError`. That happens outside both of `activate()`'s
`except SettingsError` / `except (OSError, subprocess.CalledProcessError)`
blocks, so the exception propagates out of `activate()` and out of `main()`
uncaught. The shell's `|| true` turns that crash into a silent no-op: the
build-time render stays in place, any GUI change made since the last switch
is lost at reboot, and the boot-check dialog (`krane.hypr.execOnce`) ends up
asking the user to keep or revert display settings that were never actually
re-applied live.

A second, related ordering gap: `modules/home/desktop/illogical-impulse.nix:176`
defines `kraneIiHyprReload = lib.hm.dag.entryAfter [ "kraneIiOverrides"
"kraneIiPatches" ]`, without `kraneIiActivate`. Nothing orders the Hyprland
config reload after the GUI re-render, so a reload triggered by that step can
race `kraneIiActivate`'s write of `krane_gui.lua`.

**M1**: `render()` only emits the `KRANE_GUI_MONITORS = {}` Lua table inside
`if monitors:` (`krane_ii_settings.py:252-260`). When the repo file has no
`monitors` key at all (a fresh host, or after `revert-unconfirmed` deletes
the last entry), the table is never emitted, so any Lua that reads the
global (`krane_after_gui()`'s hotplug merge, used e.g. by
`hosts/tarmantria/display.nix`'s `scale_internal`) sees it undefined instead
of empty.

**M2**: `boot_check()` waits for the lock-on-start session lock only through
ii's own IPC (`runtime.lock_state()`, which calls `qs ... ipc call lock
isLocked`, `krane_ii_settings.py:457-463`). If ii's Quickshell instance never
comes up, lock-on-start falls back to plain `hyprlock`, and `lock_state()`
returns `None` forever; the deadline loop
(`krane_ii_settings.py:793-796`) times out after `wait_seconds` and the
second loop (`while lock_state() == "true"`) exits immediately since `None
!= "true"`, so `boot_check()` opens the settings dialog while the fallback
`hyprlock` may still be covering the screen.

**Subprocess timeouts**: every `subprocess.run` in `Runtime` (hyprctl,
`systemctl`, `systemd-run`, `pkill`, the idle configurator, the lock IPC
query) has no `timeout=`. A hung `hyprctl` or `qs ipc call` blocks
`activate()`, `boot_check()`, or any GUI-triggered `set`/`try`/`confirm`
indefinitely.

## Goals

- `activate()` never raises before login; a missing runtime directory is a
  normal, logged case, not a crash hidden by `|| true`.
- `krane_gui.lua`'s re-render is ordered before the Hyprland config reload
  that follows it in activation.
- `KRANE_GUI_MONITORS` is always defined once `render()` has run.
- `boot_check()` does not open the settings dialog while a fallback
  `hyprlock` is still locking the screen.
- Every subprocess call has a bounded timeout, and a timeout is reported as
  a `SettingsError` (nothing applied), not an unhandled exception.

## Non-goals

- No change to the GUI write paths (`set`/`try`/`confirm`) beyond the
  timeout addition — those are Spec 2's scope
  ([2026-10-02-ii-settings-gui-write-paths-design.md](2026-10-02-ii-settings-gui-write-paths-design.md)).
- No change to input validation or approval gating — Spec 3's scope
  ([2026-10-02-ii-settings-input-hardening-design.md](2026-10-02-ii-settings-input-hardening-design.md)).
- Not redesigning the confirm-or-revert state machine itself.

## Design

### `locked()` falls back to a repo-relative lock file

```python
def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


@contextlib.contextmanager
def locked(manifest=None):
    rt = runtime_dir()
    if os.path.isdir(rt):
        path = os.path.join(rt, "krane-ii-settings.lock")
    else:
        path = os.path.join(os.path.dirname(manifest["repoFile"]), ".ii-settings.lock")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield
```

`locked()` gains an optional `manifest` argument (all current call sites
already have one in scope) so the fallback path can be derived from
`manifest["repoFile"]`'s directory, i.e. `hosts/<host>/.ii-settings.lock` in
the repo checkout — not `/tmp`, so two writers on different checkouts of the
same host never collide, and the path is stable across reboots.

Rationale for falling back to a lock file instead of skipping the lock
outright: before login, `activate()` is the only writer running (the GUI and
its `set`/`try`/`confirm` paths need a running Hyprland + ii session, which
implies the user is already logged in), so there is no real contention to
guard against yet — but skipping the lock entirely would leave a race the
moment a session starts concurrently with a second `activate()` (e.g. a
manual `home-manager switch` run right after boot). A real lock file, held
only as long as `activate()` needs it, costs nothing and removes that race.

`hosts/<host>/.ii-settings.lock` is git-ignored per host
(`hosts/{tariognatha,tarmantria,taractias}/illogical-impulse/.gitignore` and
`templates/host/illogical-impulse/.gitignore` each gain a `.ii-settings.lock`
line) so a stale lock file from a test run is never committed.

Rejected alternative: skip the lock when the runtime directory does not
exist. Simpler, but leaves exactly the race described above once a session
starts; the repo-relative lock file removes it at negligible cost.

### `kraneIiHyprReload` ordered after `kraneIiActivate`

`modules/home/desktop/illogical-impulse.nix:176`:

```nix
kraneIiHyprReload = lib.hm.dag.entryAfter [ "kraneIiOverrides" "kraneIiPatches" "kraneIiActivate" ];
```

`kraneIiActivate` is defined with `lib.hm.dag.entryAfter` (not wrapped in
`lib.mkIf`), so it always exists in the activation DAG and this reference is
always valid.

### `render()` always emits `KRANE_GUI_MONITORS`

`krane_ii_settings.py:251-260`, unconditionally:

```python
out.append("\nKRANE_GUI_MONITORS = {}\n\n")
baselines = manifest.get("monitorBaselines", {})
for output in sorted(monitors):
    ...
```

moved out of `if monitors:` so the table line is always appended, and the
`for` loop (which already does nothing when `monitors` is empty) fills it in
when there is something to render.

### `boot_check()` also waits for the `hyprlock` fallback

`krane_ii_settings.py:790-796`, both wait loops gain a second condition:

```python
def _locked(runtime):
    return runtime.lock_state() == "true" or runtime.pidof_hyprlock()
```

`Runtime.pidof_hyprlock()` runs `pidof hyprlock` (reusing the existing
`PKILL`-style constant pattern, a new `PIDOF` constant substituted by
`default.nix`) and returns whether it exited 0. `boot_check()` waits for
`_locked(self.runtime)` to become true (bounded by `wait_seconds`, as today),
then waits for it to become false, before writing the pending file and
opening the settings dialog. This covers both lock paths without needing to
know which one is active.

### Subprocess timeouts

Every `subprocess.run` call in `Runtime` and in `start_revert_timer` gains a
`timeout=`: 10 seconds for `hyprctl`, `systemctl`, `systemd-run`, `pkill`,
and the idle configurator subprocess; 5 seconds for the `qs ipc call lock
isLocked` query in `lock_state()`. `hyprctl()`
(`krane_ii_settings.py:348-356`) and `lock_state()` already treat a
non-zero exit or unreadable output as "no instance answered" / "not up
yet"; a `subprocess.TimeoutExpired` there is caught and folded into that
same "unreadable" return value, so a hung Hyprland instance behaves like one
that is not running yet.

For the write paths (`start_revert_timer`, `write_idle_conf`,
`apply_idle`'s `pkill`), a `subprocess.TimeoutExpired` is instead translated
into `SettingsError` and re-raised: nothing has been written to the repo
file yet at that point in every caller (`try_monitor`, `boot_check`), so
"nothing applied" is accurate.

## Error handling

- `activate()`: unchanged behaviour for `SettingsError` and `(OSError,
  subprocess.CalledProcessError)` — both are already caught and logged as
  "activation skipped". The fix is that `locked()` no longer raises
  `FileNotFoundError` in the one case that used to escape both blocks.
- `boot_check()`: a `TimeoutExpired` from the new `pidof_hyprlock()` call is
  treated the same as `pidof` reporting "not running" (empty/non-zero
  exit), since a hung `pidof` is not evidence either way and the existing
  `wait_seconds` deadline already bounds the whole wait.
- Timeout → `SettingsError` on write paths is surfaced to the GUI exactly
  like today's other refusals (shown in the AI/settings error banner via
  `get()`'s existing `error` field, or the command's non-zero exit for a
  direct CLI call).

## Testing

- `locked()`: a test with `XDG_RUNTIME_DIR` pointed at a path that does not
  exist asserts `activate()` still returns `"activated"` (or `"activation
  skipped"` for a broken repo file) with exit code 0, and that the lock file
  ends up at `<repoFile dir>/.ii-settings.lock`.
- `render()`: a test with an empty repo file (`{}`, no `monitors` key)
  asserts the rendered text still contains `KRANE_GUI_MONITORS = {}`.
- `boot_check()`: a `FakeRuntime` test where `lock_state()` always returns
  `None` but a fake `pidof_hyprlock()` returns `True` then `False` asserts
  `boot_check()` waits for the second transition before opening settings.
- A `FakeRuntime`/subprocess test asserting `hyprctl()` returns `None` (not
  an exception) on `subprocess.TimeoutExpired`.

## Docs

`docs/VERIFY.md`'s "Settings window (after two consecutive switches)"
section gains a row: reboot without an intervening switch, then confirm the
live `krane_gui.lua` matches a `set`/`reset` made before that reboot (the
reboot-without-switch check this spec exists to make pass).
`docs/II-INTEGRATION.md`'s "Settings persistence" section already describes
`activate`; it gains one sentence noting the pre-login lock fallback.

## Commits

One dotfiles commit: `pkgs/krane-ii-settings/krane_ii_settings.py` and its
tests, `pkgs/krane-ii-settings/default.nix` (new `PIDOF` substitution),
`modules/home/desktop/illogical-impulse.nix` (the `entryAfter` addition),
`hosts/{tariognatha,tarmantria,taractias}/illogical-impulse/.gitignore` and
`templates/host/illogical-impulse/.gitignore` (the new ignore line),
`docs/VERIFY.md`, `docs/II-INTEGRATION.md`. No clone-side change — this
spec is entirely inside `pkgs/krane-ii-settings` and the Nix modules.
