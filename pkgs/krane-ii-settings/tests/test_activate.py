"""Tests for the activate command (C1): re-render the live GUI config from
the repo file at every home-manager activation, without ever touching
hyprctl, reload, the revert timer or the pending file.
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import pathlib
import unittest

from test_commands import Base, k


class TestActivate(Base):
    def test_activate_renders_from_repo_without_reload_or_timer(self):
        self.repo.write_text('{"hyprland": {"general:gaps_in": 12}}\n')
        out = self.s.activate()
        self.assertEqual(out, "activated")
        self.assertIn("gaps_in = 12", pathlib.Path(self.manifest["liveFile"]).read_text())
        kinds = {call[0] for call in self.runtime.calls}
        self.assertIn("write_live", kinds)
        self.assertIn("write_idle_conf", kinds)
        self.assertNotIn("reload", kinds)
        self.assertNotIn("apply_idle", kinds)
        self.assertNotIn("start_timer", kinds)
        self.assertNotIn("stop_timer", kinds)
        self.assertNotIn("open_settings", kinds)
        self.assertIsNone(k.read_pending())

    def test_activate_on_missing_repo_file_changes_nothing_and_exits_clean(self):
        self.repo.unlink()
        self.assertEqual(self.s.activate(), "activation skipped")
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())
        self.assertEqual(self.runtime.calls, [])

    def test_activate_on_broken_repo_file_changes_nothing_and_exits_clean(self):
        pathlib.Path(self.manifest["liveFile"]).write_text("BEFORE\n")
        self.repo.write_text("<<<<<<< HEAD\n")
        self.assertEqual(self.s.activate(), "activation skipped")
        self.assertEqual(pathlib.Path(self.manifest["liveFile"]).read_text(), "BEFORE\n")
        self.assertEqual(self.runtime.calls, [])

    def test_activate_on_nix_owned_rejection_changes_nothing_and_exits_clean(self):
        # nixOwned.monitors.DP-2 includes "scale" in the fixture manifest; a
        # repo file claiming to GUI-own that field is a rejected (owned) write.
        self.repo.write_text('{"monitors": {"DP-2": {"scale": 2.0}}}\n')
        self.assertEqual(self.s.activate(), "activation skipped")
        self.assertFalse(pathlib.Path(self.manifest["liveFile"]).exists())
        self.assertEqual(self.runtime.calls, [])

    def test_activate_does_not_touch_pending_file(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        k.write_pending({"kind": "boot", "outputs": ["DP-2"]})
        self.s.activate()
        self.assertIsNotNone(k.read_pending())


if __name__ == "__main__":
    unittest.main()
