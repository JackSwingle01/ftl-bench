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

- `ftl state`: the current Observation as JSON: your ship (with its augments and cargo hold), the
  enemy ship, any open event, whether
  the game is paused, the game time and the sector. Use `jq` or any tool you like to filter it.
- `ftl events`: everything that happened since you last ran `ftl events`, one JSON object per line.
  While any of the game's red WARNING banners are up (e.g. "HULL CRITICAL", "INTRUDERS DETECTED"),
  the first line lists them: `{"type": "warnings", "active": [...]}`. `ftl state` has them too, as
  `warnings`.
- `ftl events history N`: the last N events, whether or not you have read them.
- `ftl map`, `ftl store`, `ftl upgrades`: the sector map (beacons linked to yours are marked
  `reachable`, `drive` says whether the FTL drive is ready, and at the exit `sectors` lists the
  next sectors), the store's stock (each item's `description` is the text the game shows when you
  hover it: what it does, its stats, its scrap value), and the upgrades on offer (each system's
  `description` and its `levels`, with the price of each level not yet bought and what it gives,
  as the upgrade screen lists them). Each also opens that window on screen, as it would for a player (not during an
  event, and the game refuses some windows mid-fight). While a window is open every other Command
  is refused until you `close` it, except `jump` from the map. `ftl state` shows the drive too.
- `ftl help`: this list of views, Commands and IDs. `ftl help <id>` prints the game's own hover
  text for anything of yours or in the open store: a system, weapon, drone, augment, cargo item,
  crew member or store item, e.g. `ftl help system:engines`, `ftl help weapon:0`.

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
- Travel and events: `jump <beacon>`, `jump <sector>` (from the exit beacon), `choose <choice>`
- Store and ship: `buy <item>`, `upgrade <system|reactor>`, `close` (shut the open map, upgrades or store window).
  `buy` needs `ftl store` first and `upgrade` needs `ftl upgrades` first

Run each as `ftl <command>`, e.g. `ftl power shields +2 && ftl weapon weapon:1 on`.

## IDs

Everything you can refer to has an ID of the form `type:index`, e.g. `room:4`, `door:7`,
`weapon:0`, `drone:1`, `augment:0`, `cargo:2`, `crew:101`, `system:shields`, `beacon:12`, `sector:5`, `choice:2`. Things on the enemy ship start
with `enemy:`, e.g. `enemy:room:3`. In `ftl state` every object has its `id` next to its `name`;
events and error messages write IDs as `room:4 (engines)`.

## Rules for you

Use only the `ftl` command to learn about or affect the game. Do not read the game's files, the
mod's files or anything under the FTL save folder.
