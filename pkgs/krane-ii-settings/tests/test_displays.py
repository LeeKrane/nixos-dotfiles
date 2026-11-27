"""Display tests for krane_ii_settings (try, confirm, boot check)."""

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
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"bitdepth": 10, "bootConfirmed": False, "bootPrevious": {}, "cm": "hdr"}}})
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
            self.s.try_monitor("DP-2", [("output", "DP-9")])

    def test_gui_mode_and_scale_override_nix_baseline_and_reset_restores_it(self):
        self.s.try_monitor("DP-2", [("mode", "1920x1080@60"), ("scale", "1")])
        self.s.confirm()
        entry = self.repo_data()["monitors"]["DP-2"]
        self.assertEqual((entry["mode"], entry["scale"]), ("1920x1080@60", 1))
        live = pathlib.Path(self.manifest["liveFile"]).read_text()
        self.assertIn('mode = "1920x1080@60"', live)
        self.assertIn("scale = 1\n", live)
        self.assertIn('position = "0x0"', live)
        self.s.reset("monitor", "DP-2", ["mode", "scale"])
        self.assertEqual(self.repo_data(), {})
        # No GUI entry left: the render is empty and monitors.lua's Nix rule applies again.
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), self.s.render({}))

    def test_revert_unconfirmed_restores_previous_gui_scale_over_nix(self):
        self.repo.write_text('{"monitors": {"DP-2": {"scale": 2}}}\n')
        self.s.try_monitor("DP-2", [("scale", "1")])
        self.s.confirm()
        k.write_pending({"kind": "boot", "outputs": ["DP-2"]})
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"scale": 2}}})
        self.assertIn("scale = 2\n", pathlib.Path(self.manifest["liveFile"]).read_text())

    def test_gui_owned_output_gets_complete_rule(self):
        self.runtime.live_monitors = {"HDMI-A-1": {"mode": "1920x1080@60", "position": "3840x0", "scale": 1.0}}
        self.s.try_monitor("HDMI-A-1", [("position", "-1920x0")])
        self.s.confirm()
        entry = self.repo_data()["monitors"]["HDMI-A-1"]
        self.assertEqual(entry["position"], "-1920x0")
        self.assertEqual(entry["mode"], "1920x1080@60")
        self.assertEqual(entry["scale"], 1.0)

    def test_try_several_outputs_in_one_try(self):
        self.runtime.live_monitors = {
            "HDMI-A-1": {"mode": "1920x1080@60", "position": "3840x0", "scale": 1.0},
            "DP-3": {"mode": "1920x1080@60", "position": "5760x0", "scale": 1.0}}
        self.s.try_monitors([("HDMI-A-1", [("position", "-1920x0")]), ("DP-3", [("position", "-3840x0")])])
        live = pathlib.Path(self.manifest["liveFile"]).read_text()
        self.assertIn('position = "-1920x0"', live)
        self.assertIn('position = "-3840x0"', live)
        self.s.confirm()
        monitors = self.repo_data()["monitors"]
        self.assertEqual(monitors["HDMI-A-1"]["position"], "-1920x0")
        self.assertEqual(monitors["DP-3"]["position"], "-3840x0")
        self.assertFalse(monitors["DP-3"]["bootConfirmed"])

    def test_try_several_outputs_refuses_any_nix_owned(self):
        self.runtime.live_monitors = {"HDMI-A-1": {"mode": "1920x1080@60", "position": "3840x0", "scale": 1.0}}
        with self.assertRaisesRegex(k.SettingsError, "set in Nix"):
            self.s.try_monitors([("HDMI-A-1", [("position", "0x0")]), ("DP-2", [("output", "DP-9")])])
        self.assertIsNone(k.read_pending())

    def test_cli_try_splits_outputs_on_plus(self):
        self.assertEqual(k.monitor_groups(["DP-1", "position", "0x0", "+", "DP-2", "position", "1x0", "scale", "1"]),
                         [("DP-1", [("position", "0x0")]), ("DP-2", [("position", "1x0"), ("scale", "1")])])
        with self.assertRaises(k.SettingsError):
            k.monitor_groups(["DP-1", "position"])
        with self.assertRaises(k.SettingsError):
            k.monitor_groups(["DP-1"])
        with self.assertRaises(k.SettingsError):
            k.monitor_groups(["DP-1", "position", "0x0", "+", "DP-2"])
        with self.assertRaisesRegex(k.SettingsError, "DP-1 twice"):
            k.monitor_groups(["DP-1", "position", "0x0", "+", "DP-1", "scale", "1"])

    def test_confirm_reads_single_output_pending_from_older_version(self):
        self.runtime.live_monitors = {"HDMI-A-1": {"mode": "1920x1080@60", "position": "3840x0", "scale": 1.0}}
        self.s.try_monitor("HDMI-A-1", [("position", "-1920x0")])
        pending = k.read_pending()
        k.write_pending(dict(pending, output="HDMI-A-1", fields=pending["fields"]["HDMI-A-1"]))
        self.s.confirm()
        self.assertEqual(self.repo_data()["monitors"]["HDMI-A-1"]["position"], "-1920x0")

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

    def test_boot_check_reads_connected_after_lock_waits(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.runtime.lock_states = ["true", "false"]
        self.runtime.connected_outputs = lambda: (
            {"DP-2"} if not self.runtime.lock_states else set())
        self.assertIn("DP-2", self.s.boot_check(wait_seconds=5, poll=0))

    def test_boot_check_skips_disconnected_output(self):
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


class TestGuiOwnedPosition(Base):
    """A Nix-declared output whose position Nix leaves unset (null): position is the GUI's."""

    def setUp(self):
        super().setUp()
        self.manifest["nixOwned"]["monitors"]["DP-1"] = ["output"]
        self.manifest["monitorBaselines"]["DP-1"] = {
            "mode": "2560x1440@144", "output": "DP-1", "position": "auto", "scale": 1}

    def test_try_position_writes_only_position(self):
        self.s.try_monitor("DP-1", [("position", "2560x0")])
        self.s.confirm()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-1": {"bootConfirmed": False, "bootPrevious": {}, "position": "2560x0"}}})
        live = pathlib.Path(self.manifest["liveFile"]).read_text()
        self.assertIn('position = "2560x0"', live)
        self.assertIn('mode = "2560x1440@144"', live)
        self.assertIn("scale = 1", live)

    def test_reset_position_falls_back_to_baseline(self):
        self.repo.write_text('{"monitors": {"DP-1": {"position": "2560x0"}}}\n')
        self.s.reset("monitor", "DP-1", ["position"])
        self.assertEqual(self.repo_data(), {})
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), self.s.render({}))

    def test_revert_unconfirmed_restores_seeded_position(self):
        self.repo.write_text('{"monitors": {"DP-1": {"position": "2560x0"}}}\n')
        self.s.try_monitor("DP-1", [("bitdepth", "10")])
        self.s.confirm()
        k.write_pending({"kind": "boot", "outputs": ["DP-1"]})
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-1": {"position": "2560x0"}}})
        self.assertIn('position = "2560x0"', pathlib.Path(self.manifest["liveFile"]).read_text())

    def test_reset_during_boot_check_is_not_undone_by_revert(self):
        self.repo.write_text('{"monitors": {"DP-1": {"position": "2560x0"}}}\n')
        self.s.try_monitor("DP-1", [("bitdepth", "10")])
        self.s.confirm()
        self.s.reset("monitor", "DP-1", ["position"])
        k.write_pending({"kind": "boot", "outputs": ["DP-1"]})
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {})

    def test_revert_unconfirmed_removes_entry_that_did_not_exist(self):
        self.s.try_monitor("DP-1", [("position", "2560x0")])
        self.s.confirm()
        k.write_pending({"kind": "boot", "outputs": ["DP-1"]})
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {})

    def test_revert_unconfirmed_drops_nix_owned_previous_fields(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "bootPrevious": {"output": "DP-2", "position": "0x0"}, "position": "10x0"}}}\n')
        k.write_pending({"kind": "boot", "outputs": ["DP-2"]})
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-2": {"position": "0x0"}}})

    def test_boot_confirm_clears_previous(self):
        self.repo.write_text('{"monitors": {"DP-1": {"position": "2560x0"}}}\n')
        self.s.try_monitor("DP-1", [("bitdepth", "10")])
        self.s.confirm()
        k.write_pending({"kind": "boot", "outputs": ["DP-1"]})
        self.s.confirm()
        self.assertEqual(self.repo_data(), {"monitors": {"DP-1": {"bitdepth": 10, "position": "2560x0"}}})

    def test_revert_unconfirmed_drops_incomplete_gui_owned_previous(self):
        self.repo.write_text('{"monitors": {"DP-3": {"bootConfirmed": false, '
                             '"bootPrevious": {"position": "2560x0"}, "mode": "1x1@60", '
                             '"position": "0x0", "scale": 1}}}\n')
        k.write_pending({"kind": "boot", "outputs": ["DP-3"]})
        self.s.revert_unconfirmed()
        self.assertEqual(self.repo_data(), {})

    def test_previous_fields_are_validated(self):
        for prev in ({"nope": 1}, {"bootConfirmed": False}, {"scale": "x"}):
            with self.assertRaises(k.SettingsError):
                k.validate_data({"monitors": {"DP-1": {"bootPrevious": prev}}}, self.s.schema)

    def test_seeded_position_is_confirmed(self):
        self.repo.write_text('{"monitors": {"DP-1": {"position": "2560x0"}}}\n')
        self.assertEqual(self.s.boot_check(wait_seconds=0, poll=0), "nothing to check")


if __name__ == "__main__":
    unittest.main()
