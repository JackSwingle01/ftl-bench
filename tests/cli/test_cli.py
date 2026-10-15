"""The `ftl` CLI against a fake game side that speaks the bridge's file format."""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from collections.abc import Callable
from pathlib import Path

FTL = Path(__file__).resolve().parents[2] / "bin" / "ftl"

Responder = Callable[[str], str | None]
"""Maps Command text to a result ("ok" or "error\\t<reason>"), or None to stay silent."""


class FakeGame:
    """Plays the mod's side of the bridge: keeps the state file fresh and answers the inbox."""

    def __init__(self, base: Path, responder: Responder, state: dict[str, object]) -> None:
        self.live = base / "live"
        self.live.mkdir(parents=True)
        self.responder = responder
        self.state = state
        self.received: list[str] = []
        self._stop = threading.Event()
        self._offset = 0
        self._write_state()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _write_state(self) -> None:
        (self.live / "state.json").write_text(json.dumps(self.state))

    def _run(self) -> None:
        inbox = self.live / "inbox.txt"
        while not self._stop.is_set():
            self._write_state()
            if inbox.exists():
                data = inbox.read_text()[self._offset :]
                while "\n" in data:
                    line, data = data.split("\n", 1)
                    self._offset += len(line) + 1
                    cmd_id, _wall_ms, text = line.split("\t", 2)
                    self.received.append(text)
                    result = self.responder(text)
                    if result is not None:
                        with (self.live / "results.txt").open("a") as f:
                            f.write(f"{cmd_id}\t{result}\n")
            time.sleep(0.01)

    def start_run(self, name: str = "20261015-120000") -> Path:
        run = self.live.parent / "runs" / name
        run.mkdir(parents=True)
        (self.live / "run.txt").write_text(f"runs/{name}")
        return run

    def add_events(self, run: Path, *events: dict[str, object]) -> None:
        with (run / "events.jsonl").open("a") as f:
            for e in events:
                f.write(json.dumps(e) + "\n")

    def stop(self) -> None:
        self._stop.set()
        self._thread.join()


def ok(_text: str) -> str:
    return "ok"


class CliTest(unittest.TestCase):
    def setUp(self) -> None:
        self.base = Path(tempfile.mkdtemp())
        self.game: FakeGame | None = None

    def tearDown(self) -> None:
        if self.game:
            self.game.stop()

    def start_game(self, responder: Responder = ok, state: dict[str, object] | None = None) -> None:
        self.game = FakeGame(self.base, responder, state or {"in_run": True, "paused": False})

    def ftl(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = {**os.environ, "FTL_BENCH_DIR": str(self.base)}
        return subprocess.run(
            [sys.executable, str(FTL), *args], capture_output=True, text=True, env=env, timeout=30
        )

    def test_state_prints_the_observation(self) -> None:
        state: dict[str, object] = {"in_run": True, "paused": True, "ship": {"hull": 27}}
        self.start_game(state=state)
        r = self.ftl("state")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout), state)

    def test_game_not_running_when_no_bridge_files(self) -> None:
        r = self.ftl("state")
        self.assertEqual(r.returncode, 2)
        self.assertIn("game not running", r.stderr)

    def test_game_not_running_when_state_is_stale(self) -> None:
        live = self.base / "live"
        live.mkdir(parents=True)
        (live / "state.json").write_text("{}")
        old = time.time() - 60
        os.utime(live / "state.json", (old, old))
        for args in (["state"], ["pause"]):
            r = self.ftl(*args)
            self.assertEqual(r.returncode, 2, args)
            self.assertIn("game not running", r.stderr)

    def test_successful_command_is_silent(self) -> None:
        self.start_game()
        r = self.ftl("pause")
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
        assert self.game
        self.assertEqual(self.game.received, ["pause"])

    def test_failed_command_prints_reason_and_exits_1(self) -> None:
        self.start_game(lambda _t: "error\tunknown command: fly")
        r = self.ftl("fly", "away")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout, "")
        self.assertEqual(r.stderr.strip(), "unknown command: fly")
        assert self.game
        self.assertEqual(self.game.received, ["fly away"])

    def test_no_answer_means_game_not_responding(self) -> None:
        self.start_game(lambda _t: None)
        r = self.ftl("pause")
        self.assertEqual(r.returncode, 2)
        self.assertIn("game not responding", r.stderr)

    def test_wait_sleeps_for_the_time_the_mod_resolved(self) -> None:
        self.start_game(lambda t: "ok\t0.5" if t == "wait 0.5" else "ok")
        started = time.monotonic()
        r = self.ftl("wait", "0.5")
        elapsed = time.monotonic() - started
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertGreaterEqual(elapsed, 0.5)

    def test_cli_does_not_interpret_command_arguments(self) -> None:
        # Only the mod parses Commands: an ok without seconds means no sleep at all.
        self.start_game()
        started = time.monotonic()
        r = self.ftl("wait", "5")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertLess(time.monotonic() - started, 2)

    def test_bridge_error_is_reported_instead_of_not_running(self) -> None:
        live = self.base / "live"
        live.mkdir(parents=True)
        (live / "state.json").write_text("{}")
        (live / "bridge_error.txt").write_text("bridge.lua:42: attempt to index a nil value")
        old = time.time() - 60
        os.utime(live / "state.json", (old, old))
        r = self.ftl("state")
        self.assertEqual(r.returncode, 2)
        self.assertIn("mod error: bridge.lua:42: attempt to index a nil value", r.stderr)

    def test_rejected_wait_does_not_sleep(self) -> None:
        self.start_game(lambda _t: "error\twait takes 0.1 to 10 seconds in steps of 0.1")
        started = time.monotonic()
        r = self.ftl("wait", "9.99")
        self.assertEqual(r.returncode, 1)
        self.assertLess(time.monotonic() - started, 2)

    def events_out(self, *args: str) -> list[dict[str, object]]:
        r = self.ftl("events", *args)
        self.assertEqual(r.returncode, 0, r.stderr)
        return [json.loads(line) for line in r.stdout.splitlines()]

    def test_events_returns_each_event_exactly_once(self) -> None:
        self.start_game()
        assert self.game
        run = self.game.start_run()
        self.game.add_events(run, {"type": "a"}, {"type": "b"})
        self.assertEqual(self.events_out(), [{"type": "a"}, {"type": "b"}])
        self.assertEqual(self.events_out(), [])
        self.game.add_events(run, {"type": "c"})
        self.assertEqual(self.events_out(), [{"type": "c"}])

    def test_events_history_shows_the_last_n_regardless(self) -> None:
        self.start_game()
        assert self.game
        run = self.game.start_run()
        self.game.add_events(run, {"type": "a"}, {"type": "b"}, {"type": "c"})
        self.events_out()
        self.assertEqual(self.events_out("history", "2"), [{"type": "b"}, {"type": "c"}])
        self.assertEqual(self.events_out(), [])

    def test_a_new_run_starts_a_new_event_stream(self) -> None:
        self.start_game()
        assert self.game
        first = self.game.start_run("20261015-120000")
        self.game.add_events(first, {"type": "old"})
        self.events_out()
        second = self.game.start_run("20261015-130000")
        self.game.add_events(second, {"type": "new"})
        self.assertEqual(self.events_out(), [{"type": "new"}])

    def test_a_half_written_event_waits_for_the_next_call(self) -> None:
        self.start_game()
        assert self.game
        run = self.game.start_run()
        (run / "events.jsonl").write_text('{"type": "a"}\n{"type": "b"')
        self.assertEqual(self.events_out(), [{"type": "a"}])
        with (run / "events.jsonl").open("a") as f:
            f.write("}\n")
        self.assertEqual(self.events_out(), [{"type": "b"}])

    def test_events_before_any_run(self) -> None:
        self.start_game()
        r = self.ftl("events")
        self.assertEqual((r.returncode, r.stderr.strip()), (1, "no Run in progress"))

    def test_events_with_no_events_yet(self) -> None:
        self.start_game()
        assert self.game
        self.game.start_run()
        self.assertEqual(self.events_out(), [])

    def test_events_usage(self) -> None:
        self.start_game()
        assert self.game
        self.game.start_run()
        r = self.ftl("events", "history", "lots")
        self.assertEqual((r.returncode, r.stderr.strip()), (1, "usage: ftl events [history N]"))

    def test_rules_prints_the_primer_without_a_running_game(self) -> None:
        r = self.ftl("rules")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith("FTL Primer v"))
        for topic in ("Goal", "Rebel fleet", "Resources", "Systems", "Weapons", "Crew"):
            self.assertIn(topic, r.stdout)

    def test_primer_and_task_prompt_give_no_strategy_advice(self) -> None:
        prompts = FTL.parents[1] / "prompts"
        advice = ("should", "best", "recommend", "prioriti", "tip", "strategy", "good idea")
        for path in prompts.glob("*.md"):
            text = path.read_text().lower()
            for word in advice:
                self.assertNotIn(word, text, f"{path.name} contains '{word}'")

    def test_no_arguments_prints_usage(self) -> None:
        r = self.ftl()
        self.assertEqual(r.returncode, 1)
        self.assertIn("usage", r.stderr.lower())


if __name__ == "__main__":
    unittest.main()
