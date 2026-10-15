local t = ...
local C = FtlBench.Commands

---@return RawState
local function raw_in_run()
    return {
        in_run = true,
        frame = 10,
        game_time = 1,
        pause = { player = false, event = false, menu = false },
        player = { hull = 30, hull_max = 30, scrap = 0 },
    }
end

t.test("pause and unpause resolve to actions", function()
    t.eq(C.plan("pause", raw_in_run()), { kind = "pause" })
    t.eq(C.plan("unpause", raw_in_run()), { kind = "unpause" })
end)

t.test("wait accepts 0.1 to 10 seconds in 0.1 steps", function()
    t.eq(C.plan("wait 0.1", raw_in_run()), { kind = "wait", seconds = 0.1 })
    t.eq(C.plan("wait 2.5", raw_in_run()), { kind = "wait", seconds = 2.5 })
    t.eq(C.plan("wait 10", raw_in_run()), { kind = "wait", seconds = 10 })
end)

t.test("wait rejects out-of-range, too-fine and non-numeric values", function()
    local msg = "wait takes 0.1 to 10 seconds in steps of 0.1"
    t.eq(select(2, C.plan("wait 0", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait 10.1", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait 2.55", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait soon", raw_in_run())), msg)
    t.eq(select(2, C.plan("wait", raw_in_run())), msg)
end)

t.test("unknown Commands are rejected by name", function()
    local action, err = C.plan("fly away", raw_in_run())
    t.eq(action, nil)
    t.eq(err, "unknown command: fly")
end)

t.test("Commands need a Run in progress", function()
    local raw = raw_in_run()
    raw.in_run = false
    t.eq(select(2, C.plan("pause", raw)), "no Run in progress")
end)

t.test("unpause is refused while an event is open", function()
    local raw = raw_in_run()
    raw.pause.event = true
    t.eq(select(2, C.plan("unpause", raw)), "an event is open; answer it first")
end)

t.test("extra whitespace is tolerated", function()
    t.eq(C.plan("  wait   3 ", raw_in_run()), { kind = "wait", seconds = 3 })
end)
