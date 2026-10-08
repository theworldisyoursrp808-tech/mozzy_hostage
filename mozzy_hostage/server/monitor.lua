local AimState = {} -- [src] = { aiming = bool, last = os.time() }

AddStateBagChangeHandler('mozzyAiming', nil, function(bagName, _, value)
    local src = GetPlayerFromStateBagName(bagName)
    if not src or src == 0 then return end
    local entry = AimState[src] or { last = os.time() }
    entry.aiming = value == true
    if entry.aiming then entry.last = os.time() end
    AimState[src] = entry
end)

AddEventHandler('playerDropped', function()
    AimState[source] = nil
end)

local function secondsSinceAim(src)
    local entry = AimState[src]
    if not entry then return 0 end
    if entry.aiming then entry.last = os.time() return 0 end
    return os.time() - entry.last
end

---------------------------------------------------------------------------
-- Integrity loop: NPC death / despawn, owner down
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(1000)
        for netId, r in pairs(Hostages) do
            if MH.Active[r.state] then
                if not DoesEntityExist(r.entity) then
                    MH.SetState(netId, 'RELEASED', { force = true, reason = 'despawned' })
                elseif GetEntityHealth(r.entity) <= 0 then
                    MH.SetState(netId, 'DEAD', { force = true, reason = 'died' })
                    MH.Debug('hostage died', netId)
                    if GetPlayerName(r.owner) then Bridge.Notify(r.owner, Lang.died, 'error') end
                elseif not GetPlayerName(r.owner) then
                    MH.Escape(netId, 'owner_missing')
                elseif Config.Cleanup.onOwnerDown ~= 'none' and Bridge.IsPlayerDown(r.owner) then
                    if Config.Cleanup.onOwnerDown == 'release' then
                        MH.Release(netId, 'owner_down')
                    else
                        MH.Escape(netId, 'owner_down')
                    end
                end
            end
        end
    end
end)

-- The ped's network owner reports death (more reliable than server health for NPCs)
RegisterNetEvent('mozzy_hostage:server:pedDied', function(netId)
    local src = source
    local r = Hostages[netId]
    if not r or not MH.Active[r.state] then return end
    if MH.RateLimited(src, 'pedDied', 250) then return end
    if not DoesEntityExist(r.entity) or NetworkGetEntityOwner(r.entity) ~= src then return end
    MH.SetState(netId, 'DEAD', { force = true, reason = 'died' })
    if GetPlayerName(r.owner) then Bridge.Notify(r.owner, Lang.died, 'error') end
end)

---------------------------------------------------------------------------
-- Escape rolls (server-authoritative)
---------------------------------------------------------------------------
local function policeNear(coords, radius)
    local count = 0
    for _, cop in ipairs(Bridge.GetOnDutyPolice()) do
        local ped = GetPlayerPed(cop)
        if ped ~= 0 and #(GetEntityCoords(ped) - coords) <= radius then count = count + 1 end
    end
    return count
end

local function escapeChance(r)
    local E = Config.Escape
    local F = E.factors
    local ownerPed = GetPlayerPed(r.owner)
    if ownerPed == 0 then return E.maxChance end

    local hostageCoords = GetEntityCoords(r.entity)
    local dist = #(GetEntityCoords(ownerPed) - hostageCoords)
    local chance = E.baseChance

    if F.unattended.enabled and dist >= F.unattended.distance then
        chance = chance + F.unattended.chance
    elseif F.distance.enabled and dist >= F.distance.distance then
        chance = chance + F.distance.chance
    end

    if F.noWeapon.enabled and not MH.CheckWeapon(r.owner) then
        chance = chance + F.noWeapon.chance
    end

    if F.notAiming.enabled and r.state ~= 'HELD' and secondsSinceAim(r.owner) >= F.notAiming.after then
        chance = chance + F.notAiming.chance
    end

    if F.ownerVehicle.enabled and r.state ~= 'VEHICLE' and GetVehiclePedIsIn(ownerPed, false) ~= 0 then
        chance = chance + F.ownerVehicle.chance
    end

    if F.police.enabled then
        local cops = policeNear(hostageCoords, F.police.radius)
        if cops > 0 then chance = chance + math.min(F.police.max, cops * F.police.chance) end
    end

    if r.panicked then chance = chance + E.panicBonus end

    -- Brave NPCs are more likely to try their luck
    chance = chance * (0.5 + (r.courage or 50) / 100)
    chance = chance * (E.stateMultiplier[r.state] or 1.0)

    if r.lastThreat and os.time() - r.lastThreat < E.threatenProtection then
        chance = chance * E.threatenMultiplier
    end

    return math.min(E.maxChance, chance)
end

CreateThread(function()
    while true do
        Wait(Config.Escape.interval * 1000)
        if Config.Escape.enabled then
            for netId, r in pairs(Hostages) do
                if MH.Active[r.state] and DoesEntityExist(r.entity) and GetEntityHealth(r.entity) > 0 then
                    local chance = escapeChance(r)
                    if MH.Chance(chance) then
                        MH.Debug(('hostage %s escaped (%.1f%%)'):format(netId, chance))
                        MH.Escape(netId, 'escaped')
                    end
                end
            end
        end
    end
end)

MH.EscapeChance = escapeChance
