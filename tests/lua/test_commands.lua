local t = ...
local C = FtlBench.Commands

---@return RawState
local function raw_in_run()
    return {
        in_run = true,
        frame = 10,
        game_time = 1,
        pause = { manual = false, event = false, menu = false },
        player = { hull = 30, hull_max = 30, scrap = 0 },
    }
end

t.test("pause and unpause resolve to actions", function()
    t.eq(C.plan("pause", raw_in_run()), { kind = "pause" })
    t.eq(C.plan("unpause", raw_in_run()), { kind = "unpause" })
end)

t.test("wait accepts 0.1 to 10 seconds in 0.1 steps", function()
    t.eq(C.plan("wait 0.1", raw_in_run()), { kind = "wait", seconds = 0.1 })
    t.eq(C.plan("wait 2.5", raw_in_run()), { kind = "wait", seconds = 2.5 })
    t.eq(C.plan("wait 10", raw_in_run()), { kind = "wait", seconds = 10 })
end)

t.test("wait rejects out-of-range, too-fine and non-numeric values", function()
    local msg = "wait takes 0.1 to 10 seconds in steps of 0.1"
    t.eq(select(2, C.plan("wait 0", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait 10.1", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait 2.55", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait soon", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait", raw_in_run())), msg)
end)

t.test("unknown Commands are rejected by name", function()
    local action, err = C.plan("fly away", raw_in_run())
    t.eq(action, nil)
    t.eq(err, "unknown command: fly")
end)

t.test("Commands need a Run in progress", function()
    local raw = raw_in_run()
    raw.in_run = false
    t.eq(select(2, C.plan("pause", raw)), "no Run in progress")
end)

t.test("unpause is refused while an event is open", function()
    local raw = raw_in_run()
    raw.pause.event = true
    t.eq(select(2, C.plan("unpause", raw)), "an event is open; answer it first")
end)

t.test("extra whitespace is tolerated", function()
    t.eq(C.plan("  wait   3 ", raw_in_run()), { kind = "wait", seconds = 3 })
end)

-- #3: move and door. Ship: rooms 0-2, interior doors 0-1, airlock door 2.
-- Crew: Maria (uid 101) in room 0, Sam (uid 102) aboard the enemy ship.
local function raw_with_interior()
    local raw = raw_in_run()
    raw.player.rooms = {
        { id = 0, x = 0, y = 0, w = 35, h = 35, oxygen = 100, fires = 0, breaches = 0 },
        { id = 1, x = 35, y = 0, w = 35, h = 35, oxygen = 100, fires = 0, breaches = 0 },
        { id = 2, x = 70, y = 0, w = 35, h = 35, oxygen = 100, fires = 0, breaches = 0 },
    }
    raw.player.doors = {
        { id = 0, room1 = 0, room2 = 1, open = false },
        { id = 1, room1 = 1, room2 = 2, open = false },
        { id = 2, room1 = 2, room2 = -1, open = false },
    }
    local skills = { 1, 1, 1, 1, 1, 1 }
    raw.player.crew = {
        {
            uid = 101,
            name = "Maria",
            species = "human",
            health = 100,
            health_max = 100,
            room = 0,
            on_enemy_ship = false,
            skills = skills,
        },
        {
            uid = 102,
            name = "Sam",
            species = "human",
            health = 100,
            health_max = 100,
            room = 4,
            on_enemy_ship = true,
            skills = skills,
        },
    }
    return raw
end

t.test("move resolves a crew member and a room on our ship", function()
    t.eq(
        C.plan("move crew:101 room:2", raw_with_interior()),
        { kind = "move", crew = 101, room = 2, enemy = false }
    )
end)

t.test("move sends crew aboard the enemy ship to enemy rooms", function()
    t.eq(
        C.plan("move crew:102 enemy:room:1", raw_with_interior()),
        { kind = "move", crew = 102, room = 1, enemy = true }
    )
end)

t.test("move rejects unknown crew, unknown rooms and the wrong ship", function()
    local raw = raw_with_interior()
    t.eq(select(2, C.plan("move crew:999 room:1", raw)), "no crew:999")
    t.eq(select(2, C.plan("move crew:101 room:9", raw)), "no room:9")
    t.eq(
        select(2, C.plan("move crew:101 enemy:room:1", raw)),
        "crew:101 (Maria) is on our ship; use a room:N"
    )
    t.eq(
        select(2, C.plan("move crew:102 room:1", raw)),
        "crew:102 (Sam) is on the enemy ship; use an enemy:room:N"
    )
end)

t.test("move refuses dead crew by name", function()
    local raw = raw_with_interior()
    raw.player.crew[1].dead = true
    t.eq(select(2, C.plan("move crew:101 room:1", raw)), "crew:101 (Maria) is dead")
end)

t.test("move explains malformed IDs", function()
    local raw = raw_with_interior()
    t.eq(select(2, C.plan("move Maria room:1", raw)), "expected a crew ID like crew:101, got Maria")
    t.eq(
        select(2, C.plan("move crew:101 engines", raw)),
        "expected a room ID like room:4, got engines"
    )
    t.eq(select(2, C.plan("move crew:101", raw)), "usage: move <crew> <room>")
end)

t.test("door opens or closes one door, including airlocks", function()
    local raw = raw_with_interior()
    t.eq(C.plan("door door:1 open", raw), { kind = "door", doors = { 1 }, open = true })
    t.eq(C.plan("door door:2 close", raw), { kind = "door", doors = { 2 }, open = false })
end)

t.test("door all affects every door", function()
    t.eq(
        C.plan("door all open", raw_with_interior()),
        { kind = "door", doors = { 0, 1, 2 }, open = true, all = true }
    )
end)

t.test("door rejects unknown doors and bad states", function()
    local raw = raw_with_interior()
    t.eq(select(2, C.plan("door door:7 open", raw)), "no door:7")
    t.eq(select(2, C.plan("door door:1 ajar", raw)), "usage: door <door|all> open|close")
    t.eq(select(2, C.plan("door 1 open", raw)), "expected a door ID like door:3 or all, got 1")
end)

-- #4: power, weapon, drone. Reactor 5 of 8 used (3 free).
-- Systems: shields 2/2, piloting (subsystem), weapons 1 power with cap 3, engines ionized 1/2, drones 1/2.
local function raw_with_systems()
    local raw = raw_with_interior()
    local ship = raw.player
    ship.reactor = { used = 5, max = 8 }
    ship.systems = {
        {
            type = 0,
            room = 0,
            power = 2,
            level = 2,
            cap = 2,
            damage = 0,
            ion = 0,
            uses_reactor = true,
        },
        {
            type = 6,
            room = 1,
            power = 1,
            level = 1,
            cap = 1,
            damage = 0,
            ion = 0,
            uses_reactor = false,
        },
        {
            type = 3,
            room = 2,
            power = 1,
            level = 3,
            cap = 3,
            damage = 0,
            ion = 0,
            uses_reactor = true,
        },
        {
            type = 1,
            room = 2,
            power = 1,
            level = 2,
            cap = 2,
            damage = 0,
            ion = 1,
            uses_reactor = true,
        },
        {
            type = 4,
            room = 1,
            power = 1,
            level = 2,
            cap = 2,
            damage = 0,
            ion = 0,
            uses_reactor = true,
        },
    }
    ship.weapons = {
        {
            name = "Artemis Missiles",
            powered = true,
            power = 1,
            charge = 0,
            charge_time = 11,
            missiles = true,
        },
        {
            name = "Burst Laser Mark II",
            powered = false,
            power = 2,
            charge = 0,
            charge_time = 12,
            missiles = false,
        },
        {
            name = "Heavy Laser",
            powered = false,
            power = 3,
            charge = 0,
            charge_time = 9,
            missiles = false,
        },
    }
    ship.drones = { { name = "Defense Drone I", powered = true, deployed = true } }
    return raw
end

t.test("power changes a system by name or system ID", function()
    local raw = raw_with_systems()
    raw.player.systems[5].type = 2 -- an oxygen system with 1 power
    t.eq(C.plan("power oxygen -1", raw), { kind = "power", system = 2, delta = -1 })
    t.eq(C.plan("power system:shields -2", raw), { kind = "power", system = 0, delta = -2 })
end)

t.test("shields power moves a whole layer (2 power) at a time, as in the game", function()
    t.eq(
        select(2, C.plan("power shields -1", raw_with_systems())),
        "system:shields power changes 2 at a time (one layer)"
    )
end)

t.test("power respects free reactor power and the system's cap", function()
    local raw = raw_with_systems()
    t.eq(
        select(2, C.plan("power shields +2", raw)),
        "system:shields can take at most 2 power (has 2)"
    )
    raw.player.systems[1].power = 0
    raw.player.reactor.used = 7
    t.eq(
        select(2, C.plan("power shields +2", raw)),
        "system:shields needs 2 reactor power (1 free)"
    )
end)

t.test("power can't drop below zero", function()
    t.eq(
        select(2, C.plan("power shields -4", raw_with_systems())),
        "system:shields has only 2 power"
    )
end)

t.test("power refuses subsystems, ionized systems and weapon/drone systems", function()
    local raw = raw_with_systems()
    t.eq(
        select(2, C.plan("power piloting +1", raw)),
        "system:piloting is a subsystem; its power follows its level"
    )
    t.eq(
        select(2, C.plan("power engines -1", raw)),
        "system:engines is ionized; its power is locked until the ion wears off"
    )
    t.eq(
        select(2, C.plan("power weapons +1", raw)),
        "power weapons by weapon: use weapon <weapon> on|off"
    )
    t.eq(
        select(2, C.plan("power drones -1", raw)),
        "power drones by drone: use drone <drone> on|off"
    )
end)

t.test("power explains unknown systems and bad amounts", function()
    local raw = raw_with_systems()
    t.eq(select(2, C.plan("power cloaking +1", raw)), "no system:cloaking on this ship")
    t.eq(select(2, C.plan("power warp +1", raw)), "unknown system: warp")
    t.eq(select(2, C.plan("power shields 2", raw)), "usage: power <system> +N|-N")
    t.eq(select(2, C.plan("power shields +0", raw)), "usage: power <system> +N|-N")
end)

t.test("weapon on/off resolves a weapon slot", function()
    local raw = raw_with_systems()
    t.eq(C.plan("weapon weapon:1 on", raw), { kind = "weapon", slot = 1, on = true })
    t.eq(C.plan("weapon weapon:0 off", raw), { kind = "weapon", slot = 0, on = false })
end)

t.test("weapon on needs reactor power and room in the weapons system", function()
    local raw = raw_with_systems()
    t.eq(
        select(2, C.plan("weapon weapon:2 on", raw)),
        "weapon:2 (Heavy Laser) needs 3 power; system:weapons has room for 2 more"
    )
    raw.player.reactor.used = 7
    t.eq(
        select(2, C.plan("weapon weapon:1 on", raw)),
        "weapon:1 (Burst Laser Mark II) needs 2 power; 1 reactor power free"
    )
end)

t.test("weapon and drone explain bad IDs and states", function()
    local raw = raw_with_systems()
    t.eq(select(2, C.plan("weapon weapon:5 on", raw)), "no weapon:5")
    t.eq(select(2, C.plan("weapon weapon:1 fire", raw)), "usage: weapon <weapon> on|off")
    t.eq(select(2, C.plan("drone drone:3 on", raw)), "no drone:3")
    t.eq(C.plan("drone drone:0 off", raw), { kind = "drone", slot = 0, on = false })
end)

t.test("weapons can't be powered while the weapons system is ionized", function()
    local raw = raw_with_systems()
    raw.player.systems[3].ion = 1
    t.eq(
        select(2, C.plan("weapon weapon:1 on", raw)),
        "system:weapons is ionized; its power is locked until the ion wears off"
    )
end)

t.test("drones need drone parts and an un-ionized drones system", function()
    local raw = raw_with_systems()
    raw.player.drones[1].powered = false
    raw.player.drone_parts = 0
    t.eq(
        select(2, C.plan("drone drone:0 on", raw)),
        "drone:0 (Defense Drone I) needs a drone part; none left"
    )
    raw.player.drone_parts = 3
    raw.player.systems[5].ion = 2
    t.eq(
        select(2, C.plan("drone drone:0 on", raw)),
        "system:drones is ionized; its power is locked until the ion wears off"
    )
end)

-- #10: jump. Current beacon 0 links to 1 and 3; beacon 2 is the exit (links to 1).
local function raw_with_map()
    local raw = raw_with_systems()
    raw.player.fuel, raw.player.ftl_charge, raw.player.ftl_charge_time = 4, 1, 1
    raw.map = {
        current = 0,
        beacons = {
            { id = 0, x = 0, y = 0, links = { 1, 3 } },
            { id = 1, x = 1, y = 0, links = { 0, 2 } },
            { id = 2, x = 2, y = 0, links = { 1 }, exit = true },
            { id = 3, x = 1, y = 1, links = { 0 } },
        },
        fleet = { x = -100, y = 0, radius = 10, advance = 10 },
    }
    return raw
end

t.test("jump resolves a linked beacon", function()
    t.eq(C.plan("jump beacon:3", raw_with_map()), { kind = "jump", beacon = 3 })
end)

t.test("jump refuses beacons that aren't linked or don't exist", function()
    local raw = raw_with_map()
    t.eq(
        select(2, C.plan("jump beacon:2", raw)),
        "beacon:2 is not linked to the current beacon (beacon:0)"
    )
    t.eq(select(2, C.plan("jump beacon:9", raw)), "no beacon:9")
    t.eq(select(2, C.plan("jump 3", raw)), "usage: jump <beacon> | jump <sector> (at the exit)")
end)

t.test("jump needs fuel and a charged FTL drive", function()
    local raw = raw_with_map()
    raw.player.fuel = 0
    t.eq(select(2, C.plan("jump beacon:1", raw)), "no fuel")
    raw = raw_with_map()
    raw.player.ftl_charge = 0.25
    t.eq(select(2, C.plan("jump beacon:1", raw)), "FTL drive charging (0.3 of 1.0)")
end)

t.test("jump refuses while an event is open", function()
    local raw = raw_with_map()
    raw.pause.event = true
    t.eq(select(2, C.plan("jump beacon:1", raw)), "an event is open; answer it first")
end)

t.test("at the exit, jump picks one of the offered sectors", function()
    local raw = raw_with_map()
    raw.map.current = 2
    raw.map.sector_choices = { { index = 5, type = 1 }, { index = 6, type = 2 } }
    t.eq(C.plan("jump sector:6", raw), { kind = "jump_sector", sector = 6 })
    t.eq(
        select(2, C.plan("jump sector:4", raw)),
        "sector:4 is not one of the next sectors (sector:5, sector:6)"
    )
end)

t.test("sector jumps only work at the exit", function()
    t.eq(
        select(2, C.plan("jump sector:5", raw_with_map())),
        "next sectors can only be chosen at the exit beacon"
    )
end)

t.test("jump refuses enemy-prefixed IDs", function()
    t.eq(
        select(2, C.plan("jump enemy:beacon:1", raw_with_map())),
        "usage: jump <beacon> | jump <sector> (at the exit)"
    )
end)

-- #11: choose.
local function raw_with_event()
    local raw = raw_with_systems()
    raw.pause.event = true
    raw.event = {
        text = "An event.",
        choices = {
            { text = "Yes.", blue = false, available = true },
            { text = "(Scanners) Scan.", blue = false, available = false },
        },
        received = {},
    }
    return raw
end

t.test("choose resolves an available choice", function()
    t.eq(C.plan("choose choice:0", raw_with_event()), { kind = "choose", choice = 0 })
end)

t.test("choose refuses unavailable, unknown or absent choices", function()
    local raw = raw_with_event()
    t.eq(select(2, C.plan("choose choice:1", raw)), "choice:1 ((Scanners) Scan.) is not available")
    t.eq(select(2, C.plan("choose choice:5", raw)), "no choice:5")
    t.eq(select(2, C.plan("choose 1", raw)), "usage: choose <choice>")
    t.eq(select(2, C.plan("choose choice:0", raw_with_systems())), "no event is open")
end)

t.test("jump reports a bad target before a charging drive", function()
    local raw = raw_with_map()
    raw.player.ftl_charge = 0.25
    t.eq(
        select(2, C.plan("jump beacon:2", raw)),
        "beacon:2 is not linked to the current beacon (beacon:0)"
    )
end)

t.test("unpause is refused while a game window holds the pause", function()
    local raw = raw_in_run()
    raw.pause.menu = true
    t.eq(
        select(2, C.plan("unpause", raw)),
        "a game window is open (store, upgrades or menu); close it first"
    )
end)

t.test("choose only reaches the first nine choices, as the game's keys do", function()
    local raw = raw_with_event()
    for i = 3, 10 do
        raw.event.choices[i] = { text = "More.", blue = false, available = true }
    end
    t.eq(
        select(2, C.plan("choose choice:9", raw)),
        "choice:9 can't be picked: the game only has keys for the first 9"
    )
end)

t.test("an open event window blocks every action except choose, wait and pause", function()
    local raw = raw_with_event()
    raw.player.crew = raw_with_interior().player.crew
    t.eq(select(2, C.plan("move crew:101 room:1", raw)), "an event is open; answer it first")
    t.eq(select(2, C.plan("power shields -2", raw)), "an event is open; answer it first")
    t.eq(C.plan("wait 1", raw), { kind = "wait", seconds = 1 })
    t.eq(C.plan("pause", raw), { kind = "pause" })
    t.eq(C.plan("choose choice:0", raw), { kind = "choose", choice = 0 })
end)

t.test("move to an enemy room checks the enemy ship has it", function()
    local raw = raw_with_interior()
    raw.enemy = raw_with_interior().player --[[@as RawEnemy]] -- any ship with rooms 0-2
    t.eq(
        C.plan("move crew:102 enemy:room:1", raw),
        { kind = "move", crew = 102, room = 1, enemy = true }
    )
    t.eq(select(2, C.plan("move crew:102 enemy:room:7", raw)), "no enemy:room:7")
end)

-- #7: combat. Weapons: 0 Artemis (powered), 1 Burst Laser (unpowered), 2 Heavy Laser; plus a beam.
local function raw_in_fight()
    local raw = raw_with_systems()
    raw.player.weapons[2].powered = true
    raw.player.weapons[4] = {
        name = "Halberd Beam",
        powered = true,
        power = 3,
        charge = 0,
        charge_time = 17,
        missiles = false,
        beam = true,
    }
    raw.enemy = raw_with_interior().player --[[@as RawEnemy]] -- an enemy with rooms 0-2
    return raw
end

t.test("a burst weapon aims every shot at the one room given", function()
    t.eq(
        C.plan("target weapon:1 enemy:room:2", raw_in_fight()),
        { kind = "target", slot = 1, rooms = { 2 } }
    )
end)

t.test("a beam takes a start and an end room", function()
    local raw = raw_in_fight()
    t.eq(
        C.plan("target weapon:3 enemy:room:0 enemy:room:2", raw),
        { kind = "target", slot = 3, rooms = { 0, 2 } }
    )
    t.eq(
        select(2, C.plan("target weapon:3 enemy:room:0", raw)),
        "weapon:3 (Halberd Beam) is a beam: give a start and an end room"
    )
end)

t.test("target refuses unpowered weapons, our own rooms, missing rooms and no enemy", function()
    local raw = raw_in_fight()
    t.eq(
        select(2, C.plan("target weapon:2 enemy:room:0", raw)),
        "weapon:2 (Heavy Laser) is not powered"
    )
    t.eq(
        select(2, C.plan("target weapon:1 room:0", raw)),
        "target an enemy room, like enemy:room:3"
    )
    t.eq(select(2, C.plan("target weapon:1 enemy:room:9", raw)), "no enemy:room:9")
    t.eq(
        select(2, C.plan("target weapon:1 enemy:room:0", raw_with_systems())),
        "there is no enemy ship to target"
    )
end)

t.test("untarget and autofire", function()
    local raw = raw_in_fight()
    t.eq(C.plan("untarget weapon:1", raw), { kind = "untarget", slot = 1 })
    t.eq(C.plan("autofire on", raw), { kind = "autofire", on = true })
    t.eq(select(2, C.plan("autofire maybe", raw)), "usage: autofire on|off")
end)

t.test("a beam needs two different rooms", function()
    t.eq(
        select(2, C.plan("target weapon:3 enemy:room:2 enemy:room:2", raw_in_fight())),
        "weapon:3 (Halberd Beam) needs a start and an end room that differ"
    )
end)

-- #12: buy, upgrade, close.
local function raw_at_store(window)
    local raw = raw_with_systems()
    raw.window, raw.pause.menu = window or "store", true
    raw.player.scrap = 60
    raw.store = {
        open = true,
        items = {
            { name = "Burst Laser I", cost = 50, stock = 1, can_hold = true },
            { name = "Ion Blast II", cost = 70, stock = 1, can_hold = true },
            { name = "Defense Drone I", cost = 50, stock = 0, can_hold = true },
            { name = "Hacking", cost = 40, stock = 1, can_hold = false },
        },
    }
    raw.upgrades = {
        reactor = { level = 8, cost = 30 },
        systems = {
            { type = 0, level = 2, max_level = 8, cost = 20 },
            { type = 3, level = 3, max_level = 3 },
        },
    }
    return raw
end

t.test("buy resolves an affordable item in stock", function()
    t.eq(C.plan("buy item:0", raw_at_store()), { kind = "buy", item = 0 })
end)

t.test("buy explains why it can't", function()
    local raw = raw_at_store()
    t.eq(select(2, C.plan("buy item:1", raw)), "item:1 (Ion Blast II) costs 70 scrap; you have 60")
    t.eq(select(2, C.plan("buy item:2", raw)), "item:2 (Defense Drone I) is sold out")
    t.eq(
        select(2, C.plan("buy item:3", raw)),
        "item:3 (Hacking) can't be held: no room or already installed"
    )
    t.eq(select(2, C.plan("buy item:9", raw)), "no item:9")
    t.eq(select(2, C.plan("buy item:0", raw_with_systems())), "there is no store here")
end)

t.test("upgrade a system or the reactor", function()
    local raw = raw_at_store("upgrades")
    t.eq(C.plan("upgrade shields", raw), { kind = "upgrade", system = 0, cost = 20 })
    t.eq(C.plan("upgrade reactor", raw), { kind = "upgrade_reactor" })
    t.eq(select(2, C.plan("upgrade weapons", raw)), "system:weapons is at its maximum level")
    raw.player.scrap = 10
    t.eq(
        select(2, C.plan("upgrade reactor", raw)),
        "the reactor upgrade costs 30 scrap; you have 10"
    )
end)

t.test("close shuts an open window", function()
    t.eq(C.plan("close", raw_at_store()), { kind = "close" })
    local raw = raw_at_store()
    raw.window = nil
    t.eq(select(2, C.plan("close", raw)), "no window is open")
end)

t.test("an open game window blocks actions except close, wait and pause", function()
    local raw = raw_at_store()
    raw.pause.menu = true
    t.eq(select(2, C.plan("power shields -2", raw)), "a game window is open; close it first")
    t.eq(C.plan("close", raw), { kind = "close" })
    t.eq(C.plan("buy item:0", raw), { kind = "buy", item = 0 })
    t.eq(C.plan("wait 1", raw), { kind = "wait", seconds = 1 })
end)

t.test("upgrade carries the cost it was checked against", function()
    t.eq(
        C.plan("upgrade shields", raw_at_store("upgrades")),
        { kind = "upgrade", system = 0, cost = 20 }
    )
end)

-- #8: system abilities. Our ship gains cloaking (10), battery (12), hacking (15), mind control (14)
-- and a teleporter (9); the enemy is a two-room ship with weapons in room 0 and crew Grub (201).
local function raw_with_abilities()
    local raw = raw_with_systems()
    local function add(type, power)
        raw.player.systems[#raw.player.systems + 1] = {
            type = type,
            room = 1,
            power = power,
            level = 1,
            cap = 1,
            damage = 0,
            ion = 0,
            uses_reactor = true,
        }
    end
    add(10, 1)
    add(12, 1)
    add(15, 1)
    add(14, 1)
    add(9, 1)
    raw.player.abilities = {
        cloak = { on = false },
        battery = { on = false },
        hacking = { drone = false, launched = false },
        teleporter = { charged = true },
    }
    raw.player.sensors_power, raw.player.sensors_manned = 2, false
    raw.player.drone_parts = 2
    raw.enemy = {
        class = "Rebel Fighter",
        hostile = true,
        cloaked = false,
        flagship = false,
        hull = 8,
        hull_max = 10,
        scrap = 0,
        shield_layers = 1,
        shield_layers_max = 1,
        evasion = 0,
        oxygen = 100,
        rooms = {
            {
                id = 0,
                x = 0,
                y = 0,
                w = 35,
                h = 35,
                system = 3,
                oxygen = 100,
                fires = 0,
                breaches = 0,
            },
            { id = 1, x = 35, y = 0, w = 35, h = 35, oxygen = 100, fires = 0, breaches = 0 },
        },
        doors = {},
        systems = {
            {
                type = 3,
                room = 0,
                power = 1,
                level = 1,
                cap = 1,
                damage = 0,
                ion = 0,
                uses_reactor = true,
            },
        },
        crew = {
            {
                uid = 201,
                name = "Grub",
                species = "human",
                health = 100,
                health_max = 100,
                room = 1,
                on_enemy_ship = false,
                skills = { 1, 1, 1, 1, 1, 1 },
            },
        },
    }
    return raw
end

t.test("cloak and battery activate when the system is ready", function()
    local raw = raw_with_abilities()
    t.eq(C.plan("cloak", raw), { kind = "cloak" })
    t.eq(C.plan("battery", raw), { kind = "battery" })
    raw.player.abilities.cloak.on = true
    t.eq(select(2, C.plan("cloak", raw)), "already cloaked")
    t.eq(select(2, C.plan("cloak", raw_with_systems())), "no system:cloaking on this ship")
end)

t.test("hack launches the drone at an enemy system, then starts the pulse", function()
    local raw = raw_with_abilities()
    t.eq(C.plan("hack enemy:room:0", raw), { kind = "hack", room = 0 })
    t.eq(select(2, C.plan("hack enemy:room:1", raw)), "enemy:room:1 has no system to hack")
    t.eq(select(2, C.plan("hack", raw)), "no hacking drone attached yet: hack <enemy:room> first")
    raw.player.abilities.hacking.drone = true
    t.eq(C.plan("hack", raw), { kind = "hack_pulse" })
end)

t.test("hack can't launch a second drone, or one without drone parts", function()
    local raw = raw_with_abilities()
    raw.player.abilities.hacking.launched = true
    t.eq(select(2, C.plan("hack enemy:room:0", raw)), "a hacking drone is already out")
    raw.player.abilities.hacking.launched, raw.player.drone_parts = false, 0
    t.eq(select(2, C.plan("hack enemy:room:0", raw)), "no drone parts to build a hacking drone")
end)

t.test("mind control needs an enemy crew member we can see", function()
    local raw = raw_with_abilities()
    t.eq(C.plan("mindcontrol enemy:crew:201", raw), { kind = "mindcontrol", crew = 201 })
    t.eq(select(2, C.plan("mindcontrol enemy:crew:999", raw)), "no visible enemy:crew:999")
    raw.player.sensors_power = 0 -- no longer visible
    t.eq(select(2, C.plan("mindcontrol enemy:crew:201", raw)), "no visible enemy:crew:201")
end)

t.test("teleport sends crew to, or brings them back from, an enemy room", function()
    local raw = raw_with_abilities()
    raw.player.crew[1].room = 1 -- on the teleporter pad
    raw.player.crew[2].room, raw.player.crew[2].on_enemy_ship = 1, true
    t.eq(C.plan("teleport send enemy:room:1", raw), { kind = "teleport", room = 1, command = 1 })
    t.eq(C.plan("teleport return enemy:room:1", raw), { kind = "teleport", room = 1, command = 2 })
    raw.player.abilities.teleporter.charged = false
    t.eq(
        select(2, C.plan("teleport send enemy:room:1", raw)),
        "system:teleporter is still charging"
    )
    t.eq(select(2, C.plan("teleport away", raw)), "usage: teleport send|return <enemy:room>")
end)

t.test("teleport needs crew to send, or crew to bring back", function()
    local raw = raw_with_abilities()
    for _, c in ipairs(raw.player.crew) do
        c.room = 0
    end
    t.eq(
        select(2, C.plan("teleport send enemy:room:1", raw)),
        "no crew on the teleporter pad (room:1)"
    )
    t.eq(
        select(2, C.plan("teleport return enemy:room:1", raw)),
        "none of our crew are in enemy:room:1"
    )
end)

t.test("show opens the map, upgrades or store window, even with an event or window up", function()
    local raw = raw_at_store()
    t.eq(C.plan("show map", raw), { kind = "show", window = "map" })
    t.eq(C.plan("show upgrades", raw), { kind = "show", window = "upgrades" })
    t.eq(C.plan("show store", raw), { kind = "show", window = "store" })
    t.eq(select(2, C.plan("show store", raw_with_systems())), "there is no store here")
    t.eq(select(2, C.plan("show crew", raw)), "usage: show map|upgrades|store")
end)

t.test("buy and upgrade need their window open; other actions need every window closed", function()
    local raw = raw_at_store()
    raw.window = nil
    t.eq(select(2, C.plan("buy item:0", raw)), "the store window isn't open; run ftl store first")
    t.eq(
        select(2, C.plan("upgrade shields", raw)),
        "the upgrades window isn't open; run ftl upgrades first"
    )
    raw.window, raw.pause.menu = "map", true
    t.eq(select(2, C.plan("jump beacon:1", raw)), "a game window is open; close it first")
    t.eq(C.plan("close", raw), { kind = "close" })
    raw.window = "upgrades"
    t.eq(C.plan("upgrade shields", raw), { kind = "upgrade", system = 0, cost = 20 })
end)

t.test("a shown event box blocks buy even when the game's event pause is clear", function()
    local raw = raw_at_store()
    raw.event = { text = "", choices = {}, received = {} }
    t.eq(select(2, C.plan("buy item:0", raw)), "an event is open; answer it first")
end)

t.test("an open event blocks buy and upgrade", function()
    local raw = raw_at_store()
    raw.pause.event, raw.event = true, { text = "", choices = {}, received = {} }
    t.eq(select(2, C.plan("buy item:0", raw)), "an event is open; answer it first")
    t.eq(select(2, C.plan("upgrade shields", raw)), "an event is open; answer it first")
end)
