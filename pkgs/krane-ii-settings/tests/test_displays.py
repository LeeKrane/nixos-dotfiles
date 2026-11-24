"""Display tests for krane_ii_settings (try, confirm, boot check).
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import pathlib
import unittest

from test_commands import Base, k


class TestMonitors(Base):
    def test_try_then_timeout_reverts(self):
        out = self.s.try_monitor("DP-2", [("cm", "hdr"), ("bitdepth", "10")])
        self.assertIn("reverting", out)
        self.assertEqual(self.repo.read_text(), "{}\n")
        self.assertIn('cm = "hdr"', pathlib.Path(self.manifest["liveFile"]).read_text())
        self.assertIn(("start_timer", ("apply",)), self.runtime.calls)
        self.s.apply()
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), self.s.render({}))
        self.assertIn(("reload", True), self.runtime.calls)
        self.assertIsNone(k.read_pending())

    def test_try_then_confirm_persists_unconfirmed(self):
        self.s.try_monitor("DP-2", [("cm", "hdr"), ("bitdepth", "10")])
        self.s.confirm()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"bitdepth": 10, "bootConfirmed": False, "cm": "hdr"}}})
        self.assertFalse(self.runtime.timer)

    def test_no_revert_timer_means_no_change(self):
        def fail(command):
            raise OSError("systemd-run not found")
        self.runtime.start_revert_timer = fail
        with self.assertRaisesRegex(k.SettingsError, "nothing applied"):
            self.s.try_monitor("DP-2", [("cm", "hdr")])
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())
        self.assertIsNone(k.read_pending())

    def test_revert_survives_broken_repo_file(self):
        pathlib.Path(self.manifest["liveFile"]).write_text("BEFORE\n")
        self.s.try_monitor("DP-2", [("cm", "hdr")])
        self.repo.write_text("<<<<<<< HEAD\n")
        with self.assertRaisesRegex(k.SettingsError, "cannot parse"):
            self.s.apply()
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), "BEFORE\n")
        self.assertIsNone(k.read_pending())
        self.assertIn(("reload", True), self.runtime.calls)

    def test_confirm_leaves_timer_armed_on_broken_repo_file(self):
        self.s.try_monitor("DP-2", [("cm", "hdr")])
        self.repo.write_text("<<<<<<< HEAD\n")
        with self.assertRaisesRegex(k.SettingsError, "cannot parse"):
            self.s.confirm()
        self.assertTrue(self.runtime.timer)
        self.assertIsNotNone(k.read_pending())

    def test_try_refuses_nix_owned_field(self):
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.try_monitor("DP-2", [("scale", "1")])

    def test_gui_owned_output_gets_complete_rule(self):
        self.runtime.live_monitors = {"HDMI-A-1": {"mode": "1920x1080@60", "position": "3840x0", "scale": 1.0}}
        self.s.try_monitor("HDMI-A-1", [("position", "-1920x0")])
        self.s.confirm()
        entry = self.repo_data()["monitors"]["HDMI-A-1"]
        self.assertEqual(entry["position"], "-1920x0")
        self.assertEqual(entry["mode"], "1920x1080@60")
        self.assertEqual(entry["scale"], 1.0)

    def test_gui_owned_output_needs_hyprland(self):
        with self.assertRaisesRegex(k.SettingsError, "cannot be read"):
            self.s.try_monitor("HDMI-A-1", [("position", "0x0")])

    def test_boot_check_and_timeout(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.runtime.lock_states = ["false", "true", "true", "false"]
        self.assertIn("DP-2", self.s.boot_check(wait_seconds=5, poll=0))
        self.assertIn(("start_timer", ("revert-unconfirmed",)), self.runtime.calls)
        self.assertIn(("open_settings",), self.runtime.calls)
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {})
        self.assertIn(("stop_timer",), self.runtime.calls)

    def test_boot_check_skips_disconnected_output(self):
        # I1: an output Hyprland does not currently report connected stays
        # bootConfirmed=false and is never added to the pending file.
        self.repo.write_text(
            '{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"},'
            ' "HDMI-A-1": {"bootConfirmed": false, "cm": "srgb"}}}\n')
        self.runtime.connected = {"DP-2"}
        out = self.s.boot_check(wait_seconds=0, poll=0)
        self.assertIn("DP-2", out)
        self.assertNotIn("HDMI-A-1", out)
        self.assertEqual(k.read_pending()["outputs"], ["DP-2"])

    def test_boot_check_warns_and_checks_nothing_when_hyprctl_unreadable(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.runtime.connected = None
        self.assertEqual(self.s.boot_check(wait_seconds=0, poll=0), "nothing to check")
        self.assertIsNone(k.read_pending())
        self.assertNotIn(("open_settings",), self.runtime.calls)

    def test_revert_unconfirmed_only_touches_pending_outputs(self):
        # I1 + Minor 1: revert_unconfirmed must act only on the outputs the
        # pending file listed, and must stop the revert timer.
        self.repo.write_text(
            '{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"},'
            ' "HDMI-A-1": {"bootConfirmed": false, "cm": "srgb"}}}\n')
        k.write_pending({"kind": "boot", "outputs": ["DP-2"]})
        self.runtime.timer = True
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {"monitors": {"HDMI-A-1": {"bootConfirmed": False, "cm": "srgb"}}})
        self.assertIn(("stop_timer",), self.runtime.calls)
        self.assertIsNone(k.read_pending())

    def test_boot_check_keep(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.s.boot_check(wait_seconds=0, poll=0)
        self.s.confirm()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"cm": "hdr"}}})

    def test_boot_check_nothing_to_do(self):
        self.assertEqual(self.s.boot_check(wait_seconds=0, poll=0), "nothing to check")

    def test_boot_check_no_revert_timer_means_no_settings_window(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')

        def fail(command):
            raise OSError("systemd-run not found")
        self.runtime.start_revert_timer = fail
        with self.assertRaisesRegex(k.SettingsError, "cannot start the revert timer"):
            self.s.boot_check(wait_seconds=0, poll=0)
        self.assertIsNone(k.read_pending())
        self.assertNotIn(("open_settings",), self.runtime.calls)


if __name__ == "__main__":
    unittest.main()
