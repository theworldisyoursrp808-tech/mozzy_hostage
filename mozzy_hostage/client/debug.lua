if not Config.Debug then return end

local function draw3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.3, 0.3)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 220)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

CreateThread(function()
    local tracked = {}
    local nextScan = 0
    while true do
        local now = GetGameTimer()
        if now > nextScan then
            nextScan = now + 1000
            tracked = {}
            local myCoords = GetEntityCoords(cache.ped)
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and #(GetEntityCoords(ped) - myCoords) < 40.0 then
                    local st = Utils.HostageState(ped)
                    if st then tracked[#tracked + 1] = ped end
                end
            end
        end
        for _, ped in ipairs(tracked) do
            local st = DoesEntityExist(ped) and Utils.HostageState(ped)
            if st then
                local owned = NetworkHasControlOfEntity(ped) and '~g~owned' or '~r~remote'
                draw3D(GetEntityCoords(ped) + vec3(0, 0, 1.1),
                    ('%s %s~w~\n%s/%s seq:%s owner:%s'):format(owned, NetworkGetNetworkIdFromEntity(ped), st.state, tostring(st.mode), st.seq, st.owner))
            end
        end
        Wait(0)
    end
end)
