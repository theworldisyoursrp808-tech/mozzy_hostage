if GetResourceState('ox_target') == 'missing' then return end

local function myHostage(entity)
    if not NetworkGetEntityIsNetworked(entity) then return nil end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    local h = MyHostages[netId]
    if h and MH.Active[h.state] then return netId, h end
    return nil
end

local options = {}

if Config.Take.useTarget then
    options[#options + 1] = {
        name = 'mozzy_hostage_take',
        icon = 'fas fa-gun',
        label = Lang.target.take,
        distance = Config.Take.targetDistance,
        canInteract = function(entity)
            if cache.vehicle then return false end
            return Client.CanTake(entity, true)
        end,
        onSelect = function(data)
            Client.TryTake(data.entity, Config.Take.targetDistance + 0.5)
        end,
    }
end

options[#options + 1] = {
    name = 'mozzy_hostage_grab',
    icon = 'fas fa-hand',
    label = Lang.target.grab,
    distance = Config.Actions.distance.grab,
    canInteract = function(entity)
        if Hold.netId or cache.vehicle then return false end
        local _, h = myHostage(entity)
        return h ~= nil and (h.state == 'COMPLIANT' or h.state == 'KNEELING')
    end,
    onSelect = function(data)
        local netId = myHostage(data.entity)
        if netId then Client.Action(netId, 'grab') end
    end,
}

options[#options + 1] = {
    name = 'mozzy_hostage_commands',
    icon = 'fas fa-user-lock',
    label = Lang.target.commands,
    distance = 4.0,
    canInteract = function(entity)
        if Hold.netId then return false end
        return myHostage(entity) ~= nil
    end,
    onSelect = function(data)
        local netId = myHostage(data.entity)
        if netId then Menu.OpenHostage(netId) end
    end,
}

if Config.Police.rescue.enabled then
    options[#options + 1] = {
        name = 'mozzy_hostage_rescue',
        icon = 'fas fa-shield-halved',
        label = Lang.target.rescue,
        distance = Config.Police.rescue.distance,
        canInteract = function(entity)
            if not Client.IsPolice() then return false end
            local st = Utils.HostageState(entity)
            return st ~= nil and MH.Active[st.state] and st.state ~= 'HELD'
        end,
        onSelect = function(data) Client.Rescue(data.entity) end,
    }
end

exports.ox_target:addGlobalPed(options)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local names = {}
    for _, o in ipairs(options) do names[#names + 1] = o.name end
    exports.ox_target:removeGlobalPed(names)
end)
