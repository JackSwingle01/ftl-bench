# Fork Hyperspace to add missing Lua bindings

Stock Hyperspace Lua cannot jump to a beacon, commit an event choice, or buy from a store, and cannot simulate input. We add only those bindings in our fork (JackSwingle01/FTL-Hyperspace) rather than simulating OS mouse clicks, because synthetic clicks need a focused window and collide with a human touching the game during a Realtime-mode Run.
