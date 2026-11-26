"""Boot-path fixes: pre-login lock fallback, always-emitted monitors table,
hyprlock fallback wait and subprocess timeouts."""

import os
import pathlib
import subprocess
import unittest
from unittest import mock

from test_commands import Base, FakeRuntime, k


def _timeout(*args, **kwargs):
    raise subprocess.TimeoutExpired(args[0], kwargs.get("timeout"))


class TestLockFallback(Base):
    def test_activate_without_runtime_dir_uses_repo_lock(self):
        os.environ["XDG_RUNTIME_DIR"] = str(self.dir / "does-not-exist")
        self.repo.write_text('{"hyprland": {"general:gaps_in": 12}}\n')
        self.assertEqual(self.s.activate(), "activated")
        self.assertTrue((self.dir / ".ii-settings.lock").exists())
        self.assertIn("gaps_in = 12", pathlib.Path(self.manifest["liveFile"]).read_text())


class TestMonitorsTable(Base):
    def test_empty_repo_still_defines_monitors_table(self):
        self.assertIn("KRANE_GUI_MONITORS = {}", k.render({}, self.manifest, k.load_schema()))


class TestHyprlockFallback(Base):
    def test_boot_check_waits_for_hyprlock_when_ii_ipc_is_down(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.runtime.lock_states = [None] * 4
        pids = [False, True, True, False]
        self.runtime.pidof_hyprlock = lambda: pids.pop(0)
        self.s.boot_check(wait_seconds=5, poll=0)
        self.assertEqual(pids, [])
        self.assertIn(("open_settings",), self.runtime.calls)


class TestTimeouts(Base):
    def test_hyprctl_timeout_is_no_answer(self):
        with mock.patch.object(k, "hyprland_signatures", return_value=["sig"]), \
                mock.patch.object(k.subprocess, "run", _timeout):
            self.assertIsNone(k.hyprctl(["reload"]))

    def test_lock_state_and_pidof_timeout_mean_not_up(self):
        rt = k.Runtime(self.manifest)
        with mock.patch.object(k.subprocess, "run", _timeout):
            self.assertIsNone(rt.lock_state())
            self.assertFalse(rt.pidof_hyprlock())

    def test_revert_timer_timeout_is_settings_error_and_clears_pending(self):
        self.repo.write_text("{}\n")
        self.runtime.live_monitors = {"DP-2": {"mode": "1x1@60", "position": "0x0", "scale": 1.0}}

        def hang(command):
            with mock.patch.object(k.subprocess, "run", _timeout):
                k.Runtime(self.manifest).start_revert_timer(command)
        self.runtime.start_revert_timer = hang
        with self.assertRaises(k.SettingsError):
            self.s.try_monitor("DP-2", [("cm", "hdr")])
        self.assertIsNone(k.read_pending())
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())


if __name__ == "__main__":
    unittest.main()
