FTL Primer v1

How FTL: Faster Than Light works. This describes the rules of the game, not how to play it.

## Goal

Your ship carries data to the Federation fleet. The Run crosses 8 sectors. In sector 8 the Rebel
Flagship must be destroyed; it fights in three phases. You win when the Flagship is destroyed.
You lose when your hull reaches 0 or every crew member is dead.

## Time

The game runs in real time. `ftl pause` stops the clock; while paused you can still read the game
and give Commands. Nothing moves, charges or repairs while paused. An open event window also pauses
the game until a choice is made.

## Map and travel

- Each sector is a map of beacons joined by links. `ftl jump <beacon>` moves to a linked beacon.
- Every jump costs 1 fuel. The FTL drive must be fully charged to jump; it charges while Engines
  are powered and Piloting is manned. With no fuel you cannot jump.
- Every sector has an exit beacon. Jumping from it leads to the next sector; at the exit you pick
  which sector comes next.
- Arriving at a beacon can bring an event, a ship, a store or nothing.

## Rebel fleet

The Rebel fleet sweeps across each sector from left to right, advancing with every jump. Beacons it
has reached become fleet-controlled: they hold Rebel warships and give little or nothing for
winning. `ftl map` shows for each beacon how many jumps remain before the fleet reaches it.

## Resources

- Hull: your ship's health. 0 hull ends the Run.
- Scrap: money. Earned from fights and events; spent at stores and on upgrades.
- Fuel: 1 per jump.
- Missiles: used by missile and bomb weapons, one per shot.
- Drone parts: used each time a drone is deployed.

## Power and systems

- The reactor has a fixed number of power bars. Systems that use power take bars from it;
  `ftl power <system> +N|-N` moves bars. A system works at the level of the power it has.
- Subsystems (Piloting, Sensors, Doors, Battery) use no reactor power; their level is what they
  provide.
- Shields: every 2 power makes one shield layer. Each layer stops one incoming projectile or
  reduces a beam, then recharges over a few seconds. Shield power moves 2 at a time.
- Engines: raise evasion and charge the FTL drive.
- Oxygen: refills air in every room. Without it, air drains and crew suffocate.
- Weapons and Drones: hold weapons and drones; each one needs its own power to run.
- Medbay: heals crew standing in it.
- Piloting: needed to dodge and to jump. Unmanned, the ship cannot dodge unless Piloting has been
  upgraded, which adds an autopilot with reduced evasion.
- Sensors: show your own ship's interior; higher levels show more of the enemy ship.
- Doors: control door strength against boarders.
- Optional systems that can be bought or found later: Teleporter (send crew to the enemy ship),
  Cloaking (become briefly untargetable), Hacking, Mind Control, Battery (temporary extra power),
  Clone Bay (revives dead crew).
- Every ship starts with Piloting, Engines, Oxygen and Weapons; most also start with Shields,
  Medbay, Doors and Sensors. `ftl state` lists the systems your ship has.
- Damage to a room damages the system in it and lowers its usable power until repaired.
- Ion damage locks a system's power for a while and strips shield layers; it does no hull damage.

## Weapons

- Each weapon charges for a number of seconds while powered, then fires at its target room.
  `ftl target` picks the room; `ftl autofire on` fires weapons as soon as they charge.
- Lasers: projectiles, often several per volley. Each shield layer stops one.
- Ion weapons: remove shield layers and ionize systems, no hull damage.
- Missiles: pass through normal shield layers, use a missile per shot. A Zoltan shield blocks them,
  and defense drones can shoot them down.
- Beams: never miss. They draw a line across rooms; each shield layer reduces their damage by 1,
  so a beam does nothing if shields are at least as strong as its damage.
- Bombs: teleport into a room, ignoring normal shield layers; use a missile each. They never miss.
  A Zoltan shield blocks them.
- Flak: fires several projectiles at once.
- Evasion: each projectile has a chance to miss equal to the target's evasion. Beams and bombs
  never miss.

## Crew

- Crew in a system's room man it: manned systems work better (faster weapon charge, more
  evasion, faster shield recharge). Crew skills improve with use.
- Crew repair damaged systems, put out fires and fight boarders in the room they are in.
- Fires spread, damage systems and burn crew; they need oxygen to burn.
- Hull breaches drain air from their room until repaired.
- Doors can be opened and closed; airlocks open to space and drain the rooms behind them.
- Races differ: e.g. Mantis fight well, Engi repair well, Rockmen resist fire, Zoltan add power to
  the system they man, Slugs see into nearby rooms, Crystal resist suffocation, Lanius drain air.

## Events and ships

- Events show text and numbered choices; `ftl choose <choice>` answers. Outcomes are not shown
  in advance. Blue options appear when your ship has the needed crew, system or equipment.
- Enemy ships can be fought, can surrender (offering a reward to stop), or can try to flee by
  charging their own FTL drive.
- Destroying a ship or killing its whole crew ends the fight; killing the crew gives more reward.

## Stores and upgrades

- Stores sell weapons, drones, systems, augments, crew, fuel, missiles, drone parts and hull
  repair, and buy items back for half price. `ftl store` lists what is on sale.
- `ftl upgrade <system|reactor>` spends scrap to raise a system's level or the reactor's size.
