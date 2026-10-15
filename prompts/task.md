# FTL benchmark task prompt v1

You are playing FTL: Faster Than Light. The game is running right now in a window on this
computer, and you control it only through the `ftl` command in your shell.

## Your goal

Reach sector 8 and destroy the Rebel Flagship. The Run ends in a loss if your hull reaches 0 or
your whole crew dies. Play the Run to its end.

## Start here

Run `ftl rules` once. It explains how the game works.

## Time works like the real game

The game runs in real time, including while you think. `ftl pause` stops the clock and
`ftl unpause` restarts it. While paused you can read the game and give Commands; time only passes
when unpaused. `ftl wait <seconds>` (0.1 to 10, in steps of 0.1) lets real time pass on purpose.
An open event window keeps the game paused until you answer it.

## Reading the game

- `ftl state`: the current Observation as JSON: your ship, the enemy ship, any open event, whether
  the game is paused, the game time and the sector. Use `jq` or any tool you like to filter it.
- `ftl events`: everything that happened since you last ran `ftl events`, one JSON object per line.
- `ftl events history N`: the last N events, whether or not you have read them.
- `ftl map`, `ftl jumps`, `ftl store`, `ftl upgrades`: the sector map, the beacons you can jump to
  now, the store's stock, and the upgrades on offer.

You only see what a human player could see on screen. Anything else is left out or marked
`hidden` with a reason.

## Acting

Every Command takes effect immediately. It prints nothing and exits 0 when it works, and prints the
reason and exits non-zero when it does not, so `&&` chains stop at the first failure.

- Time: `pause`, `unpause`, `wait <seconds>`
- Power: `power <system> +N|-N`, `weapon <weapon> on|off`, `drone <drone> on|off`
- Combat: `target <weapon> <enemy:room>`, `target <beam weapon> <enemy:room> <enemy:room>`,
  `untarget <weapon>`, `autofire on|off`
- Crew and doors: `move <crew> <room>`, `door <door|all> open|close`
- Abilities: `cloak`, `battery`, `hack <enemy:room>`, `mindcontrol <enemy:crew>`,
  `teleport send|return <room>`
- Travel and events: `jump <beacon>`, `choose <choice>`
- Store and ship: `buy <item>`, `upgrade <system|reactor>`, `close` (leave an open store window)

Run each as `ftl <command>`, e.g. `ftl power shields +2 && ftl weapon weapon:1 on`.

## IDs

Everything you can refer to has an ID of the form `type:index`, e.g. `room:4`, `door:7`,
`weapon:0`, `crew:101`, `system:shields`, `beacon:12`, `choice:2`. Things on the enemy ship start
with `enemy:`, e.g. `enemy:room:3`. In `ftl state` every object has its `id` next to its `name`;
events and error messages write IDs as `room:4 (engines)`.

## Rules for you

Use only the `ftl` command to learn about or affect the game. Do not read the game's files, the
mod's files or anything under the FTL save folder.
