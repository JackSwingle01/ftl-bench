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
            ion = 0,
            uses_reactor = true,
        },
        {
            type = 6,
            room = 0,
            power = 1,
            level = 1,
            cap = 1,
            damage = 0,
            ion = 0,
            uses_reactor = false,
        },
        {
            type = 3,
            room = 1,
            power = 0,
            level = 3,
            cap = 2,
            damage = 1,
            ion = 2,
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
        ion = 0,
        subsystem = false,
    })
    t.eq({ systems[2].id, systems[2].subsystem }, { "system:piloting", true })
    t.eq({ systems[3].max_power, systems[3].damage, systems[3].ion }, { 2, 1, 2 })
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

-- #5: events found by comparing frames. Copies one raw state so a test can change the second.
local function deep_copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = deep_copy(x)
    end
    return out
end

---@return RawState, RawState
local function two_frames()
    local before = raw_with_systems()
    return before, deep_copy(before)
end

local function events(before, after)
    return V.observe(before, after, {}).events
end

t.test("no change means no events", function()
    local before, after = two_frames()
    t.eq(#events(before, after), 0)
end)

t.test("fire starting and going out in a visible room", function()
    local before, after = two_frames()
    before.player.rooms[1].fires, after.player.rooms[1].fires = 0, 2
    t.eq(
        events(before, after),
        { { type = "fire_started", room = "room:0 (piloting)", fires = 2 } }
    )
    t.eq(events(after, before), { { type = "fire_out", room = "room:0 (piloting)" } })
end)

t.test("breaches opening and being repaired", function()
    local before, after = two_frames()
    before.player.rooms[2].breaches, after.player.rooms[2].breaches = 0, 1
    t.eq(events(before, after), { { type = "breach", room = "room:1", breaches = 1 } })
    t.eq(events(after, before), { { type = "breach_repaired", room = "room:1" } })
end)

t.test("fires and breaches in dark rooms make no events", function()
    local before, after = two_frames()
    before.player.sensors_power, after.player.sensors_power = 0, 0
    after.player.rooms[2].fires, after.player.rooms[2].breaches = 1, 1 -- room 1: no crew, no system
    t.eq(#events(before, after), 0)
end)

t.test("fire above a system shows even in the dark", function()
    local before, after = two_frames()
    before.player.sensors_power, after.player.sensors_power = 0, 0
    before.player.rooms[3].fires, after.player.rooms[3].fires = 0, 1 -- room 2 holds shields
    t.eq(events(before, after), { { type = "fire_started", room = "room:2 (shields)", fires = 1 } })
end)

t.test("crew hurt is reported when health crosses 75, 50 and 25 percent", function()
    local before, after = two_frames()
    before.player.crew[1].health, after.player.crew[1].health = 80, 70
    t.eq(events(before, after), {
        { type = "crew_hurt", crew = "crew:101 (Maria)", health = 70, health_max = 100 },
    })
    before.player.crew[1].health, after.player.crew[1].health = 70, 60
    t.eq(#events(before, after), 0)
    before.player.crew[1].health, after.player.crew[1].health = 60, 20
    t.eq(#events(before, after), 1) -- one event even when crossing two thresholds
end)

t.test("crew killed", function()
    local before, after = two_frames()
    after.player.crew[1].dead, after.player.crew[1].health = true, 0
    t.eq(events(before, after), { { type = "crew_killed", crew = "crew:101 (Maria)" } })
end)

t.test("crew stunned and recovering", function()
    local before, after = two_frames()
    before.player.crew[1].stun, after.player.crew[1].stun = 0, 3.5
    t.eq(
        events(before, after),
        { { type = "crew_stunned", crew = "crew:101 (Maria)", seconds = 3.5 } }
    )
    t.eq(events(after, before), { { type = "crew_recovered", crew = "crew:101 (Maria)" } })
end)

t.test("systems ionized and clearing", function()
    local before, after = two_frames()
    after.player.systems[1].ion = 2
    t.eq(events(before, after), { { type = "system_ionized", system = "system:shields", ion = 2 } })
    t.eq(events(after, before), { { type = "system_ion_cleared", system = "system:shields" } })
end)

t.test("events are lists, so they encode as JSON arrays", function()
    local before, after = two_frames()
    t.eq(getmetatable(events(before, after)).__jsontype, "array")
end)

-- #10: the sector map. Beacons (map pixels):
--   0 current (50,100) -- 1 (150,100) -- 2 exit (250,100); 0 -- 3 (150,200) -- 4 quest (250,200)
-- Fleet: centre (-200,100), radius 280, advancing 100 per jump. Beacon 0 is 250 from the centre.
---@return RawState
local function raw_with_map()
    local raw = raw_with_systems()
    raw.player.fuel = 5
    raw.player.ftl_charge, raw.player.ftl_charge_time = 1, 1
    raw.map = {
        current = 0,
        beacons = {
            { id = 0, x = 50, y = 100, links = { 1, 3 }, visited = true },
            { id = 1, x = 150, y = 100, links = { 0, 2 }, store = true, distress = false },
            { id = 2, x = 250, y = 100, links = { 1 }, exit = true, store = true },
            { id = 3, x = 150, y = 200, links = { 0, 4 }, nebula = true, distress = true },
            { id = 4, x = 250, y = 200, links = { 3 }, quest = true, distress = true },
        },
        fleet = { x = -200, y = 100, radius = 280, advance = 100 },
    }
    return raw
end

local function map_view(raw)
    return V.observe(nil, raw, {}).views.map
end

t.test("map lists every beacon with position, links and always-visible markers", function()
    local b = map_view(raw_with_map()).beacons
    t.eq(b[1], {
        id = "beacon:0",
        x = 50,
        y = 100,
        links = { "beacon:1", "beacon:3" },
        current = true,
        visited = true,
        fleet = true,
        jumps_until_fleet = 0,
    })
    t.eq({ b[3].exit, b[4].nebula, b[5].quest }, { true, true, true })
end)

t.test("store and distress markers show only within one jump", function()
    local b = map_view(raw_with_map()).beacons
    t.eq({ b[2].store, b[4].distress }, { true, true }) -- adjacent to the current beacon
    t.eq({ b[3].store, b[5].distress }, { nil, nil }) -- two jumps away
end)

t.test("markers stay once a beacon has been next to the ship", function()
    local raw = raw_with_map()
    raw.map.beacons[3].scouted = true
    t.eq(map_view(raw).beacons[3].store, true)
end)

t.test("jumps until the fleet reaches each beacon", function()
    local b = map_view(raw_with_map()).beacons
    -- distances from the fleet centre: 350, 450, 380, 474; radius 280, +100 per jump
    t.eq({ b[2].jumps_until_fleet, b[3].jumps_until_fleet }, { 1, 2 })
    t.eq({ b[4].jumps_until_fleet, b[5].jumps_until_fleet }, { 1, 2 })
end)

t.test("the map reports the sector", function()
    local raw = raw_with_map()
    raw.sector = 3
    t.eq(map_view(raw).sector, 3)
end)

t.test("jumps lists linked beacons, fuel and FTL charge", function()
    t.eq(V.observe(nil, raw_with_map(), {}).views.jumps, {
        beacons = { "beacon:1", "beacon:3" },
        fuel = 5,
        ftl_charge = 1,
        ftl_charge_time = 1,
        ready = true,
        sectors = {},
    })
end)

t.test("jumps says why it can't jump", function()
    local raw = raw_with_map()
    raw.player.fuel = 0
    local j = V.observe(nil, raw, {}).views.jumps --[[@as table]]
    t.eq({ j.ready, j.not_ready }, { false, "no fuel" })
    raw = raw_with_map()
    raw.player.ftl_charge = 0.4
    j = V.observe(nil, raw, {}).views.jumps --[[@as table]]
    t.eq({ j.ready, j.not_ready }, { false, "FTL drive charging" })
end)

t.test("at the exit, jumps offers the next sectors by type only", function()
    local raw = raw_with_map()
    raw.map.current = 2
    raw.map.sector_choices = { { index = 5, type = 1 }, { index = 6, type = 2 } }
    t.eq(V.observe(nil, raw, {}).views.jumps.sectors, {
        { id = "sector:5", type = "hostile" },
        { id = "sector:6", type = "nebula" },
    })
end)

t.test("jumps is not ready while an event is open", function()
    local raw = raw_with_map()
    raw.pause.event = true
    local j = V.observe(nil, raw, {}).views.jumps --[[@as table]]
    t.eq({ j.ready, j.not_ready }, { false, "an event is open" })
end)

t.test("arriving at a beacon and entering a sector make events", function()
    local before, after = raw_with_map(), raw_with_map()
    after.map.current = 3
    t.eq(V.observe(before, after, {}).events, { { type = "arrived", beacon = "beacon:3" } })
    before.sector, after.sector, after.map.current = 1, 2, 0
    t.eq(V.observe(before, after, {}).events, { { type = "new_sector", sector = 2 } })
end)

-- #11: events and choices. ChoiceText type: 0 normal, 1 blue option, 2 requirement not met.
---@return RawState
local function raw_with_event()
    local raw = raw_with_systems()
    raw.pause.event = true
    raw.event = {
        text = "You find a small ship struggling through the asteroids.",
        choices = {
            { text = "Hail them.", type = 0, rewards = {} },
            { text = "(Engi Crew) Talk them through.", type = 1, rewards = {} },
            { text = "(Long-Ranged Scanners) Scan.", type = 2, rewards = {} },
            { text = "Take the fuel.", type = 0, rewards = { fuel = 3, scrap = 0 } },
        },
        received = { scrap = 15, fuel = 0 },
    }
    return raw
end

t.test("an open event shows its text and numbered choices", function()
    local e = V.observe(nil, raw_with_event(), {}).views.state.event
    t.eq(e.text, "You find a small ship struggling through the asteroids.")
    t.eq(e.choices[1], { id = "choice:0", text = "Hail them.", available = true })
    t.eq(
        e.choices[2],
        { id = "choice:1", text = "(Engi Crew) Talk them through.", blue = true, available = true }
    )
    t.eq(
        e.choices[3],
        { id = "choice:2", text = "(Long-Ranged Scanners) Scan.", available = false }
    )
end)

t.test("a choice shows only the resource changes the game displays", function()
    local e = V.observe(nil, raw_with_event(), {}).views.state.event
    t.eq(e.choices[4].shows, { fuel = 3 })
    t.eq(e.choices[1].shows, nil)
end)

t.test("rewards the event window displays are reported as received", function()
    t.eq(V.observe(nil, raw_with_event(), {}).views.state.event.received, { scrap = 15 })
end)

t.test("no event window, no event in the state", function()
    t.eq(V.observe(nil, raw_with_systems(), {}).views.state.event, nil)
end)

t.test("a new event window produces an event", function()
    local before, after = raw_with_systems(), raw_with_event()
    t.eq(events(before, after), {
        {
            type = "event",
            text = "You find a small ship struggling through the asteroids.",
            choices = 4,
            received = { scrap = 15 },
        },
    })
    t.eq(#events(after, after), 0)
end)

t.test("the state says why the game is paused", function()
    local raw = raw_in_run()
    raw.pause.manual, raw.pause.menu = true, true
    local state = V.observe(nil, raw, {}).views.state
    t.eq({ state.paused, state.paused_by }, { true, { "player", "menu" } })
    t.eq(V.observe(nil, raw_in_run(), {}).views.state.paused_by, nil)
end)
