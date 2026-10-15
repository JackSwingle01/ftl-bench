-- DEVELOPMENT ONLY: dumps raw game facts to ftlbench/probe.txt every 2s during a Run.
-- Writes hidden information, so it must never be installed for a scored Run.
FtlBench = FtlBench or {}
FtlBench.dev_probe = true
local n = 0
local function dump()
    local s = Hyperspace.ships.player
    if not s or Hyperspace.App.menu.bOpen then
        return
    end
    local out = {}
    local function p(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        out[#out + 1] = table.concat(parts, " ")
    end
    p("== rooms")
    for i = 0, s.ship.vRoomList:size() - 1 do
        local r = s.ship.vRoomList[i]
        local sys = s:GetSystemInRoom(r.iRoomId)
        p(
            "idx",
            i,
            "id",
            r.iRoomId,
            "rect",
            r.rect.x,
            r.rect.y,
            r.rect.w,
            r.rect.h,
            "sys",
            sys and sys.name,
            sys and sys.iSystemType,
            "o2",
            s.oxygenSystem and s.oxygenSystem.oxygenLevels[r.iRoomId],
            "fires",
            s:GetFireCount(r.iRoomId)
        )
    end
    p("== doors")
    for i = 0, s.ship.vDoorList:size() - 1 do
        local d = s.ship.vDoorList[i]
        p(
            "idx",
            i,
            "iDoorId",
            d.iDoorId,
            "rooms",
            d.iRoom1,
            d.iRoom2,
            "open",
            d.bOpen,
            "xy",
            d.x,
            d.y,
            "locked",
            d.lockedDown
        )
    end
    p("== airlocks")
    for i = 0, s.ship.vOuterAirlocks:size() - 1 do
        local d = s.ship.vOuterAirlocks[i]
        p(
            "idx",
            i,
            "iDoorId",
            d.iDoorId,
            "rooms",
            d.iRoom1,
            d.iRoom2,
            "open",
            d.bOpen,
            "xy",
            d.x,
            d.y
        )
    end
    p("== crew on player ship list")
    for i = 0, s.vCrewList:size() - 1 do
        local c = s.vCrewList[i]
        local ok, sid = pcall(function()
            return c.extend.selfId
        end)
        p(
            "idx",
            i,
            "name",
            c:GetName(),
            "species",
            c:GetSpecies(),
            "iShipId",
            c.iShipId,
            "currentShipId",
            c.currentShipId,
            "room",
            c.iRoomId,
            "hp",
            c.health.first,
            c.health.second,
            "selfId",
            ok and sid or ("ERR " .. tostring(sid)),
            "intruder",
            c.intruder,
            "dead",
            c:IsDead(),
            "skills",
            c:GetSkillLevel(0),
            c:GetSkillLevel(1),
            c:GetSkillLevel(2),
            c:GetSkillLevel(3),
            c:GetSkillLevel(4),
            c:GetSkillLevel(5)
        )
    end
    p("== breaches")
    local b = s.ship:GetHullBreaches(true)
    for i = 0, b:size() - 1 do
        p("room", b[i].roomId)
    end
    p(
        "== o2 total",
        s:GetOxygenPercentage(),
        "sensors",
        s:GetSystem(7) and s:GetSystem(7):GetEffectivePower()
    )
    local f = assert(io.open("ftlbench/probe.txt", "w"))
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
end
script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    n = n + 1
    if n % 120 == 0 then
        local ok, err = pcall(dump)
        if not ok then
            local f = assert(io.open("ftlbench/probe.txt", "w"))
            f:write("PROBE ERROR " .. tostring(err) .. "\n")
            f:close()
        end
    end
end)
