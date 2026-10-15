-- DEVELOPMENT ONLY: dumps every exposed aiming field of our weapons, weapon system and combat
-- control to ftlbench/probe_weapons.txt twice a second, to diff a real click against ours.
local FIELDS = {
    "name",
    "powered",
    "requiredPower",
    "fireWhenReady",
    "autoFiring",
    "targetId",
    "currentShipTarget",
    "chargeLevel",
    "goalChargeLevel",
    "iHackLevel",
    "isArtillery",
    "shotsFiredAtTarget",
    "numShots",
    "iAmmo",
    "iBonusPower",
    "radius",
    "currentFiringAngle",
    "currentEntryAngle",
    "iSpendMissile",
    "boostLevel",
    "lastProjectile",
    "spaceDestination",
    "subCooldown",
    "baseCooldown",
}
local n = 0

local function dump()
    local ship = Hyperspace.ships.player
    if not ship or Hyperspace.App.menu.bOpen then
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
    local list = ship:GetWeaponList()
    for i = 0, list:size() - 1 do
        local w = list[i]
        p("== weapon", i)
        for _, f in ipairs(FIELDS) do
            local ok, v = pcall(function()
                return w[f]
            end)
            p(" ", f, ok and v or "n/a")
        end
        p("  cooldown", w.cooldown.first, w.cooldown.second)
        p("  targets", w.targets:size())
        for t = 0, w.targets:size() - 1 do
            p("    target", t, w.targets[t].x, w.targets[t].y)
        end
        local ok, lt = pcall(function()
            return w.lastTargets:size()
        end)
        p("  lastTargets", ok and lt or "n/a")
    end
    local ws = ship.weaponSystem
    p(
        "== weaponSystem target",
        ws.target and ws.target.x,
        ws.target and ws.target.y,
        "shot_timer",
        ws.shot_timer,
        "shot_count",
        ws.shot_count,
        "missile_count",
        ws.missile_count
    )
    local cc = Hyperspace.App.gui.combatControl
    p(
        "== combatControl open",
        cc.open,
        "selectedRoom",
        cc.selectedRoom,
        "selectedSelfRoom",
        cc.selectedSelfRoom,
        "potentialAiming",
        cc.potentialAiming,
        "movingBeam",
        cc.movingBeam,
        "mouseDown",
        cc.mouseDown,
        "aimingPoints",
        cc.aimingPoints and cc.aimingPoints:size()
    )
    p(
        "== weapControl armedSlot",
        cc.weapControl.armedSlot,
        "armedWeapon",
        cc.weapControl.armedWeapon,
        "autoFiring",
        cc.weapControl.autoFiring
    )
    p("== current_target", ship.current_target)
    local function fields(label, obj, names)
        if not obj then
            return p("== " .. label, "none")
        end
        local parts = { "== " .. label }
        for _, f in ipairs(names) do
            local ok, v = pcall(function()
                return obj[f]
            end)
            parts[#parts + 1] = f .. "=" .. tostring(ok and v or "n/a")
        end
        p(table.concat(parts, " "))
    end
    fields("cloak", ship.cloakSystem, { "bTurnedOn", "timer", "powerState" })
    fields("battery", ship.batterySystem, { "bTurnedOn", "powerState" })
    fields("hacking", ship.hackingSystem, {
        "bHacking",
        "bArmed",
        "bCanHack",
        "bBlocked",
        "drone",
        "queuedSystem",
        "currentSystem",
        "effectTimer",
        "spendDrone",
    })
    fields("mind", ship.mindSystem, {
        "bCanUse",
        "iArmed",
        "controlTimer",
        "iQueuedTarget",
        "iQueuedShip",
        "queuedCrew",
        "controlledCrew",
        "bBlocked",
    })
    fields(
        "teleport",
        ship.teleportSystem,
        { "chargeLevel", "bCanSend", "bCanReceive", "iArmed", "iPreparedCrew", "iNumSlots" }
    )
    local f = assert(io.open("ftlbench/probe_weapons.txt", "w"))
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
end

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    n = n + 1
    if n % 30 == 0 then
        local ok, err = pcall(dump)
        if not ok then
            local f = assert(io.open("ftlbench/probe_weapons.txt", "w"))
            f:write("PROBE ERROR " .. tostring(err) .. "\n")
            f:close()
        end
    end
end)
