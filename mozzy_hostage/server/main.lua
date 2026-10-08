---@class HostageRecord
---@field netId number
---@field entity number
---@field owner number
---@field state string
---@field mode string|nil
---@field prevState string|nil
---@field courage number
---@field profile string
---@field model number
---@field label string
---@field reaction string|nil
---@field panicked boolean
---@field vehicle number|nil
---@field seat number|nil
---@field coords vector3|nil
---@field seq number
---@field takenAt number
---@field updatedAt number
---@field lastThreat number
---@field reason string|nil

Hostages = {}        -- [netId] = HostageRecord (active + lingering terminal records)
PlayerHostages = {}  -- [src] = { [netId] = true } (active only)

local TakeCooldown = {}  -- [src] = expiry
local PedCooldown = {}   -- [netId] = expiry
local RateLimit = {}     -- [src] = { [key] = gameTimer }
local labelCounter = 0

local blockedModels = MH.HashSet(Config.Take.blockedModels)
local blockedWeapons = MH.HashSet(Config.Weapons.blocked)
local allowedWeapons = MH.HashSet(Config.Weapons.allowed)
local UNARMED = MH.Hash('WEAPON_UNARMED')

for _, profile in ipairs(Config.Reactions.profiles) do
    profile.lookup = MH.HashSet(profile.models)
end

function MH.Debug(...)
    if Config.Debug then print('^5[mozzy_hostage]^7', ...) end
end

function MH.Fail(code)
    return { ok = false, err = code }
end

function MH.RateLimited(src, key, ms)
    local t = GetGameTimer()
    RateLimit[src] = RateLimit[src] or {}
    local last = RateLimit[src][key]
    if last and t - last < ms then return true end
    RateLimit[src][key] = t
    return false
end

function MH.Chance(pct)
    return math.random() * 100 < (pct or 0)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function MH.ActiveCount(src, stateFilter)
    local n = 0
    for netId in pairs(PlayerHostages[src] or {}) do
        local r = Hostages[netId]
        if r and MH.Active[r.state] and (not stateFilter or stateFilter[r.state]) then n = n + 1 end
    end
    return n
end

function MH.CheckWeapon(src)
    if not Config.Weapons.requireWeapon then return true end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false, 'no_weapon' end
    local hash = MH.Hash(GetSelectedPedWeapon(ped))
    if hash == 0 or hash == UNARMED then return false, 'no_weapon' end
    if blockedWeapons[hash] then return false, 'blocked_weapon' end
    if next(allowedWeapons) and not allowedWeapons[hash] then return false, 'blocked_weapon' end

    if Config.Weapons.requireLoaded and Config.Weapons.useOxInventory and GetResourceState('ox_inventory') == 'started' then
        local weapon = exports.ox_inventory:GetCurrentWeapon(src)
        if not weapon then return false, 'no_weapon' end
        local ammo = weapon.metadata and weapon.metadata.ammo
        if not ammo or ammo <= 0 then return false, 'not_loaded' end
    end
    return true
end

function MH.PublicData(r)
    if not r then return nil end
    return {
        netId = r.netId,
        entity = r.entity,
        owner = r.owner,
        state = r.state,
        mode = r.mode,
        label = r.label,
        profile = r.profile,
        courage = r.courage,
        reaction = r.reaction,
        vehicle = r.vehicle,
        seat = r.seat,
        takenAt = r.takenAt,
        alive = r.state ~= 'DEAD',
        released = r.state == 'RELEASED',
        escaped = r.state == 'ESCAPED',
        reason = r.reason,
    }
end

local function pickProfile(model)
    for _, profile in ipairs(Config.Reactions.profiles) do
        if profile.lookup[model] then return profile end
    end
    return Config.Reactions.default
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
function MH.SyncOwner(src)
    if not src or not GetPlayerName(src) then return end
    local list = {}
    for netId in pairs(PlayerHostages[src] or {}) do
        local r = Hostages[netId]
        if r and MH.Active[r.state] then
            list[#list + 1] = { netId = netId, state = r.state, mode = r.mode, label = r.label, profile = r.profile, vehicle = r.vehicle }
        end
    end
    TriggerClientEvent('mozzy_hostage:client:sync', src, list)
end

local function pushState(r, event)
    r.seq = (r.seq or 0) + 1
    if DoesEntityExist(r.entity) then
        Entity(r.entity).state:set(MH.StateKey, {
            state = r.state,
            mode = r.mode,
            owner = r.owner,
            seq = r.seq,
            event = event,
            prev = r.prevState,
            vehicle = r.vehicle,
            seat = r.seat,
            coords = r.coords,
        }, true)
    end
end
MH.PushState = pushState

local function finalize(r)
    local owned = PlayerHostages[r.owner]
    if owned then
        owned[r.netId] = nil
        if not next(owned) then PlayerHostages[r.owner] = nil end
    end
    PedCooldown[r.netId] = os.time() + Config.Take.pedCooldown

    if DoesEntityExist(r.entity) then
        SetEntityOrphanMode(r.entity, 0)
    end

    local seq = r.seq
    SetTimeout(Config.Cleanup.linger * 1000, function()
        local cur = Hostages[r.netId]
        if cur == r and cur.seq == seq then
            Hostages[r.netId] = nil
            if DoesEntityExist(r.entity) then
                Entity(r.entity).state:set(MH.StateKey, nil, true)
            end
        end
    end)
end

---Central state setter. Every state change goes through here.
---@param netId number
---@param newState string
---@param opts? { force?: boolean, mode?: string|false, event?: string, reason?: string, vehicle?: number, seat?: number, coords?: vector3 }
function MH.SetState(netId, newState, opts)
    opts = opts or {}
    local r = Hostages[netId]
    if not r then return false, 'not_hostage' end
    if not MH.States[newState] or newState == 'FREE' then return false, 'invalid' end
    local old = r.state
    if MH.Terminal[old] then return false, 'bad_state' end
    if not opts.force and not MH.CanTransition(old, newState) then return false, 'bad_state' end

    r.prevState = old
    r.state = newState
    if opts.mode ~= nil then r.mode = opts.mode or nil end
    if newState == 'VEHICLE' then
        r.vehicle, r.seat = opts.vehicle, opts.seat
    else
        r.vehicle, r.seat = nil, nil
    end
    r.coords = opts.coords
    r.reason = opts.reason
    r.updatedAt = os.time()

    pushState(r, opts.event)

    local data = MH.PublicData(r)
    TriggerEvent('mozzy_hostage:server:stateChanged', data, old, opts.reason)
    TriggerClientEvent('mozzy_hostage:client:ownerEvent', r.owner, netId, {
        state = r.state, mode = r.mode, event = opts.event, prev = old, reason = opts.reason,
    })

    if MH.Terminal[newState] then
        finalize(r)
        if newState == 'DEAD' then TriggerEvent('mozzy_hostage:server:hostageKilled', r.owner, netId, data, opts.reason)
        elseif newState == 'ESCAPED' then TriggerEvent('mozzy_hostage:server:hostageEscaped', r.owner, netId, data, opts.reason)
        else TriggerEvent('mozzy_hostage:server:hostageReleased', r.owner, netId, data, opts.reason) end
    end

    MH.SyncOwner(r.owner)
    MH.Debug(('hostage %s: %s -> %s (%s) %s'):format(netId, old, newState, tostring(r.mode), tostring(opts.reason or opts.event)))
    return true
end

function MH.Escape(netId, reason)
    local r = Hostages[netId]
    if not r or not MH.Active[r.state] then return false end
    local event = r.state == 'HELD' and 'escape_hold' or 'escape'
    local ok = MH.SetState(netId, 'ESCAPED', { force = true, event = event, reason = reason or 'escaped' })
    if ok then
        Bridge.Notify(r.owner, Lang.escaped, 'error')
        if MH.Chance(Config.Escape.escapeAlertChance) then
            Bridge.Dispatch('escaped', r.owner, { coords = DoesEntityExist(r.entity) and GetEntityCoords(r.entity) or nil })
        end
    end
    return ok
end

function MH.Release(netId, reason, event)
    local r = Hostages[netId]
    if not r or not MH.Active[r.state] then return false end
    return MH.SetState(netId, 'RELEASED', { force = true, event = event or 'release', reason = reason or 'released' })
end

---------------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------------
local reactionOrder = { 'surrender', 'panic', 'cry', 'scream', 'refuse', 'run' }

function MH.RollReaction(r)
    local c = math.max(0, math.min(100, r.courage)) / 100
    local weights, total = {}, 0
    for _, key in ipairs(reactionOrder) do
        local w = Config.Reactions.weights[key] or 0
        if key == 'surrender' or key == 'cry' then w = w * (1.5 - c)
        elseif key == 'run' or key == 'refuse' then w = w * (0.5 + c) end
        w = math.max(0, w)
        weights[key] = w
        total = total + w
    end
    if total <= 0 then return 'surrender' end
    local roll = math.random() * total
    for _, key in ipairs(reactionOrder) do
        roll = roll - weights[key]
        if roll <= 0 then return key end
    end
    return 'surrender'
end

local reactionResult = {
    surrender = { 'COMPLIANT', 'handsup' },
    panic     = { 'COMPLIANT', 'cower' },
    cry       = { 'COMPLIANT', 'cry' },
    scream    = { 'COMPLIANT', 'cower' },
    refuse    = { 'THREATENED', 'refuse' },
}

function MH.ApplyReaction(src, r, reaction)
    r.reaction = reaction
    if reaction == 'panic' or reaction == 'scream' then r.panicked = true end

    if reaction == 'run' then
        MH.SetState(r.netId, 'ESCAPED', { force = true, event = 'run', reason = 'ran' })
        if MH.Chance(Config.Reactions.runAlertChance) then
            Bridge.Dispatch('hostage', src)
        end
        return
    end

    local result = reactionResult[reaction] or reactionResult.surrender
    MH.SetState(r.netId, result[1], { force = true, mode = result[2], event = 'react_' .. reaction })

    if reaction == 'scream' and MH.Chance(Config.Reactions.screamAlertChance) then
        Bridge.Dispatch('hostage', src, { hostages = MH.ActiveCount(src) })
    end
end

---------------------------------------------------------------------------
-- Take hostage
---------------------------------------------------------------------------
local function validateTarget(src, netId)
    if type(netId) ~= 'number' then return nil, 'invalid' end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil, 'invalid_target' end
    if GetEntityType(ent) ~= 1 or IsPedAPlayer(ent) then return nil, 'invalid_target' end
    if GetEntityHealth(ent) <= 0 then return nil, 'invalid_target' end

    local state = Entity(ent).state
    if state[MH.BlockKey] then return nil, 'invalid_target' end

    local model = MH.Hash(GetEntityModel(ent))
    if blockedModels[model] then return nil, 'invalid_target' end

    local pop = GetEntityPopulationType(ent)
    local allowedPop = Config.Take.allowedPopulationTypes[pop]
    if not allowedPop and not state[MH.AllowKey] then
        if pop ~= 7 or Config.Take.blockMissionPeds then return nil, 'invalid_target' end
    end

    if Config.Take.blockPedsInVehicles and GetVehiclePedIsIn(ent, false) ~= 0 then return nil, 'invalid_target' end

    local existing = Hostages[netId]
    if existing then
        if MH.Active[existing.state] then return nil, 'already_hostage' end
        Hostages[netId] = nil -- lingering terminal record, replace it
    end
    if PedCooldown[netId] and PedCooldown[netId] > os.time() then return nil, 'ped_cooldown' end

    local playerPed = GetPlayerPed(src)
    local maxDist = math.max(Config.Take.targetDistance, Config.Take.aimDistance) + Config.Security.distanceTolerance
    if #(GetEntityCoords(playerPed) - GetEntityCoords(ent)) > maxDist then return nil, 'too_far' end

    if Config.Security.requireEntityOwnership and NetworkGetEntityOwner(ent) ~= src then
        return nil, 'no_control'
    end

    return ent, nil, model
end

lib.callback.register('mozzy_hostage:server:take', function(src, netId)
    if MH.RateLimited(src, 'take', Config.Security.takeRateMs) then return MH.Fail('slow_down') end
    if TakeCooldown[src] and TakeCooldown[src] > os.time() then return MH.Fail('cooldown') end
    if Bridge.IsPlayerDown(src) then return MH.Fail('you_are_down') end
    if Config.Police.blockPoliceFromTaking and Bridge.IsPolice(src) then return MH.Fail('police_blocked') end
    if Config.Police.minOnDuty > 0 and #Bridge.GetOnDutyPolice() < Config.Police.minOnDuty then
        return MH.Fail('not_enough_police')
    end
    if MH.ActiveCount(src) >= Config.Take.maxHostages then return MH.Fail('max_hostages') end

    local weaponOk, weaponErr = MH.CheckWeapon(src)
    if not weaponOk then return MH.Fail(weaponErr) end

    local ent, err, model = validateTarget(src, netId)
    if not ent then return MH.Fail(err) end

    local profile = pickProfile(model)
    labelCounter = labelCounter + 1
    local now = os.time()

    ---@type HostageRecord
    local r = {
        netId = netId,
        entity = ent,
        owner = src,
        state = 'FREE',
        courage = math.random(profile.courage[1], profile.courage[2]),
        profile = profile.label,
        model = model,
        label = ('%s #%d'):format(profile.label, labelCounter),
        panicked = false,
        seq = 0,
        takenAt = now,
        updatedAt = now,
        lastThreat = now,
    }
    Hostages[netId] = r
    PlayerHostages[src] = PlayerHostages[src] or {}
    PlayerHostages[src][netId] = true
    TakeCooldown[src] = now + Config.Take.cooldown

    SetEntityOrphanMode(ent, 2) -- keep the ped alive even if its owner leaves

    MH.SetState(netId, 'THREATENED', { mode = false, event = 'threatened' })
    TriggerEvent('mozzy_hostage:server:hostageTaken', src, netId, MH.PublicData(r))

    local reaction = MH.RollReaction(r)
    MH.ApplyReaction(src, r, reaction)

    if reaction ~= 'run' then
        Bridge.Dispatch('hostage', src, { hostages = MH.ActiveCount(src) })
    end

    return { ok = true, netId = netId, reaction = reaction, label = r.label }
end)

---------------------------------------------------------------------------
-- Shots fired while holding hostages
---------------------------------------------------------------------------
RegisterNetEvent('mozzy_hostage:server:shotsFired', function()
    local src = source
    if MH.ActiveCount(src) == 0 then return end
    if MH.RateLimited(src, 'shots', 5000) then return end
    Bridge.Dispatch('shots', src, { hostages = MH.ActiveCount(src) })
end)

---------------------------------------------------------------------------
-- Owner cleanup
---------------------------------------------------------------------------
function MH.ReleaseAllFor(src, mode, reason)
    for netId in pairs(PlayerHostages[src] or {}) do
        if mode == 'escape' then
            MH.Escape(netId, reason)
        else
            MH.Release(netId, reason)
        end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    MH.ReleaseAllFor(src, Config.Cleanup.onDisconnect, 'owner_disconnected')
    PlayerHostages[src] = nil
    TakeCooldown[src] = nil
    RateLimit[src] = nil
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    src = src or source
    MH.ReleaseAllFor(src, Config.Cleanup.onLogout, 'owner_logout')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, r in pairs(Hostages) do
        if DoesEntityExist(r.entity) then
            Entity(r.entity).state:set(MH.StateKey, nil, true)
            SetEntityOrphanMode(r.entity, 0)
        end
    end
end)
