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
        { kind = "door", doors = { 0, 1, 2 }, open = true }
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
            ioned = false,
            uses_reactor = true,
        },
        {
            type = 6,
            room = 1,
            power = 1,
            level = 1,
            cap = 1,
            damage = 0,
            ioned = false,
            uses_reactor = false,
        },
        {
            type = 3,
            room = 2,
            power = 1,
            level = 3,
            cap = 3,
            damage = 0,
            ioned = false,
            uses_reactor = true,
        },
        {
            type = 1,
            room = 2,
            power = 1,
            level = 2,
            cap = 2,
            damage = 0,
            ioned = true,
            uses_reactor = true,
        },
        {
            type = 4,
            room = 1,
            power = 1,
            level = 2,
            cap = 2,
            damage = 0,
            ioned = false,
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
    t.eq(select(2, C.plan("power shields +2", raw)), "not enough reactor power (1 free)")
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
