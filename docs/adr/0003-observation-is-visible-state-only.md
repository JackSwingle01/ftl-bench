# Observations expose only what a human player could see

Hyperspace exposes hidden information (enemy interior without sensors, event outcomes, unvisited beacon contents, RNG seeds). The Observation deliberately filters this out so scores reflect play a human could match. What counts as visible is researched and documented before the Observation format is fixed; changing it later invalidates past scores.

Values a human sees only as bars or gauges (hull, weapon charge, FTL charge, rebel fleet advance) are given as exact numbers: reading a bar is a vision skill, not strategy. The line is information, not precision. One deliberate exception: the map gives each beacon the number of jumps until the rebel fleet reaches it. A human only sees which beacons the fleet takes next jump and has to infer the rest; the operator chose to precompute it from the fleet's current advance. Anything not yet confirmed visible in-game is treated as hidden (see `docs/research/visible-state.md`).
