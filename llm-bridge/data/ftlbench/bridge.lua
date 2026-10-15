-- Bridge: the only module that touches the game. Each frame it reads raw state,
-- runs it through Visibility, writes the Observation, and answers Commands from
-- the inbox. It never writes raw state to disk (ADR 0004).
--
-- Files live under the FTL save folder (Hyperspace's working directory):
--   ftlbench/live/state.json    current state view, rewritten every frame
--   ftlbench/live/map.json, jumps.json   map and jump views, rewritten every frame
--   ftlbench/live/inbox.txt     Commands from the CLI: id \t wall_ms \t text
--   ftlbench/live/results.txt   answers: id \t ok [\t seconds to wait]   or   id \t error \t reason
--   ftlbench/live/bridge_error.txt   last bridge error, if frames are failing
--   ftlbench/live/run.txt       the current Run folder, relative to ftlbench/
--   ftlbench/runs/<stamp>/actions.jsonl   Action log for that Run
--   ftlbench/runs/<stamp>/events.jsonl    events for that Run (already filtered by Visibility)
--   ftlbench/runs/<stamp>/score.json      Score record, rewritten every game-over frame so it ends final
--
-- Needs our Hyperspace fork (game-over and score fields); see docs/hyperspace-fork.md.

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

local SENSORS = 7
local KEY_1 = 49 -- SDLK_1

---@param n number
---@return integer
local function int(n)
    return math.floor(n)
end

---@param ship any ShipManager
---@return RawRoom[]
local function read_rooms(ship)
    local rooms, o2 = {}, ship.oxygenSystem
    local breaches = {}
    local list = ship.ship:GetHullBreaches(true)
    for i = 0, list:size() - 1 do
        local room = int(list[i].roomId)
        breaches[room] = (breaches[room] or 0) + 1
    end
    for i = 0, ship.ship.vRoomList:size() - 1 do
        local r = ship.ship.vRoomList[i]
        local id = int(r.iRoomId)
        local sys = ship:GetSystemInRoom(id)
        rooms[#rooms + 1] = {
            id = id,
            x = int(r.rect.x),
            y = int(r.rect.y),
            w = int(r.rect.w),
            h = int(r.rect.h),
            system = sys and int(sys.iSystemType) or nil,
            oxygen = o2 and o2.oxygenLevels[id] or 100,
            fires = int(ship:GetFireCount(id)),
            breaches = breaches[id] or 0,
        }
    end
    return rooms
end

---Interior doors keep their game ids; airlocks are numbered after them.
---@param ship any ShipManager
---@return RawDoor[], any[] game Door objects in the same order
local function read_doors(ship)
    local doors, objects = {}, {}
    for _, list in ipairs({ ship.ship.vDoorList, ship.ship.vOuterAirlocks }) do
        for i = 0, list:size() - 1 do
            local d = list[i]
            objects[#objects + 1] = d
            doors[#doors + 1] = {
                id = #doors,
                room1 = int(d.iRoom1),
                room2 = int(d.iRoom2),
                open = d.bOpen,
            }
        end
    end
    return doors, objects
end

---@param ship any ShipManager
---@return RawCrew[], table<integer, any> crew objects by uid
---@param owner integer? 0 for our crew (default), 1 for the enemy's
local function read_crew(ship, owner)
    owner = owner or 0
    local crew, objects = {}, {}
    for i = 0, ship.vCrewList:size() - 1 do
        local c = ship.vCrewList[i]
        if int(c.iShipId) == owner then
            local uid = int(c.extend.selfId)
            objects[uid] = c
            local skills = {}
            for s = 0, 5 do
                skills[s + 1] = int(c:GetSkillLevel(s))
            end
            crew[#crew + 1] = {
                uid = uid,
                name = c:GetName(),
                species = c:GetSpecies(),
                health = c.health.first,
                health_max = c.health.second,
                room = int(c.iRoomId),
                on_enemy_ship = int(c.currentShipId) ~= owner, -- aboard the other ship
                mind_controlled = c.bMindControlled,
                dead = c:IsDead(),
                stun = c.fStunTime,
                skills = skills,
            }
        end
    end
    return crew, objects
end

---@param ship any ShipManager
---@return RawSystem[]
local function read_systems(ship)
    local systems = {}
    for i = 0, ship.vSystemList:size() - 1 do
        local y = ship.vSystemList[i]
        systems[#systems + 1] = {
            type = int(y.iSystemType),
            room = int(y.roomId),
            power = int(y.powerState.first),
            level = int(y.powerState.second),
            cap = int(y:GetPowerCap()),
            damage = int(y.healthState.second - y.healthState.first),
            ion = math.max(int(y.iLockCount), 0),
            uses_reactor = y.bNeedsPower,
        }
    end
    return systems
end

---@param ship any ShipManager
---@return RawWeapon[], RawDrone[], any[], any[] game weapon and drone objects in slot order
local function read_armaments(ship)
    local weapons, drones, weapon_objs, drone_objs = {}, {}, {}, {}
    local list = ship:GetWeaponList()
    for i = 0, list:size() - 1 do
        local w = list[i]
        weapon_objs[#weapon_objs + 1] = w
        weapons[#weapons + 1] = {
            name = w.name,
            powered = w.powered,
            power = int(w.requiredPower),
            charge = w.cooldown.first,
            charge_time = w.cooldown.second,
            missiles = w.blueprint.missiles > 0,
        }
    end
    list = ship:GetDroneList()
    for i = 0, list:size() - 1 do
        local d = list[i]
        drone_objs[#drone_objs + 1] = d
        drones[#drones + 1] = { name = d:GetName(), powered = d.powered, deployed = d.deployed }
    end
    return weapons, drones, weapon_objs, drone_objs
end

-- Beacons the ship has been next to this sector: their store/distress markers stay visible.
local scouted, scouted_sector = {}, nil

---@param loc any Location
---@return string
local function loc_key(loc)
    return int(loc.loc.x) .. "," .. int(loc.loc.y)
end

---@param sm any StarMap
---@param sector integer
---@return RawMap
local function read_map(sm, sector)
    if scouted_sector ~= sector then
        scouted, scouted_sector = {}, sector
    end
    local index = {}
    for i = 0, sm.locations:size() - 1 do
        index[loc_key(sm.locations[i])] = i
    end
    local current = sm.currentLoc and index[loc_key(sm.currentLoc)] or -1
    local beacons = {}
    for i = 0, sm.locations:size() - 1 do
        local loc = sm.locations[i]
        local links = {}
        for j = 0, loc.connectedLocations:size() - 1 do
            local other = index[loc_key(loc.connectedLocations[j])]
            links[#links + 1] = other
            if i == current then
                scouted[other] = true
            end
        end
        beacons[#beacons + 1] = {
            id = i,
            x = loc.loc.x,
            y = loc.loc.y,
            links = links,
            visited = loc.visited > 0,
            exit = loc.beacon,
            quest = loc.questLoc,
            nebula = loc.nebula,
            store = loc.event ~= nil and loc.event.store,
            distress = loc.event ~= nil and loc.event.distressBeacon,
            scouted = scouted[i],
        }
    end
    local choices
    if current >= 0 and beacons[current + 1].exit then
        choices = {}
        for i = 0, sm.sectors:size() - 1 do
            if sm:NeighboringSector(i) then
                choices[#choices + 1] = { index = i, type = int(sm.sectors[i].type) }
            end
        end
    end
    return {
        current = current,
        beacons = beacons,
        fleet = {
            x = sm.dangerZone.x,
            y = sm.dangerZone.y,
            radius = sm.dangerZoneRadius,
            advance = sm:GetNextDangerMove(),
        },
        sector_choices = choices,
    }
end

---@param r any ResourceEvent
---@return table<string, number>
local function read_resources(r)
    return {
        scrap = int(r.scrap),
        fuel = int(r.fuel),
        missiles = int(r.missiles),
        drone_parts = int(r.drones),
        crew = int(r.crew),
    }
end

---@param gui any CommandGui
---@return RawEvent?
local function read_event(gui)
    if not gui.choiceBoxOpen then
        return nil
    end
    local box, choices = gui.choiceBox, {}
    for i = 0, box.choices:size() - 1 do
        local c = box.choices[i]
        -- ChoiceText.type: 0 normal, 1 requirement not met (seen live: an unaffordable toll, whose key
        -- press does nothing), 2 blue option (inferred; see #14).
        local type = int(c.type)
        choices[#choices + 1] = { text = c.text, blue = type == 2, available = type ~= 1 }
    end
    return { text = box.mainText, choices = choices, received = read_resources(box.rewards) }
end

---The enemy ship, if one is here. Raw state holds everything; Visibility decides what is shown.
---@param ship any ShipManager
---@param player any ShipManager
---@return RawEnemy
local function read_enemy(ship, player)
    local shields = ship:GetShieldPower()
    local weapons, drones = read_armaments(ship)
    local hacked
    local hacking = player.hackingSystem
    if hacking and hacking.drone and hacking.drone.arrived and hacking.currentSystem then
        hacked = int(hacking.currentSystem.iSystemType)
    end
    return {
        class = ship.myBlueprint.desc.title:GetText(),
        hostile = ship._targetable.hostile,
        cloaked = ship.cloakSystem ~= nil and ship.cloakSystem.bTurnedOn,
        flagship = ship.myBlueprint.blueprintName:find("BOSS") ~= nil,
        destroyed = ship.bDestroyed,
        hull = int(ship.ship.hullIntegrity.first),
        hull_max = int(ship.ship.hullIntegrity.second),
        scrap = int(ship.currentScrap),
        shield_layers = int(shields.first),
        shield_layers_max = int(shields.second),
        evasion = ship:GetDodgeFactor(),
        oxygen = ship:GetOxygenPercentage(),
        rooms = read_rooms(ship),
        doors = (read_doors(ship)),
        systems = read_systems(ship),
        weapons = weapons,
        drones = drones,
        crew = (read_crew(ship, 1)),
        hacked_system = hacked,
    }
end

---@param ship any ShipManager
---@param augment string
---@return boolean
local function has_augment(ship, augment)
    local ok, count = pcall(function()
        return ship:HasAugmentation(augment)
    end)
    return ok and count ~= nil and count ~= false and count ~= 0
end

-- Per crew uid: last health seen and the game time it last dropped, for taking_damage.
local health_seen, last_drop = {}, {}
local DAMAGE_WINDOW = 2 -- game seconds a drop counts as "taking damage"

---@param crew RawCrew[]
local function mark_damage(crew)
    for _, c in ipairs(crew) do
        if health_seen[c.uid] and c.health < health_seen[c.uid] then
            last_drop[c.uid] = game_time
        end
        health_seen[c.uid] = c.health
        c.taking_damage = last_drop[c.uid] ~= nil and game_time - last_drop[c.uid] < DAMAGE_WINDOW
    end
end

-- Game objects behind the last raw state, for the executor.
local door_objects, crew_objects, weapon_objects, drone_objects = {}, {}, {}, {}

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
        local sensors = ship:GetSystem(SENSORS)
        local doors
        raw.nebula = app.world.space.bNebula
        raw.sector = int(app.world.starMap.worldLevel) + 1
        raw.game_over = gui.gameover
        -- alreadyWon is set the moment the Flagship dies; bVictory once the end screen opens.
        raw.victory = gui.alreadyWon or gui.gameOverScreen.bVictory
        raw.score = int(Hyperspace.Score.currentScore.score)
        raw.player = {
            hull = int(ship.ship.hullIntegrity.first),
            hull_max = int(ship.ship.hullIntegrity.second),
            scrap = int(ship.currentScrap),
            oxygen = ship:GetOxygenPercentage(),
            sensors_power = sensors and int(sensors.powerState.first) or 0, -- base power; manning is added by Visibility
            rooms = read_rooms(ship),
        }
        doors, door_objects = read_doors(ship)
        raw.player.doors = doors
        raw.player.crew, crew_objects = read_crew(ship)
        mark_damage(raw.player.crew)
        local p, pm = raw.player, Hyperspace.PowerManager.GetPowerManager(0)
        p.reactor = { used = int(pm.currentPower.first), max = int(pm.currentPower.second) }
        p.systems = read_systems(ship)
        local shields = ship:GetShieldPower()
        p.shield_layers, p.shield_layers_max = int(shields.first), int(shields.second)
        p.evasion, p.fuel = ship:GetDodgeFactor(), int(ship.fuel_count)
        p.missiles, p.drone_parts = int(ship:GetMissileCount()), int(ship:GetDroneCount())
        p.weapons, p.drones, weapon_objects, drone_objects = read_armaments(ship)
        p.ftl_charge, p.ftl_charge_time = ship.jump_timer.first, ship.jump_timer.second
        p.sensors_manned = sensors ~= nil and int(sensors.iActiveManned) > 0
        p.lifeform_scanner = has_augment(ship, "LIFE_SCANNER")
        local enemy = Hyperspace.ships.enemy
        raw.enemy = enemy and read_enemy(enemy, ship) or nil
        raw.map = read_map(app.world.starMap, raw.sector)
        raw.event = read_event(gui)
    end
    return raw
end

---Carry out a resolved Command. Returns an error message on runtime failure.
---@param cmd ResolvedCommand
---@return string?
local function execute(cmd)
    if cmd.kind == "pause" then
        Hyperspace.App.gui.bPaused = true
    elseif cmd.kind == "unpause" then
        Hyperspace.App.gui.bPaused = false
    elseif cmd.kind == "move" then
        local crew = crew_objects[cmd.crew]
        local room = (cmd.enemy and "enemy:room:" or "room:") .. cmd.room
        if not crew then
            return ("crew:%d is no longer aboard"):format(cmd.crew)
        elseif not crew:MoveToRoom(cmd.room, -1, false) then
            return ("crew:%d (%s) cannot reach %s"):format(cmd.crew, crew:GetName(), room)
        end
    elseif cmd.kind == "door" then
        for _, id in ipairs(cmd.doors) do
            door_objects[id + 1].bOpen = cmd.open
        end
    elseif cmd.kind == "power" then
        local ship = Hyperspace.ships.player
        local sys = ship:GetSystem(cmd.system)
        local per_click = cmd.system == 0 and 2 or 1 -- the game moves shields a layer per click
        local target = int(sys.powerState.first) + cmd.delta
        for _ = 1, math.floor(math.abs(cmd.delta) / per_click) do
            local ok
            if cmd.delta > 0 then
                ok = sys:IncreasePower(1, false)
            else
                ok = ship:ForceDecreaseSystemPower(cmd.system)
            end
            if not ok then
                break
            end
        end
        -- The game keeps restoring each system toward the power the player last chose.
        sys.lastUserPower = sys.powerState.first
        if int(sys.powerState.first) ~= target then
            return ("the game stopped the change at %d power"):format(int(sys.powerState.first))
        end
    elseif cmd.kind == "choose" then
        -- Number keys 1-9 pick a choice in FTL's event window, the same as a player pressing them.
        local app = Hyperspace.App
        app:OnKeyDown(KEY_1 + cmd.choice)
        app:OnKeyUp(KEY_1 + cmd.choice)
    elseif cmd.kind == "jump" then
        -- The game travels on its next update, as when the player clicks a beacon on the map.
        local sm = Hyperspace.App.world.starMap
        sm.potentialLoc = sm.locations[cmd.beacon]
        sm.readyToTravel = true
    elseif cmd.kind == "jump_sector" then
        -- The map's own loop picks the sector (Hyperspace's sector-jump test does the same).
        local sm = Hyperspace.App.world.starMap
        sm.bOpen, sm.bChoosingNewSector, sm.finalSectorChoice = true, true, cmd.sector
    elseif cmd.kind == "weapon" then
        local ship = Hyperspace.ships.player
        local w = weapon_objects[cmd.slot + 1]
        local ok = cmd.on and ship.weaponSystem:PowerWeapon(w, true, false)
            or not cmd.on and ship.weaponSystem:DePowerWeapon(w, true)
        if not ok and w.powered ~= cmd.on then
            return ("the game refused to power %s weapon:%d (%s)"):format(
                cmd.on and "on" or "off",
                cmd.slot,
                w.name
            )
        end
    elseif cmd.kind == "drone" then
        local ship = Hyperspace.ships.player
        local d = drone_objects[cmd.slot + 1]
        local ok = cmd.on and ship.droneSystem:PowerDrone(d, true, false)
            or not cmd.on and ship.droneSystem:DePowerDrone(d, true)
        if not ok and d.powered ~= cmd.on then
            return ("the game refused to power %s drone:%d (%s)"):format(
                cmd.on and "on" or "off",
                cmd.slot,
                d:GetName()
            )
        end
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
            local cmd, err = Commands.plan(text, raw)
            if cmd then
                err = execute(cmd)
            end
            local status = err and ("error\t" .. err)
                or (cmd and cmd.seconds and ("ok\t" .. cmd.seconds))
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
    -- A dev build writes raw state to disk (dev-probe); flag it so no Run using it can pass as scored.
    out.views.state.dev_build = FtlBench.dev_probe or nil
    write_atomic(LIVE .. "/state.json", Json.encode(out.views.state))
    for _, view in ipairs({ "map", "jumps" }) do
        if out.views[view] then
            write_atomic(LIVE .. "/" .. view .. ".json", Json.encode(out.views[view]))
        else
            os.remove(LIVE .. "/" .. view .. ".json") -- never serve a finished Run's map
        end
    end
    if run_dir then
        for _, event in ipairs(out.events) do
            event.frame, event.game_time, event.wall_s = raw.frame, raw.game_time, os.time()
            append(run_dir .. "/events.jsonl", Json.encode(event) .. "\n")
        end
        local state = out.views.state
        if state.game_over then
            write_atomic(
                run_dir .. "/score.json",
                Json.encode({
                    score = state.score,
                    sector = state.sector,
                    victory = state.victory,
                    frame = raw.frame,
                    game_time = raw.game_time,
                })
            )
        end
    end
    handle_inbox(raw)
    prev = raw
end

mkdir(LIVE)
-- Start every game launch with an empty inbox so stale Commands never run.
write_atomic(LIVE .. "/inbox.txt", "")
write_atomic(LIVE .. "/results.txt", "")
os.remove(LIVE .. "/run.txt") -- no Run until on_init says so

script.on_init(function()
    frame, game_time, prev = 0, 0.0, nil
    scouted, scouted_sector = {}, nil -- markers seen in an earlier Run must not carry over
    health_seen, last_drop = {}, {}
    local name = "runs/" .. os.date("%Y%m%d-%H%M%S")
    run_dir = BASE .. "/" .. name
    mkdir(run_dir)
    write_atomic(LIVE .. "/run.txt", name)
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
