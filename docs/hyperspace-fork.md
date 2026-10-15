# Our Hyperspace fork

The bridge needs a few Lua bindings that stock Hyperspace doesn't expose (ADR 0002). They live on the
`llm-io` branch of [JackSwingle01/FTL-Hyperspace](https://github.com/JackSwingle01/FTL-Hyperspace),
based on Hyperspace v1.23.2. Every change is marked `ftl-bench` in `lua/modules/hyperspace.i`.

Added so far:

- `CApp` input functions `OnMouseMove`, `OnLButtonDown/Up`, `OnKeyDown/Up`, so a mod can press buttons inside the
  game. Only the dev autostart (`dev-probe/`) uses them; scored Runs never install it (see ADR 0002).
- `MainMenu.continueButton`, `MainMenu.startButton`, `ShipBuilder.startButton` (dev autostart).
- `WeaponSystem.PowerWeapon`, `WeaponSystem.DePowerWeapon`, `DroneSystem.PowerDrone` (power weapons and drones the way
  the UI does).
- `StarMap.readyToTravel`, `StarMap.finalSectorChoice`, `StarMap.NeighboringSector`, `StarMap.dangerZoneRadius`,
  `StarMap.GetNextDangerMove`, `Sector.type`, `Location.questLoc` (jumping, sector choice,
  the fleet's advance, quest markers).
- `CommandGui.gameover`, `CommandGui.alreadyWon`, `CommandGui.gameOverScreen`, `GameOver.bVictory` (game over and
  victory).

## Build and install

1. Push to `llm-io`, then `gh workflow run build-macos.yml -R JackSwingle01/FTL-Hyperspace --ref llm-io`.
2. When it succeeds: close FTL and run `scripts/install-hyperspace` (latest successful run) or
   `scripts/install-hyperspace <run-id>`. It swaps the library into `game/FTL.app` and re-signs the app.

To go back to stock Hyperspace, close FTL and copy
`downloads/hs-1.23.2/extracted/MacOS/Hyperspace.1.6.13.amd64.dylib` over
`game/FTL.app/Contents/MacOS/Hyperspace.1.6.13.amd64.dylib`, then re-sign with
`codesign -f -s - --timestamp=none --all-architectures --deep game/FTL.app`. The bridge needs the fork, so it will
report a bridge error on stock Hyperspace.

## Development loop

`scripts/dev-run [continue|new]` closes FTL, reinstalls the mod with the dev tools (`dev-probe/`), relaunches, and
presses Continue (or New Game) for you, then waits until a Run is live. Dev builds write raw state to disk and set
`dev_build: true` in the state view; never score a Run made with them.

`dev-run new` sets an existing saved Run aside as `hs_continue.sav.dev-bak` in the FTL save folder. To get it back,
close FTL and rename it to `hs_continue.sav`.
