-- Bridge: the only module that touches the game. Each frame it reads raw state,
-- runs it through Visibility, writes the Observation, and answers Commands from
-- the inbox. It never writes raw state to disk (ADR 0004).
--
-- Files live under the FTL save folder (Hyperspace's working directory):
--   ftlbench/live/state.json    current state view, rewritten every frame
--   ftlbench/live/map.json, store.json, upgrades.json   other views, every frame
--   ftlbench/live/inbox.txt     Commands from the CLI: id \t wall_ms \t text
--   ftlbench/live/results.txt   answers: id \t ok [\t seconds to wait]   or   id \t error \t reason
--   ftlbench/live/bridge_error.txt   last bridge error, if frames are failing
--   ftlbench/live/run.txt       the current Run folder, relative to ftlbench/
--   ftlbench/runs/<stamp>/actions.jsonl   Action log for that Run (each line also printed to the console)
--   ftlbench/runs/<stamp>/events.jsonl    events for that Run (already filtered by Visibility)
--   ftlbench/runs/<stamp>/score.json      Score record, rewritten every game-over frame so it ends final
--   ftlbench/console_commands   "off" stops printing Commands; missing or anything else leaves it on
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
local BEAM_TYPE = 2 -- WeaponBlueprint.type
local KEY_1 = 49 -- SDLK_1: FTL's weapon1 and first-choice hotkey
---A hotkey from the player's FTL settings.ini, so a custom keymap still works (ADR 0005).
---@param name string
---@param default integer SDL key code FTL uses out of the box
---@return integer
local function hotkey(name, default)
    local f = io.open("settings.ini", "r")
    local key = f and f:read("a"):match("\n" .. name .. "=(%d+)")
    if f then
        f:close()
    end
    return tonumber(key) or default
end
local KEY_AUTOFIRE = hotkey("autofire", 118)
local KEY_ESCAPE = 27 -- SDLK_ESCAPE: closes the open window (not rebindable)
local KEY_OPEN_DOORS, KEY_CLOSE_DOORS = hotkey("open", 122), hotkey("close", 120)
local KEY_STORE = hotkey("store", 0) -- unbound by default; scripts/install-mod binds it
local KEY_CLOAK, KEY_BATTERY = hotkey("activate_cloak", 99), hotkey("activate_battery", 98)
local KEY_HACK = hotkey("start_hacking", 110)
local KEY_MAP, KEY_UPGRADES = hotkey("jump", 106), hotkey("ship_info", 117)

-- Power hotkeys by FTL system type id: the player's key to add power and (bound by
-- scripts/install-mod) to remove it.
local POWER_KEYS = {}
for type, name in pairs({
    [0] = "shields",
    [1] = "engines",
    [2] = "oxygen",
    [3] = "weapons",
    [4] = "drones",
    [5] = "medbay",
    [9] = "teleporter",
    [10] = "cloaking",
    [11] = "artillery",
    [14] = "mind",
    [15] = "hacking",
}) do
    POWER_KEYS[type] = { up = hotkey(name, 0), down = hotkey("un_" .. name, 0) }
end

---@param key integer
local function press(key)
    Hyperspace.App:OnKeyDown(key)
    Hyperspace.App:OnKeyUp(key)
end

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
---Crew owned by `owner`, wherever they are. Both ships' lists are read and split by owner, so a
---crew member counts once whichever list the game keeps them in while boarding.
---@param owner integer? 0 for our crew (default), 1 for the enemy's
local function read_crew(ship, owner)
    owner = owner or 0
    local crew, objects = {}, {}
    local lists = { ship.vCrewList }
    local other = Hyperspace.ships[owner == 0 and "enemy" or "player"]
    if other then
        lists[2] = other.vCrewList
    end
    for _, list in ipairs(lists) do
        for i = 0, list:size() - 1 do
            local c = list[i]
            local uid = int(c.extend.selfId)
            if int(c.iShipId) == owner and not objects[uid] then
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
                    drone = c:IsDrone(),
                    skills = skills,
                }
            end
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
            -- Damaged bars can't hold power: the most it takes is its cap or its undamaged bars.
            cap = math.min(int(y:GetPowerCap()), int(y.healthState.first)),
            damage = int(y.healthState.second - y.healthState.first),
            ion = math.max(int(y.iLockCount), 0),
            ion_seconds = y.lockTimer.currGoal - y.lockTimer.currTime, -- the icon's blue bar
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
            beam = int(w.blueprint.type) == BEAM_TYPE,
            aimed = w.targets:size() > 0,
        }
    end
    list = ship:GetDroneList()
    for i = 0, list:size() - 1 do
        local d = list[i]
        drone_objs[#drone_objs + 1] = d
        drones[#drones + 1] = {
            name = d:GetName(),
            powered = d.powered,
            deployed = d.deployed,
            power = int(d.blueprint.power),
            type = d.blueprint.typeName,
        }
    end
    return weapons, drones, weapon_objs, drone_objs
end

---@param loc any Location
---@return string
local function loc_key(loc)
    return int(loc.loc.x) .. "," .. int(loc.loc.y)
end

---@param sm any StarMap
---@return RawMap
local function read_map(sm)
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
            -- The game's own flag: set once the ship is next to the beacon, kept in the save, so its
            -- store/distress markers stay (visible-state.md Q13).
            scouted = loc.known,
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

-- The window the Agent opened by reading a view (`ftl map|upgrades|store`); stays until `close`.
-- The game opens a window a frame or so after its key press, so a `show` waits a few frames
-- (pending) before counting the window as refused (the game won't open some mid-fight).
-- Accepted moves by crew uid, until the crew member arrives (or command_failed reports it).
local pending_moves = {}

local SHOW_GRACE_FRAMES = 5
-- The window a `show` pressed for until it opens (pending), and the last one the game refused.
local shown = { pending = nil, frames = 0, refused = nil }

---The game window open over the ship view, read from the windows themselves (an event box sets
---the same menu pause, so that pause alone can't tell them apart).
---@return string?
local function game_window()
    local app = Hyperspace.App
    local loc = app.world.starMap.currentLoc
    local store = loc and loc.event and loc.event.pStore
    if not app.gui.menu_pause then
        return nil -- a window's open flag can linger a moment after it closes
    elseif app.world.starMap.bOpen then
        return "map"
    elseif store and store.bOpen then
        return "store"
    elseif app.gui.shipScreens.bOpen then
        return "upgrades" -- the ship-info window, which opens on its upgrades tab
    end
    return nil
end

-- Enemy crew objects by uid, for mind control (filled by read_enemy).
local enemy_crew_objects = {}

---The enemy ship, if one is here. Raw state holds everything; Visibility decides what is shown.
---@param ship any ShipManager
---@param player any ShipManager
---@return RawEnemy
local function read_enemy(ship, player)
    local shields = ship:GetShieldPower()
    local weapons, drones = read_armaments(ship)
    local enemy_crew
    enemy_crew, enemy_crew_objects = read_crew(ship, 1)
    local hacked
    local hacking = player.hackingSystem
    if hacking and hacking.drone and hacking.drone.arrived and hacking.currentSystem then
        hacked = int(hacking.currentSystem.iSystemType)
    end
    return {
        class = ship.myBlueprint.desc.title:GetText(),
        hostile = ship._targetable.hostile,
        cloaked = ship.cloakSystem ~= nil and ship.cloakSystem.bTurnedOn,
        flagship = ship.myBlueprint.blueprintName:find("^BOSS") ~= nil,
        destroyed = ship.bDestroyed,
        hull = int(ship.ship.hullIntegrity.first),
        hull_max = int(ship.ship.hullIntegrity.second),
        scrap = int(ship.currentScrap),
        shield_layers = int(shields.first),
        shield_layers_max = int(shields.second),
        zoltan = int(shields.super.first),
        zoltan_max = int(shields.super.second),
        evasion = ship:GetDodgeFactor(),
        oxygen = ship:GetOxygenPercentage(),
        rooms = read_rooms(ship),
        doors = (read_doors(ship)),
        systems = read_systems(ship),
        weapons = weapons,
        drones = drones,
        crew = enemy_crew,
        hacked_system = hacked,
        hacking_powered = hacking ~= nil and int(hacking.powerState.first) > 0,
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

local WARNINGS = { -- banners and the action refusals our Command errors share
    "warning_hull_75",
    "warning_hull_50",
    "warning_hull_25",
    "warning_shields",
    "warning_oxygen",
    "warning_intruders",
    "warning_engine",
    "warning_clone_off_1",
    "warning_clone_off_2",
    "warning_environment_danger",
    "warning_pds_allies",
    "warning_pds_all",
    "warning_in_danger",
    "warning_no_missiles",
    "warning_no_drones",
    "warning_no_enemy_ship",
    "warning_no_power",
    "warning_system_broken",
    "warning_needs_upgrade",
    "warning_no_system_power",
    "warning_super_shield_mind",
    "warning_super_shield_hacking",
    "warning_super_shield_teleporter",
}
local warning_text_cache

---The warning texts, from the game's text library (read once).
---@return table<string, string>
local function warning_texts()
    if not warning_text_cache then
        warning_text_cache = {}
        for _, name in ipairs(WARNINGS) do
            warning_text_cache[name] = Hyperspace.Text:GetText(name)
        end
    end
    return warning_text_cache
end

---@param v any a std::vector<std::string>
---@return string[]
local function string_list(v)
    local out = {}
    for i = 0, v:size() - 1 do
        out[#out + 1] = v[i]
    end
    return out
end

---An equipment blueprint's display name, whichever kind it is.
---@param name string
---@return string
local function title_of(name)
    local B = Hyperspace.Blueprints
    for _, bp in ipairs({
        B:GetWeaponBlueprint(name),
        B:GetDroneBlueprint(name),
        B:GetAugmentBlueprint(name),
    }) do
        local title = bp.desc.title:GetText()
        if title ~= "" then
            return title
        end
    end
    return name
end

local tooltips = {} -- by blueprint name: an item's text doesn't change

---The text a player sees hovering an item in the store or the equipment screen: the game fills the
---equipment screen's info box for it (with Hyperspace's redesigned tooltips, switched on in our
---hyperspace.xml.append) and we read the box back. Nil for a name that is no equipment.
---@param name string a blueprint name
---@return string?
local function hover_text(name)
    if tooltips[name] == nil then
        local B, info = Hyperspace.Blueprints, Hyperspace.App.gui.equipScreen.infoBox
        local weapon, drone = B:GetWeaponBlueprint(name), B:GetDroneBlueprint(name)
        local augment, crew = B:GetAugmentBlueprint(name), B:GetCrewBlueprint(name)
        -- Unknown names get a stand-in back: a blank weapon, drone or augment, or the default crew.
        local filled = true
        if int(weapon.power) > 0 then
            info:SetBlueprint(weapon, 0, true, 0)
        elseif int(drone.power) > 0 then
            info:SetBlueprint(drone, 0, true, 0)
        elseif augment.name == name and augment.desc.title:GetText() ~= "" then
            info:SetBlueprint(augment)
        elseif crew.name == name then
            info:SetBlueprint(crew, 0, false)
        else
            filled = false -- systems, fuel, missiles, drone parts: their description is all
        end
        tooltips[name] = filled and info.desc.description:GetText():gsub("%s+$", "") or ""
        info:Clear()
    end
    return tooltips[name] ~= "" and tooltips[name] or nil
end

---A store box's hover text. Systems, fuel, missiles and the like show their description.
---@param box any StoreBox
---@return string
local function store_tooltip(box)
    return box.pBlueprint and hover_text(box.pBlueprint.name) or box.desc.description:GetText()
end

---A system box's hover text without its hotkey lines (Commands move power, not keys).
---@param box any SystemBox
---@return string
local function system_tooltip(box)
    local add = Hyperspace.Text:GetText("add_power"):match("^[^\\]*")
    local remove = Hyperspace.Text:GetText("remove_power"):match("^[^\\]*")
    local lines = {}
    for line in (box:GenerateTooltip() .. "\n"):gmatch("(.-)\n") do
        if line:sub(1, #add) ~= add and line:sub(1, #remove) ~= remove then
            lines[#lines + 1] = line
        end
    end
    return (table.concat(lines, "\n"):gsub("%s+$", ""))
end

---The store at the current beacon, if any (a human can open it from the store button here).
---@return table? store raw store view
---@return any[] boxes StoreBox objects in item order
---@return any? object the Store itself, for the executor
local function read_store()
    local loc = Hyperspace.App.world.starMap.currentLoc
    local store = loc and loc.event and loc.event.pStore
    if not store then
        return nil, {}, nil
    end
    local items, boxes = {}, {}
    for _, list in ipairs({ store.vStoreBoxes, store.vItemBoxes }) do
        for i = 0, list:size() - 1 do
            local box = list[i]
            boxes[#boxes + 1] = box
            items[#items + 1] = {
                name = box.desc.title:GetText(),
                cost = int(box.desc.cost),
                stock = int(box.count),
                can_hold = box:CanHold(),
                description = store_tooltip(box),
            }
        end
    end
    return { open = store.bOpen, items = items }, boxes, store
end

local system_texts = {} -- by system type: fixed for the Run, so read once

---A system's upgrade-screen text: its description and each level's line (0-based in the game).
---@param y any ShipSystem
---@param bp any SystemBlueprint?
---@param max integer
---@return { description: string?, levels: string[] }
local function system_text(y, bp, max)
    local key = int(y.iSystemType)
    local text = system_texts[key]
    if not text or #text.levels < max then
        text = { description = bp and bp.desc.description:GetText(), levels = {} }
        for l = 1, max do
            text.levels[l] = Hyperspace.ShipSystem.GetLevelDescription(y.iSystemType, l - 1, false)
        end
        system_texts[key] = text
    end
    return text
end

---@param ship any ShipManager
---@return RawUpgrades
local function read_upgrades(ship)
    local systems = {}
    for i = 0, ship.vSystemList:size() - 1 do
        local y = ship.vSystemList[i]
        local level, max = int(y.powerState.second), int(y.maxLevel)
        local bp = Hyperspace.Blueprints:GetSystemBlueprint(y.name)
        local cost
        if level < max and bp and bp.upgradeCosts:size() >= level then
            cost = int(bp.upgradeCosts[level - 1]) -- costs[i] buys level i + 2
        end
        local text = system_text(y, bp, max)
        local levels = {}
        for l = 1, max do -- the upgrade screen's list: prices for levels not yet bought
            local price = l > level and bp and bp.upgradeCosts:size() >= l - 1
            levels[l] = {
                level = l,
                cost = price and int(bp.upgradeCosts[l - 2]) or nil,
                text = text.levels[l],
            }
        end
        systems[#systems + 1] = {
            type = int(y.iSystemType),
            level = level,
            max_level = max,
            cost = cost,
            description = text.description,
            levels = levels,
        }
    end
    local reactor_cost = int(Hyperspace.App.gui.upgradeScreen.reactorButton:GetUpgradeCost())
    local pm = Hyperspace.PowerManager.GetPowerManager(0)
    return {
        reactor = {
            level = int(pm.currentPower.second),
            cost = reactor_cost >= 0 and reactor_cost or nil,
        },
        systems = systems,
    }
end

---Status of our ability systems, for the ones this ship has.
---@param ship any ShipManager
---@return table<string, table>
local function read_abilities(ship)
    local a = {}
    if ship.cloakSystem then
        a.cloak = { on = ship.cloakSystem.bTurnedOn }
    end
    if ship.batterySystem then
        a.battery = { on = ship.batterySystem.bTurnedOn }
    end
    if ship.hackingSystem then
        local drone = ship.hackingSystem.drone
        a.hacking =
            { drone = drone ~= nil and drone.arrived, launched = ship.hackingSystem.bHacking }
    end
    if ship.mindSystem then
        a.mind = { controlling = ship.mindSystem.controlledCrew:size() > 0 }
    end
    if ship.teleportSystem then
        local charge = int(ship.teleportSystem.chargeLevel)
        a.teleporter = { charged = charge >= 100, charge = charge }
    end
    return a
end

-- Game objects behind the last raw state, for the executor.
local door_objects, crew_objects, weapon_objects, drone_objects, store_boxes = {}, {}, {}, {}, {}
local augment_names, cargo_names = {}, {} -- blueprint names, in the state view's order

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
        local space = app.world.space
        raw.nebula = space.bNebula
        raw.hazards = { -- the hazard icons at the top of the screen
            asteroids = space.asteroidGenerator.bRunning,
            sun = space.sunLevel,
            pulsar = space.pulsarLevel,
            pds = space.bPDS,
            pds_target = int(space.envTarget),
        }
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
            -- Power without the manning bonus (Visibility adds it): damage and each ion point take a
            -- bar away (visible-state.md Q2), which the game's power state already reflects.
            sensors_power = sensors and int(sensors.powerState.first) or 0,
            rooms = read_rooms(ship),
        }
        doors, door_objects = read_doors(ship)
        raw.player.doors = doors
        raw.player.crew, crew_objects = read_crew(ship)
        if not Hyperspace.ships.enemy then -- boarders outlive a ship that jumps away
            raw.boarders = read_crew(ship, 1)
        end
        mark_damage(raw.player.crew)
        local p = raw.player --[[@as RawShip]]
        local pm = Hyperspace.PowerManager.GetPowerManager(0)
        p.reactor = { used = int(pm.currentPower.first), max = int(pm.currentPower.second) }
        p.systems = read_systems(ship)
        local shields = ship:GetShieldPower()
        p.shield_layers, p.shield_layers_max = int(shields.first), int(shields.second)
        p.zoltan, p.zoltan_max = int(shields.super.first), int(shields.super.second)
        p.evasion, p.fuel = ship:GetDodgeFactor(), int(ship.fuel_count)
        p.missiles, p.drone_parts = int(ship:GetMissileCount()), int(ship:GetDroneCount())
        p.weapons, p.drones, weapon_objects, drone_objects = read_armaments(ship)
        augment_names, cargo_names =
            string_list(ship:GetAugmentationList()), string_list(gui.equipScreen:GetCargoHold())
        p.augments, p.cargo = {}, {}
        for i, name in ipairs(augment_names) do
            p.augments[i] = title_of(name)
        end
        for i, name in ipairs(cargo_names) do
            p.cargo[i] = title_of(name)
        end
        p.ftl_charge, p.ftl_charge_time = ship.jump_timer.first, ship.jump_timer.second
        p.sensors_manned = sensors ~= nil and int(sensors.iActiveManned) > 0
        p.lifeform_scanner = has_augment(ship, "LIFE_SCANNER")
        p.clone_queue = int(Hyperspace.CrewFactory:GetCloneReadyList(true):size())
        p.backup_dna = has_augment(ship, "BACKUP_DNA")
        local enemy = Hyperspace.ships.enemy
        raw.enemy = enemy and read_enemy(enemy, ship) or nil
        raw.autofire = gui.combatControl.weapControl.autoFiring
        p.abilities = read_abilities(ship)
        raw.map = read_map(app.world.starMap)
        raw.event = read_event(gui)
        raw.store, store_boxes = read_store()
        raw.texts = warning_texts()
        raw.window = game_window()
        if shown.pending and raw.window == shown.pending then
            shown.pending = nil
        elseif shown.pending and shown.frames > 0 then
            shown.frames = shown.frames - 1
            raw.window = raw.window or shown.pending -- opening; Commands treat it as open
        elseif shown.pending then
            shown.refused, shown.pending = shown.pending, nil -- the game never opened it
        end
        raw.refused_window = shown.refused
        raw.upgrades = read_upgrades(ship)
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
    elseif cmd.kind == "door" and cmd.all then
        -- The game's open/close-all doors hotkeys. Opening takes two presses: the first opens the
        -- interior doors, the second the airlocks too.
        if not cmd.open then
            press(KEY_CLOSE_DOORS)
        else
            for _ = 1, 2 do
                local shut = false
                for _, d in ipairs(door_objects) do
                    shut = shut or not d.bOpen
                end
                if shut then
                    press(KEY_OPEN_DOORS)
                end
            end
        end
    elseif cmd.kind == "door" then
        for _, id in ipairs(cmd.doors) do
            door_objects[id + 1].bOpen = cmd.open
        end
    elseif cmd.kind == "power" then
        -- Press the system's power hotkey once per step, as a player does (ADR 0005); the game
        -- moves shields a whole layer per press.
        local sys = Hyperspace.ships.player:GetSystem(cmd.system)
        local keys = POWER_KEYS[cmd.system] or {}
        local key = cmd.delta > 0 and keys.up or keys.down
        if not key or key == 0 then
            return "no power hotkey is bound for this system; close FTL and run scripts/install-mod"
        end
        local per_press = cmd.system == 0 and 2 or 1
        local target = int(sys.powerState.first) + cmd.delta
        for _ = 1, math.floor(math.abs(cmd.delta) / per_press) do
            press(key)
        end
        if int(sys.powerState.first) ~= target then
            return ("the game stopped the change at %d power"):format(int(sys.powerState.first))
        end
    elseif cmd.kind == "choose" then
        -- Number keys 1-9 pick a choice in FTL's event window, the same as a player pressing them.
        local app = Hyperspace.App
        app:OnKeyDown(KEY_1 + cmd.choice)
        app:OnKeyUp(KEY_1 + cmd.choice)
    elseif cmd.kind == "target" then
        -- Aim directly: target points (room centres on the enemy ship), the target ship id, fire
        -- when charged, and the weapon system's own target ship.
        local enemy = Hyperspace.ships.enemy
        if not enemy then
            return "the enemy ship is gone"
        end
        -- A real click (diffed in-game) sets one target point per shot, or start and end for a beam,
        -- and the same points as lastTargets. The game fires once it has as many as it needs.
        local w = weapon_objects[cmd.slot + 1]
        local points = {}
        if #cmd.rooms == 2 then
            points = { enemy:GetRoomCenter(cmd.rooms[1]), enemy:GetRoomCenter(cmd.rooms[2]) }
        else
            for i = 1, int(w:NumTargetsRequired()) do
                points[i] = enemy:GetRoomCenter(cmd.rooms[1])
            end
        end
        w.targets:clear()
        w.lastTargets:clear()
        for _, point in ipairs(points) do
            w.targets:push_back(point)
            w.lastTargets:push_back(point)
        end
        w.targetId, w.fireWhenReady = 1, true
    elseif cmd.kind == "untarget" then
        local w = weapon_objects[cmd.slot + 1]
        w.targets:clear()
        w.lastTargets:clear() -- autofire re-aims from these
        w.targetId, w.fireWhenReady = -1, false
    elseif cmd.kind == "buy" then
        local ship, box = Hyperspace.ships.player, store_boxes[cmd.item + 1]
        local before, cost = int(ship.currentScrap), int(box.desc.cost)
        box:Purchase()
        if int(ship.currentScrap) == before then -- Purchase only hands over the item
            ship:ModifyScrapCount(-cost, false)
        end
    elseif cmd.kind == "upgrade" then
        local ship = Hyperspace.ships.player
        ship:GetSystem(cmd.system):UpgradeSystem(1)
        ship:ModifyScrapCount(-cmd.cost, false)
    elseif cmd.kind == "upgrade_reactor" then
        -- The game's own reactor button: OnClick charges the scrap, Accept installs the bar.
        local button = Hyperspace.App.gui.upgradeScreen.reactorButton
        button.bHover = true
        button:OnClick()
        button.bHover = false
        button:Accept()
    elseif cmd.kind == "close" then
        -- Escape closes the window the way a player does, clearing the game's window pause too
        -- (Store:Close() alone left it set). Commands only allows this while a window is open.
        press(KEY_ESCAPE)
        shown.pending = nil
    elseif cmd.kind == "cloak" or cmd.kind == "battery" then
        local ship = Hyperspace.ships.player
        local sys = cmd.kind == "cloak" and ship.cloakSystem or ship.batterySystem
        press(cmd.kind == "cloak" and KEY_CLOAK or KEY_BATTERY)
        if not sys.bTurnedOn then
            return ("the game did not turn %s on (cooling down?)"):format(cmd.kind)
        end
    elseif cmd.kind == "hack" then
        -- An aimed click queues the target system and disarms; the game then launches the drone.
        local ship, enemy = Hyperspace.ships.player, Hyperspace.ships.enemy
        if not enemy then
            return "the enemy ship is gone"
        end
        ship.hackingSystem.queuedSystem = enemy:GetSystemInRoom(cmd.room)
        ship.hackingSystem.bArmed = false
    elseif cmd.kind == "hack_pulse" then
        press(KEY_HACK)
    elseif cmd.kind == "mindcontrol" then
        local mind, crew = Hyperspace.ships.player.mindSystem, enemy_crew_objects[cmd.crew]
        if not crew then
            return "that crew member is gone"
        end
        mind.iQueuedTarget, mind.iQueuedShip = int(crew.iRoomId), 1
        mind.queuedCrew:clear()
        mind.queuedCrew:push_back(crew)
        mind:InitiateMindControl()
        if mind.controlledCrew:size() == 0 then
            return "the game did not take control (charging, or the target is shielded?)"
        end
    elseif cmd.kind == "teleport" then
        Hyperspace.App.world.playerShip:InitiateTeleport(cmd.room, cmd.command)
    elseif cmd.kind == "show" then
        -- Open the window the Agent is reading, as a player would; only over the plain ship view.
        local gui, open = Hyperspace.App.gui, game_window()
        if open == cmd.window then
            return nil -- already showing it
        elseif open then
            press(KEY_ESCAPE) -- swap the open window (ours or the game's store) for the new one
        end
        if not (gui.menu_pause or gui.event_pause) then
            local keys = { map = KEY_MAP, upgrades = KEY_UPGRADES, store = KEY_STORE }
            if keys[cmd.window] == 0 then
                return "no store hotkey is bound; close FTL and run scripts/install-mod"
            end
            press(keys[cmd.window])
            shown.pending, shown.frames, shown.refused = cmd.window, SHOW_GRACE_FRAMES, nil
        end
    elseif cmd.kind == "autofire" then
        -- autoFiring is read-only to Lua; press FTL's autofire hotkey when it needs to change.
        if Hyperspace.App.gui.combatControl.weapControl.autoFiring ~= cmd.on then
            press(KEY_AUTOFIRE)
        end
    elseif cmd.kind == "jump" then
        -- The game travels on its next update, as when the player clicks a beacon on the map.
        local sm = Hyperspace.App.world.starMap
        if sm.bOpen then
            -- Close the map first: the game froze in StarMap::OnRender when it rendered an open map
            -- with travel set this way (#21).
            press(KEY_ESCAPE)
        end
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
            if cmd and cmd.kind == "close" then
                raw.window, raw.pause.menu = nil, false -- later lines this tick see it shut
            end
            if cmd then
                local ok, result = pcall(execute, cmd)
                -- Always answer, so the CLI never waits on a Command that broke mid-way.
                if ok then
                    err = result
                else
                    err = "internal error: " .. tostring(result)
                end
            end
            if cmd and cmd.kind == "move" and not err then
                pending_moves[cmd.crew] =
                    { room = cmd.room, enemy = cmd.enemy, at = raw.game_time, command = text }
            end
            if cmd and cmd.kind == "show" and not err and shown.pending then
                raw.window, raw.pause.menu = shown.pending, true -- later lines this tick see it
            end
            local status = err and ("error\t" .. err)
                or (cmd and cmd.seconds and ("ok\t" .. cmd.seconds))
                or "ok"
            append(LIVE .. "/results.txt", id .. "\t" .. status .. "\n")
            if run_dir and not (cmd and cmd.kind == "show") then -- reading a view isn't a Command
                append(run_dir .. "/actions.jsonl", Json.encode({
                    wall_ms = tonumber(wall_ms),
                    frame = raw.frame,
                    game_time = raw.game_time,
                    command = text,
                    result = err and "error" or "ok",
                    error = err,
                }) .. "\n")
                -- ftlbench/console_commands: "off" stops echoing Commands to the console; default on.
                local setting_file = io.open(BASE .. "/console_commands", "r")
                local setting = setting_file and setting_file:read("l")
                if setting_file then
                    setting_file:close()
                end
                if setting ~= "off" then
                    print("[ftlbench] " .. text .. ": " .. (err or "ok"))
                end
            end
        end
    end
end

-- Combat hooks: collected as the game runs, handed to Visibility once per frame.
local hooks, pending_areas, shielded, beam_room = {}, {}, {}, {}

---@return table[]
local function take_hooks()
    for _, area in pairs(pending_areas) do -- reached a room but never hit it: dodged
        hooks[#hooks + 1] = { kind = "miss", ship = area.ship }
    end
    local out = hooks
    hooks, pending_areas = {}, {}
    local beam_hit = false
    for _, h in ipairs(out) do
        beam_hit = beam_hit or h.kind == "hit"
    end
    if not beam_hit then
        beam_room = {} -- the next beam starts a new sweep
    end
    if not Hyperspace.ships.enemy then
        shielded = {} -- no fight, nothing in flight
    end
    return out
end

---Slot of a weapon on its ship, matched by name (the first match).
---@param ship any ShipManager
---@param weapon any ProjectileFactory
---@return integer
local function weapon_slot(ship, weapon)
    -- SWIG prints a userdata with its native address, so equal strings mean the same weapon
    -- (names alone would confuse two weapons of the same type).
    local id = tostring(weapon)
    local list = ship:GetWeaponList()
    for i = 0, list:size() - 1 do
        if tostring(list[i]) == id then
            return i
        end
    end
    return 0
end

---Run a hook body, logging errors instead of breaking the game's hook chain.
---@param f fun()
local function guarded(f)
    local ok, err = pcall(f)
    if not ok then
        print("[ftlbench] hook error: " .. tostring(err))
    end
end

---@param ship any ShipManager
---@param location any Pointf
---@return integer? room nil outside any room
local function room_at(ship, location)
    local room = int(ship.ship:GetSelectedRoomId(int(location.x), int(location.y), true))
    return room >= 0 and room or nil -- -1 outside any room
end

-- Hyperspace requires each callback to declare the hook's exact parameters (no `...`), and hooks
-- that can change the outcome must hand the game's own values back unchanged.
local events, CONTINUE = Defines.InternalEvents, Defines.Chain.CONTINUE
script.on_internal_event(events.PROJECTILE_FIRE, function(projectile, weapon)
    guarded(function()
        local by = int(projectile.ownerId)
        local ship = Hyperspace.ships[by == 0 and "player" or "enemy"]
        if ship then
            hooks[#hooks + 1] =
                { kind = "fire", by = by, weapon = weapon.name, slot = weapon_slot(ship, weapon) }
        end
    end)
end)
script.on_internal_event(
    events.DAMAGE_AREA,
    function(ship, projectile, _location, _damage, forceHit, shipFriendlyFire)
        guarded(function()
            if projectile then
                pending_areas[int(projectile.selfId)] = { ship = int(ship.iShipId) }
            end
        end)
        return CONTINUE, forceHit, shipFriendlyFire
    end
)
script.on_internal_event(
    events.DAMAGE_AREA_HIT,
    function(ship, projectile, location, damage, _shipFriendlyFire)
        guarded(function()
            if projectile then
                pending_areas[int(projectile.selfId)] = nil
            end
            hooks[#hooks + 1] = {
                kind = "hit",
                ship = int(ship.iShipId),
                room = room_at(ship, location),
                damage = int(damage.iDamage),
            }
        end)
        return CONTINUE
    end
)
script.on_internal_event(
    events.DAMAGE_BEAM,
    function(ship, _projectile, location, damage, newTile, beamHit)
        guarded(function()
            -- A beam reports every tile it crosses; report each room once as it sweeps through.
            local id, room = int(ship.iShipId), room_at(ship, location)
            if newTile and room ~= beam_room[id] then
                beam_room[id] = room
                hooks[#hooks + 1] =
                    { kind = "hit", ship = id, room = room, damage = int(damage.iDamage) }
            end
        end)
        return CONTINUE, beamHit
    end
)
script.on_internal_event(events.SHIELD_COLLISION, function(ship, projectile, _damage, _response)
    guarded(function()
        -- The game reports an ongoing contact every frame; record each projectile once.
        local id = projectile and int(projectile.selfId)
        if id and not shielded[id] then
            shielded[id] = true
            pending_areas[id] = nil
            hooks[#hooks + 1] = { kind = "shield", ship = int(ship.iShipId) }
        end
    end)
    return CONTINUE
end)

---What `ftl help <id>` shows: the game's hover text for each thing of ours, by its state ID.
---@param raw RawState
---@return table<string, string>
local function help_texts(raw)
    local help = {}
    -- Generating a system's tooltip also hands it to the mouse, which would flash it on screen:
    -- put back whatever the mouse was really showing.
    local mouse = Hyperspace.Mouse
    local tip, title, timer = mouse.tooltip, mouse.tooltipTitle, mouse.tooltipTimer
    local boxes = Hyperspace.App.gui.sysControl.sysBoxes
    for i = 0, boxes:size() - 1 do
        local box = boxes[i]
        help[Visibility.system_id(int(box.pSystem.iSystemType))] = system_tooltip(box)
    end
    mouse.tooltip, mouse.tooltipTitle, mouse.tooltipTimer = tip, title, timer
    for kind, list in pairs({ weapon = weapon_objects, drone = drone_objects }) do
        for i, obj in ipairs(list) do
            help[kind .. ":" .. (i - 1)] = hover_text(obj.blueprint.name)
        end
    end
    for kind, names in pairs({ augment = augment_names, cargo = cargo_names }) do
        for i, name in ipairs(names) do
            help[kind .. ":" .. (i - 1)] = hover_text(name)
        end
    end
    for _, c in ipairs(raw.player.crew or {}) do
        help["crew:" .. c.uid] = hover_text(c.species)
    end
    return help
end

local function tick()
    local raw = read_raw()
    if raw.in_run then
        -- FTL's autofire toggle only flags the weapons armed when it is pressed; keep later ones in step.
        for _, w in ipairs(weapon_objects) do
            w.autoFiring = raw.autofire
        end
        frame = frame + 1
        FtlBench.frame = frame -- for the dev replayer
        if not Visibility.is_paused(raw) then
            game_time = game_time + Hyperspace.FPS.SpeedFactor / 16
        end
    end
    local out = Visibility.observe(prev, raw, take_hooks())
    if raw.in_run then
        for _, e in ipairs(Commands.failed_moves(pending_moves, raw, raw.game_time)) do
            out.events[#out.events + 1] = e
        end
    end
    -- A dev build writes raw state to disk (dev-probe); flag it so no Run using it can pass as scored.
    out.views.state.dev_build = FtlBench.dev_probe or nil
    write_atomic(LIVE .. "/state.json", Json.encode(out.views.state))
    if raw.in_run and frame % 30 == 0 then -- system status changes; twice a second is plenty
        write_atomic(LIVE .. "/help.json", Json.encode(help_texts(raw)))
    elseif not raw.in_run then
        os.remove(LIVE .. "/help.json")
    end
    for _, view in ipairs({ "map", "store", "upgrades" }) do
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
                    seed = int(Hyperspace.Global.currentSeed),
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
    health_seen, last_drop = {}, {}
    local name = "runs/" .. os.date("%Y%m%d-%H%M%S")
    run_dir = BASE .. "/" .. name
    mkdir(run_dir)
    write_atomic(LIVE .. "/run.txt", name)
    print("[ftlbench] Run folder " .. run_dir)
end)

local failed = false
-- A Run's Seed: ftlbench/run_seed (one number) fixes the seed of the next New Game.
script.on_internal_event(Defines.InternalEvents.GET_RUN_SEED, function(isCustomSeed, seed)
    local f = io.open("ftlbench/run_seed", "r")
    local wanted = f and tonumber(f:read("l"))
    if f then
        f:close()
    end
    if wanted then
        return true, math.tointeger(wanted)
    end
    return isCustomSeed, seed
end)

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
