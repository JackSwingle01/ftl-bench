local t = ...
local V = FtlBench.Visibility

---@return RawState
local function raw_in_run()
    return {
        in_run = true,
        frame = 1200,
        game_time = 20.5,
        pause = { player = false, event = false, menu = false },
        player = { hull = 27, hull_max = 30, scrap = 45 },
    }
end

t.test("state view shows pause status, game time, hull and scrap", function()
    local out = V.observe(nil, raw_in_run(), {})
    t.eq(out.views.state, {
        in_run = true,
        paused = false,
        frame = 1200,
        game_time = 20.5,
        ship = { hull = 27, hull_max = 30, scrap = 45 },
    })
end)

t.test("outside a Run the state view says so and shows no ship", function()
    local raw = {
        in_run = false,
        frame = 0,
        game_time = 0,
        pause = { player = false, event = false, menu = false },
    }
    t.eq(
        V.observe(nil, raw, {}).views.state,
        { in_run = false, paused = false, frame = 0, game_time = 0 }
    )
end)

t.test("an open event or menu counts as paused", function()
    local raw = raw_in_run()
    raw.pause.event = true
    t.eq(V.observe(nil, raw, {}).views.state.paused, true)
    raw = raw_in_run()
    raw.pause.menu = true
    t.eq(V.observe(nil, raw, {}).views.state.paused, true)
end)
