local Fail = MH.Fail
local T = true

local CONTROLLED = { THREATENED = T, COMPLIANT = T, HELD = T, KNEELING = T, VEHICLE = T }
local ON_FOOT = { COMPLIANT = T, HELD = T, KNEELING = T }

local function ok(extra)
    extra = extra or {}
    extra.ok = true
    return extra
end

local function set(r, state, opts)
    local success, err = MH.SetState(r.netId, state, opts)
    if not success then return Fail(err) end
    return ok()
end

---@type table<string, { from: table, weapon?: boolean, run: fun(src: number, r: HostageRecord, data: table): table }>
local Actions = {}

Actions.grab = {
    from = { COMPLIANT = T, KNEELING = T },
    weapon = true,
    run = function(src, r)
        if MH.ActiveCount(src, { HELD = T }) >= Config.Take.maxHeld then return Fail('max_held') end
        local res = set(r, 'HELD', { mode = false, event = 'grab' })
        if res.ok then Bridge.Dispatch('armed', src, { hostages = MH.ActiveCount(src) }) end
        return res
    end,
}

Actions.letgo = {
    from = { HELD = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'handsup', event = 'letgo' }) end,
}

Actions.follow = {
    from = { COMPLIANT = T, KNEELING = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'follow', event = 'follow' }) end,
}

Actions.stay = {
    from = { COMPLIANT = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'stay', event = 'stay' }) end,
}

Actions.handsup = {
    from = { COMPLIANT = T, KNEELING = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'handsup', event = 'handsup' }) end,
}

Actions.kneel = {
    from = { COMPLIANT = T, HELD = T },
    run = function(_, r) return set(r, 'KNEELING', { mode = false, event = 'kneel' }) end,
}

Actions.stand = {
    from = { KNEELING = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'handsup', event = 'stand' }) end,
}

Actions.moveto = {
    from = { COMPLIANT = T, KNEELING = T },
    run = function(src, r, data)
        local c = data.coords
        if type(c) ~= 'table' and type(c) ~= 'vector3' then return Fail('no_point') end
        local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
        if not x or not y or not z then return Fail('no_point') end
        local point = vec3(x, y, z)
        if #(GetEntityCoords(GetPlayerPed(src)) - point) > Config.Actions.moveToMaxDistance + Config.Security.distanceTolerance then
            return Fail('too_far')
        end
        return set(r, 'COMPLIANT', { mode = 'moveto', event = 'moveto', coords = point })
    end,
}

Actions.threaten = {
    from = CONTROLLED,
    weapon = true,
    run = function(src, r)
        local now = os.time()
        if r.lastThreat and now - r.lastThreat < Config.Reactions.threatenCooldown then
            return Fail('slow_down')
        end
        r.lastThreat = now

        if r.state == 'THREATENED' then
            r.courage = math.max(0, r.courage - Config.Reactions.threatenCourageDrop)
            local reaction = MH.RollReaction(r)
            MH.ApplyReaction(src, r, reaction)
            return ok({ reaction = reaction })
        end

        MH.PushState(r, 'threaten') -- same state, new seq -> ped flinches
        return ok()
    end,
}

Actions.vehicle_in = {
    from = ON_FOOT,
    run = function(src, r, data)
        if not Config.Vehicle.enabled then return Fail('disabled') end
        local vehNet, seat = tonumber(data.vehicle), math.tointeger(tonumber(data.seat))
        if not vehNet or not seat or seat < 0 or seat > 14 then return Fail('no_vehicle') end
        local veh = NetworkGetEntityFromNetworkId(vehNet)
        if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return Fail('no_vehicle') end
        local maxDist = Config.Vehicle.searchDistance + Config.Security.distanceTolerance
        if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > maxDist then return Fail('too_far') end
        if GetPedInVehicleSeat(veh, seat) ~= 0 then return Fail('no_seat') end
        for netId, other in pairs(Hostages) do
            if netId ~= r.netId and other.state == 'VEHICLE' and other.vehicle == vehNet and other.seat == seat then
                return Fail('no_seat')
            end
        end
        return set(r, 'VEHICLE', { mode = false, event = 'vehicle_in', vehicle = vehNet, seat = seat })
    end,
}

Actions.vehicle_out = {
    from = { VEHICLE = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'handsup', event = 'vehicle_out' }) end,
}

Actions.vehicle_remove = {
    from = { VEHICLE = T },
    run = function(_, r) return set(r, 'COMPLIANT', { mode = 'follow', event = 'vehicle_remove' }) end,
}

Actions.push = {
    from = { HELD = T },
    run = function(_, r)
        local success = MH.Release(r.netId, 'pushed', 'push')
        return success and ok() or Fail('bad_state')
    end,
}

Actions.release = {
    from = CONTROLLED,
    run = function(_, r)
        local success = MH.Release(r.netId, 'released', 'release')
        return success and ok() or Fail('bad_state')
    end,
}

Actions.execute = {
    from = { THREATENED = T, COMPLIANT = T, HELD = T, KNEELING = T },
    weapon = true,
    run = function(src, r)
        if not Config.Execute.enabled then return Fail('disabled') end
        local res = set(r, 'DEAD', { event = 'execute', reason = 'executed' })
        if res.ok then Bridge.Dispatch('shots', src, { hostages = MH.ActiveCount(src) }) end
        return res
    end,
}

MH.Actions = Actions

lib.callback.register('mozzy_hostage:server:action', function(src, netId, action, data)
    if type(netId) ~= 'number' or type(action) ~= 'string' then return Fail('invalid') end
    if data ~= nil and type(data) ~= 'table' then return Fail('invalid') end
    if MH.RateLimited(src, 'action', Config.Security.actionRateMs) then return Fail('slow_down') end

    local def = Actions[action]
    if not def then return Fail('invalid') end

    local r = Hostages[netId]
    if not r or r.owner ~= src or not MH.Active[r.state] then return Fail('not_your_hostage') end

    if not DoesEntityExist(r.entity) then
        MH.Release(netId, 'despawned')
        return Fail('hostage_gone')
    end
    if GetEntityHealth(r.entity) <= 0 then
        MH.SetState(netId, 'DEAD', { force = true, reason = 'died' })
        return Fail('hostage_dead')
    end
    if Bridge.IsPlayerDown(src) then return Fail('you_are_down') end
    if not def.from[r.state] then return Fail('bad_state') end

    local maxDist = (Config.Actions.distance[action] or Config.Actions.defaultDistance) + Config.Security.distanceTolerance
    local dist = #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(r.entity))
    if dist > maxDist then return Fail('too_far') end

    if def.weapon then
        local weaponOk, weaponErr = MH.CheckWeapon(src)
        if not weaponOk then return Fail(weaponErr) end
    end

    return def.run(src, r, data or {})
end)

---------------------------------------------------------------------------
-- Police: secure a civilian that isn't being held
---------------------------------------------------------------------------
lib.callback.register('mozzy_hostage:server:rescue', function(src, netId)
    if not Config.Police.rescue.enabled then return Fail('disabled') end
    if type(netId) ~= 'number' then return Fail('invalid') end
    if MH.RateLimited(src, 'rescue', 1000) then return Fail('slow_down') end
    if not Bridge.IsPolice(src) then return Fail('not_police') end

    local r = Hostages[netId]
    if not r or not MH.Active[r.state] or r.state == 'HELD' then return Fail('bad_state') end
    if not DoesEntityExist(r.entity) then return Fail('hostage_gone') end

    local hostageCoords = GetEntityCoords(r.entity)
    if #(GetEntityCoords(GetPlayerPed(src)) - hostageCoords) > Config.Police.rescue.distance + Config.Security.distanceTolerance then
        return Fail('too_far')
    end
    local ownerPed = GetPlayerPed(r.owner)
    if ownerPed ~= 0 and #(GetEntityCoords(ownerPed) - hostageCoords) < Config.Police.rescue.ownerMinDistance then
        return Fail('captor_close')
    end

    local owner = r.owner
    local success = MH.SetState(netId, 'RELEASED', { force = true, event = 'rescued', reason = 'rescued_by_police' })
    if not success then return Fail('bad_state') end
    Bridge.Notify(owner, Lang.rescued, 'error')
    TriggerEvent('mozzy_hostage:server:hostageRescued', src, owner, netId)
    return ok()
end)
