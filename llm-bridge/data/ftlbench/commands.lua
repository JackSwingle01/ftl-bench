-- Commands: the only Command parser. Turns Command text plus raw state into a
-- resolved action or an error message. Pure: no game access, no I/O.

FtlBench = FtlBench or {}

---@class Action
---@field kind "pause"|"unpause"|"wait"
---@field seconds number?

local Commands = {}

local WAIT_ERROR = "wait takes 0.1 to 10 seconds in steps of 0.1"

---@param arg string?
---@return Action?, string?
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

---@type table<string, fun(args: string[], raw: RawState): Action?, string?>
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
}

---Resolve Command text against the current raw state.
---@param text string
---@param raw RawState
---@return Action? action
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
