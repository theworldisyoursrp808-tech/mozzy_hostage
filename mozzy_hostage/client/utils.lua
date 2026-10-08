Utils = {}

local groupSet = MH.HashSet(Config.Weapons.allowedGroups)
local holdSet = MH.HashSet(Config.Weapons.holdGroups)
local blockedSet = MH.HashSet(Config.Weapons.blocked)
local allowedSet = MH.HashSet(Config.Weapons.allowed)
local UNARMED = MH.Hash('WEAPON_UNARMED')

function Utils.Debug(...)
    if Config.Debug then print('^5[mozzy_hostage]^7', ...) end
end

function Utils.Notify(message, notifyType, duration)
    ClientBridge.Notify(message, notifyType, duration)
end

function Utils.Error(code)
    Utils.Notify(Lang.errors[code] or tostring(code or 'Error'), 'error')
end

function Utils.LoadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    local ok = pcall(lib.requestAnimDict, dict, 3000)
    return ok and HasAnimDictLoaded(dict)
end

---@param ped number
---@param anim table { dict, name, flag, blendIn, blendOut, duration }
function Utils.PlayAnim(ped, anim)
    if not anim or not anim.dict or not DoesEntityExist(ped) then return false end
    if not Utils.LoadDict(anim.dict) then
        Utils.Debug('failed to load anim dict', anim.dict)
        return false
    end
    TaskPlayAnim(ped, anim.dict, anim.name, anim.blendIn or 4.0, anim.blendOut or -4.0, anim.duration or -1, anim.flag or 1, 0.0, false, false, false)
    return true
end

function Utils.IsPlaying(ped, anim)
    return anim ~= nil and IsEntityPlayingAnim(ped, anim.dict, anim.name, 3)
end

function Utils.StopAnim(ped, anim)
    if anim and IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then
        StopAnimTask(ped, anim.dict, anim.name, 2.0)
    end
end

function Utils.RequestControl(entity, timeout)
    if NetworkHasControlOfEntity(entity) then return true end
    local deadline = GetGameTimer() + (timeout or 1500)
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        Wait(50)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

function Utils.EntityFromNet(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return 0 end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent ~= 0 and DoesEntityExist(ent) then return ent end
    return 0
end

function Utils.Speech(ped, line)
    if ped ~= 0 and DoesEntityExist(ped) then
        PlayPedAmbientSpeechNative(ped, line, 'SPEECH_PARAMS_FORCE_SHOUTED')
    end
end

---Client-side weapon pre-check (server re-validates)
---@param forHold? boolean
function Utils.WeaponCheck(forHold)
    if not Config.Weapons.requireWeapon then return true end
    local hash = MH.Hash(GetSelectedPedWeapon(cache.ped))
    if hash == UNARMED or hash == 0 then return false, 'no_weapon' end
    if blockedSet[hash] then return false, 'blocked_weapon' end
    local group = MH.Hash(GetWeapontypeGroup(hash))
    if next(allowedSet) then
        if not allowedSet[hash] then return false, 'blocked_weapon' end
    elseif not groupSet[group] then
        return false, 'blocked_weapon'
    end
    if forHold and not holdSet[group] then return false, 'cant_hold_weapon' end
    if Config.Weapons.requireLoaded then
        local _, clip = GetAmmoInClip(cache.ped, hash)
        if (clip or 0) <= 0 then return false, 'not_loaded' end
    end
    return true
end

function Utils.HostageState(entity)
    if entity == 0 or not DoesEntityExist(entity) then return nil end
    return Entity(entity).state[MH.StateKey]
end

---lib.callback.await with a timeout so a lost/errored server response can
---never leave the script stuck in a "busy" state.
function Utils.Await(name, timeout, ...)
    local p = promise.new()
    local done = false
    lib.callback(name, false, function(...)
        if done then return end
        done = true
        p:resolve({ ... })
    end, ...)
    SetTimeout(timeout or 8000, function()
        if done then return end
        done = true
        p:resolve({ { ok = false, err = 'timeout' } })
    end)
    local result = Citizen.Await(p)
    return table.unpack(result)
end
