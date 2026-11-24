"""Render and schema tests for krane_ii_settings.
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import copy
import json
import pathlib
import re
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import krane_ii_settings as k  # noqa: E402

FIXTURES = HERE / "fixtures"
GOLDEN = HERE / "golden"
SCHEMA = k.load_schema()


class RenderBase(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((FIXTURES / "manifest.json").read_text())


class TestRender(RenderBase):
    def test_empty_is_header_only(self):
        self.assertEqual(k.render({}, self.manifest, SCHEMA), k.HEADER + "\nKRANE_GUI_MONITORS = {}\n\n")
        self.assertEqual(k.render({}, self.manifest, SCHEMA), (GOLDEN / "empty.lua").read_text())

    def test_all_keys_golden(self):
        data = json.loads((FIXTURES / "all-keys.json").read_text())
        self.assertEqual(k.render(data, self.manifest, SCHEMA), (GOLDEN / "all-keys.lua").read_text())

    def test_fixture_covers_every_schema_key(self):
        data = json.loads((FIXTURES / "all-keys.json").read_text())
        self.assertEqual(set(data["hyprland"]), set(SCHEMA["hyprland"]))
        self.assertEqual(set(data["idle"]), set(SCHEMA["idle"]))
        fields = set(data["monitors"]["DP-2"]) | set(data["monitors"]["HDMI-A-1"])
        self.assertEqual(fields, set(SCHEMA["monitor"]))

    def test_render_rejects_unknown_key(self):
        with self.assertRaisesRegex(k.SettingsError, "unknown key"):
            k.render({"hyprland": {"general:nope": 1}}, self.manifest, SCHEMA)

    def test_render_rejects_out_of_range(self):
        with self.assertRaisesRegex(k.SettingsError, "above the maximum"):
            k.render({"hyprland": {"decoration:rounding": 99}}, self.manifest, SCHEMA)

    def test_monitor_rule_is_complete(self):
        out = k.render({"monitors": {"DP-2": {"cm": "hdr"}}}, self.manifest, SCHEMA)
        self.assertIn('mode = "3840x2160@240"', out)
        self.assertIn('cm = "hdr"', out)
        self.assertNotIn("bootConfirmed", out)

    def test_monitor_rule_is_stashed_in_krane_gui_monitors(self):
        # hosts/<host>/display.nix's extraMonitorsLua (e.g. tarmantria's
        # scale_internal) reads KRANE_GUI_MONITORS[output] back to merge
        # GUI-owned fields into a rule it builds itself.
        out = k.render({"monitors": {"DP-2": {"cm": "hdr"}}}, self.manifest, SCHEMA)
        self.assertIn("KRANE_GUI_MONITORS = {}", out)
        self.assertIn('KRANE_GUI_MONITORS["DP-2"] = {', out)
        self.assertIn('hl.monitor(KRANE_GUI_MONITORS["DP-2"])', out)
        self.assertNotIn("hl.monitor({", out)

    def test_krane_gui_monitors_defined_without_monitors(self):
        out = k.render({"hyprland": {"decoration:rounding": 12}}, self.manifest, SCHEMA)
        self.assertIn("KRANE_GUI_MONITORS = {}", out)
        self.assertNotIn("KRANE_GUI_MONITORS[", out)

    def test_check_value_rejects_nan(self):
        with self.assertRaisesRegex(k.SettingsError, "not a finite number"):
            k.check_value(SCHEMA["hyprland"]["decoration:active_opacity"], float("nan"), "x")

    def test_check_value_rejects_inf(self):
        with self.assertRaisesRegex(k.SettingsError, "not a finite number"):
            k.check_value(SCHEMA["hyprland"]["decoration:active_opacity"], float("inf"), "x")


class TestOwnership(RenderBase):
    def test_refuses_nix_owned_hyprland_key(self):
        with self.assertRaisesRegex(
            k.SettingsError,
            re.escape("hyprland.input:kb_layout: set in Nix (hosts/testhost/display.nix or modules/home)"),
        ):
            k.check_ownership({"hyprland": {"input:kb_layout": "us"}}, self.manifest)

    def test_refuses_nix_owned_monitor_field(self):
        with self.assertRaisesRegex(k.SettingsError, "monitors.DP-2.scale: set in Nix"):
            k.check_ownership({"monitors": {"DP-2": {"scale": 1.5}}}, self.manifest)

    def test_accepts_non_owned_monitor_field(self):
        k.check_ownership({"monitors": {"DP-2": {"cm": "hdr"}}}, self.manifest)

    def test_accepts_non_owned_hyprland_key(self):
        k.check_ownership({"hyprland": {"decoration:rounding": 12}}, self.manifest)

    def test_accepts_idle_when_not_nix_owned(self):
        k.check_ownership({"idle": {"lock": 600}}, self.manifest)

    def test_refuses_idle_when_nix_owned(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["nixOwned"]["idle"] = True
        with self.assertRaisesRegex(k.SettingsError, "idle: set in Nix"):
            k.check_ownership({"idle": {"lock": 600}}, manifest)


if __name__ == "__main__":
    unittest.main()
