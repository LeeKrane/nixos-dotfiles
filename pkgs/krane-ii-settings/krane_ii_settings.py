"""krane-ii-settings: persist ii settings GUI changes in the dotfiles repo.

hosts/<host>/ii-settings.json holds sparse deltas that the GUI owns. `render`
turns it into ~/.config/hypr/custom/krane_gui.lua; `set` and `reset` write the
repo file, re-render the live file and reload Hyprland. The manifest from
modules/home/desktop/ii-settings.nix names the keys Nix owns and carries the
monitor and idle baselines. See docs/II-INTEGRATION.md, "Settings persistence".
"""

import argparse
import contextlib
import copy
import fcntl
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time

HYPRCTL = "@hyprctl@"
SYSTEMD_RUN = "@systemdRun@"
SYSTEMCTL = "@systemctl@"
PKILL = "@pkill@"
PIDOF = "@pidof@"
SETSID = "@setsid@"
HYPRIDLE = "@hypridle@"
SCHEMA_FILE = "@schema@"

REVERT_UNIT = "krane-ii-settings-revert"
REVERT_SECONDS = 15
TOP_LEVEL = ("animationPreset", "hyprland", "idle", "monitors")
OUTPUT_RE = re.compile(r"^[A-Za-z0-9-]+$")
LUA_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

HEADER = (
    "-- GENERATED FILE -- DO NOT EDIT.\n"
    "-- Rendered by krane-ii-settings from hosts/<host>/ii-settings.json.\n"
    "-- Installed as ~/.config/hypr/custom/krane_gui.lua at switch time and\n"
    "-- rewritten live by the ii settings GUI. Loaded from monitors.lua.\n"
)

MONITOR_ORDER = (
    "output", "mode", "position", "scale", "transform", "vrr", "mirror",
    "bitdepth", "disabled", "cm", "sdrbrightness", "sdrsaturation",
    "sdr_min_luminance", "sdr_max_luminance", "min_luminance",
    "max_luminance", "max_avg_luminance",
)


class SettingsError(Exception):
    """A refusal shown to the user. Exit status 1."""


# Schema and values


def load_schema(path=None):
    if path is None:
        path = SCHEMA_FILE
        if path.startswith("@"):
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.json")
    with open(path) as f:
        return json.load(f)


def parse_cli(spec, text, what):
    """Turn a command-line string into a typed value for `spec`."""
    kind = spec["type"]
    try:
        if kind == "bool":
            low = text.lower()
            if low in ("true", "1", "yes", "on"):
                return True
            if low in ("false", "0", "no", "off"):
                return False
            raise ValueError(text)
        if kind == "int":
            return int(text)
        if kind == "float":
            number = float(text)
            return int(number) if number.is_integer() and "." not in text else number
        if kind == "enum":
            if all(isinstance(v, int) for v in spec["values"]):
                return int(text)
            return text
        return text
    except ValueError:
        raise SettingsError(f"{what}: {text!r} is not a valid {kind}")


def check_value(spec, value, what):
    """Raise SettingsError unless `value` fits `spec`. Returns the value."""
    kind = spec["type"]
    ok = False
    if kind == "bool":
        ok = isinstance(value, bool)
    elif kind == "int":
        ok = isinstance(value, int) and not isinstance(value, bool)
    elif kind == "float":
        ok = isinstance(value, (int, float)) and not isinstance(value, bool)
    elif kind == "object":
        ok = isinstance(value, dict)
    elif kind == "enum":
        ok = value in spec["values"] and not isinstance(value, bool)
    elif kind == "str":
        ok = isinstance(value, str) and re.fullmatch(spec["pattern"], value) is not None
    if not ok:
        raise SettingsError(f"{what}: {value!r} is not a valid {kind}")
    if kind in ("int", "float"):
        if not math.isfinite(value):
            raise SettingsError(f"{what}: {value!r} is not a finite number")
        if "min" in spec and value < spec["min"]:
            raise SettingsError(f"{what}: {value} is below the minimum {spec['min']}")
        if "max" in spec and value > spec["max"]:
            raise SettingsError(f"{what}: {value} is above the maximum {spec['max']}")
    return value


def validate_data(data, schema):
    """Check a whole ii-settings.json document against the schema."""
    if not isinstance(data, dict):
        raise SettingsError("ii-settings.json: the top level must be a JSON object")
    for key in data:
        if key not in TOP_LEVEL:
            raise SettingsError(f"ii-settings.json: unknown top-level key {key!r}")
    hypr = data.get("hyprland", {})
    if not isinstance(hypr, dict):
        raise SettingsError("hyprland: must be an object")
    for key, value in hypr.items():
        if key not in schema["hyprland"]:
            raise SettingsError(f"hyprland.{key}: unknown key (not in the schema)")
        check_value(schema["hyprland"][key], value, f"hyprland.{key}")
    idle = data.get("idle", {})
    if not isinstance(idle, dict):
        raise SettingsError("idle: must be an object")
    for key, value in idle.items():
        if key not in schema["idle"]:
            raise SettingsError(f"idle.{key}: unknown key")
        check_value(schema["idle"][key], value, f"idle.{key}")
    if "animationPreset" in data:
        check_value(schema["animationPreset"], data["animationPreset"], "animationPreset")
    monitors = data.get("monitors", {})
    if not isinstance(monitors, dict):
        raise SettingsError("monitors: must be an object")
    for output, fields in monitors.items():
        if not OUTPUT_RE.match(output):
            raise SettingsError(f"monitors: {output!r} is not an output name")
        if not isinstance(fields, dict):
            raise SettingsError(f"monitors.{output}: must be an object")
        for field, value in fields.items():
            if field not in schema["monitor"]:
                raise SettingsError(f"monitors.{output}.{field}: unknown field")
            check_value(schema["monitor"][field], value, f"monitors.{output}.{field}")
            if field == "bootPrevious":
                for f, v in value.items():
                    spec = schema["monitor"].get(f)
                    if spec is None or spec.get("internal"):
                        raise SettingsError(f"monitors.{output}.bootPrevious.{f}: unknown field")
                    check_value(spec, v, f"monitors.{output}.bootPrevious.{f}")


def check_ownership(data, manifest):
    """Refuse any key the manifest says Nix owns."""
    owned = manifest["nixOwned"]
    for key in data.get("hyprland", {}):
        if key in owned["hyprland"]:
            raise SettingsError(f"hyprland.{key}: set in Nix ({nix_hint(manifest)})")
    for output, fields in data.get("monitors", {}).items():
        for field in fields:
            if field in owned["monitors"].get(output, []):
                raise SettingsError(f"monitors.{output}.{field}: set in Nix ({nix_hint(manifest)})")


def nix_hint(manifest):
    return f"hosts/{manifest['host']}/display.nix or modules/home"


# Rendering


def lua_str(text):
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return '"' + escaped + '"'


def lua_key(key):
    return key if LUA_IDENT_RE.match(key) else "[" + lua_str(key) + "]"


def lua_value(value, indent):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return lua_str(value)
    if isinstance(value, dict):
        if not value:
            return "{}"
        pad = indent + "    "
        items = [pad + lua_key(k) + " = " + lua_value(value[k], pad) for k in sorted(value)]
        return "{\n" + ",\n".join(items) + "\n" + indent + "}"
    raise SettingsError(f"cannot render {value!r} to Lua")


def nest(flat):
    """{"a:b:c": 1} -> {"a": {"b": {"c": 1}}}"""
    tree = {}
    for key, value in flat.items():
        node = tree
        parts = key.split(":")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    return tree


def monitor_lua(output, rule):
    """Render one hl.monitor rule, also stashed in KRANE_GUI_MONITORS[output]
    so a host's extraMonitorsLua (hosts/<host>/display.nix) can read back
    what the GUI set and merge it into a rule it builds itself."""
    pad = "    "
    items = []
    for field in MONITOR_ORDER:
        if field not in rule or rule[field] is None:
            continue
        if field == "disabled" and rule[field] is not True:
            continue
        items.append(pad + field + " = " + lua_value(rule[field], pad))
    ref = "KRANE_GUI_MONITORS[" + lua_str(output) + "]"
    return (
        ref + " = {\n" + ",\n".join(items) + "\n}\n"
        + "hl.monitor(" + ref + ")\n"
    )


INTERNAL_FIELDS = ("bootConfirmed", "bootPrevious")


def mark_unconfirmed(old, entry):
    """Flag `entry` for a boot check, remembering the entry to restore if it
    is never confirmed: `old` as it was before, or the one it already
    remembered if `old` was itself still unconfirmed."""
    if old and old.get("bootConfirmed") is False:
        prev = old.get("bootPrevious", {})
    else:
        prev = {k: v for k, v in (old or {}).items() if k not in INTERNAL_FIELDS}
    entry["bootConfirmed"] = False
    entry["bootPrevious"] = prev


def render(data, manifest, schema):
    validate_data(data, schema)
    out = [HEADER]
    hypr = data.get("hyprland", {})
    if hypr:
        out.append("\nhl.config(" + lua_value(nest(hypr), "") + ")\n")
    preset = data.get("animationPreset")
    if preset:
        out.append(f'\nrequire("hyprland.animationPresets.{preset}")\n')
    monitors = data.get("monitors", {})
    out.append("\nKRANE_GUI_MONITORS = {}\n\n")
    baselines = manifest.get("monitorBaselines", {})
    for output in sorted(monitors):
        rule = dict(baselines.get(output, {}))
        rule.update({k: v for k, v in monitors[output].items() if k not in INTERNAL_FIELDS})
        rule["output"] = output
        out.append(monitor_lua(output, rule))
    return "".join(out)


# Files


def dump(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def atomic_write(path, text):
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".krane-ii-settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        mode = os.stat(path).st_mode & 0o7777 if os.path.exists(path) else 0o644
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def read_repo(path):
    """Return (data, text). Never creates the file."""
    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        raise SettingsError(f"not persisted: {path} missing")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        raise SettingsError(f"cannot parse {path}: {e}")
    if not isinstance(data, dict):
        raise SettingsError(f"{path}: the top level must be a JSON object")
    return data, text


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def pending_path():
    return os.path.join(runtime_dir(), "krane-ii-settings-pending.json")


def read_pending():
    try:
        with open(pending_path()) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def write_pending(obj):
    atomic_write(pending_path(), json.dumps(obj, sort_keys=True) + "\n")


def clear_pending():
    with contextlib.suppress(FileNotFoundError):
        os.unlink(pending_path())


@contextlib.contextmanager
def locked(manifest):
    rt = runtime_dir()
    if os.path.isdir(rt):
        path = os.path.join(rt, "krane-ii-settings.lock")
    else:
        path = os.path.join(os.path.dirname(manifest["repoFile"]), ".ii-settings.lock")
    with open(path, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def run(cmd, timeout=10, **kwargs):
    """subprocess.run with a bounded wait; a timeout is a SettingsError."""
    try:
        return subprocess.run(cmd, timeout=timeout, **kwargs)
    except subprocess.TimeoutExpired:
        raise SettingsError(f"{os.path.basename(cmd[0])} timed out after {timeout}s")


def hyprland_signatures():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig:
        return [sig]
    base = os.path.join(runtime_dir(), "hypr")
    try:
        names = sorted(os.listdir(base))
    except FileNotFoundError:
        return []
    return [n for n in names if os.path.exists(os.path.join(base, n, ".socket.sock"))]


def hyprctl(args):
    """Run hyprctl against the first instance that answers. None if none does."""
    for sig in hyprland_signatures():
        env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=sig)
        try:
            result = run([HYPRCTL, *args], env=env, capture_output=True, text=True)
        except SettingsError:
            continue
        if result.returncode == 0:
            return result.stdout
    return None


class Runtime:
    def __init__(self, manifest):
        self.manifest = manifest

    def read_live(self):
        try:
            with open(self.manifest["liveFile"]) as f:
                return f.read()
        except FileNotFoundError:
            return None

    def write_live(self, text):
        os.makedirs(os.path.dirname(self.manifest["liveFile"]), exist_ok=True)
        atomic_write(self.manifest["liveFile"], text)

    def reload(self, full=False):
        return hyprctl(["reload"] if full else ["reload", "config-only"]) is not None

    def config_errors(self):
        return hyprctl(["configerrors"]) or ""

    def live_monitor(self, output):
        out = hyprctl(["monitors", "all", "-j"])
        if out is None:
            return None
        for mon in json.loads(out):
            if mon.get("name") == output:
                refresh = round(float(mon["refreshRate"]), 3)
                return {
                    "mode": f"{mon['width']}x{mon['height']}@{refresh:g}",
                    "position": f"{mon['x']}x{mon['y']}",
                    "scale": float(mon["scale"]),
                }
        return None

    def connected_outputs(self):
        """Output names Hyprland currently reports connected, or None if
        hyprctl is unreadable (no instance answers, or its output cannot be
        parsed)."""
        out = hyprctl(["monitors", "all", "-j"])
        if out is None:
            return None
        try:
            return {mon["name"] for mon in json.loads(out)}
        except (ValueError, TypeError, KeyError):
            return None

    def write_idle_conf(self, values):
        """Run the idle configurator against hypridleFile. Returns True if
        its content changed. Never restarts hypridle or touches Hyprland:
        callers that need the live timers to pick up the change call
        apply_idle instead."""
        conf = self.manifest["hypridleFile"]
        script = self.manifest["idleConfigurator"]
        if not (os.path.isfile(conf) and os.path.isfile(script)):
            return False
        try:
            with open(conf) as f:
                before = f.read()
        except FileNotFoundError:
            before = None
        run(
            [sys.executable, script, "--file", conf,
             "--lock", str(values["lock"]),
             "--screen-off", str(values["screenOff"]),
             "--suspend", str(values["suspend"])],
            check=True, capture_output=True, text=True)
        try:
            with open(conf) as f:
                after = f.read()
        except FileNotFoundError:
            after = None
        return after != before

    def apply_idle(self, values):
        if self.write_idle_conf(values):
            run([PKILL, "-x", "hypridle"], capture_output=True)
            hyprctl(["dispatch", 'hl.dsp.exec_cmd("hypridle")'])

    def start_revert_timer(self, command):
        units = [f"{REVERT_UNIT}.timer", f"{REVERT_UNIT}.service"]
        run([SYSTEMCTL, "--user", "stop", *units], capture_output=True)
        run([SYSTEMCTL, "--user", "reset-failed", *units], capture_output=True)
        run(
            [SYSTEMD_RUN, "--user", f"--unit={REVERT_UNIT}", "--collect",
             f"--on-active={REVERT_SECONDS}s", "--timer-property=AccuracySec=100ms",
             f"--setenv=KRANE_II_SETTINGS_MANIFEST={self.manifest['path']}",
             os.path.realpath(sys.argv[0]), *command],
            check=True, capture_output=True, text=True)

    def stop_revert_timer(self):
        run([SYSTEMCTL, "--user", "stop", f"{REVERT_UNIT}.timer"], capture_output=True)

    def revert_timer_active(self):
        try:
            result = run(
                [SYSTEMCTL, "--user", "is-active", "--quiet", f"{REVERT_UNIT}.timer"])
        except SettingsError:
            return False
        return result.returncode == 0

    def lock_state(self):
        """"true"/"false" from ii's lock IPC, or None while it is not up."""
        try:
            result = run(
                [self.manifest["qsBin"], "-c", "ii", "ipc", "call", "lock", "isLocked"],
                timeout=5, capture_output=True, text=True)
        except SettingsError:
            return None
        text = result.stdout.strip()
        return text if result.returncode == 0 and text in ("true", "false") else None

    def pidof_hyprlock(self):
        """Whether a hyprlock process runs (the lock-on-start fallback)."""
        try:
            return run([PIDOF, "hyprlock"], capture_output=True).returncode == 0
        except SettingsError:
            return False

    def open_settings(self):
        env = dict(os.environ, II_SETTINGS_PAGE="HyprlandConfig")
        run([SETSID, "-f", self.manifest["qsBin"], "-p", self.manifest["settingsQml"]],
            env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# Edits


def effective_idle(data, manifest):
    return {**manifest["idleBaseline"], **data.get("idle", {})}


def edit_set(data, section, key, pairs, schema):
    """Return a copy of `data` with the change applied. `pairs` is a list of
    (field, raw string) for monitors and [(key, raw)] otherwise."""
    new = copy.deepcopy(data)
    if section == "hyprland":
        if key not in schema["hyprland"]:
            raise SettingsError(f"hyprland.{key}: unknown key (not in the schema)")
        (_, raw), = pairs
        spec = schema["hyprland"][key]
        new.setdefault("hyprland", {})[key] = check_value(
            spec, parse_cli(spec, raw, f"hyprland.{key}"), f"hyprland.{key}")
    elif section == "idle":
        if key not in schema["idle"]:
            raise SettingsError(f"idle.{key}: unknown key")
        (_, raw), = pairs
        spec = schema["idle"][key]
        new.setdefault("idle", {})[key] = check_value(
            spec, parse_cli(spec, raw, f"idle.{key}"), f"idle.{key}")
    elif section == "animation":
        if key != "preset":
            raise SettingsError(f"animation.{key}: unknown key")
        (_, raw), = pairs
        new["animationPreset"] = check_value(schema["animationPreset"], raw, "animationPreset")
    elif section == "monitor":
        if not OUTPUT_RE.match(key):
            raise SettingsError(f"monitor: {key!r} is not an output name")
        entry = new.setdefault("monitors", {}).setdefault(key, {})
        for field, raw in pairs:
            spec = schema["monitor"].get(field)
            if spec is None or spec.get("internal"):
                raise SettingsError(f"monitors.{key}.{field}: unknown field")
            what = f"monitors.{key}.{field}"
            entry[field] = check_value(spec, parse_cli(spec, raw, what), what)
    else:
        raise SettingsError(f"unknown section {section!r}")
    return new


def complete_rule(data, output, manifest, runtime):
    """An output Nix does not know needs a complete rule in the GUI file."""
    if output in manifest["monitorBaselines"]:
        return data
    entry = data["monitors"][output]
    missing = [f for f in ("mode", "position", "scale") if f not in entry]
    if not missing:
        return data
    live = runtime.live_monitor(output)
    if live is None:
        raise SettingsError(
            f"monitors.{output}: not in krane.hypr.monitors, and its current rule cannot be "
            "read from Hyprland")
    for field in missing:
        entry[field] = live[field]
    return data


def edit_reset(data, section, key, fields, manifest):
    new = copy.deepcopy(data)
    if section == "hyprland":
        new.get("hyprland", {}).pop(key, None)
    elif section == "idle":
        new.get("idle", {}).pop(key, None)
    elif section == "animation":
        if key != "preset":
            raise SettingsError(f"animation.{key}: unknown key")
        new.pop("animationPreset", None)
    elif section == "monitor":
        monitors = new.get("monitors", {})
        if key in monitors:
            gui_owned_rule = key not in manifest["monitorBaselines"]
            if not fields or (gui_owned_rule and {"mode", "position", "scale"} & set(fields)):
                del monitors[key]
            else:
                for field in fields:
                    monitors[key].pop(field, None)
                    # Else a boot revert would restore it.
                    monitors[key].get("bootPrevious", {}).pop(field, None)
    else:
        raise SettingsError(f"unknown section {section!r}")
    for output in list(new.get("monitors", {})):
        if not set(new["monitors"][output]) - set(INTERNAL_FIELDS):
            del new["monitors"][output]
    for name in ("hyprland", "idle", "monitors"):
        if name in new and not new[name]:
            del new[name]
    return new


def check_owner(section, key, fields, manifest):
    owned = manifest["nixOwned"]
    if section == "hyprland" and key in owned["hyprland"]:
        raise SettingsError(f"hyprland.{key}: set in Nix ({nix_hint(manifest)})")
    if section == "monitor":
        for field in fields:
            if field in owned["monitors"].get(key, []):
                raise SettingsError(f"monitors.{key}.{field}: set in Nix ({nix_hint(manifest)})")


# Commands


class Settings:
    def __init__(self, manifest, schema, runtime):
        self.manifest = manifest
        self.schema = schema
        self.runtime = runtime
        self.repo = manifest["repoFile"]

    def render(self, data):
        return render(data, self.manifest, self.schema)

    def commit(self, old_text, new, full_reload=False):
        """Write `new` to the repo and live file and reload; revert if
        Hyprland reports an error in krane_gui.lua. No-op when unchanged."""
        validate_data(new, self.schema)
        check_ownership(new, self.manifest)
        new_text = dump(new)
        if new_text == old_text:
            return "unchanged"
        old_live = self.runtime.read_live()
        atomic_write(self.repo, new_text)
        self.runtime.write_live(self.render(new))
        if self.runtime.reload(full=full_reload):
            errors = self.runtime.config_errors()
            if "krane_gui" in errors:
                atomic_write(self.repo, old_text)
                if old_live is None:
                    old_live = self.render(json.loads(old_text))
                self.runtime.write_live(old_live)
                self.runtime.reload(full=full_reload)
                raise SettingsError("Hyprland rejected the change; reverted.\n" + errors.strip())
        old = json.loads(old_text)
        if old.get("idle") != new.get("idle"):
            self.runtime.apply_idle(effective_idle(new, self.manifest))
        return "written"

    def get(self):
        state = {
            "host": self.manifest["host"],
            "repoFile": self.repo,
            "liveFile": self.manifest["liveFile"],
            "nixOwned": self.manifest["nixOwned"],
            "monitorBaselines": self.manifest["monitorBaselines"],
            "idleBaseline": self.manifest["idleBaseline"],
            # xkeyboard-config's layout and variant list, for the keyboard dropdowns.
            "xkbRules": self.manifest.get("xkbRules"),
            "repo": None,
            "error": None,
            "pending": read_pending(),
            "revertPending": self.runtime.revert_timer_active(),
            "unconfirmed": [],
        }
        state["revertDeadline"] = (state["pending"] or {}).get("deadline") if state["revertPending"] else None
        try:
            data, _ = read_repo(self.repo)
            validate_data(data, self.schema)
            state["repo"] = data
            state["idle"] = effective_idle(data, self.manifest)
            state["unconfirmed"] = sorted(
                o for o, e in data.get("monitors", {}).items() if e.get("bootConfirmed") is False)
        except SettingsError as e:
            state["error"] = str(e)
            state["idle"] = dict(self.manifest["idleBaseline"])
        return json.dumps(state, sort_keys=True)

    def set(self, section, key, pairs):
        # hyprland: pairs are (key, value) and may name several keys, written together.
        for k in ([f for f, _ in pairs] if section == "hyprland" else [key]):
            check_owner(section, k, [f for f, _ in pairs], self.manifest)
        with locked(self.manifest):
            data, text = read_repo(self.repo)
            validate_data(data, self.schema)
            if section == "hyprland":
                new = data
                for k, raw in pairs:
                    new = edit_set(new, section, k, [(k, raw)], self.schema)
            else:
                new = edit_set(data, section, key, pairs, self.schema)
            if section == "monitor":
                new = complete_rule(new, key, self.manifest, self.runtime)
                mark_unconfirmed(data.get("monitors", {}).get(key), new["monitors"][key])
            return self.commit(text, new, full_reload=section == "monitor")

    def reset(self, section, key, fields):
        check_owner(section, key, fields, self.manifest)
        with locked(self.manifest):
            data, text = read_repo(self.repo)
            validate_data(data, self.schema)
            new = edit_reset(data, section, key, fields, self.manifest)
            return self.commit(text, new, full_reload=section == "monitor")

    def apply(self):
        with locked(self.manifest):
            pending = read_pending()
            try:
                data, _ = read_repo(self.repo)
                validate_data(data, self.schema)
                check_ownership(data, self.manifest)
            except SettingsError:
                # Repo file broke since the try: restore the pre-try live file.
                if pending and pending.get("kind") == "try":
                    self.runtime.stop_revert_timer()
                    self.runtime.write_live(pending.get("previousLive") or HEADER)
                    clear_pending()
                    self.runtime.reload(full=True)
                raise
            full = pending is not None
            self.runtime.stop_revert_timer()
            self.runtime.write_live(self.render(data))
            clear_pending()
            self.runtime.reload(full=full)
            if "idle" in data:
                self.runtime.apply_idle(effective_idle(data, self.manifest))
            return "applied"

    def try_monitor(self, output, pairs):
        return self.try_monitors([(output, pairs)])

    def try_monitors(self, changes):
        """One try, one confirm or revert, for every (output, pairs) in changes."""
        for output, pairs in changes:
            check_owner("monitor", output, [f for f, _ in pairs], self.manifest)
        with locked(self.manifest):
            data, _ = read_repo(self.repo)
            proposed = data
            for output, pairs in changes:
                proposed = edit_set(proposed, "monitor", output, pairs, self.schema)
                proposed = complete_rule(proposed, output, self.manifest, self.runtime)
            validate_data(proposed, self.schema)
            check_ownership(proposed, self.manifest)
            live = self.render(proposed)
            outputs = [output for output, _ in changes]
            # Revert must not depend on the repo file staying readable.
            write_pending({"kind": "try",
                           "deadline": time.time() + REVERT_SECONDS,
                           "fields": {o: proposed["monitors"][o] for o in outputs},
                           "previousLive": self.runtime.read_live()})
            # Timer first: if it cannot be started, nothing has been applied yet.
            try:
                self.runtime.start_revert_timer(["apply"])
            except (OSError, subprocess.CalledProcessError, SettingsError) as e:
                clear_pending()
                raise SettingsError(f"cannot start the revert timer, nothing applied: {e}")
            self.runtime.write_live(live)
            self.runtime.reload(full=True)
            return f"trying {', '.join(outputs)}; reverting in {REVERT_SECONDS}s unless confirmed"

    def confirm(self):
        with locked(self.manifest):
            pending = read_pending()
            if pending is None:
                raise SettingsError("nothing to confirm")
            data, text = read_repo(self.repo)
            new = copy.deepcopy(data)
            if pending["kind"] == "try":
                by_output = pending["fields"]
                if "output" in pending:  # written by a version that tried one output
                    by_output = {pending["output"]: by_output}
                for output, fields in by_output.items():
                    entry = dict(fields)
                    mark_unconfirmed(data.get("monitors", {}).get(output), entry)
                    new.setdefault("monitors", {})[output] = entry
            else:
                # Only outputs the pending check listed; one still disconnected at boot
                # keeps bootConfirmed=false.
                monitors = new.get("monitors", {})
                for output in pending.get("outputs", []):
                    entry = monitors.get(output)
                    if entry is not None:
                        entry.pop("bootConfirmed", None)
                        entry.pop("bootPrevious", None)
            # Everything that can fail runs before the timer stops, so failure leaves it armed.
            validate_data(new, self.schema)
            check_ownership(new, self.manifest)
            self.runtime.stop_revert_timer()
            new_text = dump(new)
            if new_text != text:
                atomic_write(self.repo, new_text)
            live = self.render(new)
            if live != self.runtime.read_live():
                self.runtime.write_live(live)
                self.runtime.reload(full=True)
            clear_pending()
            return "confirmed"

    def revert_unconfirmed(self):
        with locked(self.manifest):
            # Only outputs the pending check listed; one absent at boot keeps
            # bootConfirmed=false for the next boot check.
            pending = read_pending()
            outputs = pending.get("outputs", []) if pending else []
            data, text = read_repo(self.repo)
            new = copy.deepcopy(data)
            monitors = new.get("monitors", {})
            for output in outputs:
                prev = (monitors.pop(output, None) or {}).get("bootPrevious") or {}
                owned = self.manifest["nixOwned"]["monitors"].get(output, [])
                prev = {f: v for f, v in prev.items() if f not in owned}
                # An output Nix no longer declares needs a complete rule (see complete_rule).
                if output not in self.manifest["monitorBaselines"] and not all(
                        f in prev for f in ("mode", "position", "scale")):
                    prev = {}
                if prev:
                    monitors[output] = prev
            if "monitors" in new and not new["monitors"]:
                del new["monitors"]
            # Render (which validates) before writing, so a bad file is left as it was.
            live = self.render(new)
            new_text = dump(new)
            if new_text != text:
                atomic_write(self.repo, new_text)
            self.runtime.write_live(live)
            self.runtime.stop_revert_timer()
            clear_pending()
            self.runtime.reload(full=True)
            return "reverted unconfirmed display settings"

    def boot_check(self, wait_seconds=60, poll=1.0):
        data, _ = read_repo(self.repo)
        unconfirmed_all = sorted(
            o for o, e in data.get("monitors", {}).items() if e.get("bootConfirmed") is False)
        if not unconfirmed_all:
            return "nothing to check"
        # lock-on-start locks once ii's lock IPC is up. Wait for that lock (up to
        # wait_seconds), then the unlock, so the dialog starts when the user can answer.
        deadline = time.monotonic() + wait_seconds
        # The fallback hyprlock (ii's IPC never came up) counts as locked too.

        def is_locked():
            return self.runtime.lock_state() == "true" or self.runtime.pidof_hyprlock()
        while time.monotonic() < deadline and not is_locked():
            time.sleep(poll)
        while is_locked():
            time.sleep(poll)
        # Read after the lock waits so late outputs (dock, MST, dGPU) have appeared.
        # Absent outputs keep bootConfirmed=false until a boot where they are connected.
        connected = self.runtime.connected_outputs()
        if connected is None:
            print("krane-ii-settings: boot-check: hyprctl is unreadable; "
                  "checking nothing", file=sys.stderr)
            return "nothing to check"
        unconfirmed = [o for o in unconfirmed_all if o in connected]
        if not unconfirmed:
            return "nothing to check"
        with locked(self.manifest):
            write_pending({"kind": "boot", "outputs": unconfirmed,
                           "deadline": time.time() + REVERT_SECONDS})
            try:
                self.runtime.start_revert_timer(["revert-unconfirmed"])
            except (OSError, subprocess.CalledProcessError, SettingsError) as e:
                clear_pending()
                raise SettingsError(f"cannot start the revert timer: {e}")
        self.runtime.open_settings()
        return "asking to keep " + ", ".join(unconfirmed)

    def activate(self):
        """Re-render the live GUI config from the repo file at home-manager activation,
        which otherwise restores the last switch's render and loses later GUI changes.
        Never fails: on a bad repo file or any error, warn and keep the existing render.
        Never touches hyprctl, reload, the revert timer or the pending file."""
        with locked(self.manifest):
            try:
                data, _ = read_repo(self.repo)
                validate_data(data, self.schema)
                check_ownership(data, self.manifest)
                live = self.render(data)
                idle = effective_idle(data, self.manifest)
            except SettingsError as e:
                print(f"krane-ii-settings: activate: {e}; leaving the "
                      "build-time render in place", file=sys.stderr)
                return "activation skipped"
            try:
                self.runtime.write_live(live)
                self.runtime.write_idle_conf(idle)
            except (OSError, subprocess.CalledProcessError, SettingsError) as e:
                print(f"krane-ii-settings: activate: {e}; leaving the "
                      "build-time render in place", file=sys.stderr)
                return "activation skipped"
            return "activated"


def load_manifest(path):
    if not path:
        raise SettingsError("no manifest: pass --manifest or set KRANE_II_SETTINGS_MANIFEST")
    with open(path) as f:
        manifest = json.load(f)
    manifest["path"] = path
    return manifest


def pairs_from(args, what):
    if len(args) % 2:
        raise SettingsError(f"{what}: expected FIELD VALUE pairs")
    return [(args[i], args[i + 1]) for i in range(0, len(args), 2)]


def monitor_groups(args):
    """Split `OUTPUT FIELD VALUE ... + OUTPUT FIELD VALUE ...` into (output, pairs) groups."""
    groups, current = [], []
    for arg in args + ["+"]:
        if arg != "+":
            current.append(arg)
            continue
        if len(current) < 3:
            raise SettingsError("try monitor: expected OUTPUT FIELD VALUE ...")
        if any(current[0] == output for output, _ in groups):
            raise SettingsError(f"try monitor: {current[0]} twice")
        groups.append((current[0], pairs_from(current[1:], "try monitor")))
        current = []
    return groups


def main(argv=None, runtime_factory=Runtime):
    parser = argparse.ArgumentParser(prog="krane-ii-settings")
    parser.add_argument("--manifest", default=os.environ.get("KRANE_II_SETTINGS_MANIFEST"))
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("get")
    p_set = sub.add_parser("set")
    p_set.add_argument("section", choices=["hyprland", "idle", "animation", "monitor"])
    p_set.add_argument("key")
    p_set.add_argument("rest", nargs="+")
    p_reset = sub.add_parser("reset")
    p_reset.add_argument("section", choices=["hyprland", "idle", "animation", "monitor"])
    p_reset.add_argument("key")
    p_reset.add_argument("fields", nargs="*")
    sub.add_parser("apply")
    p_render = sub.add_parser("render")
    p_render.add_argument("--json", required=True)
    p_try = sub.add_parser("try")
    p_try.add_argument("section", choices=["monitor"])
    p_try.add_argument("rest", nargs="+", metavar="OUTPUT FIELD VALUE ... [+ OUTPUT ...]")
    sub.add_parser("confirm")
    sub.add_parser("boot-check")
    sub.add_parser("revert-unconfirmed")
    sub.add_parser("activate")
    sub.add_parser("schema")
    args = parser.parse_args(argv)
    schema = load_schema()
    try:
        if args.cmd == "schema":
            print(dump(schema), end="")
            return 0
        manifest = load_manifest(args.manifest)
        if args.cmd == "render":
            data, _ = read_repo(args.json)
            print(render(data, manifest, schema), end="")
            return 0
        settings = Settings(manifest, schema, runtime_factory(manifest))
        if args.cmd == "get":
            out = settings.get()
        elif args.cmd == "set":
            if args.section == "monitor":
                pairs = pairs_from(args.rest, "set monitor")
            elif args.section == "hyprland":
                pairs = pairs_from([args.key] + args.rest, "set hyprland")
            else:
                if len(args.rest) != 1:
                    raise SettingsError(f"set {args.section} {args.key}: expected one value")
                pairs = [(args.key, args.rest[0])]
            out = settings.set(args.section, args.key, pairs)
        elif args.cmd == "reset":
            out = settings.reset(args.section, args.key, args.fields)
        elif args.cmd == "apply":
            out = settings.apply()
        elif args.cmd == "try":
            out = settings.try_monitors(monitor_groups(args.rest))
        elif args.cmd == "confirm":
            out = settings.confirm()
        elif args.cmd == "boot-check":
            out = settings.boot_check()
        elif args.cmd == "activate":
            out = settings.activate()
        else:
            out = settings.revert_unconfirmed()
        print(out)
        return 0
    except SettingsError as e:
        print(f"krane-ii-settings: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
