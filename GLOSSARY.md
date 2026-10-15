# ftl-bench

A benchmark that measures how well LLM agents play FTL: Faster Than Light, by giving them a text view of the live game and a command line to act with.

## Language

**Agent**:
The LLM under test, running inside a general coding-agent harness and playing only through the `ftl` CLI.
_Avoid_: Player, bot, model (when meaning the playing agent)

**Run**:
One playthrough of FTL from a fresh start to victory or defeat, played by one Agent on one Seed.
_Avoid_: Game, episode, playthrough

**Seed**:
The fixed value that determines a Run's sectors, beacons and events, so different Agents face the same game.

**Seed list**:
The published set of Seeds every Agent is scored on.

**Realtime mode**:
The game clock runs continuously; the Agent controls pausing like a human player does.
_Avoid_: Live mode

**Observation**:
The JSON the Agent reads describing the current game, limited to Visible state.
_Avoid_: State dump, snapshot (when meaning what the Agent sees)

**Visible state**:
Everything a human player could see on screen at that moment, and nothing more.
_Avoid_: Full state, game state (when meaning what the Agent may see)

**Command**:
A single action the Agent issues through the CLI, such as moving crew or choosing an event option. A Command takes effect immediately; there is no queue.
_Avoid_: Input, move

**Action log**:
The timestamped record of every Command an Agent issued during a Run, kept so the Run can be replayed.
_Avoid_: History, transcript

**Replay**:
Re-running a recorded Run by feeding its Action log back into the game on the same Seed.

**ID**:
The stable `type:index` handle for anything the Agent can refer to (e.g. `room:4`, `enemy:weapon:1`). Crew use the game's own permanent crew number (`crew:101`) so IDs never shift when someone dies. In the Observation every object carries its `id` beside its `name`, and references between objects use the bare ID; in events and messages an ID is written with its display name, e.g. `room:4 (engines)`.

**Primer**:
The short game-rules reference the Agent reads once via `ftl rules`: systems, weapon types, the rebel fleet, resources and the goal. It explains mechanics, never strategy.
_Avoid_: Tutorial, guide, tips

**Score**:
FTL's own end-of-Run score; the headline number, reported alongside sector reached and win rate.
