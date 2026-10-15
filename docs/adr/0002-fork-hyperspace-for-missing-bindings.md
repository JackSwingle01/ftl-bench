# Fork Hyperspace to add missing Lua bindings

Stock Hyperspace Lua cannot jump to a beacon, commit an event choice, buy from a store, power weapons and drones the way the player does, or simulate input. We add only those bindings in our fork (JackSwingle01/FTL-Hyperspace) rather than simulating OS mouse clicks, because synthetic clicks need a focused window and collide with a human touching the game during a Realtime-mode Run.

The fork also exposes in-game input (mouse and key) and the main-menu buttons. The development launcher (`scripts/dev-run`) uses them to start or continue a Run without clicking. The bridge uses only the number keys, for `choose`: FTL's own shortcut for event choices, so no separate choice binding is needed. These calls are in-process, need no window focus and never collide with a human's mouse or keyboard.
