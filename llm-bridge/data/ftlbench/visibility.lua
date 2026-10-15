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
---@field skills integer[] piloting, engines, shields, weapons, repair, combat

---@class RawShip
---@field hull integer
---@field hull_max integer
---@field scrap integer
---@field oxygen number?          whole-ship percentage
---@field sensors_power integer?  effective Sensors power (0 if missing, broken or ionized)
---@field rooms RawRoom[]?
---@field doors RawDoor[]?
---@field crew RawCrew[]?         own crew only

---@class RawState
---@field in_run boolean
---@field frame integer        bridge ticks since the Run started
---@field game_time number     unpaused game seconds since the Run started
---@field pause RawPause
---@field nebula boolean?
---@field player RawShip?

---@class Observation
---@field views { state: table }
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
    "mind control",
    "hacking",
}
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

---@param n number
---@return integer
local function round(n)
    return math.floor(n + 0.5)
end

---Rooms a human can see into on their own ship.
---@param raw RawState
---@param ship RawShip
---@return table<integer, boolean>? lit nil when every room is visible
local function lit_rooms(raw, ship)
    if (ship.sensors_power or 0) >= 1 and not raw.nebula then
        return nil
    end
    local lit = {}
    for _, c in ipairs(ship.crew or {}) do
        if not c.on_enemy_ship then
            lit[c.room] = true
            if c.species == "slug" then
                for _, d in ipairs(ship.doors or {}) do
                    if d.room1 == c.room and d.room2 >= 0 then
                        lit[d.room2] = true
                    elseif d.room2 == c.room then
                        lit[d.room1] = true
                    end
                end
            end
        end
    end
    return lit
end

---@param r RawRoom
---@param visible boolean
local function observe_room(r, visible)
    local room = {
        id = "room:" .. r.id,
        name = r.system and SYSTEM_NAMES[r.system + 1],
        x = math.floor(r.x / TILE),
        y = math.floor(r.y / TILE),
        w = math.floor(r.w / TILE),
        h = math.floor(r.h / TILE),
    }
    if visible then
        room.oxygen, room.fires, room.breaches = round(r.oxygen), r.fires, r.breaches
    else
        room.hidden = DARK
        if r.system then
            room.fires = r.fires -- fire icons show above systems even in the dark
        end
    end
    return room
end

---@param d RawDoor
local function observe_door(d)
    local other = d.room2 >= 0 and ("room:" .. d.room2) or "space"
    return { id = "door:" .. d.id, rooms = { "room:" .. d.room1, other }, open = d.open }
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
    for i, c in ipairs(ship.crew or {}) do
        view.crew[i] = observe_crew(c)
    end
    return view
end

---Build the Observation and the new Visible events.
---@param _prev RawState? raw state from the previous frame (nil on the first frame)
---@param raw RawState
---@param _hooks table[] game-hook occurrences since the previous frame
---@return Observation
function Visibility.observe(_prev, raw, _hooks)
    if not raw.in_run then
        return {
            views = { state = { in_run = false, paused = false, frame = 0, game_time = 0 } },
            events = {},
        }
    end
    return {
        views = {
            state = {
                in_run = true,
                paused = Visibility.is_paused(raw),
                frame = raw.frame,
                game_time = raw.game_time,
                ship = raw.player and observe_ship(raw, raw.player),
            },
        },
        events = {},
    }
end

FtlBench.Visibility = Visibility
