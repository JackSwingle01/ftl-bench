-- DEVELOPMENT ONLY: test fixtures. Reads ftlbench/dev_give ("scrap 100"), applies it once, deletes it.
script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    local f = io.open("ftlbench/dev_give", "r")
    if not f then
        return
    end
    local line = f:read("l") or ""
    f:close()
    os.remove("ftlbench/dev_give")
    local amount = tonumber(line:match("^scrap (%d+)$"))
    local ship = Hyperspace.ships.player
    if amount and ship then
        ship:ModifyScrapCount(amount, false)
        print("[ftlbench] dev: gave " .. amount .. " scrap")
    end
end)
