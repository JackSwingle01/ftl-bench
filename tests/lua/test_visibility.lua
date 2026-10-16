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

t.test("crew hurt is reported the moment damage starts", function()
    local before, after = two_frames()
    after.player.crew[1].health, after.player.crew[1].taking_damage = 84, true -- was 85
    t.eq(events(before, after), {
        { type = "crew_hurt", crew = "crew:101 (Maria)", health = 84, health_max = 100 },
    })
    local still = deep_copy(after)
    still.player.crew[1].health = 83 -- still taking damage, same band: no new event
    t.eq(#events(after, still), 0)
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
            { text = "Hail them.", blue = false, available = true },
            { text = "(Engi Crew) Talk them through.", blue = true, available = true },
            { text = "(Long-Ranged Scanners) Scan.", blue = false, available = false },
            { text = "Take the fuel.", blue = false, available = true },
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

t.test("a choice carries nothing beyond its id, text and availability", function()
    local e = V.observe(nil, raw_with_event(), {}).views.state.event
    for _, c in ipairs(e.choices) do
        for key in pairs(c) do
            t.eq(
                ({ id = true, text = true, blue = true, available = true })[key],
                true,
                "choice." .. key
            )
        end
    end
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

t.test("an event window is reported as an event, not also as a menu", function()
    local raw = raw_in_run()
    raw.pause.event, raw.pause.menu = true, true -- the game sets both for an event window
    t.eq(V.observe(nil, raw, {}).views.state.paused_by, { "event" })
end)

-- #6: the enemy ship. Two rooms: 0 (weapons), 1 (shields). One door. Two crew: Grub in room 0 (human),
-- Krix in room 1 (mantis). Our Sensors: level 1, unmanned, so no enemy interior unless stated.
---@return RawState
local function raw_with_enemy()
    local raw = raw_with_systems()
    raw.player.sensors_power, raw.player.sensors_manned = 1, false
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
        evasion = 25,
        oxygen = 90,
        rooms = {
            {
                id = 0,
                x = 0,
                y = 0,
                w = 70,
                h = 70,
                system = 3,
                oxygen = 100,
                fires = 1,
                breaches = 1,
            },
            {
                id = 1,
                x = 70,
                y = 0,
                w = 70,
                h = 35,
                system = 0,
                oxygen = 80,
                fires = 0,
                breaches = 0,
            },
        },
        doors = { { id = 0, room1 = 0, room2 = 1, open = true } },
        systems = {
            {
                type = 3,
                room = 0,
                power = 2,
                level = 3,
                cap = 3,
                damage = 0,
                ion = 0,
                uses_reactor = true,
            },
            {
                type = 0,
                room = 1,
                power = 2,
                level = 2,
                cap = 2,
                damage = 1,
                ion = 0,
                uses_reactor = true,
            },
        },
        weapons = {
            {
                name = "Basic Laser",
                powered = true,
                power = 1,
                charge = 3.2,
                charge_time = 10,
                missiles = false,
            },
        },
        drones = { { name = "Defense Drone", powered = true, deployed = true } },
        crew = {
            {
                uid = 201,
                name = "Grub",
                species = "human",
                health = 90,
                health_max = 100,
                room = 0,
                on_enemy_ship = false,
                skills = { 1, 1, 1, 1, 1, 1 },
            },
            {
                uid = 202,
                name = "Krix",
                species = "mantis",
                health = 40,
                health_max = 100,
                room = 1,
                on_enemy_ship = false,
                skills = { 1, 1, 1, 1, 1, 1 },
            },
        },
    }
    return raw
end

local function enemy_view(raw)
    return V.observe(nil, raw, {}).views.state.enemy
end

t.test("a Zoltan shield shows on either ship only when it has one", function()
    local raw = raw_with_systems()
    raw.player.zoltan, raw.player.zoltan_max = 3, 5
    t.eq(ship_view(raw).shields, { layers = 1, max_layers = 1, zoltan = 3, max_zoltan = 5 })
    raw = raw_with_enemy()
    t.eq(enemy_view(raw).shields.zoltan, nil)
    raw.enemy.zoltan, raw.enemy.zoltan_max = 0, 4 -- knocked down, but still fitted
    t.eq(enemy_view(raw).shields, { layers = 1, max_layers = 1, zoltan = 0, max_zoltan = 4 })
end)

t.test("with no enemy ship there is no enemy view", function()
    t.eq(enemy_view(raw_with_systems()), nil)
end)

t.test(
    "always visible: class, relationship, cloak, hull, shields, layout, doors, system names, deployed drones",
    function()
        local e = enemy_view(raw_with_enemy())
        t.eq(
            { e.class, e.hostile, e.cloaked, e.hull, e.hull_max },
            { "Rebel Fighter", true, false, 8, 10 }
        )
        t.eq(e.shields, { layers = 1, max_layers = 1 })
        t.eq(
            e.doors,
            { { id = "enemy:door:0", rooms = { "enemy:room:0", "enemy:room:1" }, open = true } }
        )
        t.eq(e.systems[1], { id = "enemy:system:weapons", name = "weapons", room = "enemy:room:0" })
        t.eq(e.drones, { { id = "enemy:drone:0", name = "Defense Drone" } })
        t.eq(e.sensors_level, 1)
    end
)

t.test("below Sensors 2 the interior, crew and weapons are hidden", function()
    local e = enemy_view(raw_with_enemy())
    t.eq(e.rooms[1], {
        id = "enemy:room:0",
        name = "weapons",
        x = 0,
        y = 0,
        w = 2,
        h = 2,
        hidden = "needs Sensors level 2",
    })
    t.eq(#e.crew, 0)
    t.eq(e.weapons, "needs Sensors level 3")
    t.eq({ e.evasion, e.oxygen }, { nil, nil })
end)

t.test("Sensors 2 (level 1 manned) shows rooms and crew with names and health", function()
    local raw = raw_with_enemy()
    raw.player.sensors_manned = true
    local e = enemy_view(raw)
    t.eq(e.sensors_level, 2)
    t.eq({ e.rooms[1].oxygen, e.rooms[1].fires, e.rooms[1].breaches }, { 100, 1, 1 })
    t.eq(e.crew[2], {
        id = "enemy:crew:202",
        name = "Krix",
        race = "mantis",
        room = "enemy:room:1",
        health = 40,
        health_max = 100,
    })
    t.eq(e.weapons, "needs Sensors level 3")
end)

t.test("Sensors 3 shows weapons and their charge", function()
    local raw = raw_with_enemy()
    raw.player.sensors_power = 3
    t.eq(enemy_view(raw).weapons, {
        {
            id = "enemy:weapon:0",
            name = "Basic Laser",
            charge = 3.2,
            charge_time = 10,
        },
    })
end)

t.test("system power, level, damage and ion need Sensors 4 (level 3 manned)", function()
    local raw = raw_with_enemy()
    raw.player.sensors_power = 3
    t.eq(enemy_view(raw).systems[2].power, nil)
    raw.player.sensors_manned = true
    local s = enemy_view(raw).systems[2]
    t.eq({ s.power, s.max_power, s.level, s.damage, s.ion }, { 2, 2, 2, 1, 0 })
end)

t.test("broken Sensors and nebulas give level 0; the Flagship caps it at 2", function()
    local raw = raw_with_enemy()
    raw.player.sensors_power, raw.player.sensors_manned = 0, true -- manning a broken system gives nothing
    t.eq(enemy_view(raw).sensors_level, 0)
    raw = raw_with_enemy()
    raw.player.sensors_power, raw.nebula = 3, true
    t.eq(enemy_view(raw).sensors_level, 0)
    raw = raw_with_enemy()
    raw.player.sensors_power, raw.player.sensors_manned, raw.enemy.flagship = 3, true, true
    t.eq(enemy_view(raw).sensors_level, 2)
end)

t.test("our crew aboard give vision of their room only", function()
    local raw = raw_with_enemy()
    raw.player.crew[1].on_enemy_ship, raw.player.crew[1].room = true, 1
    local e = enemy_view(raw)
    t.eq(e.rooms[2].oxygen, 80)
    t.eq(e.rooms[1].hidden, "needs Sensors level 2")
    t.eq(e.crew, { { id = "enemy:crew:202", race = "mantis", room = "enemy:room:1" } }) -- no name below Sensors 2
end)

t.test("a Slug or the Lifeform Scanner reveals where live enemy crew are", function()
    local raw = raw_with_enemy()
    raw.player.lifeform_scanner = true
    t.eq(#enemy_view(raw).crew, 2)
    raw = raw_with_enemy()
    raw.player.crew[1].species = "slug"
    t.eq(#enemy_view(raw).crew, 2)
    t.eq(enemy_view(raw).rooms[1].hidden, "needs Sensors level 2") -- crew only, no room vision
end)

t.test(
    "a cloak hides the interior except where our crew are, but Sensors 2+ still names crew",
    function()
        local raw = raw_with_enemy()
        raw.enemy.cloaked, raw.player.sensors_power, raw.player.lifeform_scanner = true, 3, true
        local e = enemy_view(raw)
        t.eq(e.rooms[1].hidden, "enemy is cloaked")
        t.eq({ #e.crew, e.crew[1].name, e.crew[1].health }, { 2, "Grub", 90 })
        t.eq(e.weapons, "enemy is cloaked")
    end
)

t.test(
    "a hacked system shows its room and its details, plus evasion or oxygen for those systems",
    function()
        local raw = raw_with_enemy()
        raw.enemy.hacked_system = 0 -- shields, room 1
        local e = enemy_view(raw)
        t.eq(e.rooms[2].oxygen, 80)
        t.eq(e.systems[2].power, 2)
        t.eq(e.evasion, nil)
        raw.enemy.hacked_system, raw.enemy.systems[2].type = 1, 1 -- engines
        raw.enemy.hacking_powered = true
        t.eq(enemy_view(raw).evasion, 25)
    end
)

t.test("never: evasion, oxygen, enemy skills, or a hidden room's contents", function()
    local raw = raw_with_enemy()
    raw.player.sensors_power, raw.player.sensors_manned = 3, true
    local e = enemy_view(raw)
    t.eq({ e.evasion, e.oxygen }, { nil, nil })
    for _, c in ipairs(e.crew) do
        t.eq(c.skills, nil)
    end
end)

t.test("enemy ships appearing, being destroyed and leaving make events", function()
    local none, enemy = raw_with_systems(), raw_with_enemy()
    t.eq(
        events(none, enemy),
        { { type = "enemy_appeared", class = "Rebel Fighter", hostile = true } }
    )
    local dead = raw_with_enemy()
    dead.enemy.destroyed = true
    t.eq(events(enemy, dead), { { type = "enemy_destroyed", class = "Rebel Fighter" } })
    t.eq(events(enemy, none), { { type = "enemy_left", class = "Rebel Fighter" } })
end)

t.test("enemy crew deaths are reported only if we could see that crew member", function()
    local before, after = raw_with_enemy(), raw_with_enemy()
    after.enemy.crew[2].dead = true
    t.eq(#events(before, after), 0) -- Sensors 1: crew not visible
    before.player.sensors_manned, after.player.sensors_manned = true, true
    t.eq(events(before, after), { { type = "enemy_crew_killed", crew = "enemy:crew:202 (Krix)" } })
end)

t.test("boarders on our ship: the warning always, details in rooms we can see", function()
    local raw = raw_with_enemy()
    local boarder = raw.enemy.crew[2]
    boarder.on_enemy_ship, boarder.room = true, 2 -- in our shields room
    local ship = V.observe(nil, raw, {}).views.state.ship
    t.eq(ship.intruders_detected, true)
    t.eq(ship.intruders, {
        {
            id = "enemy:crew:202",
            race = "mantis",
            room = "room:2",
            health = 40,
            health_max = 100,
        },
    })
    raw.player.sensors_power = 0 -- room 2 has no crew of ours: dark
    ship = V.observe(nil, raw, {}).views.state.ship
    t.eq({ ship.intruders_detected, #ship.intruders }, { true, 0 })
end)

-- #6 review: leaks that must stay closed.
t.test("a cloak hides even the hacked system's details", function()
    local raw = raw_with_enemy()
    raw.enemy.cloaked, raw.enemy.hacked_system = true, 0
    t.eq(enemy_view(raw).systems[2].power, nil)
end)

t.test("evasion and oxygen need Hacking powered, not just the drone attached", function()
    local raw = raw_with_enemy()
    raw.enemy.hacked_system, raw.enemy.systems[2].type, raw.enemy.hacking_powered = 1, 1, false
    t.eq(enemy_view(raw).evasion, nil)
    raw.enemy.hacking_powered = true
    t.eq(enemy_view(raw).evasion, 25)
end)

t.test("an enemy crew death names the crew only at Sensors 2+", function()
    local before, after = raw_with_enemy(), raw_with_enemy()
    before.player.lifeform_scanner, after.player.lifeform_scanner = true, true
    after.enemy.crew[2].dead = true
    t.eq(events(before, after), { { type = "enemy_crew_killed", crew = "enemy:crew:202" } })
end)

t.test("Slugs and the Lifeform Scanner don't sense crew drones", function()
    local raw = raw_with_enemy()
    raw.player.lifeform_scanner = true
    raw.enemy.crew[2].drone = true
    t.eq(#enemy_view(raw).crew, 1)
end)

t.test("sensed-only intruders show race and room but not health", function()
    local raw = raw_with_enemy()
    raw.enemy.crew[2].on_enemy_ship, raw.enemy.crew[2].room = true, 2
    raw.player.sensors_power, raw.player.lifeform_scanner = 0, true
    t.eq(V.observe(nil, raw, {}).views.state.ship.intruders, {
        { id = "enemy:crew:202", race = "mantis", room = "room:2" },
    })
end)

t.test("at Sensors 3 enemy weapons show charge but not power", function()
    local raw = raw_with_enemy()
    raw.player.sensors_power = 3
    t.eq(enemy_view(raw).weapons[1].powered, nil)
end)

t.test("a cloak hides enemy door states", function()
    local raw = raw_with_enemy()
    raw.enemy.cloaked = true
    t.eq(enemy_view(raw).doors[1].open, nil)
end)

t.test("in a nebula the hidden reason says so", function()
    local raw = raw_with_enemy()
    raw.nebula = true
    t.eq(enemy_view(raw).rooms[1].hidden, "Sensors don't work inside a nebula")
end)

t.test("enemy drones carry IDs", function()
    t.eq(enemy_view(raw_with_enemy()).drones, { { id = "enemy:drone:0", name = "Defense Drone" } })
end)

t.test("no enemy_left when we are the ones who jumped away", function()
    local before, after = raw_with_enemy(), raw_with_systems()
    before.map, after.map =
        { current = 0, beacons = {}, fleet = {} }, { current = 3, beacons = {}, fleet = {} }
    t.eq(#events(before, after), 1) -- only "arrived"
    t.eq(events(before, after)[1].type, "arrived")
end)

-- #7: combat events from game hooks.
local function hooks(raw, list)
    return V.observe(raw, raw, list).events
end

t.test("our shots, hits on the enemy and their shield blocks", function()
    local raw = raw_with_enemy()
    t.eq(
        hooks(raw, {
            { kind = "fire", by = 0, weapon = "Burst Laser Mark II", slot = 1 },
            { kind = "hit", ship = 1, room = 0, damage = 2 },
            { kind = "shield", ship = 1 },
            { kind = "miss", ship = 1 },
        }),
        {
            { type = "fired", by = "us", weapon = "weapon:1 (Burst Laser Mark II)" },
            { type = "hit", target = "enemy", room = "enemy:room:0 (weapons)", damage = 2 },
            { type = "shield_block", target = "enemy" },
            { type = "miss", target = "enemy" },
        }
    )
end)

t.test("enemy shots name the weapon only at Sensors 3+", function()
    local raw = raw_with_enemy()
    t.eq(
        hooks(raw, { { kind = "fire", by = 1, weapon = "Basic Laser", slot = 0 } }),
        { { type = "fired", by = "enemy" } }
    )
    raw.player.sensors_power = 3
    t.eq(
        hooks(raw, { { kind = "fire", by = 1, weapon = "Basic Laser", slot = 0 } }),
        { { type = "fired", by = "enemy", weapon = "enemy:weapon:0 (Basic Laser)" } }
    )
end)

t.test("hits on our ship name the room", function()
    t.eq(hooks(raw_with_enemy(), { { kind = "hit", ship = 0, room = 2, damage = 1 } }), {
        { type = "hit", target = "us", room = "room:2 (shields)", damage = 1 },
    })
end)

t.test("weapons show whether they are aimed, and the state shows autofire", function()
    local raw = raw_with_systems()
    raw.player.weapons[2].aimed = true
    raw.autofire = true
    local state = V.observe(nil, raw, {}).views.state
    t.eq(
        { state.ship.weapons[2].aimed, state.ship.weapons[1].aimed, state.autofire },
        { true, nil, true }
    )
end)

t.test("a hit outside any room names no room", function()
    t.eq(hooks(raw_with_enemy(), { { kind = "hit", ship = 1, damage = 1 } }), {
        { type = "hit", target = "enemy", damage = 1 },
    })
end)

-- #12: store and upgrades.
---@return RawState
local function raw_at_store()
    local raw = raw_with_systems()
    raw.player.scrap = 60
    raw.store = {
        open = false,
        items = {
            { name = "Burst Laser I", cost = 50, stock = 1, can_hold = true },
            { name = "Hull Repair", cost = 2, stock = 10, can_hold = true },
            { name = "Ion Blast II", cost = 70, stock = 1, can_hold = true },
            { name = "Defense Drone I", cost = 50, stock = 0, can_hold = true },
        },
    }
    raw.upgrades = {
        reactor = { level = 8, cost = 30 },
        systems = {
            { type = 0, level = 2, max_level = 8, cost = 20 },
            { type = 3, level = 3, max_level = 8 },
        },
    }
    return raw
end

t.test("the store lists items with price, stock and whether we can buy them", function()
    local store = V.observe(nil, raw_at_store(), {}).views.store --[[@as table]]
    t.eq(store.items[1], {
        id = "item:0",
        name = "Burst Laser I",
        cost = 50,
        stock = 1,
        affordable = true,
        can_hold = true,
    })
    t.eq(store.items[3].affordable, false) -- 70 > 60 scrap
    t.eq(store.items[4].stock, 0)
    t.eq(store.open, false)
end)

t.test("no store here, no store view", function()
    t.eq(V.observe(nil, raw_with_systems(), {}).views.store, nil)
end)

t.test("upgrades list the reactor and each system's next cost", function()
    local u = V.observe(nil, raw_at_store(), {}).views.upgrades --[[@as table]]
    t.eq(u.reactor, { level = 8, cost = 30, affordable = true })
    t.eq(
        u.systems[1],
        { id = "system:shields", level = 2, max_level = 8, cost = 20, affordable = true }
    )
    t.eq(u.systems[2], { id = "system:weapons", level = 3, max_level = 8, maxed = true })
end)

t.test("the store shows only when a human could open it", function()
    local raw = raw_at_store()
    raw.pause.event = true
    t.eq(V.observe(nil, raw, {}).views.store, nil)
    raw = raw_at_store()
    raw.enemy = raw_with_enemy().enemy -- hostile
    t.eq(V.observe(nil, raw, {}).views.store, nil)
end)

t.test("store items say whether they can be held, and opening the store is an event", function()
    local closed, open = raw_at_store(), raw_at_store()
    open.store.open = true
    t.eq((V.observe(nil, open, {}).views.store --[[@as table]]).items[1].can_hold, true)
    t.eq(events(closed, open), { { type = "store_opened" } })
end)

t.test("a destroyed enemy ship shows as destroyed", function()
    local raw = raw_with_enemy()
    raw.enemy.destroyed = true
    t.eq(enemy_view(raw).destroyed, true)
    t.eq(enemy_view(raw_with_enemy()).destroyed, nil)
end)

t.test("our ability status is shown", function()
    local raw = raw_with_systems()
    raw.player.abilities = { cloak = { on = true }, teleporter = { charged = false, charge = 40 } }
    t.eq(V.observe(nil, raw, {}).views.state.ship.abilities, {
        cloak = { on = true },
        teleporter = { charged = false, charge = 40 },
    })
end)
