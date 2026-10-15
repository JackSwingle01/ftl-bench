-- Commands: the only Command parser. Turns Command text plus raw state into a
-- resolved Command or an error message. Pure: no game access, no I/O.

FtlBench = FtlBench or {}

---@class ResolvedCommand
---@field kind "pause"|"unpause"|"wait"|"move"|"door"
---@field seconds number?   wait
---@field crew integer?     move: crew uid
---@field room integer?     move: room id
---@field enemy boolean?    move: room is on the enemy ship
---@field doors integer[]?  door: door ids
---@field open boolean?     door

local Commands = {}

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
    if crew.on_enemy_ship and not enemy then
        return nil, label .. " is on the enemy ship; use an enemy:room:N"
    elseif enemy and not crew.on_enemy_ship then
        return nil, label .. " is on our ship; use a room:N"
    end
    -- ponytail: enemy rooms are not range-checked until the enemy ship is in raw state (#6).
    if not enemy and not (raw.player.rooms or {})[room + 1] then
        return nil, "no room:" .. room
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
        end
        return { kind = "unpause" }
    end,
    wait = function(args)
        return plan_wait(args[1])
    end,
    move = plan_move,
    door = plan_door,
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
    end
    return handler(words, raw)
end

FtlBench.Commands = Commands
