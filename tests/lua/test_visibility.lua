local t = ...
local V = FtlBench.Visibility

---@return RawState
local function raw_in_run()
    return {
        in_run = true,
        frame = 1200,
        game_time = 20.5,
        pause = { manual = false, event = false, menu = false },
        player = { hull = 27, hull_max = 30, scrap = 45 },
    }
end

t.test("state view shows pause status, game time, hull and scrap", function()
    local state = V.observe(nil, raw_in_run(), {}).views.state
    t.eq({ state.in_run, state.paused, state.frame, state.game_time }, { true, false, 1200, 20.5 })
    t.eq({ state.ship.hull, state.ship.hull_max, state.ship.scrap }, { 27, 30, 45 })
end)

t.test("outside a Run the state view says so and shows no ship", function()
    local raw = {
        in_run = false,
        frame = 0,
        game_time = 0,
        pause = { manual = false, event = false, menu = false },
    }
    t.eq(
        V.observe(nil, raw, {}).views.state,
        { in_run = false, paused = false, frame = 0, game_time = 0 }
    )
end)

t.test("an open event or menu counts as paused", function()
    local raw = raw_in_run()
    raw.pause.event = true
    t.eq(V.observe(nil, raw, {}).views.state.paused, true)
    raw = raw_in_run()
    raw.pause.menu = true
    t.eq(V.observe(nil, raw, {}).views.state.paused, true)
end)

-- Own ship interior (#3). A small three-room ship:
--   room 0: piloting, holds crew Maria   room 1: no system   room 2: shields
--   door 0 joins rooms 0-1, door 1 joins rooms 1-2, door 2 is an airlock on room 1.
---@return RawState
local function raw_with_interior()
    local raw = raw_in_run()
    raw.nebula = false
    local ship = raw.player --[[@as RawShip]]
    ship.oxygen = 92
    ship.sensors_power = 1
    ship.rooms = {
        {
            id = 0,
            x = 70,
            y = 35,
            w = 35,
            h = 70,
            system = 6,
            oxygen = 100,
            fires = 0,
            breaches = 0,
        },
        { id = 1, x = 0, y = 35, w = 70, h = 70, oxygen = 80.4, fires = 1, breaches = 1 },
        {
            id = 2,
            x = 0,
            y = 105,
            w = 70,
            h = 35,
            system = 0,
            oxygen = 95,
            fires = 2,
            breaches = 0,
        },
    }
    ship.doors = {
        { id = 0, room1 = 0, room2 = 1, open = false },
        { id = 1, room1 = 1, room2 = 2, open = true },
        { id = 2, room1 = 1, room2 = -1, open = false },
    }
    ship.crew = {
        {
            uid = 101,
            name = "Maria",
            species = "human",
            health = 85,
            health_max = 100,
            room = 0,
            on_enemy_ship = false,
            skills = { 2, 1, 1, 3, 1, 1 },
        },
    }
    return raw
end

local function ship_view(raw)
    return V.observe(nil, raw, {}).views.state.ship
end

t.test("rooms show tile position and size, and their system name", function()
    local rooms = ship_view(raw_with_interior()).rooms
    t.eq(rooms[1], {
        id = "room:0",
        name = "piloting",
        x = 2,
        y = 1,
        w = 1,
        h = 2,
        oxygen = 100,
        fires = 0,
        breaches = 0,
    })
    t.eq(rooms[3].name, "shields")
    t.eq(rooms[2].name, nil)
end)

t.test("room oxygen is a whole percentage", function()
    t.eq(ship_view(raw_with_interior()).rooms[2].oxygen, 80)
end)

t.test("doors list the rooms they join, with space for airlocks", function()
    t.eq(ship_view(raw_with_interior()).doors, {
        { id = "door:0", rooms = { "room:0", "room:1" }, open = false },
        { id = "door:1", rooms = { "room:1", "room:2" }, open = true },
        { id = "door:2", rooms = { "room:1", "space" }, open = false },
    })
end)

t.test("own crew show ID, name, race, health, room and skills", function()
    t.eq(ship_view(raw_with_interior()).crew, {
        {
            id = "crew:101",
            name = "Maria",
            race = "human",
            health = 85,
            health_max = 100,
            room = "room:0",
            skills = { piloting = 2, engines = 1, shields = 1, weapons = 3, repair = 1, combat = 1 },
        },
    })
end)

t.test("crew aboard the enemy ship are placed in an enemy room", function()
    local raw = raw_with_interior()
    raw.player.crew[1].on_enemy_ship = true
    raw.player.crew[1].room = 3
    t.eq(ship_view(raw).crew[1].room, "enemy:room:3")
end)

t.test("whole-ship oxygen is always shown", function()
    local raw = raw_with_interior()
    raw.player.sensors_power = 0
    t.eq(ship_view(raw).oxygen, 92)
end)

t.test("without Sensors, rooms with no own crew hide oxygen and breaches", function()
    local raw = raw_with_interior()
    raw.player.sensors_power = 0
    local rooms = ship_view(raw).rooms
    t.eq(rooms[1].oxygen, 100) -- Maria is there
    t.eq(rooms[2], {
        id = "room:1",
        x = 0,
        y = 1,
        w = 2,
        h = 2,
        hidden = "no crew in room and Sensors not working",
    })
end)

t.test("without Sensors, fires still show in system rooms but not in empty ones", function()
    local raw = raw_with_interior()
    raw.player.sensors_power = 0
    local rooms = ship_view(raw).rooms
    t.eq(rooms[3].fires, 2)
    t.eq(rooms[3].oxygen, nil)
    t.eq(rooms[2].fires, nil)
end)

t.test("a nebula blinds Sensors even when powered", function()
    local raw = raw_with_interior()
    raw.nebula = true
    t.eq(ship_view(raw).rooms[2].hidden, "no crew in room and Sensors not working")
end)

t.test("a Slug crew member reveals rooms sharing a wall with its room", function()
    local raw = raw_with_interior()
    raw.player.sensors_power = 0
    raw.player.crew[1].species = "slug"
    raw.player.doors = {} -- adjacency is by wall, not by door
    local rooms = ship_view(raw).rooms
    t.eq(rooms[2].oxygen, 80) -- room 1 shares room 0's left wall
    t.eq(rooms[3].hidden, "no crew in room and Sensors not working") -- touches only at a corner
end)

t.test("dead crew are not shown", function()
    local raw = raw_with_interior()
    raw.player.crew[1].dead = true
    t.eq(#ship_view(raw).crew, 0)
end)

t.test("layout and door state stay visible without Sensors", function()
    local raw = raw_with_interior()
    raw.player.sensors_power = 0
    local view = ship_view(raw)
    t.eq(#view.doors, 3)
    t.eq(view.doors[2].open, true)
end)

t.test("lists stay lists when empty, so they encode as JSON arrays", function()
    local raw = raw_with_interior()
    raw.player.crew = {}
    local mt = getmetatable(ship_view(raw).crew)
    t.eq(mt and mt.__jsontype, "array")
end)

-- #9: game over, victory, sector and Score.
t.test("the current sector is always shown", function()
    local raw = raw_in_run()
    raw.sector = 3
    t.eq(V.observe(nil, raw, {}).views.state.sector, 3)
end)

t.test("the Score is hidden until the Run ends", function()
    local raw = raw_in_run()
    raw.score = 512
    local state = V.observe(nil, raw, {}).views.state
    t.eq({ state.game_over, state.score }, { nil, nil })
end)

t.test("a finished Run shows game over, victory and the Score", function()
    local raw = raw_in_run()
    raw.sector, raw.score, raw.game_over, raw.victory = 8, 2650, true, true
    local state = V.observe(nil, raw, {}).views.state
    t.eq({ state.game_over, state.victory, state.score }, { true, true, 2650 })
end)

t.test("the frame the Run ends produces one game_over event", function()
    local before, after = raw_in_run(), raw_in_run()
    after.game_over, after.victory, after.score, after.sector = true, false, 300, 2
    t.eq(V.observe(before, after, {}).events, {
        { type = "game_over", victory = false, score = 300, sector = 2 },
    })
    t.eq(#V.observe(after, after, {}).events, 0)
end)

t.test("a lost Run shows victory as false, not missing", function()
    local raw = raw_in_run()
    raw.sector, raw.score, raw.game_over, raw.victory = 2, 300, true, false
    t.eq(V.observe(nil, raw, {}).views.state.victory, false)
end)

-- #4: power, systems, weapons and drones (values from the live Kestrel).
---@return RawState
local function raw_with_systems()
    local raw = raw_with_interior()
    local ship = raw.player --[[@as RawShip]]
    ship.reactor = { used = 5, max = 8 }
    ship.systems = {
        {
            type = 0,
            room = 2,
            power = 2,
            level = 2,
            cap = 2,
            damage = 0,
            ioned = false,
            uses_reactor = true,
        },
        {
            type = 6,
            room = 0,
            power = 1,
            level = 1,
            cap = 1,
            damage = 0,
            ioned = false,
            uses_reactor = false,
        },
        {
            type = 3,
            room = 1,
            power = 0,
            level = 3,
            cap = 2,
            damage = 1,
            ioned = true,
            uses_reactor = true,
        },
    }
    ship.shield_layers, ship.shield_layers_max = 1, 1
    ship.evasion, ship.fuel, ship.missiles, ship.drone_parts = 15, 16, 8, 2
    ship.weapons = {
        {
            name = "Artemis Missiles",
            powered = false,
            power = 1,
            charge = 0,
            charge_time = 11,
            missiles = true,
        },
        {
            name = "Burst Laser Mark II",
            powered = true,
            power = 2,
            charge = 4.25,
            charge_time = 12,
            missiles = false,
        },
    }
    ship.drones = { { name = "Defense Drone I", powered = true, deployed = false } }
    return raw
end

t.test("reactor, shields, evasion and resources are exact numbers", function()
    local ship = ship_view(raw_with_systems())
    t.eq(ship.reactor, { used = 5, max = 8 })
    t.eq(ship.shields, { layers = 1, max_layers = 1 })
    t.eq({ ship.evasion, ship.fuel, ship.missiles, ship.drone_parts }, { 15, 16, 8, 2 })
end)

t.test("systems show power, level, damage and ion by system ID", function()
    local systems = ship_view(raw_with_systems()).systems
    t.eq(systems[1], {
        id = "system:shields",
        name = "shields",
        room = "room:2",
        power = 2,
        max_power = 2,
        level = 2,
        damage = 0,
        ionized = false,
        subsystem = false,
    })
    t.eq({ systems[2].id, systems[2].subsystem }, { "system:piloting", true })
    t.eq({ systems[3].max_power, systems[3].damage, systems[3].ionized }, { 2, 1, true })
end)

t.test("weapons show slot ID, name, power and charge in seconds", function()
    local weapons = ship_view(raw_with_systems()).weapons
    t.eq(weapons[2], {
        id = "weapon:1",
        name = "Burst Laser Mark II",
        powered = true,
        power = 2,
        charge = 4.3,
        charge_time = 12,
        uses_missiles = false,
    })
    t.eq({ weapons[1].id, weapons[1].uses_missiles }, { "weapon:0", true })
end)

t.test("drones show slot ID, name, power and whether deployed", function()
    t.eq(ship_view(raw_with_systems()).drones, {
        { id = "drone:0", name = "Defense Drone I", powered = true, deployed = false },
    })
end)

t.test("a ship without weapons or drones gets empty lists", function()
    local raw = raw_with_systems()
    raw.player.weapons, raw.player.drones = {}, {}
    local ship = ship_view(raw)
    t.eq(
        { getmetatable(ship.weapons).__jsontype, getmetatable(ship.drones).__jsontype },
        { "array", "array" }
    )
end)
