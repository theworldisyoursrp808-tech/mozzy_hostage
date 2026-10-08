Client = {}
MyHostages = {} -- [netId] = { netId, state, mode, label, profile, vehicle } (server-synced)

local busy = false
local isPolice = false

---------------------------------------------------------------------------
-- Police job cache (for target options)
---------------------------------------------------------------------------
local function refreshJob()
    local pd = exports.qbx_core:GetPlayerData()
    local job = pd and pd.job
    isPolice = job ~= nil and (job.type == Config.Police.jobType or Config.Police.jobs[job.name] == true) and job.onduty == true
end
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshJob)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function() Wait(100) refreshJob() end)
RegisterNetEvent('QBCore:Client:SetDuty', function() Wait(100) refreshJob() end)
CreateThread(refreshJob)

function Client.IsPolice() return isPolice end

---------------------------------------------------------------------------
-- Server sync of our own hostages
---------------------------------------------------------------------------
RegisterNetEvent('mozzy_hostage:client:sync', function(list)
    local fresh = {}
    for _, h in ipairs(list or {}) do fresh[h.netId] = h end
    MyHostages = fresh
    if Hold.netId and (not fresh[Hold.netId] or fresh[Hold.netId].state ~= 'HELD') then
        Hold.Stop()
    end
end)

function Client.Count()
    local n = 0
    for _ in pairs(MyHostages) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Replicated statebag -> ped behaviour (only the ped's network owner acts)
---------------------------------------------------------------------------
AddStateBagChangeHandler(MH.StateKey, nil, function(bagName, _, value)
    if not value then return end
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 then return end
    CreateThread(function()
        -- statebag can arrive a tick before ownership settles
        Wait(0)
        if DoesEntityExist(entity) and NetworkHasControlOfEntity(entity) then
            Behavior.Apply(entity, NetworkGetNetworkIdFromEntity(entity), value)
        end
    end)
end)

---------------------------------------------------------------------------
-- Aiming + shots fired reporting (feeds server escape + dispatch)
---------------------------------------------------------------------------
CreateThread(function()
    local lastAim = false
    while true do
        local sleep = 1000
        if next(MyHostages) then
            sleep = 500
            local aiming = Hold.netId ~= nil or IsPlayerFreeAiming(cache.playerId)
            if aiming ~= lastAim then
                lastAim = aiming
                LocalPlayer.state:set('mozzyAiming', aiming, true)
            end
        elseif lastAim then
            lastAim = false
            LocalPlayer.state:set('mozzyAiming', false, true)
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    local nextReport = 0
    while true do
        if next(MyHostages) then
            if IsPedShooting(cache.ped) and GetGameTimer() > nextReport then
                nextReport = GetGameTimer() + 10000
                TriggerServerEvent('mozzy_hostage:server:shotsFired')
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- Taking a hostage
---------------------------------------------------------------------------
---@param ped number
---@param silent? boolean don't notify on failure (used by canInteract)
function Client.CanTake(ped, silent)
    local function no(code) if not silent then Utils.Error(code) end return false end
    if Hold.netId then return no('max_held') end
    if busy then return false end
    if ped == 0 or not DoesEntityExist(ped) or IsPedAPlayer(ped) or IsPedDeadOrDying(ped, true) then return no('invalid_target') end
    if not IsPedHuman(ped) then return no('invalid_target') end
    if Config.Take.blockPedsInVehicles and IsPedInAnyVehicle(ped, false) then return no('invalid_target') end
    local state = Entity(ped).state
    if state[MH.BlockKey] then return no('invalid_target') end
    local st = state[MH.StateKey]
    if st and MH.Active[st.state] then return no('already_hostage') end
    if Config.Police.blockPoliceFromTaking and isPolice then return no('police_blocked') end
    if Client.Count() >= Config.Take.maxHostages then return no('max_hostages') end
    local ok, err = Utils.WeaponCheck(false)
    if not ok then return no(err) end
    return true
end

function Client.TryTake(ped, maxDistance)
    if not Client.CanTake(ped) then return end
    if #(GetEntityCoords(cache.ped) - GetEntityCoords(ped)) > (maxDistance or Config.Take.targetDistance) then
        return Utils.Error('too_far')
    end
    if Config.Take.requireLineOfSight and not HasEntityClearLosToEntity(cache.ped, ped, 17) then
        return Utils.Error('no_los')
    end

    busy = true
    if not NetworkGetEntityIsNetworked(ped) then
        NetworkRegisterEntityAsNetworked(ped)
        Wait(150)
    end
    if not NetworkGetEntityIsNetworked(ped) or not Utils.RequestControl(ped, 2000) then
        busy = false
        return Utils.Error('no_control')
    end

    local netId = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdCanMigrate(netId, false)
    -- freeze the ped in place while the server decides
    ClearPedTasks(ped)
    TaskStandStill(ped, 1500)
    Utils.Speech(cache.ped, 'GENERIC_INSULT_HIGH')

    local res = Utils.Await('mozzy_hostage:server:take', 8000, netId)
    busy = false

    if not res or not res.ok then
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then SetNetworkIdCanMigrate(netId, true) end
        return Utils.Error(res and res.err or 'invalid')
    end

    local reactionType = (res.reaction == 'run' or res.reaction == 'refuse' or res.reaction == 'scream') and 'warning' or 'success'
    Utils.Notify(Lang.reactions[res.reaction] or res.reaction, reactionType)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function findVehicleSeat()
    local veh = lib.getClosestVehicle(GetEntityCoords(cache.ped), Config.Vehicle.searchDistance, true)
    if not veh or veh == 0 then return nil, nil, 'no_vehicle' end
    if GetVehicleDoorLockStatus(veh) >= 2 then return nil, nil, 'vehicle_locked' end
    local maxPassengers = GetVehicleMaxNumberOfPassengers(veh)
    for _, seat in ipairs(Config.Vehicle.seatOrder) do
        if seat < maxPassengers and IsVehicleSeatFree(veh, seat) then
            return veh, seat
        end
    end
    return nil, nil, 'no_seat'
end

---@param netId number
---@param action string
---@param data? table
function Client.Action(netId, action, data)
    if busy then return end
    data = data or {}
    local ped = Utils.EntityFromNet(netId)

    if action == 'grab' then
        if Hold.netId then return Utils.Error('max_held') end
        local ok, err = Utils.WeaponCheck(true)
        if not ok then return Utils.Error(err) end
        if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(cache.ped)) > Config.Actions.distance.grab then
            return Utils.Error('too_far')
        end
        Utils.RequestControl(ped, 1000)
    elseif action == 'vehicle_in' then
        local veh, seat, err = findVehicleSeat()
        if not veh then return Utils.Error(err) end
        data.vehicle = NetworkGetNetworkIdFromEntity(veh)
        data.seat = seat
    elseif action == 'moveto' then
        local raycast = lib.raycast.fromCamera or lib.raycast.cam
        local hit, _, endCoords = raycast(1 | 16, 4, Config.Actions.moveToMaxDistance)
        if not hit or not endCoords then return Utils.Error('no_point') end
        data.coords = { x = endCoords.x, y = endCoords.y, z = endCoords.z }
    elseif action == 'execute' then
        if not Config.Execute.enabled then return Utils.Error('disabled') end
        local ok = Utils.WeaponCheck(false)
        if not ok then return Utils.Error('no_weapon') end
        if Config.Execute.confirm then
            local answer = lib.alertDialog({ header = Lang.actions.execute, content = Lang.executeConfirm, centered = true, cancel = true })
            if answer ~= 'confirm' then return end
        end
    elseif action == 'threaten' then
        Utils.Speech(cache.ped, 'GENERIC_CURSE_HIGH')
    end

    busy = true
    local res = Utils.Await('mozzy_hostage:server:action', 8000, netId, action, data)
    busy = false

    if not res or not res.ok then
        Utils.Error(res and res.err or 'invalid')
        return res
    end
    if res.reaction then
        Utils.Notify(Lang.reactions[res.reaction] or res.reaction, res.reaction == 'surrender' and 'success' or 'warning')
    end
    return res
end

function Client.Rescue(ped)
    if not DoesEntityExist(ped) then return end
    local res = lib.callback.await('mozzy_hostage:server:rescue', false, NetworkGetNetworkIdFromEntity(ped))
    if not res or not res.ok then return Utils.Error(res and res.err or 'invalid') end
    Utils.Notify(Lang.youRescued, 'success')
end

---------------------------------------------------------------------------
-- Keybinds
---------------------------------------------------------------------------
if Config.Take.useKeybind then
    lib.addKeybind({
        name = 'mozzy_hostage_take',
        description = 'Take aimed NPC hostage',
        defaultKey = Config.Keybinds.take,
        onPressed = function()
            if Hold.netId or busy or cache.vehicle then return end
            local aiming, ent = GetEntityPlayerIsFreeAimingAt(cache.playerId)
            if Config.Take.requireAimingForKeybind and (not aiming or not ent or ent == 0) then return end
            if not ent or ent == 0 or not IsEntityAPed(ent) or IsPedAPlayer(ent) then return end
            Client.TryTake(ent, Config.Take.aimDistance)
        end,
    })
end

Hold.RegisterKeys(
    function(netId) Client.Action(netId, 'letgo') end,
    function(netId) Client.Action(netId, 'push') end,
    function(netId) Client.Action(netId, 'execute') end
)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Hold.netId then Hold.Stop() end
    Behavior.ReleaseAll()
    LocalPlayer.state:set('mozzyAiming', false, true)
end)

---------------------------------------------------------------------------
-- Client exports
---------------------------------------------------------------------------
exports('HasHostage', function() return next(MyHostages) ~= nil end)
exports('GetHostages', function()
    local list = {}
    for netId, h in pairs(MyHostages) do
        list[#list + 1] = { netId = netId, entity = Utils.EntityFromNet(netId), state = h.state, mode = h.mode, label = h.label }
    end
    return list
end)
exports('GetHeldHostage', function()
    if not Hold.netId then return nil end
    return Utils.EntityFromNet(Hold.netId), Hold.netId
end)
exports('IsPedHostage', function(ped)
    local st = Utils.HostageState(ped)
    return st ~= nil and MH.Active[st.state] == true
end)
exports('GetHostageState', function(ped)
    local st = Utils.HostageState(ped)
    return st and st.state or 'FREE', st
end)
exports('TryTakeHostage', function(ped) Client.TryTake(ped, Config.Take.aimDistance) end)
