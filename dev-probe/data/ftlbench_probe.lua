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
    p("== systems")
    for i = 0, s.vSystemList:size() - 1 do
        local y = s.vSystemList[i]
        p(
            "type",
            y.iSystemType,
            y.name,
            "room",
            y.roomId,
            "power",
            y.powerState.first,
            y.powerState.second,
            "eff",
            y:GetEffectivePower(),
            "max",
            y:GetMaxPower(),
            "cap",
            y:GetPowerCap(),
            "health",
            y.healthState.first,
            y.healthState.second,
            "ioned",
            y:Ioned(1),
            "lock",
            y.iLockCount,
            "needsPower",
            y.bNeedsPower,
            "manned",
            y.iActiveManned,
            "bonus",
            y.iBonusPower,
            "batt",
            y.iBatteryPower
        )
    end
    local pm = Hyperspace.PowerManager.GetPowerManager(0)
    p(
        "== reactor current",
        pm.currentPower.first,
        pm.currentPower.second,
        "max",
        pm:GetMaxPower(),
        "avail",
        pm:GetAvailablePower(),
        "battery",
        pm.batteryPower.first,
        pm.batteryPower.second
    )
    p(
        "== shields",
        s:GetShieldPower().first,
        s:GetShieldPower().second,
        "dodge",
        s:GetDodgeFactor(),
        "fuel",
        s.fuel_count,
        "missiles",
        s:GetMissileCount(),
        "drones",
        s:GetDroneCount()
    )
    p("== weapons")
    local wl = s:GetWeaponList()
    for i = 0, wl:size() - 1 do
        local w = wl[i]
        p(
            "slot",
            i,
            "name",
            w.name,
            "title",
            w.blueprint.desc.title:GetText(),
            "bp",
            w.blueprint.name,
            "powered",
            w.powered,
            "req",
            w.requiredPower,
            "cd",
            w.cooldown.first,
            w.cooldown.second,
            "missiles",
            w.blueprint.missiles
        )
    end
    p("== weapon slots", s.weaponSystem and s.weaponSystem.slot_count)
    p("== drones")
    local dl = s:GetDroneList()
    for i = 0, dl:size() - 1 do
        local d = dl[i]
        p("slot", i, "name", d:GetName(), "powered", d.powered, "deployed", d.deployed)
    end
    local gui = Hyperspace.App.gui
    p("== choicebox open", gui.choiceBoxOpen, "event_pause", gui.event_pause)
    local cb = gui.choiceBox
    p("main", cb.mainText)
    p(
        "box rewards scrap",
        cb.rewards.scrap,
        "fuel",
        cb.rewards.fuel,
        "missiles",
        cb.rewards.missiles
    )
    for i = 0, cb.choices:size() - 1 do
        local c = cb.choices[i]
        p(
            "choice",
            i,
            "type",
            c.type,
            "text",
            c.text,
            "r.scrap",
            c.rewards.scrap,
            "r.fuel",
            c.rewards.fuel,
            "r.missiles",
            c.rewards.missiles,
            "r.drones",
            c.rewards.drones,
            "r.crew",
            c.rewards.crew
        )
    end
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
