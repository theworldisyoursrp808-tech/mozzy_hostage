--[[
    Mozzy NPC Hostage System - Server API
    Every function accepts either a network id (preferred) or a server entity handle.
]]

local function resolve(entityOrNetId)
    if type(entityOrNetId) ~= 'number' then return nil end
    if Hostages[entityOrNetId] then return Hostages[entityOrNetId], entityOrNetId end
    if DoesEntityExist(entityOrNetId) then
        local netId = NetworkGetNetworkIdFromEntity(entityOrNetId)
        if Hostages[netId] then return Hostages[netId], netId end
    end
    return nil
end

local function toSet(list)
    if not list then return nil end
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

---Does the player currently control at least one active hostage?
exports('HasHostage', function(src)
    return MH.ActiveCount(src) > 0
end)

---All active hostages controlled by a player
---@return table[] list of hostage data
exports('GetPlayerHostages', function(src)
    local list = {}
    for netId in pairs(PlayerHostages[src] or {}) do
        local r = Hostages[netId]
        if r and MH.Active[r.state] then list[#list + 1] = MH.PublicData(r) end
    end
    return list
end)

---First active hostage of a player (held one preferred)
---@return number|nil entity, table|nil data
exports('GetPlayerHostage', function(src)
    local first
    for netId in pairs(PlayerHostages[src] or {}) do
        local r = Hostages[netId]
        if r and MH.Active[r.state] then
            if r.state == 'HELD' then return r.entity, MH.PublicData(r) end
            first = first or r
        end
    end
    if first then return first.entity, MH.PublicData(first) end
    return nil, nil
end)

---@param states? string[] optional state filter, e.g. { 'HELD', 'KNEELING' }
exports('CountPlayerHostages', function(src, states)
    return MH.ActiveCount(src, toSet(states))
end)

---Hostages around a point.
---@param coords vector3
---@param radius number
---@param opts? { owner?: number, states?: string[], includeInactive?: boolean }
exports('GetNearbyHostages', function(coords, radius, opts)
    opts = opts or {}
    local states = toSet(opts.states)
    local list = {}
    for _, r in pairs(Hostages) do
        if (opts.includeInactive or MH.Active[r.state])
            and (not opts.owner or r.owner == opts.owner)
            and (not states or states[r.state])
            and DoesEntityExist(r.entity)
            and #(GetEntityCoords(r.entity) - coords) <= radius then
            list[#list + 1] = MH.PublicData(r)
        end
    end
    return list
end)

---Count active hostages around a point (optionally only one owner's)
exports('CountHostagesInArea', function(coords, radius, owner)
    local n = 0
    for _, r in pairs(Hostages) do
        if MH.Active[r.state] and (not owner or r.owner == owner) and DoesEntityExist(r.entity)
            and #(GetEntityCoords(r.entity) - coords) <= radius then
            n = n + 1
        end
    end
    return n
end)

exports('GetHostage', function(entityOrNetId)
    return MH.PublicData((resolve(entityOrNetId)))
end)

---@return string state ('FREE' when not a hostage)
exports('GetHostageState', function(entityOrNetId)
    local r = resolve(entityOrNetId)
    return r and r.state or 'FREE'
end)

exports('GetHostageOwner', function(entityOrNetId)
    local r = resolve(entityOrNetId)
    return r and r.owner or nil
end)

exports('IsHostage', function(entityOrNetId)
    local r = resolve(entityOrNetId)
    return r ~= nil and MH.Active[r.state] == true
end)

exports('IsHostageAlive', function(entityOrNetId)
    local r = resolve(entityOrNetId)
    if not r then return false end
    return r.state ~= 'DEAD' and DoesEntityExist(r.entity) and GetEntityHealth(r.entity) > 0
end)

exports('IsHostageReleased', function(entityOrNetId)
    local r = resolve(entityOrNetId)
    return r ~= nil and (r.state == 'RELEASED' or r.state == 'ESCAPED')
end)

---@param reason? string
exports('ReleaseHostage', function(entityOrNetId, reason)
    local _, netId = resolve(entityOrNetId)
    if not netId then return false end
    return MH.Release(netId, reason or ('script:' .. (GetInvokingResource() or 'unknown')))
end)

exports('ForceEscape', function(entityOrNetId, reason)
    local _, netId = resolve(entityOrNetId)
    if not netId then return false end
    return MH.Escape(netId, reason or 'script')
end)

exports('ReleaseAllHostages', function(src, reason)
    MH.ReleaseAllFor(src, 'release', reason or 'script')
    return true
end)

---Force a state. Uses the transition table unless force = true.
---@param state string THREATENED|COMPLIANT|HELD|KNEELING|VEHICLE|RELEASED|ESCAPED|DEAD
---@param mode? string stay|follow|handsup|cower|cry (COMPLIANT only)
---@param force? boolean
exports('SetHostageState', function(entityOrNetId, state, mode, force)
    local _, netId = resolve(entityOrNetId)
    if not netId then return false, 'not_hostage' end
    if state == 'HELD' or state == 'VEHICLE' then return false, 'use_actions' end
    return MH.SetState(netId, state, {
        mode = mode or false,
        force = force == true,
        event = 'script',
        reason = 'script:' .. (GetInvokingResource() or 'unknown'),
    })
end)

---Run a hostage action as if the owner had pressed it (still validated)
exports('RunAction', function(entityOrNetId, action, data)
    local r, netId = resolve(entityOrNetId)
    if not r then return { ok = false, err = 'not_hostage' } end
    local def = MH.Actions[action]
    if not def or not def.from[r.state] then return { ok = false, err = 'bad_state' } end
    return def.run(r.owner, r, data or {})
end)

exports('GetEscapeChance', function(entityOrNetId)
    local r = resolve(entityOrNetId)
    if not r or not MH.Active[r.state] or not DoesEntityExist(r.entity) then return 0 end
    return MH.EscapeChance(r)
end)

-- Negotiations
exports('CreateNegotiation', function(src, demandKeys, custom, label)
    return MH.CreateNegotiation(src, demandKeys, custom, label)
end)
exports('GetNegotiation', function(id) return MH.GetNegotiation(id) end)
exports('GetPlayerNegotiation', function(src) return MH.GetPlayerNegotiation(src) end)
exports('CloseNegotiation', function(id, reason) return MH.CloseNegotiation(id, reason or 'script') end)

---------------------------------------------------------------------------
-- Admin debug command
---------------------------------------------------------------------------
lib.addCommand('hostagedebug', { help = 'List active NPC hostages', restricted = 'group.admin' }, function(src)
    local count = 0
    for netId, r in pairs(Hostages) do
        count = count + 1
        local msg = ('[%s] %s owner=%s state=%s mode=%s courage=%s escape=%.1f%%'):format(
            netId, r.label, r.owner, r.state, tostring(r.mode), r.courage,
            (MH.Active[r.state] and DoesEntityExist(r.entity)) and MH.EscapeChance(r) or 0)
        if src == 0 then print(msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'mozzy_hostage', msg } }) end
    end
    if count == 0 then
        if src == 0 then print('no hostages') else TriggerClientEvent('chat:addMessage', src, { args = { 'mozzy_hostage', 'no hostages' } }) end
    end
end)
