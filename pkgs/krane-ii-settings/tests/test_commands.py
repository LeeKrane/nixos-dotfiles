"""Command tests for krane_ii_settings (set, reset, apply, get, idle, CLI).
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import krane_ii_settings as k  # noqa: E402

FIXTURES = HERE / "fixtures"
SCHEMA = k.load_schema()


class _AllConnected:
    """Sentinel `in`-container standing in for "hyprctl reports every output
    connected", so tests that never set FakeRuntime.connected keep their
    existing behavior (I1 does not filter anything out for them)."""

    def __contains__(self, item):
        return True


ALL_CONNECTED = _AllConnected()


class FakeRuntime:
    """Records side effects instead of touching Hyprland, systemd or hypridle."""

    def __init__(self, manifest, errors="", live_monitors=None, running=True, installed_idle=None):
        self.manifest = manifest
        self.errors = errors
        self.live_monitors = live_monitors or {}
        self.running = running
        self.calls = []
        self.timer = False
        self.lock_states = []
        self.installed_idle = installed_idle
        # None means "hyprctl unreadable" (I1); set to a set of output names,
        # or leave as ALL_CONNECTED to mean every output is connected.
        self.connected = ALL_CONNECTED

    def read_live(self):
        try:
            return pathlib.Path(self.manifest["liveFile"]).read_text()
        except FileNotFoundError:
            return None

    def write_live(self, text):
        pathlib.Path(self.manifest["liveFile"]).write_text(text)
        self.calls.append(("write_live",))

    def reload(self, full=False):
        self.calls.append(("reload", full))
        return self.running

    def config_errors(self):
        return self.errors

    def live_monitor(self, output):
        return self.live_monitors.get(output)

    def connected_outputs(self):
        self.calls.append(("connected_outputs",))
        return self.connected

    def write_idle_conf(self, values):
        values = dict(values)
        changed = values != self.installed_idle
        if changed:
            self.installed_idle = values
        self.calls.append(("write_idle_conf", values))
        return changed

    def apply_idle(self, values):
        values = dict(values)
        if values == self.installed_idle:
            return
        self.installed_idle = values
        self.calls.append(("apply_idle", values))

    def start_revert_timer(self, command):
        self.timer = True
        self.calls.append(("start_timer", tuple(command)))

    def stop_revert_timer(self):
        self.timer = False
        self.calls.append(("stop_timer",))

    def revert_timer_active(self):
        return self.timer

    def lock_state(self):
        return self.lock_states.pop(0) if self.lock_states else "false"

    def open_settings(self):
        self.calls.append(("open_settings",))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        os.environ["XDG_RUNTIME_DIR"] = str(self.dir)
        self.manifest = json.loads((FIXTURES / "manifest.json").read_text())
        self.manifest["repoFile"] = str(self.dir / "ii-settings.json")
        self.manifest["liveFile"] = str(self.dir / "krane_gui.lua")
        self.manifest["path"] = str(self.dir / "manifest.json")
        self.repo = pathlib.Path(self.manifest["repoFile"])
        self.repo.write_text("{}\n")
        self.runtime = FakeRuntime(self.manifest)
        self.s = k.Settings(self.manifest, SCHEMA, self.runtime)

    def tearDown(self):
        self.tmp.cleanup()

    def repo_data(self):
        return json.loads(self.repo.read_text())


class TestSetReset(Base):
    def test_sparse_sorted_write(self):
        self.assertEqual(self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")]), "written")
        self.assertEqual(self.repo.read_text(), '{\n  "hyprland": {\n    "general:gaps_in": 12\n  }\n}\n')
        self.assertIn("gaps_in = 12", pathlib.Path(self.manifest["liveFile"]).read_text())
        self.assertIn(("reload", False), self.runtime.calls)

    def test_unchanged_is_noop(self):
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        before = self.repo.stat().st_mtime_ns
        self.runtime.calls.clear()
        self.assertEqual(self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")]), "unchanged")
        self.assertEqual(self.repo.stat().st_mtime_ns, before)
        self.assertEqual(self.runtime.calls, [])

    def test_reset_removes_key_and_section(self):
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.s.reset("hyprland", "general:gaps_in", [])
        self.assertEqual(self.repo_data(), {})
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), k.HEADER)

    def test_bool_from_cli(self):
        self.s.set("hyprland", "decoration:blur:enabled", [("decoration:blur:enabled", "0")])
        self.assertIs(self.repo_data()["hyprland"]["decoration:blur:enabled"], False)

    def test_refuses_nix_owned_key(self):
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.set("hyprland", "input:kb_layout", [("input:kb_layout", "us")])
        self.assertEqual(self.repo.read_text(), "{}\n")

    def test_refuses_nix_owned_reset(self):
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.reset("hyprland", "input:kb_layout", [])

    def test_refuses_unknown_key(self):
        with self.assertRaisesRegex(k.SettingsError, "unknown key"):
            self.s.set("hyprland", "general:nope", [("general:nope", "1")])

    def test_refuses_bad_json_and_leaves_file(self):
        self.repo.write_text('{\n<<<<<<< HEAD\n')
        with self.assertRaisesRegex(k.SettingsError, "cannot parse"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo.read_text(), '{\n<<<<<<< HEAD\n')
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())

    def test_refuses_missing_file_and_never_creates_it(self):
        self.repo.unlink()
        with self.assertRaisesRegex(k.SettingsError, "not persisted"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertFalse(self.repo.exists())

    def test_hyprland_error_reverts(self):
        self.runtime.errors = "error in custom/krane_gui.lua:3: bad value"
        pathlib.Path(self.manifest["liveFile"]).write_text("OLD LIVE\n")
        with self.assertRaisesRegex(k.SettingsError, "rejected"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo.read_text(), "{}\n")
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), "OLD LIVE\n")

    def test_no_hyprland_still_writes(self):
        self.runtime.running = False
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo_data(), {"hyprland": {"general:gaps_in": 12}})

    def test_keeps_external_edits(self):
        self.repo.write_text('{"hyprland": {"general:gaps_out": 7}}\n')
        self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])
        self.assertEqual(self.repo_data()["hyprland"], {"general:gaps_in": 12, "general:gaps_out": 7})

    def test_animation_preset(self):
        self.s.set("animation", "preset", [("preset", "fast")])
        self.assertIn('require("hyprland.animationPresets.fast")',
                      pathlib.Path(self.manifest["liveFile"]).read_text())
        with self.assertRaisesRegex(k.SettingsError, "not a valid enum"):
            self.s.set("animation", "preset", [("preset", "bouncy")])


class TestIdle(Base):
    def test_set_idle_applies(self):
        self.s.set("idle", "lock", [("lock", "60")])
        self.assertEqual(self.repo_data(), {"idle": {"lock": 60}})
        self.assertIn(("apply_idle", {"lock": 60, "screenOff": 600, "suspend": 900}), self.runtime.calls)

    def test_idle_owned_by_nix(self):
        self.manifest["nixOwned"]["idle"] = True
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.set("idle", "lock", [("lock", "60")])

    def test_apply_does_not_restart_hypridle_when_idle_unchanged(self):
        self.s.set("idle", "lock", [("lock", "60")])
        self.runtime.calls.clear()
        self.assertEqual(self.s.apply(), "applied")
        self.assertFalse(any(c[0] == "apply_idle" for c in self.runtime.calls))

    def test_apply_restarts_hypridle_when_idle_changed(self):
        self.repo.write_text(json.dumps({"idle": {"lock": 60}}) + "\n")
        self.assertEqual(self.s.apply(), "applied")
        self.assertIn(("apply_idle", {"lock": 60, "screenOff": 600, "suspend": 900}), self.runtime.calls)


class TestValidateShape(Base):
    def test_get_reports_wrong_shape(self):
        self.repo.write_text('{"hyprland": null}\n')
        state = json.loads(self.s.get())
        self.assertIn("must be an object", state["error"])

    def test_set_refuses_wrong_shape_cleanly(self):
        self.repo.write_text('{"hyprland": null}\n')
        with self.assertRaisesRegex(k.SettingsError, "must be an object"):
            self.s.set("hyprland", "general:gaps_in", [("general:gaps_in", "12")])

    def test_reset_refuses_wrong_shape_cleanly(self):
        self.repo.write_text('{"idle": 5}\n')
        with self.assertRaisesRegex(k.SettingsError, "must be an object"):
            self.s.reset("idle", "lock", [])

    def test_main_set_wrong_shape_exits_1_no_traceback(self):
        self.repo.write_text('{"hyprland": null}\n')
        (self.dir / "manifest.json").write_text(json.dumps(self.manifest))
        mp = str(self.dir / "manifest.json")
        factory = lambda m: FakeRuntime(m)  # noqa: E731
        self.assertEqual(
            k.main(["--manifest", mp, "set", "hyprland", "general:gaps_in", "12"], factory), 1)


class TestApplyIdleRuntime(unittest.TestCase):
    """Runtime.apply_idle against a scratch dir. subprocess.run and
    hyprland_signatures are monkeypatched: never the real Hyprland or hypridle."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        os.environ["XDG_RUNTIME_DIR"] = str(self.dir)
        self.conf = self.dir / "hypridle.conf"
        self.conf.write_text("OLD\n")
        self.script = self.dir / "fake_configurator.py"
        self.script.write_text("# stub: subprocess.run is mocked in these tests\n")
        manifest = json.loads((FIXTURES / "manifest.json").read_text())
        manifest["hypridleFile"] = str(self.conf)
        manifest["idleConfigurator"] = str(self.script)
        self.runtime = k.Runtime(manifest)
        self.calls = []
        self._real_run = k.subprocess.run
        self._real_signatures = k.hyprland_signatures

    def tearDown(self):
        k.subprocess.run = self._real_run
        k.hyprland_signatures = self._real_signatures
        self.tmp.cleanup()

    def test_unchanged_idle_config_does_not_restart(self):
        def fake_run(args, **kwargs):
            self.calls.append(list(args))
            return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

        k.subprocess.run = fake_run
        k.hyprland_signatures = lambda: ["fake-sig"]
        self.runtime.apply_idle({"lock": 60, "screenOff": 600, "suspend": 900})
        self.assertEqual(len(self.calls), 1, self.calls)
        self.assertEqual(self.calls[0][0], sys.executable)

    def test_changed_idle_config_restarts_via_hyprctl_dispatch(self):
        def fake_run(args, **kwargs):
            self.calls.append(list(args))
            if args[0] == sys.executable:
                self.conf.write_text("NEW\n")
            return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

        k.subprocess.run = fake_run
        k.hyprland_signatures = lambda: ["fake-sig"]
        self.runtime.apply_idle({"lock": 60, "screenOff": 600, "suspend": 900})
        self.assertEqual(self.calls[0][0], sys.executable)
        self.assertEqual(self.calls[1], [k.PKILL, "-x", "hypridle"])
        self.assertEqual(self.calls[2], [k.HYPRCTL, "dispatch", 'hl.dsp.exec_cmd("hypridle")'])
        flat = [a for call in self.calls for a in call]
        self.assertNotIn(k.SETSID, flat)
        self.assertNotIn(k.HYPRIDLE, flat)


class TestCli(Base):
    def test_get_reports_parse_error(self):
        self.repo.write_text("not json")
        (self.dir / "manifest.json").write_text(json.dumps(self.manifest))
        state = json.loads(k.Settings(self.manifest, SCHEMA, self.runtime).get())
        self.assertIn("cannot parse", state["error"])
        self.assertEqual(state["nixOwned"]["hyprland"], ["cursor:default_monitor", "input:kb_layout", "input:kb_variant"])

    def test_main_exit_codes(self):
        (self.dir / "manifest.json").write_text(json.dumps(self.manifest))
        mp = str(self.dir / "manifest.json")
        factory = lambda m: FakeRuntime(m)  # noqa: E731
        self.assertEqual(k.main(["--manifest", mp, "set", "hyprland", "input:kb_layout", "us"], factory), 1)
        self.assertEqual(k.main(["--manifest", mp, "set", "hyprland", "general:gaps_in", "12"], factory), 0)
        self.assertEqual(k.main(["--manifest", mp, "reset", "hyprland", "general:gaps_in"], factory), 0)
        self.assertEqual(self.repo.read_text(), "{}\n")


if __name__ == "__main__":
    unittest.main()
