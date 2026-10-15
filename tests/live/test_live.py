"""Scripted integration test against the real, running game (seam 4).

Needs FTL open with the mod installed and a Run in progress (start a new Run first).
Run: python3 -m unittest -v tests/live/test_live.py
"""

import json
import os
import subprocess
import sys
import time
import unittest
from pathlib import Path
from typing import Any

FTL = Path(__file__).resolve().parents[2] / "bin" / "ftl"


def ftl(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(FTL), *args], capture_output=True, text=True, timeout=30
    )


def state() -> dict[str, Any]:
    r = ftl("state")
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


class LiveGameTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        r = ftl("state")
        if r.returncode != 0:
            raise unittest.SkipTest(f"game not available: {r.stderr.strip()}")
        if not json.loads(r.stdout).get("in_run"):
            raise unittest.SkipTest("no Run in progress; start a new Run first")

    def tearDown(self) -> None:
        ftl("pause")

    def test_state_shows_the_starting_ship(self) -> None:
        s = state()
        self.assertEqual(s["in_run"], True)
        self.assertGreater(s["ship"]["hull_max"], 0)
        self.assertLessEqual(s["ship"]["hull"], s["ship"]["hull_max"])
        self.assertGreaterEqual(s["ship"]["scrap"], 0)

    def test_pause_and_unpause(self) -> None:
        self.assertEqual(ftl("pause").returncode, 0)
        self.assertEqual(state()["paused"], True)
        self.assertEqual(ftl("unpause").returncode, 0)
        self.assertEqual(state()["paused"], False)

    def test_game_time_advances_only_while_unpaused(self) -> None:
        ftl("pause")
        before = state()["game_time"]
        self.assertEqual(ftl("wait", "1").returncode, 0)
        self.assertEqual(state()["game_time"], before)
        ftl("unpause")
        before = state()["game_time"]
        self.assertEqual(ftl("wait", "1").returncode, 0)
        advanced = state()["game_time"] - before
        self.assertGreater(advanced, 0.8)
        self.assertLess(advanced, 1.5)

    def test_bad_commands_fail_with_a_reason(self) -> None:
        r = ftl("wait", "11")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "wait takes 0.1 to 10 seconds in steps of 0.1")
        r = ftl("fly", "away")
        self.assertEqual((r.returncode, r.stderr.strip()), (1, "unknown command: fly"))

    def test_commands_reach_the_action_log(self) -> None:
        marker = "wait 0.1"
        start = time.time()
        self.assertEqual(ftl(*marker.split()).returncode, 0)
        default = Path.home() / "Library/Application Support/FasterThanLight/ftlbench"
        base = Path(os.environ.get("FTL_BENCH_DIR", default)) / "runs"
        newest = max(base.iterdir(), key=lambda p: p.stat().st_mtime)
        last = json.loads((newest / "actions.jsonl").read_text().splitlines()[-1])
        self.assertEqual(last["command"], marker)
        self.assertEqual(last["result"], "ok")
        self.assertGreaterEqual(last["wall_ms"], int(start * 1000) - 1)
        self.assertIn("frame", last)


if __name__ == "__main__":
    unittest.main()
