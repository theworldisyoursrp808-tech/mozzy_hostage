--[[
    Captor side: gun-to-head hold loop and the captor's own animations.
    Driven by 'mozzy_hostage:client:ownerEvent' which the server sends
    straight to the owner, so it works even if the ped isn't streamed.
]]

Hold = { netId = nil }
local A = Config.Animations
local HoldKeys = {}
local restoreToken = 0

local CONTROL_ATTACK, CONTROL_AIM, CONTROL_ATTACK2, CONTROL_RELOAD = 24, 25, 257, 45

function Hold.SetKeysEnabled(enabled)
    for _, key in pairs(HoldKeys) do key:disable(not enabled) end
end

function Hold.RegisterKeys(onLetGo, onPush, onExecute)
    HoldKeys.letgo = lib.addKeybind({
        name = 'mozzy_hostage_letgo', description = 'Hostage: let go (keep control)',
        defaultKey = Config.Keybinds.holdLetGo, disabled = true,
        onPressed = function() if Hold.netId then onLetGo(Hold.netId) end end,
    })
    HoldKeys.push = lib.addKeybind({
        name = 'mozzy_hostage_push', description = 'Hostage: push away',
        defaultKey = Config.Keybinds.holdPush, disabled = true,
        onPressed = function() if Hold.netId then onPush(Hold.netId) end end,
    })
    if Config.Execute.enabled then
        HoldKeys.execute = lib.addKeybind({
            name = 'mozzy_hostage_execute', description = 'Hostage: execute',
            defaultKey = Config.Keybinds.holdExecute, disabled = true,
            onPressed = function() if Hold.netId then onExecute(Hold.netId) end end,
        })
    end
end

---Hand full weapon control back to the player after any hostage anim.
---Runs after `delay` ms unless a new hold started in the meantime.
function Hold.RestorePlayer(delay)
    restoreToken = restoreToken + 1
    local token = restoreToken
    SetTimeout(delay or 0, function()
        if token ~= restoreToken or Hold.netId then return end
        local ped = cache.ped
        for _, anim in pairs({ A.perpHold, A.perpExecute, A.perpPush, A.perpShoved }) do
            if anim and IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then
                StopAnimTask(ped, anim.dict, anim.name, 4.0)
            end
        end
        ClearPedSecondaryTask(ped)
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        -- re-arm the weapon the player was holding so aim/fire/reload work again
        local weapon = GetSelectedPedWeapon(ped)
        SetPedCanSwitchWeapon(ped, true)
        if weapon ~= `WEAPON_UNARMED` then
            SetCurrentPedWeapon(ped, weapon, true)
        end
        LocalPlayer.state:set('mozzyAiming', false, true)
    end)
end

function Hold.Start(netId)
    if Hold.netId == netId then return end
    Hold.netId = netId
    restoreToken = restoreToken + 1 -- cancel any pending restore
    Hold.SetKeysEnabled(true)
    lib.showTextUI(Lang.holdHelp, { position = 'left-center', icon = 'user-lock' })
    LocalPlayer.state:set('mozzyAiming', true, true)

    CreateThread(function()
        local H = Config.Hold
        local controls = H.disabledControls
        local animPausedUntil = 0
        local nextCheck = 0
        Utils.PlayAnim(cache.ped, A.perpHold)

        while Hold.netId == netId do
            local ped = cache.ped
            local now = GetGameTimer()

            for i = 1, #controls do DisableControlAction(0, controls[i], true) end

            local aiming = H.allowAiming and IsControlPressed(0, CONTROL_AIM)
            if not H.allowAiming then DisableControlAction(0, CONTROL_AIM, true) end
            if not (H.allowShooting and aiming) then
                DisableControlAction(0, CONTROL_ATTACK, true)
                DisableControlAction(0, CONTROL_ATTACK2, true)
                DisablePlayerFiring(cache.playerId, true)
            end

            if H.allowReload then
                if IsControlJustPressed(0, CONTROL_RELOAD) or IsDisabledControlJustPressed(0, CONTROL_RELOAD) or IsPedReloading(ped) then
                    animPausedUntil = now + H.reloadPause
                end
            else
                DisableControlAction(0, CONTROL_RELOAD, true)
            end

            if H.walkOnly then SetPedMaxMoveBlendRatio(ped, H.moveBlendRatio) end

            -- The gun-to-head anim overrides the weapon's aim/reload anims,
            -- so pause it while aiming or reloading and bring it back after.
            local paused = aiming or now < animPausedUntil or IsPedReloading(ped)
            if paused then
                if Utils.IsPlaying(ped, A.perpHold) then StopAnimTask(ped, A.perpHold.dict, A.perpHold.name, 4.0) end
            elseif now > nextCheck then
                nextCheck = now + 300
                if not IsPedRagdoll(ped) and not IsPedDeadOrDying(ped, true) and not Utils.IsPlaying(ped, A.perpHold) then
                    Utils.PlayAnim(ped, A.perpHold)
                end
            end
            Wait(0)
        end
    end)
end

---@param anim? table animation to play on the captor after letting go
function Hold.Stop(anim)
    if not Hold.netId then return end
    Hold.netId = nil
    Hold.SetKeysEnabled(false)
    lib.hideTextUI()
    Utils.StopAnim(cache.ped, A.perpHold)
    if anim then Utils.PlayAnim(cache.ped, anim) end
    Hold.RestorePlayer((anim and anim.duration or 0) + 150)
end

---Fire one real bullet from the captor's gun into the hostage's head.
---Uses a bullet instead of SetPedShootsAtCoord, which tasks the player ped
---and could leave the weapon stuck until the task cleared.
local function shootAt(netId, delay)
    SetTimeout(delay or 0, function()
        local ped = Utils.EntityFromNet(netId)
        if ped == 0 then return end
        local weapon = GetSelectedPedWeapon(cache.ped)
        if weapon == `WEAPON_UNARMED` then return end
        local from = GetPedBoneCoords(cache.ped, 57005, 0.15, 0.0, 0.0) -- right hand
        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        ShootSingleBulletBetweenCoords(from.x, from.y, from.z, head.x, head.y, head.z, 200, true, weapon, cache.ped, true, false, -1.0)
        local ammo = GetAmmoInPedWeapon(cache.ped, weapon)
        if ammo > 0 then SetPedAmmo(cache.ped, weapon, ammo - 1) end
    end)
end

-- Server -> owner: state changed for one of our hostages
RegisterNetEvent('mozzy_hostage:client:ownerEvent', function(netId, data)
    if data.state == 'HELD' then
        Hold.Start(netId)
        return
    end

    if Hold.netId == netId then
        local anim
        if data.event == 'push' then anim = A.perpPush
        elseif data.event == 'execute' then anim = A.perpExecute
        elseif data.event == 'escape_hold' then anim = A.perpShoved end
        Hold.Stop(anim)
    end

    if data.event == 'execute' then
        shootAt(netId, data.prev == 'HELD' and 450 or 0)
        Hold.RestorePlayer((A.perpExecute.duration or 1200) + 300)
    end

    if data.state == 'RELEASED' and data.event ~= 'rescued' and data.reason == 'released' then
        Utils.Notify(Lang.released, 'inform')
    end
end)

-- Safety net: if we somehow end up not holding anyone while a hold anim is
-- still on the player (missed event, resource hiccup), clean it up.
CreateThread(function()
    while true do
        Wait(2000)
        if not Hold.netId and Utils.IsPlaying(cache.ped, A.perpHold) then
            Hold.RestorePlayer(0)
        end
    end
end)
