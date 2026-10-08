Config = {}

-- Prints debug info (server + client) and draws hostage state above peds.
Config.Debug = false

-- 'ox_lib' | 'qbx' | 'custom'  (custom uses Config.CustomNotify on the client)
Config.Notify = 'ox_lib'
Config.CustomNotify = function(message, notifyType, duration)
    -- exports['your_notify']:Show(message, notifyType, duration)
end

---------------------------------------------------------------------------
-- POLICE
---------------------------------------------------------------------------
Config.Police = {
    jobType = 'leo',                    -- qbx job type counted as police
    jobs = { police = true, sheriff = true, bcso = true, sasp = true, lspd = true }, -- fallback job names
    minOnDuty = 0,                      -- cops required on duty to take a hostage
    blockPoliceFromTaking = true,       -- on-duty police cannot take hostages
    rescue = {
        enabled = true,                 -- police can "Secure Civilian" on an unheld hostage
        distance = 2.5,
        ownerMinDistance = 8.0,         -- captor must be at least this far from the hostage
    },
}

---------------------------------------------------------------------------
-- TAKING A HOSTAGE
---------------------------------------------------------------------------
Config.Take = {
    useTarget = true,                   -- ox_target "Take Hostage" option on NPCs
    targetDistance = 2.5,
    useKeybind = true,                  -- aim at an NPC and press the take key
    aimDistance = 10.0,
    requireAimingForKeybind = true,
    requireLineOfSight = true,          -- client-side LOS check (no taking through walls)

    cooldown = 20,                      -- seconds between take attempts per player
    pedCooldown = 180,                  -- seconds before a released/escaped NPC can be taken again
    maxHostages = 3,                    -- active hostages per player
    maxHeld = 1,                        -- physically held (gun to head) at once

    -- GTA population types allowed: 4 = scenario peds, 5 = ambient peds, 1/6 = permanent
    allowedPopulationTypes = { [1] = true, [4] = true, [5] = true },
    blockMissionPeds = true,            -- script-spawned peds (type 7) unless they have the allow statebag
    blockPedsInVehicles = true,         -- can't take a driver/passenger as hostage

    -- Models that can never be taken (cops, special NPCs, etc.)
    blockedModels = {
        's_m_y_cop_01', 's_f_y_cop_01', 's_m_y_sheriff_01', 's_f_y_sheriff_01',
        's_m_y_hwaycop_01', 's_m_y_swat_01', 's_m_m_snowcop_01', 's_m_y_ranger_01',
        's_m_m_fiboffice_01', 's_m_y_marine_01', 's_m_y_marine_03',
    },
}

---------------------------------------------------------------------------
-- WEAPONS
---------------------------------------------------------------------------
Config.Weapons = {
    requireWeapon = true,
    requireLoaded = true,
    useOxInventory = true,              -- server verifies loaded ammo via ox_inventory:GetCurrentWeapon

    -- Weapon groups that count as a firearm (client side)
    allowedGroups = { 'GROUP_PISTOL', 'GROUP_SMG', 'GROUP_RIFLE', 'GROUP_SHOTGUN', 'GROUP_MG', 'GROUP_SNIPER' },
    -- Groups allowed to physically hold a hostage (gun-to-head anim is built for one-handed weapons)
    holdGroups = { 'GROUP_PISTOL', 'GROUP_SMG' },

    allowed = {},                       -- if not empty, ONLY these weapons can take hostages
    blocked = { 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FLAREGUN', 'WEAPON_RAYPISTOL', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN' },
}

---------------------------------------------------------------------------
-- NPC REACTIONS
---------------------------------------------------------------------------
Config.Reactions = {
    -- Base weights. Courage (0-100) shifts weight from surrender/cry toward run/refuse.
    weights = {
        surrender = 55,
        panic     = 14,
        cry       = 10,
        scream    = 6,
        refuse    = 8,
        run       = 7,
    },
    screamAlertChance = 60,             -- % chance a screaming NPC alerts police
    runAlertChance = 50,                -- % chance an NPC that runs away calls police
    threatenCooldown = 4,               -- seconds between threats on one hostage
    threatenCourageDrop = 25,           -- courage lost each time a refusing NPC is threatened

    default = { label = 'Civilian', courage = { 5, 55 } },

    -- First matching profile wins
    profiles = {
        { label = 'Security Guard', courage = { 60, 95 }, models = { 's_m_m_security_01', 's_m_m_armoured_01', 's_m_m_armoured_02', 's_m_y_doorman_01', 's_m_m_bouncer_01' } },
        { label = 'Gang Member', courage = { 50, 90 }, models = { 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_m_y_famca_01', 'g_m_y_famdnf_01', 'g_m_y_mexgoon_01', 'g_m_y_lost_01', 'g_m_y_salvagoon_01' } },
        { label = 'Shop Clerk', courage = { 10, 40 }, models = { 'mp_m_shopkeep_01', 's_m_m_ammucountry', 's_m_y_ammucity_01' } },
        { label = 'Elderly Civilian', courage = { 0, 25 }, models = { 'a_m_o_genstreet_01', 'a_f_o_genstreet_01', 'a_m_o_soucent_01', 'a_f_o_soucent_01', 'a_m_o_tramp_01' } },
    },
}

---------------------------------------------------------------------------
-- HOLDING (gun to head)
---------------------------------------------------------------------------
Config.Hold = {
    bone = 0,
    offset = vec3(-0.24, 0.11, 0.0),
    rotation = vec3(0.5, -0.2, 0.0),
    walkOnly = true,
    moveBlendRatio = 1.0,               -- 1.0 walk, 2.0 jog
    allowAiming = true,                 -- right-click aims over the hostage (human shield)
    allowShooting = true,               -- fire while aiming (only while aiming, never from the hip)
    allowReload = true,                 -- R / auto-reload pauses the hold anim so the reload plays
    reloadPause = 2500,                 -- ms the hold anim stays paused for a reload
    -- always disabled while holding: melee, sprint, jump, enter vehicle, cover, weapon wheel
    disabledControls = { 140, 141, 142, 143, 263, 264, 21, 22, 23, 44, 37 },
}

Config.Follow = { distance = 1.6, speed = 1.0 }

---------------------------------------------------------------------------
-- ACTIONS
---------------------------------------------------------------------------
Config.Actions = {
    defaultDistance = 12.0,             -- server-checked distance captor <-> hostage
    distance = {
        grab = 2.5,
        kneel = 12.0,
        threaten = 15.0,
        release = 30.0,
        execute = 12.0,
        vehicle_in = 8.0,
        moveto = 15.0,
    },
    moveToMaxDistance = 25.0,           -- how far "Move To" points can be from the captor
}

Config.Execute = {
    enabled = true,
    confirm = true,                     -- confirmation dialog
}

---------------------------------------------------------------------------
-- VEHICLES
---------------------------------------------------------------------------
Config.Vehicle = {
    enabled = true,
    searchDistance = 5.0,
    seatOrder = { 1, 2, 0 },            -- rear left, rear right, front passenger
    enterTimeout = 8000,
}

---------------------------------------------------------------------------
-- ESCAPE SYSTEM (server-authoritative)
---------------------------------------------------------------------------
Config.Escape = {
    enabled = true,
    interval = 5,                       -- seconds between escape rolls
    baseChance = 1,                     -- % per roll with no factors
    maxChance = 75,
    panicBonus = 4,                     -- panicked/screaming NPCs are jumpier
    threatenProtection = 30,            -- seconds after a threat where chance is reduced
    threatenMultiplier = 0.4,
    stateMultiplier = { HELD = 0.25, KNEELING = 0.6, VEHICLE = 0.5, COMPLIANT = 1.0, THREATENED = 1.4 },
    factors = {
        distance      = { enabled = true, distance = 15.0, chance = 12 },  -- captor wandered off
        unattended    = { enabled = true, distance = 35.0, chance = 35 },  -- left alone
        noWeapon      = { enabled = true, chance = 12 },                   -- weapon holstered
        notAiming     = { enabled = true, after = 25, chance = 6 },        -- seconds since last aim/hold
        ownerVehicle  = { enabled = true, chance = 20 },                   -- captor in a car, hostage not
        police        = { enabled = true, radius = 25.0, chance = 8, max = 30 }, -- per cop nearby
    },
    escapeAlertChance = 40,
}

---------------------------------------------------------------------------
-- CLEANUP
---------------------------------------------------------------------------
Config.Cleanup = {
    onDisconnect = 'escape',            -- 'escape' | 'release'
    onOwnerDown = 'escape',             -- 'escape' | 'release' | 'none' (none = escape factors only)
    onLogout = 'release',
    linger = 60,                        -- seconds a finished hostage keeps its final state for other scripts
    pedDespawnDelay = 20,               -- seconds after release before the NPC is handed back to the game
}

---------------------------------------------------------------------------
-- DISPATCH
---------------------------------------------------------------------------
Config.Dispatch = {
    enabled = true,
    -- If the chosen system's export is missing (e.g. older lb-tablet without AddDispatch),
    -- the script logs it ONCE and permanently falls back to the next available system.
    -- 'auto' | 'lb-tablet' | 'ps-dispatch' | 'cd_dispatch' | 'builtin' | 'custom' | 'none'
    system = 'auto',
    jobs = { 'police' },
    alerts = {
        hostage = { enabled = true, chance = 65, cooldown = 90, code = '10-31H', title = 'Possible Hostage Situation', priority = 'high', blip = { sprite = 458, color = 1, scale = 1.1, time = 120 } },
        armed   = { enabled = true, chance = 40, cooldown = 120, code = '10-32', title = 'Armed Individual Holding Civilian', priority = 'high', blip = { sprite = 110, color = 1, scale = 1.0, time = 90 } },
        shots   = { enabled = true, chance = 100, cooldown = 45, code = '10-71', title = 'Shots Fired During Hostage Situation', priority = 'high', blip = { sprite = 110, color = 1, scale = 1.2, time = 90 } },
        escaped = { enabled = true, chance = 100, cooldown = 60, code = '10-31E', title = 'Hostage Escaped Captor', priority = 'medium', blip = { sprite = 280, color = 5, scale = 1.0, time = 90 } },
    },
    -- Used when system = 'custom'. Runs server-side.
    custom = function(alert, data)
        -- data: coords, street, description, weapon, vehicle, plate, suspect (source)
        -- exports['my_dispatch']:Send(...)
    end,
}

---------------------------------------------------------------------------
-- NEGOTIATION
---------------------------------------------------------------------------
Config.Negotiation = {
    enabled = true,
    minHostages = 1,
    policeCommand = 'negotiations',
    allowCustom = true,
    maxCustomLength = 120,
    maxCounterLength = 160,
    autoCloseMinutes = 45,
    demands = {
        { key = 'safe_passage', label = 'Safe passage', icon = 'road' },
        { key = 'no_spikes',    label = 'No spike strips', icon = 'ban' },
        { key = 'no_pursuit',   label = 'No immediate pursuit', icon = 'car-side' },
        { key = 'vehicle',      label = 'Vehicle access', icon = 'car' },
        { key = 'more_time',    label = 'Additional time', icon = 'clock' },
        { key = 'no_air',       label = 'No air support', icon = 'helicopter' },
    },
}

---------------------------------------------------------------------------
-- KEYBINDS (players can rebind in GTA settings > FiveM)
---------------------------------------------------------------------------
Config.Keybinds = {
    take = 'G',                         -- while aiming at an NPC
    menu = 'K',                         -- hostage command menu
    holdLetGo = 'E',
    holdPush = 'X',
    holdExecute = 'H',
}
Config.MenuCommand = 'hostages'

---------------------------------------------------------------------------
-- SECURITY
---------------------------------------------------------------------------
Config.Security = {
    distanceTolerance = 2.0,            -- extra meters allowed for desync
    takeRateMs = 1000,
    actionRateMs = 350,
    requireEntityOwnership = true,      -- taker must own the NPC network-wise when taking it
}

---------------------------------------------------------------------------
-- ANIMATIONS  { dict, name, flag, blendIn, blendOut, duration, wait }
---------------------------------------------------------------------------
Config.Animations = {
    perpHold      = { dict = 'anim@gangops@hostage@', name = 'perp_idle', flag = 49, blendIn = 8.0, blendOut = -8.0 },
    victimHeld    = { dict = 'anim@gangops@hostage@', name = 'victim_idle', flag = 49, blendIn = 8.0, blendOut = -8.0 },
    perpExecute   = { dict = 'anim@gangops@hostage@', name = 'perp_fail', flag = 48, blendIn = 8.0, blendOut = -8.0, duration = 1200 },
    victimExecute = { dict = 'anim@gangops@hostage@', name = 'victim_fail', flag = 0, blendIn = 8.0, blendOut = -8.0, wait = 600 },
    perpPush      = { dict = 'reaction@shove', name = 'shove_var_a', flag = 48, duration = 1000 },
    victimShoved  = { dict = 'reaction@shove', name = 'shoved_back', flag = 0, wait = 1000 },
    victimEscape  = { dict = 'reaction@shove', name = 'shove_var_a', flag = 120, wait = 800 },
    perpShoved    = { dict = 'reaction@shove', name = 'shoved_back', flag = 0, duration = 1200 },
    handsUp       = { dict = 'missminuteman_1ig_2', name = 'handsup_base', flag = 49 },
    stay          = { dict = 'missminuteman_1ig_2', name = 'handsup_base', flag = 1 },
    refuse        = { dict = 'mp_player_int_upperfinger', name = 'mp_player_int_finger_01_enter', flag = 49 },
    kneelEnter    = { dict = 'random@arrests', name = 'kneeling_arrest_idle', flag = 0, wait = 1200 },
    kneel         = { dict = 'random@arrests@busted', name = 'idle_a', flag = 1 },
    cower         = { dict = 'amb@code_human_cower@male@base', name = 'base', flag = 1 },
    cry           = { dict = 'amb@code_human_cower_stand@male@idle_a', name = 'idle_b', flag = 1 },
}
