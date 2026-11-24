"""get() reports the real revert timer's deadline so the GUI countdown matches it.
Run from pkgs/krane-ii-settings: python3 -m unittest discover -s tests -v
"""

import json
import subprocess
import unittest
from unittest import mock

from test_commands import Base, k


def _result(stdout="", returncode=0):
    return subprocess.CompletedProcess([], returncode, stdout=stdout, stderr="")


class TestRevertDeadline(Base):
    def test_get_reports_deadline_while_timer_active(self):
        self.runtime.timer = True
        self.runtime.deadline = 1_800_000_015.5
        self.assertEqual(json.loads(self.s.get())["revertDeadline"], 1_800_000_015.5)

    def test_get_reports_null_when_timer_inactive(self):
        self.runtime.deadline = 1_800_000_015.5
        self.assertIsNone(json.loads(self.s.get())["revertDeadline"])

    def test_runtime_parses_systemctl_microseconds(self):
        with mock.patch.object(k.subprocess, "run", return_value=_result("1800000015500000\n")) as run:
            self.assertEqual(k.Runtime(self.manifest).revert_deadline(), 1_800_000_015.5)
        self.assertIn("NextElapseUSecRealtime", run.call_args[0][0])

    def test_runtime_none_on_failure_unset_or_timeout(self):
        rt = k.Runtime(self.manifest)
        for res in (_result("", 1), _result("0\n"), _result("n/a\n"), _result("")):
            with mock.patch.object(k.subprocess, "run", return_value=res):
                self.assertIsNone(rt.revert_deadline())

        def hang(*a, **kw):
            raise subprocess.TimeoutExpired(a[0], kw.get("timeout"))
        with mock.patch.object(k.subprocess, "run", hang):
            self.assertIsNone(rt.revert_deadline())


if __name__ == "__main__":
    unittest.main()
