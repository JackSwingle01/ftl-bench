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
- Oxygen: refills air in every room. Without it, air drains and crew suffocate. Crew in a room with
  5% O2 or less take 6.4 damage per second (Crystal half, Lanius immune). A room drains from fires,
  breaches, open airlocks, open doors to thinner rooms, or unpowered Oxygen.
- Weapons and Drones: hold weapons and drones; each one needs its own power to run.
- Medbay: the only way to heal crew. Damaged crew do not recover on their own; they must stand in
  the powered Medbay room. Upgrades heal faster.
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
- Flak: fires several projectiles at once at an area, so it can miss a small room. Each projectile
  removes a shield layer like a laser. Defense drones can shoot it down.
- Crystal: like lasers, but each shard pierces one shield layer; with more layers it removes one.
- Crew damage is 15 per point of system damage, to everyone in the room hit. Beams hurt only crew
  standing on a tile they cross.
- Evasion: each projectile has a chance to miss equal to the target's evasion. Beams and bombs
  never miss.

### Weapon stats

Power bars / charge seconds / shots per volley x damage per shot / chance %. Damage is hull and
system damage per shot. Fire and breach chances are per hit; a hit cannot cause both.

Lasers (hit shields, then room):
- Basic Laser 1p/10s 1x1 fire10; Dual Lasers 1p/10s 2x1 fire10
- Burst Laser I 2p/11s 2x1 fire10; II 2p/12s 3x1 fire10; III 4p/19s 5x1
- Heavy Laser I 1p/9s 1x2 fire30 breach21; II 3p/13s 2x2 fire30 breach21
- Heavy Pierce I 2p/10s 1x2 fire30 breach21, pierces shields
- Hull Laser I 2p/14s 2x1 breach20; II 3p/15s 3x1 fire10 breach27 (hull damage doubled)
- Chain Laser 2p/16s 2x1 fire10; Chain Vulcan 4p/11s 1x1 fire10 (both charge faster as they fire)
- Laser Charger (S) 1p/5.5s, Charger 2p/6s: 1-2 shots x1; Charger II 3p/5s 1-4 shots x1 fire10
Flak (area, hit shields then room):
- Adv. Flak 1p/8s 3x1; Flak I 2p/10s 3x1; Flak II 3p/21s 7x1
Ion (shield layers and system power, no hull damage; ion damage is shield layers removed or
power bars locked):
- Ion Blast 1p/8s ion1 stun10; Ion Blast II 3p/4s ion1 stun10; Heavy Ion 2p/13s ion2 stun20
- Ion Stunner 1p/10s ion1 stuns crew 100%; Ion Charger 2p/6s 1-3 shots ion1; Chain Ion 3p/14s ion1-4
Crystal (pierce one shield layer):
- Crystal Burst I 2p/15s 2x1 breach10 stun10; II 3p/17s 3x1 breach10 stun10
- Heavy Crystal I 1p/13s 1x2 breach10 stun20; II 3p/19s 1x4 breach100 stun20
Missiles (ignore shields, 1 missile per shot):
- Leto 1p/9s 1x1 fire10 breach9; Artemis 1p/11s 1x2 fire10 breach9
- Hermes 3p/14s 1x3 fire30 breach14; Pegasus 3p/20s 2x2 fire30 breach14
- Breach Missiles 3p/22s 1x4 fire30 breach56; Hull Missile 2p/17s 1x2 breach27 (hull damage doubled)
- Swarm Missiles 2p/7s 1-3 shots x1 fire10 breach9
Bombs (teleport into room, no hull damage, 1 missile per shot; damage is to systems):
- Small Bomb 1p/13s sys2 fire10; Breach Bomb I 1p/9s sys1 breach100; II 2p/17s sys3 breach100
- Fire Bomb 2p/15s fire100; Ion Bomb 1p/22s ion, stun20; Stun Bomb 1p/17s stuns crew
- Lock Bomb 1p/15s locks doors; Healing Burst 1p/18s heals crew in room; Repair Burst 1p/14s repairs
  systems in room (the last two can target your own ship)
Beams (never miss, damage drops 1 per shield layer; damage is hull and system damage per room hit):
- Mini Beam 1p/12s dmg1 fire10 short; Pike Beam 2p/16s dmg1 long; Hull Beam 2p/14s dmg1 (hull x2)
- Halberd Beam 3p/17s dmg2; Glaive Beam 4p/25s dmg3
- Fire Beam 2p/20s no damage, fire80; Anti-Bio Beam 2p/16s no system damage, 60 crew damage per tile

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
