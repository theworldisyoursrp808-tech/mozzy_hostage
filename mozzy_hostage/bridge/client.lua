ClientBridge = {}

function ClientBridge.Notify(message, notifyType, duration)
    if Config.Notify == 'qbx' then
        exports.qbx_core:Notify(message, notifyType or 'inform', duration)
    elseif Config.Notify == 'custom' and Config.CustomNotify then
        Config.CustomNotify(message, notifyType, duration)
    else
        lib.notify({ title = Lang.title, description = message, type = notifyType or 'inform', duration = duration })
    end
end

RegisterNetEvent('mozzy_hostage:client:notify', function(message, notifyType, duration)
    ClientBridge.Notify(message, notifyType, duration)
end)

---------------------------------------------------------------------------
-- Alert context (street, suspect description, weapon, vehicle)
---------------------------------------------------------------------------
local function weaponLabel()
    if GetResourceState('ox_inventory') == 'started' then
        local ok, weapon = pcall(function() return exports.ox_inventory:getCurrentWeapon() end)
        if ok and weapon and weapon.label then return weapon.label end
    end
    local hash = GetSelectedPedWeapon(cache.ped)
    if hash == `WEAPON_UNARMED` then return nil end
    return 'Firearm'
end

lib.callback.register('mozzy_hostage:client:alertContext', function()
    local coords = GetEntityCoords(cache.ped)
    local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(s1)
    if s2 and s2 ~= 0 then street = street .. ' / ' .. GetStreetNameFromHashKey(s2) end

    local ctx = {
        street = street,
        gender = IsPedMale(cache.ped) and 'Male' or 'Female',
        weapon = weaponLabel(),
    }

    local veh = cache.vehicle
    if not veh or veh == 0 then veh = GetVehiclePedIsIn(cache.ped, true) end
    if veh and veh ~= 0 and #(GetEntityCoords(veh) - coords) < 30.0 then
        local model = GetEntityModel(veh)
        ctx.vehicle = GetLabelText(GetDisplayNameFromVehicleModel(model))
        if ctx.vehicle == 'NULL' then ctx.vehicle = GetDisplayNameFromVehicleModel(model) end
        ctx.plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s*(.-)%s*$', '%1')
    end
    return ctx
end)

---------------------------------------------------------------------------
-- Client-sided dispatch systems
---------------------------------------------------------------------------
RegisterNetEvent('mozzy_hostage:client:clientDispatch', function(system, alert, data)
    if system == 'ps-dispatch' then
        exports['ps-dispatch']:CustomAlert({
            message = alert.title,
            codeName = 'mozzy_hostage',
            code = alert.code,
            icon = 'fas fa-user-lock',
            priority = alert.priority == 'high' and 1 or 2,
            coords = data.coords,
            street = data.street,
            gender = data.gender,
            weapon = data.weapon,
            vehicle = data.vehicle,
            plate = data.plate,
            color = data.color,
            alertTime = alert.blip and alert.blip.time or nil,
            jobs = data.jobs,
            alert = alert.blip and {
                radius = 0,
                sprite = alert.blip.sprite,
                color = alert.blip.color,
                scale = alert.blip.scale,
                length = 2,
                flash = true,
            } or nil,
        })
    elseif system == 'cd_dispatch' then
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = data.jobs,
            coords = data.coords,
            title = ('%s - %s'):format(alert.code, alert.title),
            message = ('%s at %s'):format(data.description ~= '' and data.description or alert.title, data.street),
            flash = 0,
            unique_id = tostring(math.random(0000000, 9999999)),
            sound = 1,
            blip = alert.blip and {
                sprite = alert.blip.sprite,
                scale = alert.blip.scale,
                colour = alert.blip.color,
                flashes = true,
                text = alert.title,
                time = math.floor((alert.blip.time or 120) / 60),
                radius = 0,
            } or nil,
        })
    end
end)

-- Fallback built-in alert for officers (ox_lib notify + temporary blip)
RegisterNetEvent('mozzy_hostage:client:policeAlert', function(alert, data)
    lib.notify({
        title = ('%s | %s'):format(alert.code, alert.title),
        description = ('%s\n%s'):format(data.street or 'Unknown', data.description or ''),
        type = 'error',
        duration = 10000,
        icon = 'user-lock',
    })
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)
    if not alert.blip then return end
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, alert.blip.sprite or 458)
    SetBlipColour(blip, alert.blip.color or 1)
    SetBlipScale(blip, alert.blip.scale or 1.0)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(alert.title)
    EndTextCommandSetBlipName(blip)
    SetTimeout((alert.blip.time or 120) * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)
