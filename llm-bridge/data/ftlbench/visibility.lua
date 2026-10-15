-- Visibility: turns raw state (everything the game knows) into the Observation
-- (only Visible state). Pure: no game access, no I/O. See ADR 0003 and 0004.

FtlBench = FtlBench or {}

---@class RawPause
---@field manual boolean  paused by spacebar or `ftl pause`
---@field event boolean   paused because an event window is open
---@field menu boolean    paused because a menu is open

---@class RawShip
---@field hull integer
---@field hull_max integer
---@field scrap integer

---@class RawState
---@field in_run boolean
---@field frame integer        bridge ticks since the Run started
---@field game_time number     unpaused game seconds since the Run started
---@field pause RawPause
---@field player RawShip?

---@class ObservedShip
---@field hull integer
---@field hull_max integer
---@field scrap integer

---@class StateView
---@field in_run boolean
---@field paused boolean
---@field frame integer
---@field game_time number
---@field ship ObservedShip?

---@class Observation
---@field views { state: StateView }
---@field events table[]

local Visibility = {}

---@param raw RawState
---@return boolean
function Visibility.is_paused(raw)
    local p = raw.pause
    return p.manual or p.event or p.menu
end

---@param raw RawShip
---@return ObservedShip
local function observe_ship(raw)
    return { hull = raw.hull, hull_max = raw.hull_max, scrap = raw.scrap }
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
                ship = raw.player and observe_ship(raw.player),
            },
        },
        events = {},
    }
end

FtlBench.Visibility = Visibility
