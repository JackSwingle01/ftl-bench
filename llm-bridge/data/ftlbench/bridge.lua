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
        raw.player = {
            hull = ship.ship.hullIntegrity.first,
            hull_max = ship.ship.hullIntegrity.second,
            scrap = ship.currentScrap,
        }
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
