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


def answer_events() -> None:
    """Answer open event windows with their first available choice; tests need the game running."""
    for _ in range(10):
        s = state()
        if "menu" in (s.get("paused_by") or []):
            raise unittest.SkipTest("a game window (e.g. a store) is open; closing it is #12")
        event = s.get("event")
        if not event:
            time.sleep(0.3)  # an event window can open a few frames after an arrival
            if not state().get("event"):
                return
            continue
        choice = next(c["id"] for c in event["choices"] if c["available"])
        r = ftl("choose", choice)
        assert r.returncode == 0, r.stderr
        time.sleep(0.5)
    raise AssertionError("event windows kept opening")


def act(*args: str) -> subprocess.CompletedProcess[str]:
    """Run a Command; if an event window opened first (common in fights), answer it and retry."""
    r = ftl(*args)
    for _ in range(5):
        if r.returncode == 0 or "event is open" not in r.stderr:
            break
        answer_events()
        r = ftl(*args)
    return r


def answer_events_and_unpause(case: unittest.TestCase) -> None:
    """Unpause after answering any open event."""
    answer_events()
    r = act("unpause")
    case.assertEqual(r.returncode, 0, r.stderr)


def runs_dir() -> Path:
    default = Path.home() / "Library/Application Support/FasterThanLight/ftlbench"
    return Path(os.environ.get("FTL_BENCH_DIR", default)) / "runs"


def newest_run() -> Path:
    return max(runs_dir().iterdir(), key=lambda p: p.stat().st_mtime)


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
        answer_events_and_unpause(self)
        self.assertEqual(state()["paused"], False)

    def test_game_time_advances_only_while_unpaused(self) -> None:
        ftl("pause")
        before = state()["game_time"]
        self.assertEqual(ftl("wait", "1").returncode, 0)
        self.assertEqual(state()["game_time"], before)
        answer_events_and_unpause(self)
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
        last = json.loads((newest_run() / "actions.jsonl").read_text().splitlines()[-1])
        self.assertEqual(last["command"], marker)
        self.assertEqual(last["result"], "ok")
        self.assertGreaterEqual(last["wall_ms"], int(start * 1000) - 1)
        self.assertIn("frame", last)


class LiveShipTest(unittest.TestCase):
    """#3: own ship layout, crew and doors.

    Assumes the Kestrel A: 17 rooms, 20 interior doors and 6 airlocks.
    """

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()

    def tearDown(self) -> None:
        ftl("door", "all", "close")
        ftl("pause")

    def test_kestrel_layout(self) -> None:
        ship = state()["ship"]
        self.assertEqual(len(ship["rooms"]), 17)
        self.assertEqual(len(ship["doors"]), 26)
        airlocks = [d for d in ship["doors"] if "space" in d["rooms"]]
        self.assertEqual(len(airlocks), 6)
        names = {r.get("name") for r in ship["rooms"]}
        for system in ("piloting", "engines", "shields", "weapons", "oxygen", "medbay", "sensors"):
            self.assertIn(system, names)
        self.assertEqual(ship["rooms"][0]["id"], "room:0")

    def test_crew_have_stable_ids_and_names(self) -> None:
        crew = state()["ship"]["crew"]
        self.assertGreaterEqual(len(crew), 1)
        for c in crew:
            self.assertRegex(c["id"], r"^crew:\d+$")
            self.assertTrue(c["name"])
            self.assertRegex(c["room"], r"^(enemy:)?room:\d+$")
            skills = {"piloting", "engines", "shields", "weapons", "repair", "combat"}
            self.assertEqual(set(c["skills"]), skills)

    def test_door_open_and_close(self) -> None:
        self.assertEqual(ftl("door", "door:0", "open").returncode, 0)
        time.sleep(0.1)
        self.assertTrue(state()["ship"]["doors"][0]["open"])
        self.assertEqual(ftl("door", "door:0", "close").returncode, 0)
        time.sleep(0.1)
        self.assertFalse(state()["ship"]["doors"][0]["open"])

    def test_door_all_opens_airlocks_too(self) -> None:
        self.assertEqual(ftl("door", "all", "open").returncode, 0)
        time.sleep(0.1)
        self.assertTrue(all(d["open"] for d in state()["ship"]["doors"]))

    def test_move_crew_to_another_room(self) -> None:
        answer_events()
        ship = state()["ship"]
        mover = ship["crew"][0]
        target = next(r["id"] for r in ship["rooms"] if r["id"] != mover["room"])
        r = act("move", mover["id"], target)
        self.assertEqual(r.returncode, 0, r.stderr)
        answer_events_and_unpause(self)
        now = mover
        for _ in range(100):
            time.sleep(0.1)
            now = next(c for c in state()["ship"]["crew"] if c["id"] == mover["id"])
            if now["room"] == target:
                break
        self.assertEqual(now["room"], target)

    def test_move_errors(self) -> None:
        r = ftl("move", "crew:999", "room:1")
        self.assertEqual((r.returncode, r.stderr.strip()), (1, "no crew:999"))


def system(name: str) -> dict[str, Any]:
    return next(x for x in state()["ship"]["systems"] if x["name"] == name)


class LivePowerTest(unittest.TestCase):
    """#4: power, systems, weapons. Assumes the Kestrel A loadout."""

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()

    def tearDown(self) -> None:
        for slot in ("weapon:0", "weapon:1"):
            ftl("weapon", slot, "off")
        ftl("pause")

    def test_kestrel_power_and_weapons(self) -> None:
        ship = state()["ship"]
        self.assertEqual(ship["reactor"]["max"], 8)
        names = [w["name"] for w in ship["weapons"]]
        self.assertEqual(names, ["Artemis Missiles", "Burst Laser Mark II"])
        self.assertEqual(ship["weapons"][1]["power"], 2)
        self.assertTrue(system("piloting")["subsystem"])
        self.assertGreaterEqual(ship["fuel"], 0)

    def test_power_a_system_down_and_up(self) -> None:
        before, used = system("shields")["power"], state()["ship"]["reactor"]["used"]
        self.assertEqual(ftl("power", "shields", "-2").returncode, 0)
        time.sleep(0.1)
        self.assertEqual(system("shields")["power"], before - 2)
        self.assertEqual(state()["ship"]["reactor"]["used"], used - 2)
        self.assertEqual(ftl("power", "shields", "+2").returncode, 0)
        time.sleep(0.1)
        self.assertEqual(system("shields")["power"], before)
        self.assertEqual(state()["ship"]["reactor"]["used"], used)

    def test_weapon_on_and_off(self) -> None:
        r = ftl("weapon", "weapon:1", "on")
        self.assertEqual(r.returncode, 0, r.stderr)
        time.sleep(0.1)
        self.assertTrue(state()["ship"]["weapons"][1]["powered"])
        self.assertEqual(system("weapons")["power"], 2)
        self.assertEqual(ftl("weapon", "weapon:1", "off").returncode, 0)
        time.sleep(0.1)
        self.assertFalse(state()["ship"]["weapons"][1]["powered"])

    def test_power_errors(self) -> None:
        r = ftl("power", "piloting", "+1")
        self.assertEqual(r.returncode, 1)
        self.assertIn("subsystem", r.stderr)


def new_events() -> list[dict[str, Any]]:
    r = ftl("events")
    assert r.returncode == 0, r.stderr
    return [json.loads(line) for line in r.stdout.splitlines()]


class LiveEventsTest(unittest.TestCase):
    """#5: events from the real game."""

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()

    def tearDown(self) -> None:
        ftl("door", "all", "close")
        ftl("pause")

    def test_events_are_new_only(self) -> None:
        new_events()
        self.assertEqual(new_events(), [])

    def test_suffocating_crew_produce_crew_hurt(self) -> None:
        # Vent a single airlock room with one crew member in it, so the rest of the ship keeps
        # its air for later tests.
        answer_events()
        ship = state()["ship"]
        airlocks = [d for d in ship["doors"] if "space" in d["rooms"]]
        room = airlocks[0]["rooms"][0]
        vents = [d["id"] for d in airlocks if d["rooms"][0] == room]
        crew = ship["crew"][0]
        home = crew["room"]
        self.assertEqual(act("move", crew["id"], room).returncode, 0)
        answer_events_and_unpause(self)
        for _ in range(100):
            time.sleep(0.1)
            if next(c for c in state()["ship"]["crew"] if c["id"] == crew["id"])["room"] == room:
                break
        new_events()
        for door in vents:
            act("door", door, "open")
        seen: list[dict[str, Any]] = []
        try:
            for _ in range(60):
                time.sleep(0.5)
                seen += new_events()
                if any(e["type"] == "crew_hurt" for e in seen):
                    break
        finally:
            for door in vents:
                act("door", door, "close")
            act("move", crew["id"], home)
        hurt = next(e for e in seen if e["type"] == "crew_hurt")
        self.assertEqual(hurt["crew"].split(" ")[0], crew["id"])
        for key in ("frame", "game_time", "wall_s", "health", "health_max"):
            self.assertIn(key, hurt)
        r = ftl("events", "history", "1")
        self.assertEqual(len(r.stdout.splitlines()), 1)


def view(name: str) -> dict[str, Any]:
    r = ftl(name)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


class LiveNavigationTest(unittest.TestCase):
    """#10: the sector map and jumping."""

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()

    def tearDown(self) -> None:
        ftl("pause")

    def test_map_has_one_current_beacon_one_exit_and_symmetric_links(self) -> None:
        beacons = {b["id"]: b for b in view("map")["beacons"]}
        self.assertGreater(len(beacons), 5)
        self.assertEqual(sum(1 for b in beacons.values() if b.get("current")), 1)
        self.assertEqual(sum(1 for b in beacons.values() if b.get("exit")), 1)
        for b in beacons.values():
            for link in b["links"]:
                self.assertIn(b["id"], beacons[link]["links"])

    def test_jump_to_a_linked_beacon_uses_one_fuel(self) -> None:
        answer_events()
        jumps = view("jumps")
        if not jumps["ready"]:
            self.skipTest(f"can't jump here: {jumps.get('not_ready')}")
        target, fuel = jumps["beacons"][0], jumps["fuel"]
        r = ftl("jump", target)
        self.assertEqual(r.returncode, 0, r.stderr)
        answer_events_and_unpause(self)
        current = None
        for _ in range(150):
            time.sleep(0.1)
            current = next(b["id"] for b in view("map")["beacons"] if b.get("current"))
            if current == target:
                break
        self.assertEqual(current, target)
        self.assertEqual(view("jumps")["fuel"], fuel - 1)

    def test_jump_refuses_unlinked_beacons(self) -> None:
        here = next(b for b in view("map")["beacons"] if b.get("current"))
        far = next(
            b["id"]
            for b in view("map")["beacons"]
            if b["id"] not in here["links"] and b is not here
        )
        r = ftl("jump", far)
        self.assertEqual(r.returncode, 1)
        self.assertIn("is not linked", r.stderr)


class LiveEventChoiceTest(unittest.TestCase):
    """#11: answer a real event window."""

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()

    def tearDown(self) -> None:
        ftl("pause")

    def test_an_event_shows_choices_and_choose_answers_it(self) -> None:
        answer_events()
        jumps = view("jumps")
        if not jumps["ready"]:
            self.skipTest(f"can't jump to reach an event: {jumps.get('not_ready')}")
        self.assertEqual(ftl("jump", jumps["beacons"][0]).returncode, 0)
        ftl("unpause")
        event = None
        for _ in range(100):
            time.sleep(0.1)
            event = state().get("event")
            if event:
                break
        if not event:
            self.skipTest("this beacon had no event window")
        self.assertTrue(event["text"])
        self.assertEqual(event["choices"][0]["id"], "choice:0")
        first_text = event["text"]
        choice = next(c["id"] for c in event["choices"] if c["available"])
        self.assertEqual(ftl("choose", choice).returncode, 0)
        time.sleep(0.5)
        after = state().get("event")
        self.assertTrue(after is None or after["text"] != first_text)
        history = ftl("events", "history", "20").stdout.splitlines()
        self.assertIn("event", [json.loads(line)["type"] for line in history])

    def test_choose_without_an_event(self) -> None:
        answer_events()
        r = ftl("choose", "choice:0")
        self.assertEqual((r.returncode, r.stderr.strip()), (1, "no event is open"))


def find_enemy() -> dict[str, Any] | None:
    """Jump (answering events) until an enemy ship is present; None if none turns up."""
    for _ in range(8):
        answer_events()
        enemy = state().get("enemy")
        if enemy:
            return enemy
        jumps = view("jumps")
        if not jumps["ready"] or ftl("jump", jumps["beacons"][0]).returncode != 0:
            return None
        ftl("unpause")
        for _ in range(100):
            time.sleep(0.1)
            if state().get("event") or state().get("enemy"):
                break
    return None


class LiveEnemyTest(unittest.TestCase):
    """#6: a real enemy ship, seen only as far as our Sensors allow (Kestrel: Sensors 1)."""

    enemy: dict[str, Any]

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()
        enemy = find_enemy()
        if not enemy:
            raise unittest.SkipTest("no enemy ship found within 8 jumps")
        cls.enemy = enemy

    def tearDown(self) -> None:
        ftl("pause")

    def test_1_unmanned_sensors_1_hide_the_enemy_interior(self) -> None:
        ftl("pause")
        e = state()["enemy"]
        if e["sensors_level"] >= 2:
            self.skipTest("Sensors already manned")
        self.assertIsInstance(e["hull"], int)
        self.assertTrue(e["rooms"] and e["doors"] and e["systems"])
        for room in e["rooms"]:
            self.assertRegex(room["id"], r"^enemy:room:\d+$")
            self.assertNotIn("oxygen", room, room)
        self.assertEqual(e["crew"], [])
        self.assertEqual(e["weapons"], "needs Sensors level 3")
        for s in e["systems"]:
            self.assertEqual(set(s), {"id", "name", "room"})

    def test_2_manning_sensors_reveals_the_interior(self) -> None:
        answer_events()
        ship = state()["ship"]
        sensors_room = system("sensors")["room"]
        r = None
        for mover in (c for c in ship["crew"] if c["room"] != sensors_room):
            r = act("move", mover["id"], sensors_room)
            if r.returncode == 0:
                break
        if r is None or r.returncode != 0:
            self.skipTest(f"no crew can reach Sensors now: {r.stderr.strip() if r else 'no crew'}")
        act("unpause")
        e: dict[str, Any] = {}
        for _ in range(100):
            time.sleep(0.1)
            e = state().get("enemy") or {}
            if e.get("sensors_level", 0) >= 2:
                break
        ftl("pause")
        if not e:
            self.skipTest("the enemy left or was destroyed")
        if e["sensors_level"] == 0:
            self.skipTest("our Sensors are down (damaged, ionized or in a nebula)")
        self.assertEqual(e["sensors_level"], 2)
        self.assertIn("oxygen", e["rooms"][0])  # level 2 shows the interior
        for crew in e["crew"]:  # automated ships have no crew at all
            self.assertIn("name", crew)


@unittest.skipUnless(
    os.environ.get("FTL_LIVE_DESTRUCTIVE"), "ends the Run; set FTL_LIVE_DESTRUCTIVE=1"
)
class LiveGameOverTest(unittest.TestCase):
    """#9: lose the Run on purpose (vent every room) and check the game-over record."""

    @classmethod
    def setUpClass(cls) -> None:
        LiveGameTest.setUpClass()

    def test_losing_writes_game_over_state_event_and_score(self) -> None:
        run_dir = newest_run()
        self.assertEqual(ftl("door", "all", "open").returncode, 0)
        r = ftl("unpause")
        self.assertEqual(r.returncode, 0, r.stderr)
        s = state()
        for _ in range(600):  # crew suffocate in a couple of minutes
            s = state()
            if s.get("game_over"):
                break
            time.sleep(1)
        self.assertEqual(s.get("game_over"), True)
        self.assertEqual(s["victory"], False)
        self.assertIsInstance(s["score"], int)
        events = [json.loads(line) for line in (run_dir / "events.jsonl").read_text().splitlines()]
        self.assertEqual(events[-1]["type"], "game_over")
        record = json.loads((run_dir / "score.json").read_text())
        self.assertEqual(
            (record["victory"], record["score"], record["sector"]),
            (False, s["score"], s["sector"]),
        )


def load_tests(
    loader: unittest.TestLoader, _tests: unittest.TestSuite, _pattern: str | None
) -> unittest.TestSuite:
    """Quiet start-beacon tests first; tests that travel or seek fights last, so a fight
    doesn't disturb the rest."""
    order = (
        LiveGameTest,
        LiveShipTest,
        LivePowerTest,
        LiveEventsTest,
        LiveNavigationTest,
        LiveEventChoiceTest,
        LiveEnemyTest,
        LiveGameOverTest,
    )
    return unittest.TestSuite(loader.loadTestsFromTestCase(case) for case in order)


if __name__ == "__main__":
    unittest.main()
