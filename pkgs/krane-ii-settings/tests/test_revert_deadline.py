"""get() reports the revert deadline stored when the timer was started, so the GUI countdown matches it."""

import json
import subprocess
import time
import unittest
from unittest import mock

from test_commands import Base, k


class TestRevertDeadline(Base):
    def test_try_stores_deadline_and_get_reports_it(self):
        self.runtime.live_monitors = {"DP-2": {"mode": "1x1@60", "position": "0x0", "scale": 1.0}}
        before = time.time()
        self.s.try_monitor("DP-2", [("cm", "hdr")])
        deadline = json.loads(self.s.get())["revertDeadline"]
        self.assertGreaterEqual(deadline, before + k.REVERT_SECONDS)
        self.assertLessEqual(deadline, time.time() + k.REVERT_SECONDS)

    def test_boot_check_stores_deadline(self):
        self.repo.write_text('{"monitors": {"DP-2": {"bootConfirmed": false, "cm": "hdr"}}}\n')
        self.s.boot_check(wait_seconds=0, poll=0)
        self.assertGreater(json.loads(self.s.get())["revertDeadline"], time.time())

    def test_get_reports_null_when_timer_inactive(self):
        k.write_pending({"kind": "try", "deadline": time.time() + 10})
        self.assertIsNone(json.loads(self.s.get())["revertDeadline"])

    def test_revert_timer_active_false_on_timeout(self):
        def hang(*a, **kw):
            raise subprocess.TimeoutExpired(a[0], kw.get("timeout"))
        with mock.patch.object(k.subprocess, "run", hang):
            self.assertFalse(k.Runtime(self.manifest).revert_timer_active())


if __name__ == "__main__":
    unittest.main()
