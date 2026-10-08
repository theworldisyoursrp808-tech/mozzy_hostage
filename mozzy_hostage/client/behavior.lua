--[[
    Ped behaviour runs ONLY on the client that network-owns the hostage ped.
    The server sets a replicated statebag; whoever owns the ped applies it.
    That keeps anims/tasks synced for every nearby player and survives
    ownership migration (owner disconnects, streams out, etc).
]]

Behavior = {}
local Applied = {} -- [netId] = { seq, data, ped }
local A = Config.Animations

local FOLLOW_TASK = `SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY`
local GOTO_TASK = `SCRIPT_TASK_GO_STRAIGHT_TO_COORD`
local ENTER_TASK = `SCRIPT_TASK_ENTER_VEHICLE`

local function ownerPed(serverId)
    if not serverId then return 0 end
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return 0 end
    return GetPlayerPed(player)
end

local function prepare(ped, netId)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedKeepTask(ped, true)
    SetPedConfigFlag(ped, 184, true) -- don't shuffle to the driver seat
    SetPedCanPlayAmbientAnims(ped, false)
    if NetworkGetEntityIsNetworked(ped) then SetNetworkIdCanMigrate(netId, false) end
end

local function detach(ped)
    if IsEntityAttached(ped) then
        DetachEntity(ped, true, false)
        ClearPedTasksImmediately(ped)
    end
end

local function handBack(ped, netId)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, true)
    SetPedCanPlayAmbientAnims(ped, true)
    if NetworkGetEntityIsNetworked(ped) then SetNetworkIdCanMigrate(netId, true) end
    SetTimeout(Config.Cleanup.pedDespawnDelay * 1000, function()
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            local st = Utils.HostageState(ped)
            if not st or MH.Terminal[st.state] then
                SetPedKeepTask(ped, false)
                SetPedAsNoLongerNeeded(ped)
            end
        end
    end)
end

local function leaveVehicle(ped, stale)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end
    TaskLeaveVehicle(ped, veh, 0)
    local deadline = GetGameTimer() + 5000
    while IsPedInAnyVehicle(ped, false) and GetGameTimer() < deadline do
        if stale() then return end
        Wait(100)
    end
end

local function playMode(ped, data, owner)
    local mode = data.mode
    if mode == 'follow' and owner ~= 0 then
        ClearPedTasks(ped)
        TaskFollowToOffsetOfEntity(ped, owner, 0.0, -Config.Follow.distance, 0.0, Config.Follow.speed, -1, 1.0, true)
    elseif mode == 'moveto' and data.coords then
        ClearPedTasks(ped)
        TaskGoStraightToCoord(ped, data.coords.x, data.coords.y, data.coords.z, 1.0, 20000, 0.0, 0.5)
    elseif mode == 'cower' then
        if not Utils.PlayAnim(ped, A.cower) then TaskCower(ped, -1) end
    elseif mode == 'cry' then
        if not Utils.PlayAnim(ped, A.cry) then TaskCower(ped, -1) end
    elseif mode == 'stay' then
        Utils.PlayAnim(ped, A.stay)
    else
        Utils.PlayAnim(ped, A.handsUp)
    end
end

local function modeAnim(mode)
    if mode == 'cower' then return A.cower
    elseif mode == 'cry' then return A.cry
    elseif mode == 'stay' then return A.stay end
    return A.handsUp
end

local reactionSpeech = {
    react_scream = 'GENERIC_FRIGHTENED_HIGH',
    react_panic = 'GENERIC_FRIGHTENED_HIGH',
    react_cry = 'GENERIC_FRIGHTENED_MED',
    react_refuse = 'GENERIC_INSULT_HIGH',
    threaten = 'GENERIC_FRIGHTENED_MED',
    threatened = 'GENERIC_SHOCKED_HIGH',
}

---Apply a replicated hostage state to a ped we own. Call inside a thread.
function Behavior.Apply(ped, netId, data)
    local cur = Applied[netId]
    if cur and cur.seq == data.seq and cur.ped == ped then return end

    local previous = cur and cur.data
    local seq = data.seq
    Applied[netId] = { seq = seq, data = data, ped = ped }
    local function stale()
        local a = Applied[netId]
        return not a or a.seq ~= seq or not DoesEntityExist(ped)
    end

    local owner = ownerPed(data.owner)
    local st = data.state
    if MH.Active[st] then prepare(ped, netId) end
    if reactionSpeech[data.event] then Utils.Speech(ped, reactionSpeech[data.event]) end

    -- Same-state threat: just a flinch, don't reset tasks/attachments
    if data.event == 'threaten' and previous and previous.state == st then
        return
    end

    if st == 'THREATENED' then
        detach(ped)
        ClearPedTasks(ped)
        if owner ~= 0 then
            TaskTurnPedToFaceEntity(ped, owner, 900)
            Wait(900)
            if stale() then return end
        end
        Utils.PlayAnim(ped, data.mode == 'refuse' and A.refuse or A.handsUp)

    elseif st == 'COMPLIANT' then
        detach(ped)
        leaveVehicle(ped, stale)
        if stale() then return end
        playMode(ped, data, owner)

    elseif st == 'HELD' then
        if owner == 0 then return end
        leaveVehicle(ped, stale)
        if stale() then return end
        ClearPedTasksImmediately(ped)
        local h = Config.Hold
        AttachEntityToEntity(ped, owner, h.bone, h.offset.x, h.offset.y, h.offset.z, h.rotation.x, h.rotation.y, h.rotation.z, false, false, false, false, 2, false)
        Utils.PlayAnim(ped, A.victimHeld)

    elseif st == 'KNEELING' then
        detach(ped)
        ClearPedTasks(ped)
        if Utils.PlayAnim(ped, A.kneelEnter) then
            Wait(A.kneelEnter.wait or 1200)
            if stale() then return end
        end
        Utils.PlayAnim(ped, A.kneel)

    elseif st == 'VEHICLE' then
        detach(ped)
        local veh = Utils.EntityFromNet(data.vehicle)
        if veh == 0 then return end
        ClearPedTasks(ped)
        TaskEnterVehicle(ped, veh, Config.Vehicle.enterTimeout, data.seat, 1.0, 1, 0)
        local deadline = GetGameTimer() + Config.Vehicle.enterTimeout + 500
        while not IsPedInVehicle(ped, veh, false) and GetGameTimer() < deadline do
            if stale() then return end
            Wait(200)
        end
        if not IsPedInVehicle(ped, veh, false) and IsVehicleSeatFree(veh, data.seat) then
            SetPedIntoVehicle(ped, veh, data.seat)
        end
        SetPedCanBeDraggedOut(ped, true)

    elseif st == 'RELEASED' or st == 'ESCAPED' then
        local wasHeld = IsEntityAttached(ped)
        if wasHeld then DetachEntity(ped, true, false) end

        if data.event == 'push' then
            ClearPedTasksImmediately(ped)
            Utils.PlayAnim(ped, A.victimShoved)
            Wait(A.victimShoved.wait or 1000)
        elseif data.event == 'escape_hold' then
            ClearPedTasksImmediately(ped)
            Utils.PlayAnim(ped, A.victimEscape)
            Wait(A.victimEscape.wait or 800)
        else
            ClearPedTasks(ped)
        end
        if stale() then return end

        leaveVehicle(ped, stale)
        handBack(ped, netId)
        ClearPedTasks(ped)

        if st == 'ESCAPED' then
            Utils.Speech(ped, 'GENERIC_FRIGHTENED_HIGH')
        end
        if data.event == 'rescued' then
            TaskWanderStandard(ped, 10.0, 10)
        elseif owner ~= 0 then
            TaskSmartFleePed(ped, owner, 200.0, -1, false, false)
        else
            TaskWanderStandard(ped, 10.0, 10)
        end
        SetTimeout(5000, function()
            if Applied[netId] and Applied[netId].seq == seq then Applied[netId] = nil end
        end)

    elseif st == 'DEAD' then
        if data.event == 'execute' and not IsPedDeadOrDying(ped, true) then
            if IsEntityAttached(ped) then
                Utils.PlayAnim(ped, A.victimExecute)
                Wait(A.victimExecute.wait or 600)
                DetachEntity(ped, true, false)
            end
            SetEntityHealth(ped, 0)
        else
            detach(ped)
        end
        handBack(ped, netId)
        Applied[netId] = nil
    end
end

---Keep anims/tasks alive for peds we own (they get interrupted by collisions, etc.)
local function maintain()
    for netId, a in pairs(Applied) do
        local ped, d = a.ped, a.data
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and IsPedDeadOrDying(ped, true) and MH.Active[d.state] then
            TriggerServerEvent('mozzy_hostage:server:pedDied', netId)
            Applied[netId] = nil
        elseif not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) or IsPedDeadOrDying(ped, true) then
            Applied[netId] = nil
        elseif d.state == 'HELD' then
            local owner = ownerPed(d.owner)
            if owner ~= 0 and not IsEntityAttachedToEntity(ped, owner) then
                local h = Config.Hold
                AttachEntityToEntity(ped, owner, h.bone, h.offset.x, h.offset.y, h.offset.z, h.rotation.x, h.rotation.y, h.rotation.z, false, false, false, false, 2, false)
            end
            if not Utils.IsPlaying(ped, A.victimHeld) then Utils.PlayAnim(ped, A.victimHeld) end
        elseif d.state == 'KNEELING' then
            if not Utils.IsPlaying(ped, A.kneel) and not Utils.IsPlaying(ped, A.kneelEnter) then Utils.PlayAnim(ped, A.kneel) end
        elseif d.state == 'THREATENED' then
            local anim = d.mode == 'refuse' and A.refuse or A.handsUp
            if not Utils.IsPlaying(ped, anim) and GetScriptTaskStatus(ped, `SCRIPT_TASK_TURN_PED_TO_FACE_ENTITY`) == 7 then
                Utils.PlayAnim(ped, anim)
            end
        elseif d.state == 'COMPLIANT' then
            if d.mode == 'follow' then
                local owner = ownerPed(d.owner)
                if owner ~= 0 and GetScriptTaskStatus(ped, FOLLOW_TASK) == 7 then
                    TaskFollowToOffsetOfEntity(ped, owner, 0.0, -Config.Follow.distance, 0.0, Config.Follow.speed, -1, 1.0, true)
                end
            elseif d.mode == 'moveto' then
                if GetScriptTaskStatus(ped, GOTO_TASK) == 7 and not Utils.IsPlaying(ped, A.handsUp) then
                    Utils.PlayAnim(ped, A.handsUp)
                end
            elseif not IsPedInAnyVehicle(ped, false) then
                local anim = modeAnim(d.mode)
                if not Utils.IsPlaying(ped, anim) then Utils.PlayAnim(ped, anim) end
            end
        elseif d.state == 'VEHICLE' then
            local veh = Utils.EntityFromNet(d.vehicle)
            if veh ~= 0 and not IsPedInVehicle(ped, veh, false) and GetScriptTaskStatus(ped, ENTER_TASK) == 7
                and #(GetEntityCoords(ped) - GetEntityCoords(veh)) < 8.0 and IsVehicleSeatFree(veh, d.seat) then
                TaskEnterVehicle(ped, veh, Config.Vehicle.enterTimeout, d.seat, 1.0, 1, 0)
            end
        end
    end
end

---Pick up hostages we became owner of without seeing a state change (migration)
local function adoptOwned()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and NetworkHasControlOfEntity(ped) then
            local st = Entity(ped).state[MH.StateKey]
            if st and MH.Active[st.state] then
                local netId = NetworkGetNetworkIdFromEntity(ped)
                local a = Applied[netId]
                if not a or a.ped ~= ped then
                    CreateThread(function() Behavior.Apply(ped, netId, st) end)
                end
            end
        end
    end
end

CreateThread(function()
    local tick = 0
    while true do
        Wait(1000)
        if next(Applied) then maintain() end
        tick = tick + 1
        if tick % 2 == 0 then adoptOwned() end
    end
end)

function Behavior.ReleaseAll()
    for netId, a in pairs(Applied) do
        if DoesEntityExist(a.ped) and NetworkHasControlOfEntity(a.ped) then
            if IsEntityAttached(a.ped) then DetachEntity(a.ped, true, false) end
            ClearPedTasksImmediately(a.ped)
            SetBlockingOfNonTemporaryEvents(a.ped, false)
            SetNetworkIdCanMigrate(netId, true)
            SetPedKeepTask(a.ped, false)
            SetPedAsNoLongerNeeded(a.ped)
        end
    end
    Applied = {}
end

function Behavior.IsApplied(netId)
    return Applied[netId] ~= nil
end
