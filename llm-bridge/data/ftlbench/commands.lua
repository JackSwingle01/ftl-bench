-- Commands: the only Command parser. Turns Command text plus raw state into a
-- resolved Command or an error message. Pure: no game access, no I/O.

FtlBench = FtlBench or {}

---@class ResolvedCommand
---@field kind "pause"|"unpause"|"wait"|"move"|"door"|"power"|"weapon"|"drone"|"jump"|"jump_sector"|"choose"|"target"|"untarget"|"autofire"
---@field seconds number?   wait
---@field crew integer?     move: crew uid
---@field room integer?     move: room id
---@field enemy boolean?    move: room is on the enemy ship
---@field doors integer[]?  door: door ids
---@field open boolean?     door
---@field system integer?   power: FTL system type id
---@field delta integer?    power: change in power
---@field slot integer?     weapon, drone: slot index
---@field on boolean?       weapon, drone
---@field beacon integer?   jump
---@field sector integer?   jump_sector: index of the chosen sector
---@field choice integer?   choose: 0-based choice index
---@field rooms integer[]?  target: enemy room ids (two for a beam)

local Commands = {}

-- Commands that still work while an event window is open.
local EVENT_SAFE = { choose = true, wait = true, pause = true, unpause = true }

local WAIT_ERROR = "wait takes 0.1 to 10 seconds in steps of 0.1"

---Parse an ID like "room:4" or "enemy:room:4".
---@param word string?
---@param kind string
---@return integer? index
---@return boolean? enemy
local function parse_id(word, kind)
    if not word then
        return nil
    end
    local prefix, n = word:match("^(.-)" .. kind .. ":(%d+)$")
    if prefix == "" then
        return tonumber(n), --[[@as integer]]
            false
    elseif prefix == "enemy:" then
        return tonumber(n), --[[@as integer]]
            true
    end
    return nil
end

---@param raw RawState
---@param uid integer
---@return RawCrew?
local function find_crew(raw, uid)
    for _, c in ipairs(raw.player.crew or {}) do
        if c.uid == uid then
            return c
        end
    end
    return nil
end

local SHIELDS, WEAPONS, DRONES = 0, 3, 4

---@param raw RawState
---@return integer
local function free_reactor(raw)
    local r = raw.player.reactor
    return r and (r.max - r.used) or 0
end

---@param raw RawState
---@param type integer
---@return RawSystem?
local function find_system(raw, type)
    for _, s in ipairs(raw.player.systems or {}) do
        if s.type == type then
            return s
        end
    end
    return nil
end

---@param id string
---@return string
local function locked(id)
    return id .. " is ionized; its power is locked until the ion wears off"
end

---@param word string
---@return integer? type
local function system_type(word)
    local name = word:match("^system:(.+)$") or word
    for i, n in ipairs(FtlBench.Visibility.SYSTEM_NAMES) do
        if n == name then
            return i - 1
        end
    end
    return nil
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_power(args, raw)
    local delta = args[2] and args[2]:match("^[+-]%d+$") and tonumber(args[2])
    if #args ~= 2 or not delta or delta == 0 then
        return nil, "usage: power <system> +N|-N"
    end
    local type = system_type(args[1])
    if not type then
        return nil, "unknown system: " .. args[1]
    end
    local id = FtlBench.Visibility.system_id(type)
    if type == WEAPONS then
        return nil, "power weapons by weapon: use weapon <weapon> on|off"
    elseif type == DRONES then
        return nil, "power drones by drone: use drone <drone> on|off"
    end
    if type == SHIELDS and delta % 2 ~= 0 then
        return nil, id .. " power changes 2 at a time (one layer)"
    end
    local sys = find_system(raw, type)
    if not sys then
        return nil, ("no %s on this ship"):format(id)
    elseif not sys.uses_reactor then
        return nil, id .. " is a subsystem; its power follows its level"
    elseif sys.ion > 0 then
        return nil, locked(id)
    elseif sys.power + delta < 0 then
        return nil, ("%s has only %d power"):format(id, sys.power)
    elseif sys.power + delta > sys.cap then
        return nil, ("%s can take at most %d power (has %d)"):format(id, sys.cap, sys.power)
    elseif delta > free_reactor(raw) then
        return nil, ("%s needs %d reactor power (%d free)"):format(id, delta, free_reactor(raw))
    end
    return { kind = "power", system = type, delta = delta }
end

---weapon <weapon> on|off and drone <drone> on|off.
---@param kind "weapon"|"drone"
---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_armament(kind, args, raw)
    local state = args[2]
    if #args ~= 2 or (state ~= "on" and state ~= "off") then
        return nil, ("usage: %s <%s> on|off"):format(kind, kind)
    end
    local slot, enemy = parse_id(args[1], kind)
    if not slot or enemy then
        return nil, ("expected a %s ID like %s:0, got %s"):format(kind, kind, args[1])
    end
    local list = kind == "weapon" and raw.player.weapons or raw.player.drones
    local item = (list or {})[slot + 1]
    if not item then
        return nil, ("no %s:%d"):format(kind, slot)
    end
    if state == "on" and not item.powered then
        local sys = find_system(raw, kind == "weapon" and WEAPONS or DRONES)
        if sys and sys.ion > 0 then
            return nil, locked(FtlBench.Visibility.system_id(sys.type))
        end
    end
    if kind == "drone" and state == "on" and not item.powered and raw.player.drone_parts == 0 then
        return nil, ("drone:%d (%s) needs a drone part; none left"):format(slot, item.name)
    end
    if kind == "weapon" and state == "on" and not item.powered then
        local label = ("weapon:%d (%s) needs %d power"):format(slot, item.name, item.power)
        local sys = find_system(raw, WEAPONS)
        local room = sys and (sys.cap - sys.power) or 0
        if item.power > room then
            return nil, ("%s; system:weapons has room for %d more"):format(label, room)
        elseif item.power > free_reactor(raw) then
            return nil, ("%s; %d reactor power free"):format(label, free_reactor(raw))
        end
    end
    -- ponytail: drone power needs are not in raw state yet; the game refuses if it can't.
    return { kind = kind, slot = slot, on = state == "on" }
end

local JUMP_USAGE = "usage: jump <beacon> | jump <sector> (at the exit)"

---@param map RawMap
---@param id integer
---@return RawBeacon?
local function find_beacon(map, id)
    for _, b in ipairs(map.beacons) do
        if b.id == id then
            return b
        end
    end
    return nil
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_jump(args, raw)
    local map = raw.map
    local beacon, b_enemy = parse_id(args[1], "beacon")
    local sector, s_enemy = parse_id(args[1], "sector")
    if #args ~= 1 or not (beacon or sector) or b_enemy or s_enemy or not map then
        return nil, JUMP_USAGE
    end
    -- First check the target is valid, then whether the ship can jump right now.
    local here = find_beacon(map, map.current) --[[@as RawBeacon]]
    local resolved
    if sector then
        if not here.exit then
            return nil, "next sectors can only be chosen at the exit beacon"
        end
        local offered = {}
        for _, s in ipairs(map.sector_choices or {}) do
            if s.index == sector then
                resolved = { kind = "jump_sector", sector = sector }
            end
            offered[#offered + 1] = "sector:" .. s.index
        end
        if not resolved then
            return nil,
                ("sector:%d is not one of the next sectors (%s)"):format(
                    sector,
                    table.concat(offered, ", ")
                )
        end
    else
        beacon = beacon --[[@as integer]] -- not a sector, so it is a beacon
        if not find_beacon(map, beacon) then
            return nil, "no beacon:" .. beacon
        end
        for _, l in ipairs(FtlBench.Visibility.current_links(map)) do
            if l == beacon then
                resolved = { kind = "jump", beacon = beacon }
            end
        end
        if not resolved then
            return nil,
                ("beacon:%d is not linked to the current beacon (beacon:%d)"):format(
                    beacon,
                    map.current
                )
        end
    end
    local blocker = FtlBench.Visibility.jump_blocker(raw)
    if blocker == "an event is open" then
        return nil, "an event is open; answer it first"
    elseif blocker then
        return nil, blocker
    end
    return resolved
end

---@param raw RawState
---@param word string?
---@return RawWeapon? weapon
---@return integer? slot
---@return string? error
local function find_weapon(raw, word)
    local slot, enemy = parse_id(word, "weapon")
    if not slot or enemy then
        return nil, nil, ("expected a weapon ID like weapon:0, got %s"):format(word or "nothing")
    end
    local w = (raw.player.weapons or {})[slot + 1]
    if not w then
        return nil, nil, "no weapon:" .. slot
    end
    return w, slot
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_target(args, raw)
    if #args < 2 or #args > 3 then
        return nil, "usage: target <weapon> <enemy:room> [<enemy:room> for a beam]"
    end
    local w, slot, err = find_weapon(raw, args[1])
    if not w then
        return nil, err
    end
    local label = ("weapon:%d (%s)"):format(slot, w.name)
    if not raw.enemy then
        return nil, "there is no enemy ship to target"
    elseif not w.powered then
        return nil, label .. " is not powered"
    end
    local rooms = {}
    for i = 2, #args do
        local room, enemy = parse_id(args[i], "room")
        if not room or not enemy then
            return nil, "target an enemy room, like enemy:room:3"
        elseif not raw.enemy.rooms[room + 1] then
            return nil, "no enemy:room:" .. room
        end
        rooms[#rooms + 1] = room
    end
    if w.beam and #rooms ~= 2 then
        return nil, label .. " is a beam: give a start and an end room"
    elseif w.beam and rooms[1] == rooms[2] then
        return nil, label .. " needs a start and an end room that differ"
    elseif not w.beam and #rooms ~= 1 then
        return nil, label .. " takes a single room"
    end
    return { kind = "target", slot = slot, rooms = rooms }
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_choose(args, raw)
    local n, enemy = parse_id(args[1], "choice")
    if #args ~= 1 or not n or enemy then
        return nil, "usage: choose <choice>"
    elseif not raw.event then
        return nil, "no event is open"
    end
    local c = raw.event.choices[n + 1]
    if not c then
        return nil, "no choice:" .. n
    elseif not c.available then
        return nil, ("choice:%d (%s) is not available"):format(n, c.text)
    elseif n > 8 then
        return nil, ("choice:%d can't be picked: the game only has keys for the first 9"):format(n)
    end
    return { kind = "choose", choice = n }
end

---@param arg string?
---@return ResolvedCommand?, string?
local function plan_wait(arg)
    local seconds = tonumber(arg or "")
    if not seconds then
        return nil, WAIT_ERROR
    end
    local tenths = seconds * 10
    if seconds < 0.1 or seconds > 10 or math.abs(tenths - math.floor(tenths + 0.5)) > 1e-9 then
        return nil, WAIT_ERROR
    end
    return { kind = "wait", seconds = seconds }
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_move(args, raw)
    if #args ~= 2 then
        return nil, "usage: move <crew> <room>"
    end
    local uid, crew_enemy = parse_id(args[1], "crew")
    if not uid or crew_enemy then
        return nil, "expected a crew ID like crew:101, got " .. args[1]
    end
    local room, enemy = parse_id(args[2], "room")
    if not room then
        return nil, "expected a room ID like room:4, got " .. args[2]
    end
    local crew = find_crew(raw, uid)
    if not crew then
        return nil, "no crew:" .. uid
    end
    local label = ("crew:%d (%s)"):format(uid, crew.name)
    if crew.dead then
        return nil, label .. " is dead"
    end
    if crew.on_enemy_ship and not enemy then
        return nil, label .. " is on the enemy ship; use an enemy:room:N"
    elseif enemy and not crew.on_enemy_ship then
        return nil, label .. " is on our ship; use a room:N"
    end
    local rooms = enemy and (raw.enemy or {}).rooms or raw.player.rooms
    if not (rooms or {})[room + 1] then
        return nil, ("no %sroom:%d"):format(enemy and "enemy:" or "", room)
    end
    return { kind = "move", crew = uid, room = room, enemy = enemy }
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_door(args, raw)
    local state = args[2]
    if #args ~= 2 or (state ~= "open" and state ~= "close") then
        return nil, "usage: door <door|all> open|close"
    end
    local all_doors = raw.player.doors or {}
    local ids = {}
    if args[1] == "all" then
        for i, d in ipairs(all_doors) do
            ids[i] = d.id
        end
    else
        local id, enemy = parse_id(args[1], "door")
        if not id or enemy then
            return nil, "expected a door ID like door:3 or all, got " .. args[1]
        end
        if not all_doors[id + 1] then
            return nil, "no door:" .. id
        end
        ids[1] = id
    end
    return { kind = "door", doors = ids, open = state == "open" }
end

---@type table<string, fun(args: string[], raw: RawState): ResolvedCommand?, string?>
local handlers = {
    pause = function()
        return { kind = "pause" }
    end,
    unpause = function(_, raw)
        if raw.pause.event then
            return nil, "an event is open; answer it first"
        elseif raw.pause.menu then
            return nil, "a game window is open (store, upgrades or menu); close it first"
        end
        return { kind = "unpause" }
    end,
    wait = function(args)
        return plan_wait(args[1])
    end,
    move = plan_move,
    door = plan_door,
    power = plan_power,
    jump = plan_jump,
    choose = plan_choose,
    target = plan_target,
    untarget = function(args, raw)
        local w, slot, err = find_weapon(raw, args[1])
        if #args ~= 1 or not w then
            return nil, err or "usage: untarget <weapon>"
        end
        return { kind = "untarget", slot = slot }
    end,
    autofire = function(args)
        if #args ~= 1 or (args[1] ~= "on" and args[1] ~= "off") then
            return nil, "usage: autofire on|off"
        end
        return { kind = "autofire", on = args[1] == "on" }
    end,
    weapon = function(args, raw)
        return plan_armament("weapon", args, raw)
    end,
    drone = function(args, raw)
        return plan_armament("drone", args, raw)
    end,
}

---Resolve Command text against the current raw state.
---@param text string
---@param raw RawState
---@return ResolvedCommand? resolved
---@return string? error
function Commands.plan(text, raw)
    local words = {}
    for w in text:gmatch("%S+") do
        words[#words + 1] = w
    end
    local name = table.remove(words, 1) or ""
    local handler = handlers[name]
    if not handler then
        return nil, "unknown command: " .. name
    end
    if not raw.in_run then
        return nil, "no Run in progress"
    elseif raw.pause.event and not EVENT_SAFE[name] then
        return nil, "an event is open; answer it first" -- the event window blocks the ship, as in the game
    end
    return handler(words, raw)
end

FtlBench.Commands = Commands
