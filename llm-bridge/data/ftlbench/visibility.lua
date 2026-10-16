-- Visibility: turns raw state (everything the game knows) into the Observation
-- (only Visible state). Pure: no game access, no I/O. See ADR 0003 and 0004 and
-- docs/research/visible-state.md for the rules.

FtlBench = FtlBench or {}

---@class RawPause
---@field manual boolean  paused by spacebar or `ftl pause`
---@field event boolean   paused because an event window is open
---@field menu boolean    paused because a menu is open

---@class RawRoom
---@field id integer
---@field x integer       pixels (35 per tile)
---@field y integer
---@field w integer
---@field h integer
---@field system integer? FTL system type id
---@field oxygen number   0-100
---@field fires integer
---@field breaches integer

---@class RawDoor
---@field id integer      interior doors first, then airlocks
---@field room1 integer
---@field room2 integer   -1 for an airlock
---@field open boolean

---@class RawCrew
---@field uid integer     the game's stable crew id
---@field name string
---@field species string
---@field health number
---@field health_max number
---@field room integer
---@field on_enemy_ship boolean
---@field dead boolean?
---@field stun number?         seconds of stun left
---@field mind_controlled boolean?
---@field taking_damage boolean? health dropped within the last couple of seconds
---@field drone boolean?          a crew drone (not a lifeform)
---@field skills integer[] piloting, engines, shields, weapons, repair, combat

---@class RawSystem
---@field type integer          FTL system type id
---@field room integer
---@field power integer         power in use now
---@field level integer         installed level
---@field cap integer           most power it can take now (level minus damage and other limits)
---@field damage integer
---@field ion integer          ion locks on the system (0 when clear)
---@field ion_seconds number?  time left on the current ion lock
---@field uses_reactor boolean  false for subsystems (piloting, doors, sensors, battery)

---@class RawWeapon
---@field name string
---@field powered boolean
---@field power integer   reactor power needed
---@field charge number   seconds charged
---@field charge_time number
---@field missiles boolean
---@field beam boolean?
---@field aimed boolean?

---@class RawDrone
---@field name string
---@field powered boolean
---@field deployed boolean
---@field power integer   reactor power needed
---@field type string    the game's drone type, e.g. "COMBAT", "BOARDER", "DEFENSE"

---@class RawShip
---@field hull integer
---@field hull_max integer
---@field scrap integer
---@field oxygen number?          whole-ship percentage
---@field sensors_power integer?  Sensors power without the manning bonus (damage and ion each take a bar)
---@field rooms RawRoom[]?
---@field doors RawDoor[]?
---@field crew RawCrew[]?         own crew only (for the enemy: its crew; on_enemy_ship = aboard our ship)
---@field sensors_manned boolean?
---@field lifeform_scanner boolean?
---@field clone_queue integer?    dead crew waiting in the clone bay's queue
---@field backup_dna boolean?     the Backup DNA Bank augment (crew keep without a working clone bay)
---@field reactor { used: integer, max: integer }?
---@field systems RawSystem[]?
---@field augments string[]? names, as the ship screen shows them
---@field cargo string[]? names of the items in the cargo hold
---@field shield_layers integer?
---@field shield_layers_max integer?
---@field zoltan integer? Zoltan (super) shield HP left
---@field zoltan_max integer?
---@field evasion number?         percent
---@field fuel integer?
---@field missiles integer?
---@field drone_parts integer?
---@field weapons RawWeapon[]?    in slot order
---@field drones RawDrone[]?      in slot order
---@field ftl_charge number?
---@field abilities table<string, table>?  cloak/battery/hacking/mind/teleporter status (own ship: visible)
---@field ftl_charge_time number?

---@class RawBeacon
---@field id integer
---@field x number         map pixels
---@field y number
---@field links integer[]
---@field visited boolean?
---@field exit boolean?
---@field quest boolean?
---@field nebula boolean?
---@field store boolean?    true even where a human can't see it yet
---@field distress boolean?
---@field scouted boolean?  the game's Location.known: the ship has been next to it

---@class RawMap
---@field current integer
---@field beacons RawBeacon[]
---@field fleet { x: number, y: number, radius: number, advance: number }
---@field sector_choices { index: integer, type: integer }[]?  only at the exit beacon

---@class RawChoice
---@field text string
---@field blue boolean          a blue option (the ship meets a special requirement)
---@field available boolean     false when the game shows the option but won't allow it

---@class RawEvent
---@field text string
---@field choices RawChoice[]
---@field received table<string, number>  rewards the event window displays

---@class RawEnemy: RawShip
---@field class string
---@field hostile boolean
---@field cloaked boolean
---@field flagship boolean
---@field evasion number
---@field oxygen number
---@field hacked_system integer?  system type our hacking drone is attached to
---@field hacking_powered boolean? our Hacking system has power (needed for evasion/oxygen readouts)
---@field destroyed boolean?

---@class RawStoreItem
---@field name string
---@field cost integer
---@field stock integer
---@field can_hold boolean   room for it, and not already installed
---@field description string? the game's tooltip text: description, stats, scrap value

---@class RawUpgrades
---@field reactor { level: integer, cost: integer? }   cost nil at the maximum
---@field systems { type: integer, level: integer, max_level: integer, cost: integer?, description: string?, levels: { level: integer, cost: integer?, text: string }[]? }[]

---@class RawState
---@field in_run boolean
---@field frame integer        bridge ticks since the Run started
---@field game_time number     unpaused game seconds since the Run started
---@field pause RawPause
---@field window string?    "map", "upgrades" or "store" while the Agent has that window open
---@field refused_window string?  a window the game last refused to open for `show`
---@field nebula boolean?
---@field hazards { asteroids: boolean, sun: boolean, pulsar: boolean, pds: boolean, pds_target: integer }?  hazard icons; pds_target 0 us, 1 the enemy (allied ASB), 2 both
---@field sector integer?     1-8, shown on the HUD
---@field game_over boolean?
---@field victory boolean?
---@field score integer?      FTL's running Score; the game only shows it when the Run ends
---@field player RawShip?
---@field map RawMap?
---@field event RawEvent?    the open event window, if any
---@field enemy RawEnemy?
---@field texts table<string, string>? game text by name (warning banners and refusals)
---@field boarders RawCrew[]? enemy crew aboard our ship after their ship has gone
---@field autofire boolean?
---@field store { open: boolean, items: RawStoreItem[] }?  the store at this beacon, if any
---@field upgrades RawUpgrades?

---@class Observation
---@field views { state: table, map: table?, store: table?, upgrades: table? }
---@field events table[]

local Visibility = {}

local TILE = 35
-- Indexed by FTL system type id + 1.
local SYSTEM_NAMES = {
    "shields",
    "engines",
    "oxygen",
    "weapons",
    "drones",
    "medbay",
    "piloting",
    "sensors",
    "doors",
    "teleporter",
    "cloaking",
    "artillery",
    "battery",
    "clonebay",
    "mind_control",
    "hacking",
}
Visibility.SYSTEM_NAMES = SYSTEM_NAMES

---@param type integer FTL system type id
---@return string
function Visibility.system_id(type)
    return "system:" .. SYSTEM_NAMES[type + 1]
end
local SKILLS = { "piloting", "engines", "shields", "weapons", "repair", "combat" }
local DARK = "no crew in room and Sensors not working"
-- Marks a table as a list so the JSON encoder writes [] even when it is empty.
local LIST = { __jsontype = "array" }

---@param raw RawState
---@return boolean
function Visibility.is_paused(raw)
    local p = raw.pause
    return p.manual or p.event or p.menu
end

---Why the game is paused, or nil when it isn't.
---@param raw RawState
---@return string[]?
local function paused_by(raw)
    local p, out = raw.pause, nil
    -- The game also sets its menu pause for an event window, so "menu" means any other window.
    local event = Visibility.event_open(raw)
    local menu = p.menu and not event
    for _, reason in ipairs({ { p.manual, "player" }, { event, "event" }, { menu, "menu" } }) do
        if reason[1] then
            out = out or setmetatable({}, LIST)
            out[#out + 1] = reason[2]
        end
    end
    return out
end

---@param n number
---@return integer
local function round(n)
    return math.floor(n + 0.5)
end

---True when two rooms share a stretch of wall (touching corners don't count).
---@param a RawRoom
---@param b RawRoom
---@return boolean
local function share_wall(a, b)
    local across = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local along = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    return (across > 0 and (a.y + a.h == b.y or b.y + b.h == a.y))
        or (along > 0 and (a.x + a.w == b.x or b.x + b.w == a.x))
end

---Copy only the non-zero numbers, or nil when there are none.
---@param t table<string, number>?
---@return table<string, number>?
local function nonzero(t)
    local out
    for k, v in pairs(t or {}) do
        if v ~= 0 then
            out = out or {}
            out[k] = v
        end
    end
    return out
end

---Rooms a human can see into on their own ship.
---Slugs see into every room sharing a wall with theirs (visible-state.md section 1.2).
---@param raw RawState
---@param ship RawShip
---@return table<integer, boolean>? lit nil when every room is visible
local function lit_rooms(raw, ship)
    if (ship.sensors_power or 0) >= 1 and not raw.nebula then
        return nil
    end
    local lit = {}
    local by_id = {}
    for _, r in ipairs(ship.rooms or {}) do
        by_id[r.id] = r
    end
    for _, c in ipairs(ship.crew or {}) do
        if not c.on_enemy_ship and not c.dead then
            lit[c.room] = true
            local home = by_id[c.room]
            if c.species == "slug" and home then
                for _, r in ipairs(ship.rooms) do
                    if share_wall(home, r) then
                        lit[r.id] = true
                    end
                end
            end
        end
    end
    return lit
end

---Fire icons show above systems even in a dark room.
---@param r RawRoom
---@param visible boolean room is lit
---@return boolean
local function fire_visible(r, visible)
    return visible or r.system ~= nil
end

---@param r RawRoom
---@return string
local function room_label(r)
    local name = r.system and SYSTEM_NAMES[r.system + 1]
    return "room:" .. r.id .. (name and (" (" .. name .. ")") or "")
end

---@param c RawCrew
---@return string
local function crew_label(c)
    return ("crew:%d (%s)"):format(c.uid, c.name)
end

---@param r RawRoom
---@param visible boolean
---@param prefix string? "enemy:" for the enemy ship
---@param hidden string? why a dark room is hidden
local function observe_room(r, visible, prefix, hidden)
    local room = {
        id = (prefix or "") .. "room:" .. r.id,
        name = r.system and SYSTEM_NAMES[r.system + 1],
        x = math.floor(r.x / TILE),
        y = math.floor(r.y / TILE),
        w = math.floor(r.w / TILE),
        h = math.floor(r.h / TILE),
    }
    if visible then
        room.oxygen, room.fires, room.breaches = round(r.oxygen), r.fires, r.breaches
    else
        room.hidden = hidden or DARK
        if not prefix and fire_visible(r, false) then -- unverified for the enemy ship, so hidden there
            room.fires = r.fires
        end
    end
    return room
end

---@param d RawDoor
---@param prefix string? "enemy:" for the enemy ship
local function observe_door(d, prefix)
    prefix = prefix or ""
    local other = d.room2 >= 0 and (prefix .. "room:" .. d.room2) or "space"
    return {
        id = prefix .. "door:" .. d.id,
        rooms = { prefix .. "room:" .. d.room1, other },
        open = d.open,
    }
end

---@param c RawCrew
local function observe_crew(c)
    local skills = {}
    for i, name in ipairs(SKILLS) do
        skills[name] = c.skills[i]
    end
    return {
        id = "crew:" .. c.uid,
        name = c.name,
        race = c.species,
        health = round(c.health),
        health_max = round(c.health_max),
        room = (c.on_enemy_ship and "enemy:room:" or "room:") .. c.room,
        skills = skills,
    }
end

---Round to one decimal place (string.format would round 0.25 down).
---@param n number
---@return number
local function tenths(n)
    return math.floor(n * 10 + 0.5) / 10
end

---@param s RawSystem
local function observe_system(s)
    local name = SYSTEM_NAMES[s.type + 1]
    return {
        id = Visibility.system_id(s.type),
        name = name,
        room = "room:" .. s.room,
        power = s.power,
        max_power = s.cap,
        level = s.level,
        damage = s.damage,
        ion = s.ion,
        ion_seconds = s.ion > 0 and s.ion_seconds and tenths(s.ion_seconds) or nil,
        subsystem = not s.uses_reactor,
    }
end

Visibility.tenths = tenths

---@param ship RawShip
---@param view table
local function observe_power(ship, view)
    view.reactor = ship.reactor and { used = ship.reactor.used, max = ship.reactor.max }
    if ship.shield_layers then
        view.shields = { layers = ship.shield_layers, max_layers = ship.shield_layers_max }
        if (ship.zoltan_max or 0) > 0 then
            view.shields.zoltan, view.shields.max_zoltan = ship.zoltan, ship.zoltan_max
        end
    end
    view.evasion, view.fuel = ship.evasion and round(ship.evasion), ship.fuel
    view.missiles, view.drone_parts = ship.missiles, ship.drone_parts
    view.systems = setmetatable({}, LIST)
    for i, s in ipairs(ship.systems or {}) do
        view.systems[i] = observe_system(s)
    end
    view.weapons = setmetatable({}, LIST)
    for i, w in ipairs(ship.weapons or {}) do
        view.weapons[i] = {
            id = "weapon:" .. (i - 1),
            name = w.name,
            powered = w.powered,
            power = w.power,
            charge = tenths(w.charge),
            charge_time = tenths(w.charge_time),
            uses_missiles = w.missiles,
            aimed = w.aimed or nil,
        }
    end
    view.drones = setmetatable({}, LIST)
    for i, d in ipairs(ship.drones or {}) do
        view.drones[i] =
            { id = "drone:" .. (i - 1), name = d.name, powered = d.powered, deployed = d.deployed }
    end
    for field, kind in pairs({ augments = "augment", cargo = "cargo" }) do -- as the ship screen lists them
        view[field] = setmetatable({}, LIST)
        for i, name in ipairs(ship[field] or {}) do
            view[field][i] = { id = kind .. ":" .. (i - 1), name = name }
        end
    end
end

---@param raw RawState
---@return boolean
local function senses_lifeforms(raw)
    local ship = raw.player or {}
    if ship.lifeform_scanner then
        return true
    end
    for _, c in ipairs(ship.crew or {}) do
        if c.species == "slug" and not c.dead then
            return true
        end
    end
    return false
end

---Enemy crew aboard our ship: the warning always shows; details only where we can see or sense.
---@param raw RawState
---@param lit table<integer, boolean>? our lit rooms (nil when all are lit)
---@param view table
local function observe_intruders(raw, lit, view)
    view.intruders = setmetatable({}, LIST)
    local sense = senses_lifeforms(raw)
    for _, c in ipairs(raw.enemy and raw.enemy.crew or raw.boarders or {}) do
        if c.on_enemy_ship and not c.dead then
            view.intruders_detected = true
            local in_sight = lit == nil or lit[c.room] == true
            if in_sight or (sense and not c.drone) then
                local intruder =
                    { id = "enemy:crew:" .. c.uid, race = c.species, room = "room:" .. c.room }
                if in_sight then -- health bars need room vision; unverified for sensed-only crew
                    intruder.health, intruder.health_max = round(c.health), round(c.health_max)
                end
                view.intruders[#view.intruders + 1] = intruder
            end
        end
    end
end

---@param raw RawState
---@param ship RawShip
local function observe_ship(raw, ship)
    local view = { hull = ship.hull, hull_max = ship.hull_max, scrap = ship.scrap }
    if not ship.rooms then
        return view
    end
    local lit = lit_rooms(raw, ship)
    view.oxygen = ship.oxygen and round(ship.oxygen)
    view.rooms = setmetatable({}, LIST)
    view.doors = setmetatable({}, LIST)
    view.crew = setmetatable({}, LIST)
    for i, r in ipairs(ship.rooms) do
        view.rooms[i] = observe_room(r, lit == nil or lit[r.id] == true)
    end
    for i, d in ipairs(ship.doors or {}) do
        view.doors[i] = observe_door(d)
    end
    for _, c in ipairs(ship.crew or {}) do
        if not c.dead then
            view.crew[#view.crew + 1] = observe_crew(c)
        end
    end
    observe_power(ship, view)
    observe_intruders(raw, lit, view)
    view.abilities = ship.abilities
    return view
end

---What a finished Run reports, in the state view and the game_over event alike.
---@param raw RawState
local function run_result(raw)
    return { victory = raw.victory == true, score = raw.score, sector = raw.sector }
end

---@param list table[]?
---@param key string
---@return table<any, table>
local function index_by(list, key)
    local out = {}
    for _, item in ipairs(list or {}) do
        out[item[key]] = item
    end
    return out
end

---0-3: how many of the 25/50/75 percent health marks a crew member is above.
---@param c RawCrew
---@return integer
local function health_band(c)
    local f = c.health / c.health_max
    return (f > 0.75 and 3) or (f > 0.5 and 2) or (f > 0.25 and 1) or 0
end

---@param raw RawState
---@param before RawShip
---@param after RawShip
---@param events table[]
local function room_events(raw, before, after, events)
    local lit = lit_rooms(raw, after)
    local old = index_by(before.rooms, "id")
    for _, r in ipairs(after.rooms or {}) do
        local was, visible = old[r.id], lit == nil or lit[r.id] == true
        if was then
            local label = room_label(r)
            if fire_visible(r, visible) then
                if was.fires == 0 and r.fires > 0 then
                    events[#events + 1] = { type = "fire_started", room = label, fires = r.fires }
                elseif was.fires > 0 and r.fires == 0 then
                    events[#events + 1] = { type = "fire_out", room = label }
                end
            end
            if visible then
                if was.breaches == 0 and r.breaches > 0 then
                    events[#events + 1] = { type = "breach", room = label, breaches = r.breaches }
                elseif was.breaches > 0 and r.breaches == 0 then
                    events[#events + 1] = { type = "breach_repaired", room = label }
                end
            end
        end
    end
end

---@param before RawShip
---@param after RawShip
---@param events table[]
local function crew_events(before, after, events)
    local old = index_by(before.crew, "uid")
    for _, c in ipairs(after.crew or {}) do
        local was = old[c.uid]
        if was and not was.dead then
            local label = crew_label(c)
            if c.dead then
                events[#events + 1] = { type = "crew_killed", crew = label }
            elseif
                (c.taking_damage and not was.taking_damage) or health_band(c) < health_band(was)
            then
                events[#events + 1] = {
                    type = "crew_hurt",
                    crew = label,
                    health = round(c.health),
                    health_max = round(c.health_max),
                }
            end
            if not c.dead and (was.stun or 0) <= 0 and (c.stun or 0) > 0 then
                events[#events + 1] =
                    { type = "crew_stunned", crew = label, seconds = tenths(c.stun) }
            elseif not c.dead and (was.stun or 0) > 0 and (c.stun or 0) <= 0 then
                events[#events + 1] = { type = "crew_recovered", crew = label }
            end
        end
    end
end

---@param before RawShip
---@param after RawShip
---@param events table[]
local function system_events(before, after, events)
    local old = index_by(before.systems, "type")
    for _, s in ipairs(after.systems or {}) do
        local was = old[s.type]
        if was and was.ion == 0 and s.ion > 0 then
            events[#events + 1] =
                { type = "system_ionized", system = Visibility.system_id(s.type), ion = s.ion }
        elseif was and was.ion > 0 and s.ion == 0 then
            events[#events + 1] =
                { type = "system_ion_cleared", system = Visibility.system_id(s.type) }
        end
        if was and s.damage ~= was.damage then
            events[#events + 1] = {
                type = s.damage > was.damage and "system_damaged" or "system_repaired",
                system = Visibility.system_id(s.type),
                damage = s.damage,
            }
        end
    end
end

local observe_enemy -- defined below with the other views; events compare enemy views too

---@param prev RawState
---@param raw RawState
---@return boolean
local function we_jumped(prev, raw)
    return prev.map ~= nil and raw.map ~= nil and prev.map.current ~= raw.map.current
end

---@param prev RawState
---@param raw RawState
---@param events table[]
local function enemy_events(prev, raw, events)
    local was, now = prev.enemy, raw.enemy
    if now and not now.destroyed and not (was and not was.destroyed) then
        events[#events + 1] = { type = "enemy_appeared", class = now.class, hostile = now.hostile }
    elseif was and not was.destroyed and now and now.destroyed then
        events[#events + 1] = { type = "enemy_destroyed", class = was.class }
    elseif was and not was.destroyed and not now and not we_jumped(prev, raw) then
        events[#events + 1] = { type = "enemy_left", class = was.class }
    end
    if was and now then
        local seen = index_by(observe_enemy(prev, was).crew, "id")
        for _, c in ipairs(now.crew or {}) do
            local id = "enemy:crew:" .. c.uid
            local visible = seen[id]
            if c.dead and visible then
                local label = visible.name and ("%s (%s)"):format(id, visible.name) or id
                events[#events + 1] = { type = "enemy_crew_killed", crew = label }
            end
        end
    end
end

---Combat seen as it happens: shots, hits, shield blocks and misses (game hooks this frame).
---@param raw RawState
---@param hooks table[]
---@param events table[]
local function hook_events(raw, hooks, events)
    local function room(ship_id, id)
        local ship = ship_id == 0 and raw.player or raw.enemy
        local r = ship and index_by(ship.rooms, "id")[id]
        local label = r and room_label(r) or ("room:" .. id)
        return (ship_id == 0 and "" or "enemy:") .. label
    end
    local target = { [0] = "us", [1] = "enemy" }
    local enemy_weapons_seen = #hooks > 0
        and raw.enemy ~= nil
        and type(observe_enemy(raw, raw.enemy).weapons) == "table"
    for _, h in ipairs(hooks) do
        if h.kind == "fire" then
            local e = { type = "fired", by = target[h.by] }
            if h.by == 0 then
                e.weapon = ("weapon:%d (%s)"):format(h.slot, h.weapon)
            elseif enemy_weapons_seen then
                e.weapon = ("enemy:weapon:%d (%s)"):format(h.slot, h.weapon) -- named only when visible
            end
            events[#events + 1] = e
        elseif h.kind == "hit" then
            events[#events + 1] = {
                type = "hit",
                target = target[h.ship],
                room = h.room and room(h.ship, h.room), -- nil when the shot landed outside any room
                damage = h.damage,
            }
        elseif h.kind == "shield" then
            events[#events + 1] = { type = "shield_block", target = target[h.ship] }
        elseif h.kind == "miss" then
            events[#events + 1] = { type = "miss", target = target[h.ship] }
        end
    end
end

---Events a human would notice, found by comparing this frame with the previous one.
-- ponytail: a load that lands straight on the game-over screen has no previous frame, so no event.
---@param prev RawState?
---@param raw RawState
---@param hooks table[]?
---@return table[]
local function observe_events(prev, raw, hooks)
    local events = {}
    if prev and prev.player and raw.player then
        room_events(raw, prev.player, raw.player, events)
        crew_events(prev.player, raw.player, events)
        system_events(prev.player, raw.player, events)
    end
    if prev and prev.map and raw.map then
        if prev.sector ~= raw.sector then
            events[#events + 1] = { type = "new_sector", sector = raw.sector }
        elseif prev.map.current ~= raw.map.current then
            events[#events + 1] = { type = "arrived", beacon = "beacon:" .. raw.map.current }
        end
    end
    if raw.event and not (prev and prev.event and prev.event.text == raw.event.text) then
        events[#events + 1] = {
            type = "event",
            text = raw.event.text,
            choices = #raw.event.choices,
            received = nonzero(raw.event.received),
        }
    end
    if prev then
        enemy_events(prev, raw, events)
    end
    hook_events(raw, hooks or {}, events)
    if prev and raw.store and raw.store.open and not (prev.store and prev.store.open) then
        events[#events + 1] = { type = "store_opened" }
    end
    if prev and raw.game_over and not prev.game_over then
        local event = run_result(raw)
        event.type = "game_over"
        events[#events + 1] = event
    end
    return events
end

---@param e RawEvent
local function observe_event(e)
    local choices = setmetatable({}, LIST)
    for i, c in ipairs(e.choices) do
        choices[i] = {
            id = "choice:" .. (i - 1),
            text = c.text,
            blue = c.blue or nil,
            available = c.available,
            -- No resource hints: whether the game fills them for hidden-outcome choices is unverified (#14).
        }
    end
    return { text = e.text, choices = choices, received = nonzero(e.received) }
end

local ENGINES, OXYGEN, PILOTING = 1, 2, 6
local HACK_EVASION = { [ENGINES] = true, [PILOTING] = true }

---Our effective Sensors level against the enemy (visible-state.md section 1.1).
---@param raw RawState
---@param enemy RawEnemy
---@return integer
local function sensors_level(raw, enemy)
    local ship = raw.player or {}
    local power = ship.sensors_power or 0
    if raw.nebula or power <= 0 then
        return 0
    end
    -- Damaged or ionized systems can't be manned, so they lose the manning bonus (visible-state.md Q2).
    local sensors = index_by(ship.systems, "type")[7]
    local hurt = sensors and (sensors.damage > 0 or sensors.ion > 0)
    local level = math.min(power + ((ship.sensors_manned and not hurt) and 1 or 0), 4)
    return enemy.flagship and math.min(level, 2) or level
end

---Enemy rooms we can see into, and why the others are hidden.
---@param raw RawState
---@param enemy RawEnemy
---@param level integer
---@return table<integer, boolean> visible
---@return string hidden
local function enemy_room_vision(raw, enemy, level)
    local seen = {}
    local hidden = raw.nebula and "Sensors don't work inside a nebula" or "needs Sensors level 2"
    local rooms = index_by(enemy.rooms, "id")
    for _, c in ipairs((raw.player or {}).crew or {}) do
        if c.on_enemy_ship and not c.dead then
            seen[c.room] = true
            if c.species == "slug" and not enemy.cloaked and rooms[c.room] then
                for _, r in ipairs(enemy.rooms) do
                    if share_wall(rooms[c.room], r) then
                        seen[r.id] = true
                    end
                end
            end
        end
    end
    for _, c in ipairs(enemy.crew or {}) do
        if c.mind_controlled and not c.on_enemy_ship then
            seen[c.room] = true
        end
    end
    if enemy.cloaked then
        return seen, "enemy is cloaked"
    end
    if level >= 2 then
        for _, r in ipairs(enemy.rooms) do
            seen[r.id] = true
        end
    end
    for _, s in ipairs(enemy.systems or {}) do
        if s.type == enemy.hacked_system then
            seen[s.room] = true
        end
    end
    return seen, hidden
end

---@param raw RawState
---@param enemy RawEnemy
function observe_enemy(raw, enemy)
    local level = sensors_level(raw, enemy)
    local seen, hidden = enemy_room_vision(raw, enemy, level)
    local view = {
        class = enemy.class,
        hostile = enemy.hostile,
        cloaked = enemy.cloaked,
        destroyed = enemy.destroyed or nil,
        hull = enemy.hull,
        hull_max = enemy.hull_max,
        shields = {
            layers = enemy.shield_layers,
            max_layers = enemy.shield_layers_max,
            zoltan = (enemy.zoltan_max or 0) > 0 and enemy.zoltan or nil,
            max_zoltan = (enemy.zoltan_max or 0) > 0 and enemy.zoltan_max or nil,
        },
        sensors_level = level,
        rooms = setmetatable({}, LIST),
        doors = setmetatable({}, LIST),
        systems = setmetatable({}, LIST),
        crew = setmetatable({}, LIST),
        drones = setmetatable({}, LIST),
    }
    for i, r in ipairs(enemy.rooms) do
        view.rooms[i] = observe_room(r, seen[r.id] == true, "enemy:", hidden)
    end
    for i, d in ipairs(enemy.doors or {}) do
        view.doors[i] = observe_door(d, "enemy:")
        if enemy.cloaked then
            view.doors[i].open = nil -- unverified whether doors can be seen through a cloak
        end
    end
    for i, s in ipairs(enemy.systems or {}) do
        local sys = observe_system(s)
        local detailed = not enemy.cloaked and (s.type == enemy.hacked_system or level >= 4)
        view.systems[i] = detailed and sys or { id = sys.id, name = sys.name, room = sys.room }
        view.systems[i].id, view.systems[i].room = "enemy:" .. sys.id, "enemy:" .. sys.room
    end
    local detect = not enemy.cloaked and senses_lifeforms(raw)
    for _, c in ipairs(enemy.crew or {}) do
        local sensed = detect and not c.drone -- Slugs and the scanner sense lifeforms only
        if not c.dead and not c.on_enemy_ship and (seen[c.room] or level >= 2 or sensed) then
            local crew =
                { id = "enemy:crew:" .. c.uid, race = c.species, room = "enemy:room:" .. c.room }
            if level >= 2 then
                crew.name, crew.health, crew.health_max =
                    c.name, round(c.health), round(c.health_max)
            end
            view.crew[#view.crew + 1] = crew
        end
    end
    if enemy.cloaked then
        view.weapons = "enemy is cloaked"
    elseif level < 3 then
        view.weapons = "needs Sensors level 3"
    else
        view.weapons = setmetatable({}, LIST)
        for i, w in ipairs(enemy.weapons or {}) do
            view.weapons[i] = {
                id = "enemy:weapon:" .. (i - 1),
                name = w.name, -- power use is a Sensors 4 datum, so not shown at level 3
                charge = tenths(w.charge),
                charge_time = tenths(w.charge_time),
            }
        end
    end
    for i, d in ipairs(enemy.drones or {}) do
        if d.deployed then
            view.drones[#view.drones + 1] = { id = "enemy:drone:" .. (i - 1), name = d.name }
        end
    end
    local readout = enemy.hacking_powered and not enemy.cloaked
    if readout and HACK_EVASION[enemy.hacked_system] then
        view.evasion = round(enemy.evasion)
    elseif readout and enemy.hacked_system == OXYGEN then
        view.oxygen = round(enemy.oxygen)
    end
    return view
end

---@param raw RawState
local function observe_store(raw)
    local scrap = (raw.player or {}).scrap or 0
    local items = setmetatable({}, LIST)
    for i, it in ipairs(raw.store.items) do
        items[i] = {
            id = "item:" .. (i - 1),
            name = it.name,
            cost = it.cost,
            stock = it.stock,
            affordable = scrap >= it.cost,
            can_hold = it.can_hold,
            description = it.description,
        }
    end
    return { open = raw.store.open, items = items }
end

---The upgrade screen's level list: every level, the price of those not yet bought, and its text
---(blank for some levels, which then carry none).
---@param levels { level: integer, cost: integer?, text: string }[]
local function levels_view(levels)
    local out = setmetatable({}, LIST)
    for i, l in ipairs(levels) do
        out[i] = { level = l.level, cost = l.cost, text = l.text ~= "" and l.text or nil }
    end
    return out
end

---@param raw RawState
local function observe_upgrades(raw)
    local scrap = (raw.player or {}).scrap or 0
    local function priced(entry, cost)
        if cost then
            entry.cost, entry.affordable = cost, scrap >= cost
        else
            entry.maxed = true
        end
        return entry
    end
    local u = raw.upgrades --[[@as RawUpgrades]]
    local systems = setmetatable({}, LIST)
    for i, s in ipairs(u.systems) do
        systems[i] = priced({
            id = Visibility.system_id(s.type),
            level = s.level,
            max_level = s.max_level,
            description = s.description,
            levels = s.levels and levels_view(s.levels),
        }, s.cost)
    end
    return { reactor = priced({ level = u.reactor.level }, u.reactor.cost), systems = systems }
end

---The enemy as we can see it right now (nil with no enemy ship), for rules such as "can target".
---@param raw RawState
---@return table?
function Visibility.enemy_view(raw)
    return raw.enemy and observe_enemy(raw, raw.enemy)
end

-- Indexed by FTL Sector.type + 1 (4 = unknown; visible-state.md I6).
local SECTOR_TYPES = { "civilian", "hostile", "nebula", "unknown", "unknown" }

---Jumps until the rebel fleet's circle reaches a point, at its current advance per jump.
---@param fleet { x: number, y: number, radius: number, advance: number }
---@param b RawBeacon
---@return integer?
local function jumps_until_fleet(fleet, b)
    local gap = math.sqrt((b.x - fleet.x) ^ 2 + (b.y - fleet.y) ^ 2) - fleet.radius
    if gap < 0 then
        return 0
    elseif fleet.advance <= 0 then
        return nil
    end
    return math.ceil(gap / fleet.advance)
end

---Beacon ids linked to the current beacon, in map order.
---@param map RawMap
---@return integer[]
function Visibility.current_links(map)
    for _, b in ipairs(map.beacons) do
        if b.id == map.current then
            return b.links
        end
    end
    return {}
end

---@param map RawMap
---@return table<integer, boolean>
local function adjacent_to_current(map)
    local near = {}
    for _, l in ipairs(Visibility.current_links(map)) do
        near[l] = true
    end
    return near
end

---Whether an event box is up. It can show with only the menu pause set (seen live: a store's
---greeting box), so the box itself counts too. It blocks the ship, as in the game.
---@param raw RawState
---@return boolean
function Visibility.event_open(raw)
    return raw.pause.event or raw.event ~= nil
end

---Why the ship can't jump right now, or nil when it can. Commands give the same reasons.
---@param raw RawState
---@return string?
function Visibility.jump_blocker(raw)
    local ship = raw.player or {}
    if Visibility.event_open(raw) then
        return "an event is open"
    elseif (ship.fuel or 0) < 1 then
        return "no fuel"
    elseif (ship.ftl_charge or 0) < (ship.ftl_charge_time or 1) then
        local systems = index_by(ship.systems, "type")
        local piloting, engines = systems[6], systems[1]
        -- The drive charges only with both systems running (damage and ion both take power away).
        if piloting and piloting.power < 1 then
            return "Piloting has no power (the FTL drive needs it to charge)"
        elseif engines and engines.power < 1 then
            return "Engines have no power (the FTL drive needs them to charge)"
        elseif piloting then -- at every level: the autopilot only dodges (wiki Piloting)
            local manned = false
            for _, c in ipairs(ship.crew or {}) do
                local able = not (c.dead or c.drone or c.mind_controlled or (c.stun or 0) > 0)
                manned = manned or (c.room == piloting.room and not c.on_enemy_ship and able)
            end
            if not manned then
                return "Piloting is unmanned (the FTL drive charges only with a pilot)"
            end
        end
        return ("FTL drive charging (%.1f of %.1f)"):format(
            tenths(ship.ftl_charge or 0),
            tenths(ship.ftl_charge_time or 1)
        )
    end
    return nil
end

---The FTL drive as the HUD shows it: fuel, charge, and whether (or why not) it can jump now.
---@param raw RawState
local function drive_status(raw)
    local ship = raw.player or {}
    local blocker = Visibility.jump_blocker(raw)
    local not_ready = blocker and blocker:match("^[^(]+"):gsub("%s+$", "")
    return {
        fuel = ship.fuel or 0,
        ftl_charge = tenths(ship.ftl_charge or 0),
        ftl_charge_time = tenths(ship.ftl_charge_time or 1),
        ready = not_ready == nil,
        not_ready = not_ready,
    }
end

---@param raw RawState
---@param map RawMap
local function observe_map(raw, map)
    local near = adjacent_to_current(map)
    local beacons = setmetatable({}, LIST)
    for i, b in ipairs(map.beacons) do
        local links = setmetatable({}, LIST)
        for j, l in ipairs(b.links) do
            links[j] = "beacon:" .. l
        end
        -- Store and distress markers show for beacons within one jump, and stay afterwards.
        local scouted = near[b.id] or b.scouted or b.visited
        local until_fleet = jumps_until_fleet(map.fleet, b)
        beacons[i] = {
            id = "beacon:" .. b.id,
            x = round(b.x),
            y = round(b.y),
            links = links,
            current = b.id == map.current or nil,
            reachable = near[b.id] or nil, -- linked to the current beacon: a jump away now
            visited = b.visited or nil,
            exit = b.exit or nil,
            quest = b.quest or nil,
            nebula = b.nebula or nil,
            store = scouted and b.store or nil,
            distress = scouted and b.distress or nil,
            fleet = until_fleet == 0 or nil,
            jumps_until_fleet = until_fleet,
        }
    end
    local sectors = setmetatable({}, LIST)
    for i, s in ipairs(map.sector_choices or {}) do
        sectors[i] = { id = "sector:" .. s.index, type = SECTOR_TYPES[s.type + 1] }
    end
    return { sector = raw.sector, beacons = beacons, sectors = sectors, drive = drive_status(raw) }
end

---The game's text by name (text_misc.xml warning_*) on one line; the name when the bridge has none.
---@param raw RawState
---@param name string
---@return string
function Visibility.text(raw, name)
    return (((raw.texts or {})[name] or name):gsub("\\n", " "):gsub("%s*\n%s*", " "))
end

---The text under the hazard icons: the first icon's (asteroids, sun, pulsar, ASB, nebula), as the
---game picks it. Nil at a beacon with no hazard.
---@param raw RawState
---@return string?
local function hazard_text(raw)
    local hz = raw.hazards or {}
    if hz.pds and not (hz.asteroids or hz.sun or hz.pulsar) and (hz.pds_target or 0) ~= 0 then
        return hz.pds_target == 1 and "warning_pds_allies" or "warning_pds_all"
    elseif hz.asteroids or hz.sun or hz.pulsar or hz.pds or raw.nebula then
        return "warning_environment_danger"
    end
    return nil
end

---The game's red WARNING banners that are up now, in its own words (text_misc.xml; the conditions
---are its own notes there). Nil when none is up.
---@param raw RawState
---@param ship table our ship's view (for intruders as the player sees them)
---@return string[]?
local function warnings(raw, ship)
    local p = raw.player --[[@as RawShip]]
    local out = nil
    local systems = index_by(p.systems or {}, "type")
    local shields, engines, clonebay = systems[0], systems[1], systems[13] -- 13: Clone Bay
    local hazard = hazard_text(raw)
    local hull = p.hull / math.max(p.hull_max, 1)
    for _, w in ipairs({
        { hull <= 0.25, "warning_hull_25" }, -- the worst hull banner only
        { hull > 0.25 and hull <= 0.5, "warning_hull_50" },
        { hull > 0.5 and hull <= 0.75, "warning_hull_75" },
        {
            shields and shields.damage > 0 and shields.level - shields.damage <= 1,
            "warning_shields",
        },
        { (p.oxygen or 100) < 25, "warning_oxygen" },
        { ship.intruders_detected, "warning_intruders" },
        { engines and engines.damage >= engines.level, "warning_engine" },
        { -- the clone bay box's banner: a dead crew member will be lost without power
            clonebay and clonebay.power < 1 and (p.clone_queue or 0) > 0 and not p.backup_dna,
            "warning_clone_off_1",
            "warning_clone_off_2",
        },
        { hazard ~= nil, hazard }, -- the text under the first hazard icon, if any
    }) do
        if w[1] then
            out = out or setmetatable({}, LIST)
            local text = Visibility.text(raw, w[2])
            out[#out + 1] = w[3] and text .. " " .. Visibility.text(raw, w[3]) or text
        end
    end
    return out
end

---Build the Observation and the new Visible events.
---@param prev RawState? raw state from the previous frame (nil on the first frame)
---@param raw RawState
---@param hooks table[] game-hook occurrences since the previous frame
---@return Observation
function Visibility.observe(prev, raw, hooks)
    if not raw.in_run then
        return {
            views = { state = { in_run = false, paused = false, frame = 0, game_time = 0 } },
            events = {},
        }
    end
    local out = {
        views = {
            state = {
                in_run = true,
                paused = Visibility.is_paused(raw),
                paused_by = paused_by(raw),
                frame = raw.frame,
                game_time = raw.game_time,
                ship = raw.player and observe_ship(raw, raw.player),
                sector = raw.sector,
                event = raw.event and observe_event(raw.event),
                enemy = raw.enemy and observe_enemy(raw, raw.enemy),
                autofire = raw.autofire or nil,
            },
        },
        events = setmetatable(observe_events(prev, raw, hooks), LIST),
    }
    if out.views.state.ship then
        out.views.state.ship.ftl_drive = drive_status(raw) -- on the HUD, so no window needed
        out.views.state.warnings = warnings(raw, out.views.state.ship)
    end
    -- A human can open the store only with no event window up and no hostile ship here.
    local store_usable = raw.store
        and not raw.pause.event
        and not raw.event
        and not (raw.enemy and raw.enemy.hostile)
    out.views.store = store_usable and observe_store(raw) or nil
    out.views.upgrades = raw.upgrades and observe_upgrades(raw)
    if raw.map then
        out.views.map = observe_map(raw, raw.map)
    end
    if raw.game_over then
        local state = out.views.state
        local result = run_result(raw)
        state.game_over, state.victory, state.score = true, result.victory, result.score
    end
    return out
end

FtlBench.Visibility = Visibility
