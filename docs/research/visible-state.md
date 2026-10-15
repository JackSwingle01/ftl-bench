# Visible state in FTL: Advanced Edition (vanilla, 1.6.x)

Research for [ADR 0003](../adr/0003-observation-is-visible-state-only.md): what a human player can see on screen at any moment. This sets the upper bound on what an **Observation** may contain.

## Sources and trust

- **[DATA]**: vanilla UI and event strings from the game's own data files. They come from `game/FTL.app/Contents/Resources/ftl.dat.vanilla` (FTL **1.6.13**, read-only, extracted to a scratch directory). `ftl.dat` in the same folder differs from vanilla because it is modded, so this note uses `ftl.dat.vanilla` throughout. These strings are Subset Games' own words, so they are the highest-trust source here. Files cited: `data/text_misc.xml`, `data/text_tooltips.xml`, `data/events*.xml`.
- **[WIKI]**: the FTL Fandom wiki (`ftl.fandom.com`). I read each page's wikitext through the MediaWiki API, because the HTML page is behind Cloudflare. Links below go to the normal article pages.
- **Not used:** `ftlwiki.com` now serves an unrelated spam/gambling page; the domain has been squatted. `ftl.wiki.gg` blocks automated access. I did not cite either.
- Claims marked **(unverified)** come from one community source, or are my own understanding without a citation. They are repeated under [Open questions](#open-questions).

## Summary table

| Information | Visible? | Condition | Source |
|---|---|---|---|
| Own ship layout (rooms, doors, airlocks) | Yes | Always | [WIKI Boarding](https://ftl.fandom.com/wiki/Boarding) (doors seen even in a nebula); in-game observation |
| Interior of own rooms (crew, intruders, O2 tint, fire, breach) | Partial | All rooms need Sensors ≥1 working. Without it, only rooms with own crew, plus Slug-adjacent rooms | [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors), [WIKI Slugs](https://ftl.fandom.com/wiki/Slugs) |
| Own system power/damage/ion (HUD bars) | Yes | Always (bottom HUD) | [WIKI Ship](https://ftl.fandom.com/wiki/Ship); DATA `tooltip_*` |
| Fire and sabotage icon above a system | Yes | Always, even without sensors | [WIKI Systems](https://ftl.fandom.com/wiki/Systems#Damaged_and_destroyed_systems) |
| Hull breach indicator | Only with room vision | No GUI icon exists | [WIKI Systems](https://ftl.fandom.com/wiki/Systems#Damaged_and_destroyed_systems) |
| Own hull, shields, evasion %, O2 %, scrap, fuel, missiles, drone parts | Yes | Always; evasion and O2 shown as % | DATA `tooltip_evadeDisplay`, `tooltip_oxygenDisplay`, `tooltip_hull`, `tooltip_*Count` |
| Own weapon charge, FTL charge | Yes (bars) | Always | DATA `ftl_charging` / `ftl_ready` |
| Enemy ship layout and system rooms | Yes | Always while the ship is present (unverified detail: system icons) | in-game observation; [WIKI Hacking](https://ftl.fandom.com/wiki/Hacking#Choosing_your_hacking_target) (targeting by room) |
| Enemy class, relationship (Hostile/Neutral) | Yes | Always (target window) | DATA `combat_class`, `combat_relationship` |
| Enemy hull, shield layers, Zoltan shield | Yes | Always | DATA `tooltip_shieldDisplay`, `tooltip_energyShieldDisplay` (unverified for enemy) |
| Enemy interior (crew position, race, HP via tooltip) | Conditional | Sensors ≥2 working; or Slug / Lifeform Scanner (crew only); or own crew / boarding drone / mind-controlled crew in the room; or attached hacking drone (that room) | [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors), [WIKI Mind Control](https://ftl.fandom.com/wiki/Mind_Control) |
| Enemy weapon charge bars | Conditional | Sensors ≥3 working (L2 + manned counts) | DATA `sensor_3`, [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors) |
| Enemy system level, power use, ion, cooldown, repair/sabotage progress | Conditional | Sensors 4 (L3 + manned), or hacked room (that system only) | DATA `sensor_4`, [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors), [WIKI Hacking](https://ftl.fandom.com/wiki/Hacking) |
| Enemy evasion % | Conditional | Only while your hacking drone is on enemy Piloting or Engines | DATA `current_evasion`, [WIKI Hacking](https://ftl.fandom.com/wiki/Hacking) |
| Enemy oxygen % | Conditional | Only while your hacking drone is on enemy Oxygen | DATA `oxygen_hacked`, `current_oxygen` |
| Enemy cloak remaining duration | Conditional | Sensors 4 or hacked Cloaking | [WIKI Boarding](https://ftl.fandom.com/wiki/Boarding) (contradicted by the Sensors page; see Open questions) |
| Enemy FTL escape | Partial | Warning text only: "ENEMY FTL CHARGING" / "DELAYED" / "JUMP IMMINENT" | DATA `warning_ftl_*` |
| Enemy drones (which ones) | Only once deployed | Not knowable before deployment | [WIKI Drone Control](https://ftl.fandom.com/wiki/Drone_Control) |
| Star map: beacons, links, own position, exit | Yes | Always (exit from any distance) | [WIKI Beacons](https://ftl.fandom.com/wiki/Beacons) |
| Store / distress markers | Conditional | Only for beacons adjacent to you (1 jump), and they then stay marked | [WIKI Beacons](https://ftl.fandom.com/wiki/Beacons) |
| Quest markers | Yes | Any distance, once spawned | [WIKI Beacons](https://ftl.fandom.com/wiki/Beacons) |
| Nebula areas on map | Yes | Always (purple cloud graphics) | [WIKI Sectors](https://ftl.fandom.com/wiki/Sectors#Nebula_generation) |
| Hazards and possible ship at a beacon | Conditional | Adjacent beacons, and only with Long-Ranged Scanners (or a map-reveal event) | [WIKI Augmentations](https://ftl.fandom.com/wiki/Augmentations#Long-Ranged_Scanners), [WIKI Environmental Hazards](https://ftl.fandom.com/wiki/Environmental_Hazards) |
| Rebel fleet controlled area + next-jump warning zone | Yes (visual) | Always; there is no numeric turn count (except the sector 8 base countdown) | [WIKI Rebel Fleet](https://ftl.fandom.com/wiki/Rebel_Fleet), DATA `map_rebels_loc`, `boss_jumps` |
| Sector map: sector type (colour) | Yes | Always; names show as "Unidentified … Sector" until known | DATA `sector_civilian` … `sector_unknown` |
| Event text, choices, blue options you qualify for | Yes | At the event | [WIKI Blue Options](https://ftl.fandom.com/wiki/Blue_Options) |
| Event outcome / random branch before choosing | **No** | Never | DATA `events*.xml` (`hidden="true"`, `eventList`, `autoReward`) |
| Resource preview on a choice | Conditional | Only on choices *not* marked `hidden="true"` (about 30% of choices) | DATA `events*.xml`; forum (unverified) |
| Store items, prices, stock, hull repair cost | Yes | While at a store | [WIKI Stores and resources](https://ftl.fandom.com/wiki/Stores_and_resources), DATA `store_*` |
| Item rarity, store generation | **No** | Hidden attribute | [WIKI Stores and resources](https://ftl.fandom.com/wiki/Stores_and_resources) |

## 1. Enemy ship

### 1.1 Sensors levels

Sensors is a subsystem. Manning it gives +1 level, and level 4 can only be reached by manning a level 3 system ([WIKI Sensors](https://ftl.fandom.com/wiki/Sensors)). The level-info strings in the game data are ([DATA] `text_misc.xml`):

| Effective level | Game text | Adds |
|---|---|---|
| 0 / none / broken | none | No interior of rooms on either ship except where some other vision source applies |
| 1 | `sensor_1` "See ship interior" | Every room of **your own** ship |
| 2 | `sensor_2` "See enemy interior" | Every enemy room: crew position and race (sprite); name and HP on hover |
| 3 | `sensor_3` "See enemy weapon charge" | Enemy weapon charge bars |
| 4 (L3 manned) | `sensor_4` "See enemy power use" | Enemy system level, power use, ion damage and cooldown, repair/sabotage progress |

Notes from [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors):
- Even level 4 does **not** show: time left on an active hack, cloak or mind control; Clone Bay progress; or how many crew are in the cloning queue. This contradicts the Boarding page; see [Open questions](#open-questions).
- With level 2 or higher working, the tooltip still shows enemy crew names and HP while the enemy is **cloaked**, including while the game is paused.
- Sensors stop working in **nebulas** and during the *Human boarders jammed sensors* event. The game's own text: "You're inside a nebula. Your sensors will not function…" ([DATA] `tooltip_nebula`).
- The **Rebel Flagship** caps Sensors at level 2.
- Enemy ships have no Sensors function ([DATA] `tooltip_sensors_enemy`: "Sensors: No functionality for the enemy."). The AI always has full information about the player. The Observation must not copy that asymmetry onto the agent.

**Damaged or ionised Sensors.** The wiki says "*Functioning* Level 2+ Sensors". I take the effective level to be the undamaged, non-ionised level plus the manning bonus. A broken system gives nothing. **(unverified:** partial damage, e.g. a level 3 system with 1 damage, probably behaves as level 2.)

### 1.2 Vision sources other than Sensors

- **Slug crew** ([WIKI Slugs](https://ftl.fandom.com/wiki/Slugs); [DATA] `crew_slug_power_1`: "Telepathic powers reveal rooms and lifeforms even when sensors are down.") A Slug does two things:
  - It reveals **live hostile crew** on both ships. Crew drones are not detected.
  - It gives full interior vision of **rooms adjacent to the Slug's room**, including rooms that touch it through a wall but have no door between them.
- **Lifeform Scanner** (AE augment): "Detects the location of any life forms, even when sensors don't function" ([DATA] `aug_LIFE_SCANNER_desc`). It "functions exactly like the slugs' ability to sense live crew" ([WIKI Augmentations](https://ftl.fandom.com/wiki/Augmentations#Lifeform_Scanner)), i.e. it shows crew only and gives no room vision. Both this and Slugs work in nebulas ([WIKI Environmental Hazards](https://ftl.fandom.com/wiki/Environmental_Hazards#Nebula)).
- **Own crew, boarding drone, or mind-controlled enemy** on the enemy ship give vision of the room they are in ([WIKI Cloaking](https://ftl.fandom.com/wiki/Cloaking), [WIKI Mind Control](https://ftl.fandom.com/wiki/Mind_Control)).
- **A bomb that hits a room** grants vision of that room ([WIKI Mind Control](https://ftl.fandom.com/wiki/Mind_Control)). The wiki does not say how long this lasts. **(unverified)**
- **Hacking drone attached** to a system room ([WIKI Hacking](https://ftl.fandom.com/wiki/Hacking)):
  - It gives "Room vision and max-level Sensors information on the system". This is passive, so it applies even when the Hacking system is unpowered.
  - If the hacked system is **Piloting or Engines** and Hacking is powered, the ship name in the target window is replaced by **"Current Evasion: X"**. The game strings are `engines_hacked`, `pilot_hacked` and `current_evasion` ([DATA]).
  - If the hacked system is **Oxygen**, the target window shows "Oxygen Hacked" and **"Current Oxygen: X"** (`oxygen_hacked`, `current_oxygen` [DATA]). The wiki does not document this; I inferred it from the strings.
  - So enemy evasion % and enemy O2 % are **not shown otherwise**.
- **Mind Control** needs vision of the target. Slug, Lifeform Scanner, manned Sensors, a bomb hit, or a hacked room all count ([WIKI Mind Control](https://ftl.fandom.com/wiki/Mind_Control)).

### 1.3 Enemy cloaking

While the enemy is cloaked, you **lose vision of its interior** except in rooms where your own crew, your boarding drone, or a mind-controlled enemy is. Sensors, Slug telepathy, the Lifeform Scanner and hacking do **not** give vision during a cloak. The exception is that Sensors 2+ crew tooltips still give location and HP on hover ([WIKI Cloaking](https://ftl.fandom.com/wiki/Cloaking)). The cloak itself is visible: the ship goes translucent, and the cloaking tooltip says your weapons stop charging ([DATA] `tooltip_cloaking_enemy`).

How long the cloak has left is visible only with Sensors 4 or with Cloaking hacked, according to [WIKI Boarding](https://ftl.fandom.com/wiki/Boarding#Boarding_support). This **conflicts** with [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors), which says L4 does not show the remaining cloak duration. See Open questions.

### 1.4 What of the enemy is always visible (no Sensors)

- **Target window header:** "Class: …" and "Relationship: Neutral/Hostile" ([DATA] `combat_class`, `combat_relationship`).
- **Hull bar and shield layers.** Shield bubbles are drawn on the ship, and a Zoltan energy shield is drawn too. The [DATA] tooltips cover the player HUD. **(unverified** whether the enemy hull is shown as a number or only as a bar.)
- **Ship hull shape, room outlines and doors.** The wiki says doors opening and closing, and the Doors system level, "can still be observed" in a nebula ([WIKI Boarding](https://ftl.fandom.com/wiki/Boarding#Boarding_support)).
- **System icons on enemy rooms.** You target weapons and hacking by room, so these are visible. **(unverified** whether a damaged or ionised state shows without L4. I believe the icon colour shows damage, but this needs an in-game check.)
- **Fire and sabotage icons above systems** are shown "even if the ship's sensors are absent/disabled/destroyed" ([WIKI Systems](https://ftl.fandom.com/wiki/Systems#Damaged_and_destroyed_systems)). The sentence is about "the ship's" icons in general; I assume it covers both ships. **(unverified** for the enemy ship.)
- **Breaches** have **no GUI icon**. The red emergency lamp in the room "requires the room vision to be seen at all" (same source).
- **Enemy weapons** are drawn as sprites on the enemy hull, and projectiles in flight can be seen. Charge **bars** need Sensors 3 ([DATA] `sensor_3`). **(unverified:** whether weapon names show without sensors, and whether the sprite's charge animation leaks charge state.)
- **Enemy drones:** deployed drones can be seen in space, with hover tooltips such as "Enemy Combat Drone…" and "Defense Drone…" ([DATA] `combat_enemy`, `defense_enemy`, …). Before deployment it is "impossible to know the exact drones the enemy ship will deploy" ([WIKI Drone Control](https://ftl.fandom.com/wiki/Drone_Control)).
- **Enemy FTL escape:** only the text warnings "ENEMY FTL CHARGING", "ENEMY FTL DELAYED" and "JUMP IMMINENT" ([DATA] `warning_ftl_*`). There is no visible progress number. **(unverified** whether a charge bar exists.)
- **Enemy reactor:** the AI always has exactly enough reactor power, halved in ion storms ([WIKI Ship](https://ftl.fandom.com/wiki/Ship)). This is a rule rather than something on screen; the power the enemy is actually using needs L4.

### 1.5 Enemy crew

| Datum | Condition |
|---|---|
| Count, location, race (sprite) | Vision of the room (Sensors 2+, own crew in the room, hacked room, Slug-adjacent room) **or** Slug / Lifeform Scanner (live crew only, no drones) |
| Name, HP | Hover tooltip with Sensors 2+, which works even while cloaked ([WIKI Sensors](https://ftl.fandom.com/wiki/Sensors)). HP bars appear above crew sprites wherever they are visible **(unverified** for Slug/Scanner-only detection) |
| Skills | Not shown for enemy crew **(unverified)** |
| Crew drones (e.g. anti-personnel) | Need real room vision; Slug and Scanner miss them ([WIKI Slugs](https://ftl.fandom.com/wiki/Slugs)) |
| Clone queue count/progress | Not shown even at L4 ([WIKI Sensors](https://ftl.fandom.com/wiki/Sensors)) |

## 2. Own ship

- **Rooms without own crew.** Sensors level 1 is what reveals "the interior of your ship" ([WIKI Sensors](https://ftl.fandom.com/wiki/Sensors), [DATA] `sensor_1`). With no Sensors, or with Sensors broken, ionised, or in a nebula, the only rooms visible are those holding own crew, plus rooms next to a Slug. In the other rooms you cannot see intruders, the O2 tint, or the breach lamp ([WIKI Systems](https://ftl.fandom.com/wiki/Systems#Damaged_and_destroyed_systems)).
- **Still visible in dark rooms:**
  - The room/door layout and the open or closed state of doors ([WIKI Boarding](https://ftl.fandom.com/wiki/Boarding#Boarding_support)).
  - System icons, plus **fire and sabotage icons** above systems ([WIKI Systems](https://ftl.fandom.com/wiki/Systems#Damaged_and_destroyed_systems)).
  - The system power, damage and ion bars in the bottom HUD.
  - The whole-ship O2 % readout.
  - The "INTRUDERS DETECTED" warning, shown "when enemy crew are on the player ship" ([DATA] `warning_intruders`).
  - Sound: boarders sabotaging, fires burning, and air escaping from breaches can all be heard ([WIKI Systems](https://ftl.fandom.com/wiki/Systems#Damaged_and_destroyed_systems)). A text Observation has no sound channel, so the warning text and icons are the fair stand-ins.
- **Own crew:** always visible: name, race, HP, skills (crew panel), location, current task. This is in-game knowledge, not given a citation here.

## 3. HUD: numeric vs visual

| Element | Shown as | Source |
|---|---|---|
| Own hull | Segmented bar labelled "HULL". **(unverified** whether a number is shown.) Thresholds trigger "HULL AT 75%/50%", "HULL CRITICAL" | DATA `status_hull`, `warning_hull_*` |
| Own evasion | **Number %** ("The percentage chance incoming shots will miss your ship") | DATA `tooltip_evadeDisplay` |
| Own oxygen | **Number %** (ship average); "O2 LOW!" below 25% | DATA `tooltip_oxygenDisplay`, `warning_oxygen` |
| Own shields | Bubbles ("Current shield status."); shield recharge bar | DATA `tooltip_shieldDisplay` |
| Scrap, fuel, missiles, drone parts | **Numbers** | DATA `tooltip_scrapCount`, `tooltip_fuelCount`, `tooltip_missileCount`, `tooltip_droneCount` |
| Reactor | Green bars (Zoltan power shows yellow) | [WIKI Ship](https://ftl.fandom.com/wiki/Ship) |
| Weapon charge | Bar per weapon, no seconds shown | in-game; [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors) calls the enemy version "charge bars" |
| FTL drive | Bar + "CHARGING" / "READY!" | DATA `ftl_drive`, `ftl_charging`, `ftl_ready` |
| Cooldowns (cloak, hacking, MC, teleporter, battery) | Visual meters / ion lock circle | [WIKI Systems](https://ftl.fandom.com/wiki/Systems#Systems_cooldown) |
| Rebel fleet | Map shading only; **no turn count** | [WIKI Rebel Fleet](https://ftl.fandom.com/wiki/Rebel_Fleet) |
| Sector 8 | "Turns until the base is destroyed" (numeric) + Flagship icon and jump line | DATA `boss_jumps`, `pc_boss` |
| Hazard timers | Warnings only: "SOLAR FLARE IMMINENT!" (5 s ahead), "ION PULSE IMMINENT!", "ASB TARGET LOCKED!", "POWER SURGE DETECTED" | DATA `warning_*`; [WIKI Environmental Hazards](https://ftl.fandom.com/wiki/Environmental_Hazards) |

Bars are a visual exact value. The ADR decides whether an Observation may quantise them (e.g. charge as a fraction); a human can read a bar about as precisely as a fraction, but **not** as remaining seconds. This needs a decision, so it is listed under Open questions.

## 4. Star map and sector map

From [WIKI Beacons](https://ftl.fandom.com/wiki/Beacons) and the [DATA] `map_*_loc` hover strings:

- **Always shown:**
  - Every beacon (unexplored ones are just dots) and your current position.
  - The **exit** ("EXIT", visible from any distance).
  - **Quest** beacons ("QUEST", any distance once spawned).
  - **Nebula** cloud areas: nebula beacons are generated so the map can draw purple clouds ([WIKI Sectors](https://ftl.fandom.com/wiki/Sectors#Nebula_generation)), and the map hover says "The nebula here will make fleet pursuit slower but will disrupt your sensors." ([DATA] `map_nebula_loc`).
- **Beacon links** are visible, and the "Show beacon paths on hover" option adds more ([DATA] `show_paths`). Links come from map generation ([WIKI Sectors](https://ftl.fandom.com/wiki/Sectors#Technical_details_of_sector_generation_and_events)).
- **Store and distress markers** appear only for beacons **within 1 jump**, then stay on the map ([WIKI Beacons](https://ftl.fandom.com/wiki/Beacons)). Hover text: "Unvisited. Reported merchant location.", "You previously found a store at this location.", "Distress beacon. Someone might need help." ([DATA]).
- **Visited beacons:** "Explored location. Nothing left of interest." or "A hostile enemy was left behind at this location." ([DATA] `map_nothing_loc`, `map_hostile_loc`).
- **Rebel fleet:** a red shaded area. The beacons it will take next jump have a warning outline with "The Rebels are about to gain control of this beacon!". Captured beacons show "The Rebels have control of this location. Very dangerous." ([WIKI Rebel Fleet](https://ftl.fandom.com/wiki/Rebel_Fleet), [DATA] `map_rebels_loc`, `map_fleet_loc`). The exact advance rate per jump (halved in a nebula, doubled by escaping scouts, delayed by mercenaries or buoys) is **not displayed** and can only be inferred from how the map changes.
- **Long-Ranged Scanners** reveal, for **adjacent** beacons only ([WIKI Augmentations](https://ftl.fandom.com/wiki/Augmentations#Long-Ranged_Scanners)):
  - **Environmental hazards** ([DATA] "Asteroid field detected…", "…very close to a nearby sun.", "…experiencing an ion storm.", "A pulsar is flooding this area…", "The fleet's anti-ship batteries will be firing on you at this location.").
  - **"Unvisited. Possible ship detected."** ([DATA] `map_ship_loc`).

  Limits:
  - It works retroactively on beacons you have already been next to, and everything it revealed disappears if the augment is sold.
  - "Possible ship" is unreliable in both directions.
  - Hazards created by an event's choices are not shown.
- **Map reveal:** some events contain `<reveal_map>` (16 occurrences in the vanilla `events*.xml`) [DATA]. It reveals the same kind of beacon information across the map ([WIKI Environmental Hazards](https://ftl.fandom.com/wiki/Environmental_Hazards) caption: "revealed by the Long-Ranged Scanners augmentation or beacon map reveal reward").
- **Sector map** (opened at the exit):
  - Each sector's type group is shown by colour: Civilian green, Hostile red, Nebula purple. The legend strings are `sector_legend_*`.
  - Sector names show as **"Unidentified Civilian / Hostile / Nebula Sector"** or "Unidentified Sector" ([DATA] `sector_civilian`, `sector_hostile`, `sector_nebula`, `sector_unknown`).
  - Hidden Crystal Worlds are "never shown on the map" ([WIKI Sectors](https://ftl.fandom.com/wiki/Sectors)).
- **Hidden on the map:** the event at an unvisited beacon, apart from the marker types above. Sector generation (event lists, counts, RNG) is also hidden.

## 5. Events

- **Shown:** the event text, the list of choices, and **blue options** whose requirement the ship meets ([WIKI Blue Options](https://ftl.fandom.com/wiki/Blue_Options): "can be selected only if your ship has the required equipment, crew, or system upgrades"). Blue options can require augments, crew races, systems at a given level (e.g. "(Advanced Sensors)"), weapons or drones ([DATA] `text_events.xml`, e.g. `event_LANIUS_FUELING_STATION_LIST_3_c3_choice`).
- **Shown after choosing:** the outcome text and the resulting resource/crew/item changes, which then appear in the HUD and inventory.
- **Resource preview on choices:**
  - In vanilla data, 721 choices have `hidden="true"`; about 288 have `hidden="false"` or no attribute ([DATA] `events*.xml`, `dlcEvents*.xml`).
  - A non-hidden choice shows its guaranteed resource change in brackets after the choice text, e.g. `REFUEL_STATION`: fuel +6 / scrap −12.
  - The bracket behaviour is documented only in a modder's post on the Subset forum ([search result, forum viewtopic p=24887](https://subsetgames.com/forum/viewtopic.php?p=24887); I could not fetch the page, which returned 403). **(unverified)**
- **Never shown before choosing:**
  - Which random branch an `<eventList>` will pick, and its probabilities.
  - The size of an `autoReward`; tiers like LOW/MED/HIGH are rolled at random.
  - Whether a ship will later `<surrender>` or `<escape>`, and what is offered.
  - Whether a fight follows.
  - Quest destinations, until they are spawned.
- **Unmet requirements:** whether vanilla hides a blue option you don't qualify for or shows it greyed out, and how a choice you can't afford is shown, is not documented on the pages I read. See Open questions.

## 6. Stores

[WIKI Stores and resources](https://ftl.fandom.com/wiki/Stores_and_resources) and [DATA] `store_*`:

- **Shown:**
  - Every item for sale, by category: weapons, drones, augmentations, crew (race shown), systems, items such as fuel, missiles and drone parts, and hull repair. AE stores can have **2 pages**.
  - Every **price**.
  - Your current hull, with "FIX 1" and "FIX ALL" costs.
  - Resource stock.
  - The sell tab, with the sell value of your own equipment.
- **Hidden:**
  - Item **rarity** ("Rarity is a hidden attribute").
  - The store-generation rules.
  - Contents of stores not yet visited.
- A store's stock, once seen, stays fixed for return visits; "You previously found a store at this location." ([DATA] `map_store_loc`).

## 7. Ship grid layout

- **Own ship:**
  - Hull, rooms, room sizes, doors and airlocks (doors on the outer hull) are always drawn. Rooms that are dark without Sensors still show their outlines and doors ([WIKI Boarding](https://ftl.fandom.com/wiki/Boarding#Boarding_support)).
  - Adjacency shows on screen, and Slug vision depends on it ([WIKI Slugs](https://ftl.fandom.com/wiki/Slugs)).
- **Enemy ship:**
  - The layout is drawn as soon as the ship appears, and you can target rooms with no sensors at all ([WIKI Hacking](https://ftl.fandom.com/wiki/Hacking#Choosing_your_hacking_target)).
  - Doors and the Doors system level are visible even in a nebula (Boarding page).
- The vanilla layout files (`data/<ship>.txt` and `.xml`) describe exactly what is drawn. Exporting room and door geometry is therefore fair game, but only for the ship that is currently on screen.

## 8. Timing information

| Datum | Visible? |
|---|---|
| Own weapon, drone, cloak, hacking, MC and teleporter cooldowns | Yes (bars/meters) |
| Enemy weapon charge | Sensors ≥3, or hacked Weapons room ([WIKI Hacking](https://ftl.fandom.com/wiki/Hacking): "max-level Sensors information on the system") |
| Enemy system ion/cooldown | Sensors 4 or hacked room |
| Enemy cloak active | Yes (visual) |
| Enemy cloak time left | Conflicting sources; see Open questions |
| Active hack / MC remaining | Not shown even with L4 ([WIKI Sensors](https://ftl.fandom.com/wiki/Sensors)) |
| Enemy FTL escape | Warning text only |
| Solar flare / pulsar / ASB | Warning shortly before firing only. Flare: 28–34 s cycle, 5 s warning; pulsar: 11–18 s cycle, 5 s warning ([WIKI Environmental Hazards](https://ftl.fandom.com/wiki/Environmental_Hazards)). The cycle lengths are wiki knowledge, not on screen. |
| Projectiles in flight | Yes (visual); hit/miss is rolled by the engine and not displayed beforehand |

## 9. Harness metadata

Not game information, so not subject to the visibility rules: whether a Run is in progress, whether the game is paused (a human always knows this) and why, and the bridge's own clocks (`frame`, `game_time`). These describe the Agent's session, not the game world. `game_time` is the bridge's count of unpaused seconds, not a value FTL shows.

## Hidden: must NOT appear in the Observation

1. Enemy room interiors (crew, fires inside the room, breaches, O2) without a valid vision source (§1.2). This includes every enemy room while the enemy is cloaked, except rooms holding your own crew, boarding drone or mind-controlled enemy.
2. Enemy weapon charge below effective Sensors 3, unless Weapons is hacked.
3. Enemy system power use, levels, ion timers, repair/sabotage progress below effective Sensors 4, unless that system is hacked.
4. Enemy evasion % unless Piloting/Engines is hacked; enemy O2 % unless Oxygen is hacked.
5. Remaining duration of enemy cloak, hack or mind control; Clone Bay queue and progress.
6. Enemy crew drones from Slug or Lifeform Scanner detection alone.
7. Enemy drone loadout before deployment; enemy cargo/inventory, AI targeting choices and AI intent.
8. Enemy FTL charge progress (beyond the three warning states).
9. Own-ship room interiors (intruders, O2 per room, breaches) in rooms with no own crew and not next to a Slug while Sensors is below level 1 or not working.
10. Event results before choosing: random branches, probabilities, reward tier and amount, surrender/escape triggers, follow-up fights. Also any resource preview on `hidden="true"` choices.
11. Blue options the ship does not qualify for (pending the open question).
12. Unvisited beacon contents. Without Long-Ranged Scanners or a map reveal, this includes hazards and ship presence; even with LRS, only adjacent beacons are revealed. Store and distress markers more than 1 jump away (until seen). Event identity at any beacon.
13. Rebel fleet internals: advance amount per jump, timer and modifiers.
14. Identity of sectors not yet known (show only the type colour group); the Hidden Crystal Worlds sector.
15. Store contents of unvisited stores; item rarity; loot tables.
16. RNG state, seed-derived future information, hit/miss rolls, fire spread timers, hazard cycle timers.
17. Exact seconds behind any bar (weapon charge, FTL, cooldowns) unless the ADR decides a fraction is an acceptable reading of the bar.

## Open questions

Each of these needs checking in-game on vanilla 1.6.13.

1. **Enemy cloak time left at Sensors 4:** [WIKI Boarding](https://ftl.fandom.com/wiki/Boarding#Boarding_support) says yes, [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors) says no. These contradict each other.
2. **Partial Sensors damage:** does a level 3 system with 1 damage act as level 2? Do ionised Sensors lose levels the same way damage does?
3. **Enemy system icons with no sensors:** are damage, destruction and ion state shown by icon colour? Are the fire and sabotage icons shown above enemy systems?
4. **Enemy hull:** a bar only, or is a number shown? The same question applies to the **player's** hull.
5. **Enemy weapons below Sensors 3:** are names or tooltips shown on hover? Does the sprite's charge animation give away charge state? This decides whether "weapon list" goes in the always-visible tier.
6. **Enemy FTL charge:** is there a visible bar, or only the warning texts?
7. **Blue options and costs:** are blue options you don't qualify for hidden or greyed out in vanilla? Are choices you can't afford (e.g. not enough scrap for `REFUEL_STATION`) hidden, greyed, or selectable?
8. **Choice resource previews:** confirm the bracketed "[Fuel +6, Scrap −12]"-style suffix appears on non-`hidden` choices, and its exact format.
9. **Sector map names:** are the adjacent next-sector choices named (e.g. "Engi Controlled Sector"), or always shown as "Unidentified … Sector" until entered? The strings exist, but when they are used is unknown.
10. **Bomb-hit vision:** how long does the room stay visible after a bomb hits it?
11. **Hacked Oxygen readout:** confirm "Current Oxygen: X" appears in the target window. It is inferred from the strings only.
12. **Enemy crew skills:** confirm they never appear. Do HP bars appear on crew detected only through Slug or Scanner?
13. **Store/distress markers seen earlier:** confirm they stay on the map after you move away (the wiki implies they do).
14. **Exact bars vs numbers:** the ADR must decide whether the Observation reports bar values as fractions, which seems fair since a human can read a bar to about the same precision, or as coarse buckets.

## Answers (ticket #14)

Covers the [Open questions](#open-questions) above (numbered **Q1–Q14**) and the extra checklist items in the comments on issue #14 (**I1–I9**). Sources follow the same trust rules as the rest of this note. **[HS]** means the Hyperspace source in `FTL-Hyperspace/` (read-only). It is only cited where it shows vanilla behaviour: reconstructed vanilla logic, or a feature Hyperspace adds because vanilla lacks it. Paths are relative to `FTL-Hyperspace/`. DATA paths are relative to the unpacked `ftl.dat.vanilla`.

Totals: **9 settled**, **14 need an in-game check**, and 1 (Q14) is a design decision for the ADR rather than a visibility fact.

### Settled

| # | Question | Answer | Citation |
|---|---|---|---|
| Q2, I1 | Partial Sensors damage; ionised Sensors; do own rooms go dark when Sensors are damaged or ionised? | **Yes, both cost levels.** Each point of damage lowers the system's max power by 1. Each ion point removes 1 power. Subsystems cannot be ion-proofed. A damaged or ionised system **cannot be manned**, so it also loses the +1 manning bonus. A level 3 Sensors with 1 damage therefore gives level 2, not 3. Vision checks effective power: own rooms need power > 0, enemy interior needs > 1. A hack on Sensors (`iHackEffect > 1`) also blinds. So own rooms go dark when L1 Sensors take 1 damage or 1 ion. | [WIKI Systems](https://ftl.fandom.com/wiki/Systems) (manning rule: "Ionized, damaged, hacked … systems cannot be manned"; damage: "maximum power … lowered by 2"; ion: "ion damage of 1 removes 1 power"); [HS] `src/game/Ship/CustomShips.cpp:368-384` (reconstructed vanilla `ShipManager::CheckVision`: `GetEffectivePower() > 0` for own ship, `> 1` for enemy, `!(iHackEffect > 1)`) |
| Q4 | Hull: bar or number (enemy and player)? | **Bar only in vanilla, for both ships.** Hyperspace adds a `<hullNumbers>` feature that draws the hull point count for the player, the enemy and the boss. It exists because vanilla shows no number. If the bench's modded `ftl.dat` turns this on, a human playing that build *does* see numbers. The ADR should pick vanilla. | [HS] `Mod Files/data/hyperspace.xml:177-196` ("Hull bar indicator: Displays the amount of hull points left"), `src/game/UserInterface/HullNumbers.cpp:237` (hooks `CombatControl::RenderTarget`) |
| Q7a | Choices you can't afford (e.g. not enough scrap): hidden, greyed or selectable? | **Shown greyed out and not selectable.** Vanilla `WorldManager::CheckRequirements` rejects a choice whose resource cost exceeds what you hold. Vanilla has a dedicated "disabled" grey choice colour (RGB 150,150,150), alongside white (normal), yellow (hover) and cyan (blue option). This has also been seen live: an unaffordable toll whose key press does nothing. | [HS] `src/game/Gameplay/World/CustomEvents.cpp:6675-6700` (comment: vanilla bug where the resource check runs before the previous event's cost); `src/game/UserInterface/CustomColors.cpp:328-337, 423-426`; `Mod Files/data/hyperspace.xml:3232` ("replace the vanilla gray color when the choice is disabled") and `:2515` ("…or the choice will be greyed out"); `llm-bridge/data/ftlbench/bridge.lua:332-334` (live observation) |
| Q8a, I5 | Do `hidden="true"` choices show a resource preview, and does `ChoiceText.rewards` matter? | **No preview on `hidden="true"` choices.** Non-hidden choices with a guaranteed `item_modify` show the trade before you choose. The engine stores the attribute per choice as `LocationEvent::Choice::hiddenReward`, which Lua exposes. Whatever ends up in `ChoiceText.rewards`, the bridge should gate hints on `event.choices[i].hiddenReward`, not on whether rewards are filled. | [WIKI Merchant's request](https://ftl.fandom.com/wiki/Merchant%27s_request) ("the actual trade offer is shown before you make the choice" on c1; "*not* shown" on c4) against DATA `data/events.xml` event `MERCHANT_DELIVER_LIST_2` (c1 has no `hidden`, c4 is `hidden="true"`); [HS] `libzhlgen/test/functions/mac/FTLGameStripped.h:4140-4146`, `lua/modules/hyperspace.i:955` |
| Q12a | Enemy crew skills | **Moot: enemy crew are always untrained** (skill level 0) and can never level up. No skill information exists to show, so the Observation omits enemy skills. | [WIKI Crew skills](https://ftl.fandom.com/wiki/Crew_skills) ("the enemy ships crew is always untrained and cannot reach higher skill levels") |
| Q13 | Do store/distress markers stay after you move away? | **Yes.** Distress beacons "remain on the map till they get overtaken by rebels". Marker visibility is keyed on the per-beacon `Location.known` flag. The flag is set when you are adjacent, never cleared, and written to the save file. The same flag gates Long-Ranged Scanners info, which is why that info is retroactive. The bridge can read `loc.known` (exposed in Lua) instead of tracking adjacency itself. | [WIKI Beacons](https://ftl.fandom.com/wiki/Beacons); DATA `text_misc.xml` `map_merchant_loc` "Unvisited. Reported merchant location."; [HS] `src/game/Gameplay/World/StarMap.cpp:173` (`known` loaded from save), `CustomMap.cpp:137`, `CustomEvents.cpp:3478, 5100` (labels/LRS gated on `known`), `lua/modules/hyperspace.i:1549` |
| I6 | Sector types; can the hidden Crystal sector be a choice? | **`Sector.type`: 0 = Civilian, 1 = Hostile, 2 = Nebula** (4 = Unknown, used only for `STANDARD_SPACE`). **The Crystal sector is never a sector-map choice.** `CRYSTAL_HOME` is in none of the `sectorType` lists. It is reached only through the `<secretSector/>` event reward (Ancient device), and you cannot choose where to go when you leave it. | [HS] `src/game/Gameplay/World/CustomSectors.cpp:131-147, 285-300`; DATA `data/sector_data.xml` `sectorType` CIVILIAN/HOSTILE/NEBULA/UNKNOWN (no `CRYSTAL_HOME`), `data/events.xml` `<secretSector/>`; [WIKI Sectors](https://ftl.fandom.com/wiki/Sectors) ("never shown on the map"), [WIKI Ancient device](https://ftl.fandom.com/wiki/Ancient_device) |
| I8 | Which list holds crew while boarding? | **The `vCrewList` of the ship the crew member is physically on.** Boarders appear there with `intruder = true` and `iShipId` = their owner. The player's boarders are found in `enemyShip.shipManager.vCrewList` with `iShipId == 0`. Enemy intruders are in the player's list with `intruder` set. | [HS] `src/game/Gameplay/World/CustomEvents.cpp:4139-4142`, `src/game/Ship/Augments.cpp:9-11`, `src/game/Ship/ShipSystems/TemporalSystem.cpp:698-704` |
| I9b | Crew tooltips through an enemy cloak | **Shown with working Sensors 2+.** While cloaked, hovering enemy room tiles still gives crew location and HP, even while paused. Interior vision is lost otherwise. | [WIKI Cloaking](https://ftl.fandom.com/wiki/Cloaking), [WIKI Sensors](https://ftl.fandom.com/wiki/Sensors) |

Also from the patch notes ([WIKI Game patches](https://ftl.fandom.com/wiki/Game_patches), AE 1.5): "Sensors at level 3 show the player the cooldowns of enemy weapons, while sensors at level 4 show the power bars." This agrees with §1.1.

### Needs an in-game check

| # | Question | What is known | In-game checklist item |
|---|---|---|---|
| Q1 | Enemy cloak time left at Sensors 4 | The wiki contradicts itself ([Boarding](https://ftl.fandom.com/wiki/Boarding) says yes, [Sensors](https://ftl.fandom.com/wiki/Sensors) says no) | With L3 Sensors manned (L4), fight a cloaking enemy: does the enemy Cloaking room icon show a draining duration/cooldown circle while it is cloaked? |
| Q3 | Enemy system icons with no Sensors | Fire/sabotage icons are documented for "the ship's" GUI only | With Sensors unpowered or destroyed, damage, ionise and set fire to an enemy system: does its room icon change colour (damaged/destroyed/ion lock), and do fire/sabotage icons appear above it? |
| Q5 | Enemy weapons below Sensors 3 | Charge bars need L3 (DATA `sensor_3`) | With Sensors below 3, hover an enemy weapon sprite (is a name/tooltip shown?) and watch it from jump-in to first shot (does the sprite visibly animate as it charges?) |
| Q6 | Enemy FTL charge | Only the `warning_ftl_*` texts are known | When an enemy starts escaping, is anything besides the "ENEMY FTL CHARGING / DELAYED / JUMP IMMINENT" text shown (a bar or timer in the target window)? |
| Q7b, I4 | Unmet blue options: hidden or greyed? Which `ChoiceText.type` is which? | Unaffordable choices are greyed (Q7a). The repo disagrees with itself on numbering: `bridge.lua:332` says 1 = not met, 2 = blue (inferred); `tests/lua/test_visibility.lua:593` and the issue say 1 = blue, 2 = not met | At an event with a blue option you *lack* (e.g. Merchant's Delivery without Mind Control) and one you *have*, note whether the unmet one is hidden or shown grey, and log `choiceBox.choices[i].type` for a normal, a blue and an unaffordable choice |
| Q8b | Exact preview format | Preview existence is settled (Q8a) | Screenshot a non-hidden choice with a guaranteed reward/cost (e.g. Merchant's Delivery "Accept the paltry payment.") and copy the exact suffix format |
| Q9 | Next-sector names on the sector map | DATA `sector_civilian` … `sector_unknown` are labelled "Names for unidentified sectors" | At an exit beacon, open the sector map and hover each reachable next sector: real name (e.g. "Engi Controlled Sector") or "Unidentified … Sector"? |
| Q10 | Bomb-hit vision duration | [WIKI Mind Control](https://ftl.fandom.com/wiki/Mind_Control) confirms a bomb hit grants vision; the engine uses a per-room `tempVision` flag ([HS] `CustomShips.cpp:390`) | With enemy Sensors vision off, land a Small Bomb in an enemy room and time how long that room stays revealed |
| Q11 | Hacked-Oxygen readout | DATA `oxygen_hacked`/`current_oxygen` sit in the `<!-- Combat box -->` block next to the wiki-confirmed `current_evasion` | Hack enemy Oxygen with Hacking powered: does the target window show "Oxygen Hacked" / "Current Oxygen: X"? |
| Q12b, I9-HP | HP bars on crew detected only by Slug/Lifeform Scanner | Detection itself is documented | With Sensors off (or in a nebula) and a Slug/Lifeform Scanner, look at detected enemy crew: are HP bars drawn above them, and does hovering give name/HP? |
| I2 | Subsystems read 0 power on a loaded save until the game runs | Bridge artefact, not a game rule | Load a mid-fight save paused, read Sensors/Doors/Piloting power from the bridge, unpause one second, read again: does power go from 0 to the real value? |
| I3 | Shields with odd power while damaged | Layers = floor(power ÷ 2) ([WIKI Shields](https://ftl.fandom.com/wiki/Shields) upgrade table); you cannot add the last bar at an odd level (DATA `warning_needs_upgrade` comment) | Damage a fully powered Shields-4 by 1: does it keep 3 bars powered or drop to 2, and does the HUD show 1 layer? |
| I7 | `jump sector:N` end to end | Not a visibility question | At an exit beacon, send `jump sector:N` for each listed choice and confirm the game arrives in that sector (type matches `Sector.type`) |
| I9a | Door states through an enemy cloak | Doors stay visible in a nebula ([WIKI Boarding](https://ftl.fandom.com/wiki/Boarding#Boarding_support)); cloaking is not mentioned | While the enemy is cloaked and none of your crew are aboard, are its doors' open/closed states still drawn? |

### Not a visibility fact

- **Q14 (bars as fractions or buckets):** this is a policy choice for [ADR 0003](../adr/0003-observation-is-visible-state-only.md), and no source can settle it. The facts the ADR needs are already settled: bars show no seconds (§3), and vanilla hull is a bar (Q4).
