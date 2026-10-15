-- Bridge: the only module that touches the game. Each frame it reads raw state,
-- runs it through Visibility, writes the Observation, and answers Commands from
-- the inbox. It never writes raw state to disk (ADR 0004).
--
-- Files live under the FTL save folder (Hyperspace's working directory):
--   ftlbench/live/state.json    current state view, rewritten every frame
--   ftlbench/live/inbox.txt     Commands from the CLI: id \t wall_ms \t text
--   ftlbench/live/results.txt   answers: id \t ok [\t seconds to wait]   or   id \t error \t reason
--   ftlbench/live/bridge_error.txt   last bridge error, if frames are failing
--   ftlbench/runs/<stamp>/actions.jsonl   Action log for that Run

local Json, Visibility, Commands = FtlBench.Json, FtlBench.Visibility, FtlBench.Commands

local BASE = "ftlbench"
local LIVE = BASE .. "/live"

-- ponytail: frame and game_time are bridge-made counters that restart on every on_init
-- (including loading a save). Ticket #15 (determinism) decides what replay really needs.
local frame, game_time, inbox_offset = 0, 0.0, 0
---@type string?
local run_dir
---@type RawState?
local prev

---@param path string
local function mkdir(path)
    os.execute('mkdir -p "' .. path .. '"')
end

---@param path string
---@param text string
local function append(path, text)
    local f = assert(io.open(path, "a"))
    f:write(text)
    f:close()
end

---@param path string
---@param text string
local function write_atomic(path, text)
    local tmp = path .. ".tmp"
    local f = assert(io.open(tmp, "w"))
    f:write(text)
    f:close()
    os.rename(tmp, path)
end

local SENSORS = 7

---@param n number
---@return integer
local function int(n)
    return math.floor(n)
end

---@param ship any ShipManager
---@return RawRoom[]
local function read_rooms(ship)
    local rooms, o2 = {}, ship.oxygenSystem
    local breaches = {}
    local list = ship.ship:GetHullBreaches(true)
    for i = 0, list:size() - 1 do
        local room = int(list[i].roomId)
        breaches[room] = (breaches[room] or 0) + 1
    end
    for i = 0, ship.ship.vRoomList:size() - 1 do
        local r = ship.ship.vRoomList[i]
        local id = int(r.iRoomId)
        local sys = ship:GetSystemInRoom(id)
        rooms[#rooms + 1] = {
            id = id,
            x = int(r.rect.x),
            y = int(r.rect.y),
            w = int(r.rect.w),
            h = int(r.rect.h),
            system = sys and int(sys.iSystemType) or nil,
            oxygen = o2 and o2.oxygenLevels[id] or 100,
            fires = int(ship:GetFireCount(id)),
            breaches = breaches[id] or 0,
        }
    end
    return rooms
end

---Interior doors keep their game ids; airlocks are numbered after them.
---@param ship any ShipManager
---@return RawDoor[], any[] game Door objects in the same order
local function read_doors(ship)
    local doors, objects = {}, {}
    for _, list in ipairs({ ship.ship.vDoorList, ship.ship.vOuterAirlocks }) do
        for i = 0, list:size() - 1 do
            local d = list[i]
            objects[#objects + 1] = d
            doors[#doors + 1] = {
                id = #doors,
                room1 = int(d.iRoom1),
                room2 = int(d.iRoom2),
                open = d.bOpen,
            }
        end
    end
    return doors, objects
end

---@param ship any ShipManager
---@return RawCrew[], table<integer, any> crew objects by uid
local function read_crew(ship)
    local crew, objects = {}, {}
    for i = 0, ship.vCrewList:size() - 1 do
        local c = ship.vCrewList[i]
        if int(c.iShipId) == 0 and not c:IsDead() then
            local uid = int(c.extend.selfId)
            objects[uid] = c
            local skills = {}
            for s = 0, 5 do
                skills[s + 1] = int(c:GetSkillLevel(s))
            end
            crew[#crew + 1] = {
                uid = uid,
                name = c:GetName(),
                species = c:GetSpecies(),
                health = c.health.first,
                health_max = c.health.second,
                room = int(c.iRoomId),
                on_enemy_ship = int(c.currentShipId) ~= 0,
                skills = skills,
            }
        end
    end
    return crew, objects
end

-- Game objects behind the last raw state, for the executor.
local door_objects, crew_objects = {}, {}

---@return RawState
local function read_raw()
    local app = Hyperspace.App
    local gui = app and app.gui
    local ship = Hyperspace.ships.player
    local in_run = gui ~= nil and ship ~= nil and not app.menu.bOpen
    ---@type RawState
    local raw = {
        in_run = in_run,
        frame = frame,
        game_time = game_time,
        pause = {
            manual = in_run and gui.bPaused or false,
            event = in_run and gui.event_pause or false,
            menu = in_run and gui.menu_pause or false,
        },
    }
    if in_run then
        local sensors = ship:GetSystem(SENSORS)
        local doors
        raw.nebula = app.world.space.bNebula
        raw.player = {
            hull = int(ship.ship.hullIntegrity.first),
            hull_max = int(ship.ship.hullIntegrity.second),
            scrap = int(ship.currentScrap),
            oxygen = ship:GetOxygenPercentage(),
            sensors_power = sensors and int(sensors:GetEffectivePower()) or 0,
            rooms = read_rooms(ship),
        }
        doors, door_objects = read_doors(ship)
        raw.player.doors = doors
        raw.player.crew, crew_objects = read_crew(ship)
    end
    return raw
end

---Carry out a resolved Command. Returns an error message on runtime failure.
---@param action ResolvedCommand
---@return string?
local function execute(action)
    if action.kind == "pause" then
        Hyperspace.App.gui.bPaused = true
    elseif action.kind == "unpause" then
        Hyperspace.App.gui.bPaused = false
    elseif action.kind == "move" then
        if not crew_objects[action.crew]:MoveToRoom(action.room, -1, false) then
            return "crew cannot reach that room"
        end
    elseif action.kind == "door" then
        for _, id in ipairs(action.doors) do
            door_objects[id + 1].bOpen = action.open
        end
    end
    -- "wait" needs nothing from the game: the CLI does the waiting.
    return nil
end

---@param raw RawState
local function handle_inbox(raw)
    local f = io.open(LIVE .. "/inbox.txt", "r")
    if not f then
        return
    end
    f:seek("set", inbox_offset)
    local data = f:read("a")
    f:close()
    for line in data:gmatch("([^\n]*)\n") do
        inbox_offset = inbox_offset + #line + 1
        local id, wall_ms, text = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
        if id then
            local action, err = Commands.plan(text, raw)
            if action then
                err = execute(action)
            end
            local status = err and ("error\t" .. err)
                or (action and action.seconds and ("ok\t" .. action.seconds))
                or "ok"
            append(LIVE .. "/results.txt", id .. "\t" .. status .. "\n")
            if run_dir then
                append(run_dir .. "/actions.jsonl", Json.encode({
                    wall_ms = tonumber(wall_ms),
                    frame = raw.frame,
                    game_time = raw.game_time,
                    command = text,
                    result = err and "error" or "ok",
                    error = err,
                }) .. "\n")
            end
        end
    end
end

local function tick()
    local raw = read_raw()
    if raw.in_run then
        frame = frame + 1
        if not Visibility.is_paused(raw) then
            game_time = game_time + Hyperspace.FPS.SpeedFactor / 16
        end
    end
    local out = Visibility.observe(prev, raw, {})
    write_atomic(LIVE .. "/state.json", Json.encode(out.views.state))
    handle_inbox(raw)
    prev = raw
end

mkdir(LIVE)
-- Start every game launch with an empty inbox so stale Commands never run.
write_atomic(LIVE .. "/inbox.txt", "")
write_atomic(LIVE .. "/results.txt", "")

script.on_init(function()
    frame, game_time, prev = 0, 0.0, nil
    run_dir = BASE .. "/runs/" .. os.date("%Y%m%d-%H%M%S")
    mkdir(run_dir)
    print("[ftlbench] Run folder " .. run_dir)
end)

local failed = false
script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    local ok, err = pcall(tick)
    if not ok and not failed then
        failed = true -- report once; a broken frame repeats 60 times a second
        print("[ftlbench] bridge error: " .. tostring(err))
        write_atomic(LIVE .. "/bridge_error.txt", tostring(err))
    elseif ok and failed then
        failed = false
        os.remove(LIVE .. "/bridge_error.txt")
    end
end)

print("[ftlbench] bridge loaded")
