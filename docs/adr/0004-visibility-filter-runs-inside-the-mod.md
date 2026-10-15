# Hidden information is filtered inside the mod, never on disk

Agents have a shell and can read files, so any unfiltered game state written to disk would leak hidden information. The mod builds raw state in memory, passes it through a pure visibility filter, and writes only the Observation. The filter is a pure function so every Sensors/visibility rule can be unit-tested outside the game. A full-state dump, if ever added, is debug-only and off for scored Runs.
