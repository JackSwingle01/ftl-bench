-- Commands: the only Command parser. Turns Command text plus raw state into a
-- resolved Command or an error message. Pure: no game access, no I/O.

FtlBench = FtlBench or {}

---@class ResolvedCommand
---@field kind "pause"|"unpause"|"wait"|"move"|"door"|"power"|"weapon"|"drone"|"jump"|"jump_sector"|"choose"|"target"|"untarget"|"autofire"|"buy"|"upgrade"|"upgrade_reactor"|"close"
---|"cloak"|"battery"|"hack"|"hack_pulse"|"mindcontrol"|"teleport"|"show"
---@field seconds number?   wait
---@field crew integer?     move: crew uid
---@field room integer?     move: room id
---@field enemy boolean?    move: room is on the enemy ship
---@field doors integer[]?  door: door ids
---@field open boolean?     door
---@field all boolean?      door: every door (the game's open/close-all hotkeys)
---@field system integer?   power: FTL system type id
---@field delta integer?    power: change in power
---@field slot integer?     weapon, drone: slot index
---@field on boolean?       weapon, drone
---@field beacon integer?   jump
---@field sector integer?   jump_sector: index of the chosen sector
---@field choice integer?   choose: 0-based choice index
---@field rooms integer[]?  target: enemy room ids (two for a beam)
---@field item integer?     buy: store item index
---@field cost integer?     upgrade: scrap it was checked against
---@field command integer?  teleport: 1 send crew out, 2 bring them back
---@field window string?    show: "map", "upgrades" or "store"

local Commands = {}

-- Commands that still work while an event window is open.
local EVENT_SAFE = { choose = true, wait = true, pause = true, unpause = true, show = true }
-- Commands that still work while another game window (store, upgrades, menu) is open.
local WINDOW_SAFE = {
    close = true,
    buy = true,
    upgrade = true,
    wait = true,
    pause = true,
    unpause = true,
    show = true,
}

---A shown event box blocks the ship even when the game's event pause isn't set (seen live:
---a store's greeting box left it clear, and the Agent bought before answering it).
---@param raw RawState
---@return boolean
local function event_open(raw)
    return raw.pause.event or raw.event ~= nil
end

---Why `buy` or `upgrade` can't use its window, or nil when it is open.
---@param raw RawState
---@param window string "store" or "upgrades"
---@return string?
local function window_needed(raw, window)
    if raw.window == window then
        return nil
    elseif raw.refused_window == window then
        return ("the game would not open the %s window just now (it refuses during some fights, "):format(
            window
        ) .. "e.g. with intruders aboard)"
    end
    return ("the %s window isn't open; run ftl %s first"):format(window, window)
end

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

local SHIELDS, WEAPONS, DRONES, DOORS = 0, 3, 4, 8

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

local CLOAKING, BATTERY, TELEPORTER, MIND, HACKING = 10, 12, 9, 14, 15

---The ship's system of this type if it can be used now, else the reason it can't.
---@param raw RawState
---@param type integer
---@return RawSystem?, string?
local function usable_system(raw, type)
    local id = FtlBench.Visibility.system_id(type)
    local sys = find_system(raw, type)
    if not sys then
        return nil, ("no %s on this ship"):format(id)
    elseif sys.ion > 0 then
        return nil, locked(id)
    elseif sys.power < 1 then
        return nil, id .. " is not powered"
    end
    return sys
end

---@param raw RawState
---@param name string
---@return table
local function ability(raw, name)
    return (raw.player.abilities or {})[name] or {}
end

---@type table<string, fun(args: string[], raw: RawState): ResolvedCommand?, string?>
local ability_handlers = {
    cloak = function(_, raw)
        local _, err = usable_system(raw, CLOAKING)
        if err then
            return nil, err
        elseif ability(raw, "cloak").on then
            return nil, "already cloaked"
        end
        return { kind = "cloak" }
    end,
    battery = function(_, raw)
        local _, err = usable_system(raw, BATTERY)
        if err then
            return nil, err
        elseif ability(raw, "battery").on then
            return nil, "the battery is already on"
        end
        return { kind = "battery" }
    end,
    hack = function(args, raw)
        local _, err = usable_system(raw, HACKING)
        if err then
            return nil, err
        elseif #args == 0 then
            if not ability(raw, "hacking").drone then
                return nil, "no hacking drone attached yet: hack <enemy:room> first"
            end
            return { kind = "hack_pulse" }
        end
        local room, enemy = parse_id(args[1], "room")
        if #args ~= 1 or not room or not enemy then
            return nil, "usage: hack <enemy:room> (launch the drone) | hack (start the pulse)"
        elseif not raw.enemy then
            return nil, "there is no enemy ship to hack"
        elseif ability(raw, "hacking").launched then
            return nil, "a hacking drone is already out"
        elseif (raw.player.drone_parts or 0) < 1 then
            return nil, "no drone parts to build a hacking drone"
        end
        for _, s in ipairs(raw.enemy.systems or {}) do
            if s.room == room then
                return { kind = "hack", room = room }
            end
        end
        return nil, ("enemy:room:%d has no system to hack"):format(room)
    end,
    mindcontrol = function(args, raw)
        local _, err = usable_system(raw, MIND)
        if err then
            return nil, err
        end
        local uid, enemy = parse_id(args[1], "crew")
        if #args ~= 1 or not uid or not enemy then
            return nil, "usage: mindcontrol <enemy:crew>"
        end
        for _, c in ipairs((FtlBench.Visibility.enemy_view(raw) or {}).crew or {}) do
            if c.id == "enemy:crew:" .. uid then
                return { kind = "mindcontrol", crew = uid }
            end
        end
        return nil, "no visible enemy:crew:" .. uid -- mind control needs to see its target
    end,
    teleport = function(args, raw)
        local command = ({ send = 1, ["return"] = 2 })[args[1] or ""]
        local room, enemy = parse_id(args[2], "room")
        if #args ~= 2 or not command or not room or not enemy then
            return nil, "usage: teleport send|return <enemy:room>"
        end
        local pad, err = usable_system(raw, TELEPORTER)
        if not pad then
            return nil, err
        elseif not ability(raw, "teleporter").charged then
            return nil, "system:teleporter is still charging"
        elseif not raw.enemy or not raw.enemy.rooms[room + 1] then
            return nil, "no enemy:room:" .. room
        end
        -- Send takes whoever stands on the pad; return brings back our crew from that enemy room.
        local from, aboard = command == 1 and pad.room or room, command == 2
        for _, c in ipairs(raw.player.crew or {}) do
            if c.room == from and c.on_enemy_ship == aboard then
                return { kind = "teleport", room = room, command = command }
            end
        end
        return nil,
            command == 1 and ("no crew on the teleporter pad (room:%d)"):format(pad.room)
                or ("none of our crew are in enemy:room:%d"):format(room)
    end,
}

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_buy(args, raw)
    local n, enemy = parse_id(args[1], "item")
    if #args ~= 1 or not n or enemy then
        return nil, "usage: buy <item>"
    elseif not raw.store then
        return nil, "there is no store here"
    elseif window_needed(raw, "store") then
        return nil, window_needed(raw, "store")
    end
    local it = raw.store.items[n + 1]
    if not it then
        return nil, "no item:" .. n
    end
    local label = ("item:%d (%s)"):format(n, it.name)
    local scrap = raw.player.scrap
    if it.stock <= 0 then
        return nil, label .. " is sold out"
    elseif scrap < it.cost then
        return nil, ("%s costs %d scrap; you have %d"):format(label, it.cost, scrap)
    elseif not it.can_hold then
        return nil, label .. " can't be held: no room or already installed"
    end
    return { kind = "buy", item = n }
end

---@param args string[]
---@param raw RawState
---@return ResolvedCommand?, string?
local function plan_upgrade(args, raw)
    if #args ~= 1 then
        return nil, "usage: upgrade <system|reactor>"
    elseif not raw.upgrades then
        return nil, "upgrades are not available right now"
    elseif window_needed(raw, "upgrades") then
        return nil, window_needed(raw, "upgrades")
    end
    local scrap = raw.player.scrap
    if args[1] == "reactor" then
        local cost = raw.upgrades.reactor.cost
        if not cost then
            return nil, "the reactor is at its maximum"
        elseif scrap < cost then
            return nil, ("the reactor upgrade costs %d scrap; you have %d"):format(cost, scrap)
        end
        return { kind = "upgrade_reactor" }
    end
    local type = system_type(args[1])
    if not type then
        return nil, "unknown system: " .. args[1]
    end
    local id = FtlBench.Visibility.system_id(type)
    for _, s in ipairs(raw.upgrades.systems) do
        if s.type == type then
            if not s.cost then
                return nil, id .. " is at its maximum level"
            elseif scrap < s.cost then
                return nil, ("%s upgrade costs %d scrap; you have %d"):format(id, s.cost, scrap)
            end
            return { kind = "upgrade", system = type, cost = s.cost }
        end
    end
    return nil, ("no %s on this ship"):format(id)
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
    -- Not usable_system: ion takes away power bars, and doors with a bar left still work.
    local sys = find_system(raw, DOORS)
    if not sys then
        return nil, "no system:doors on this ship"
    elseif sys.power < 1 then
        return nil, "system:doors is not powered"
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
    return { kind = "door", doors = ids, open = state == "open", all = args[1] == "all" or nil }
end

---@type table<string, fun(args: string[], raw: RawState): ResolvedCommand?, string?>
local handlers = {
    pause = function()
        return { kind = "pause" }
    end,
    unpause = function(_, raw)
        if event_open(raw) then
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
    show = function(args, raw)
        local w = args[1]
        if #args ~= 1 or (w ~= "map" and w ~= "upgrades" and w ~= "store") then
            return nil, "usage: show map|upgrades|store"
        elseif w == "store" and not raw.store then
            return nil, "there is no store here"
        end
        return { kind = "show", window = args[1] }
    end,
    cloak = ability_handlers.cloak,
    battery = ability_handlers.battery,
    hack = ability_handlers.hack,
    mindcontrol = ability_handlers.mindcontrol,
    teleport = ability_handlers.teleport,
    buy = plan_buy,
    upgrade = plan_upgrade,
    close = function(_, raw)
        if not raw.window then
            return nil, "no window is open"
        end
        return { kind = "close" }
    end,
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
    elseif event_open(raw) and not EVENT_SAFE[name] then
        return nil, "an event is open; answer it first" -- the event window blocks the ship, as in the game
    elseif
        raw.pause.menu
        and not event_open(raw)
        and not WINDOW_SAFE[name]
        and not (name == "jump" and raw.window == "map") -- players jump from the map
    then
        return nil, "a game window is open; close it first" -- hotkeys go to the window, not the ship
    end
    return handler(words, raw)
end

FtlBench.Commands = Commands
