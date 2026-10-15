-- DEVELOPMENT ONLY: test fixtures. Reads ftlbench/dev_give ("scrap 100" or "event STORE"), applies it
-- once and deletes it.
script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    local f = io.open("ftlbench/dev_give", "r")
    if not f then
        return
    end
    local line = f:read("l") or ""
    f:close()
    os.remove("ftlbench/dev_give")
    local amount = tonumber(line:match("^scrap (%d+)$"))
    local event = line:match("^event ([%w_]+)$")
    local ship = Hyperspace.ships.player
    if amount and ship then
        ship:ModifyScrapCount(amount, false)
        print("[ftlbench] dev: gave " .. amount .. " scrap")
    elseif event and ship then
        -- Load a named game event at this beacon (e.g. STORE, PIRATE): a store or a fight on demand.
        Hyperspace.CustomEventsParser.GetInstance():LoadEvent(Hyperspace.App.world, event, true, -1)
        print("[ftlbench] dev: loaded event " .. event)
    end
end)
