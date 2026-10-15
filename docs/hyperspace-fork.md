# Our Hyperspace fork

The bridge needs a few Lua bindings that stock Hyperspace doesn't expose (ADR 0002). They live on the
`llm-io` branch of [JackSwingle01/FTL-Hyperspace](https://github.com/JackSwingle01/FTL-Hyperspace),
based on Hyperspace v1.23.2. Every change is marked `ftl-bench` in `lua/modules/hyperspace.i`.

Added so far:

- `CApp` input functions (`OnMouseMove`, `OnLButtonDown/Up`, `OnRButtonDown/Up`, `OnKeyDown/Up`, ...) so a mod can
  press buttons inside the game. Only the dev autostart uses them.
- `MainMenu.continueButton`, `MainMenu.startButton`, `ShipBuilder.startButton`.
- `CommandGui.gameover`, `CommandGui.alreadyWon`, `CommandGui.gameOverScreen`, `GameOver.bVictory`.
- `TopScore.victory`, `TopScore.difficulty`, `TopScore.advancedContent`.

## Build and install

1. Push to `llm-io`, then `gh workflow run build-macos.yml -R JackSwingle01/FTL-Hyperspace --ref llm-io`.
2. When it succeeds: close FTL and run `scripts/install-hyperspace` (latest successful run) or
   `scripts/install-hyperspace <run-id>`. It swaps the library into `game/FTL.app` and re-signs the app.

## Development loop

`scripts/dev-run [continue|new]` closes FTL, reinstalls the mod with the dev tools (`dev-probe/`), relaunches, and
presses Continue (or New Game) for you, then waits until a Run is live. Dev builds write raw state to disk and set
`dev_build: true` in the state view; never score a Run made with them.
