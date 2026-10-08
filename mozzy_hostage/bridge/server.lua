Bridge = {}

local function debug(...)
    if Config.Debug then print('^5[mozzy_hostage:bridge]^7', ...) end
end

---------------------------------------------------------------------------
-- Player / police helpers (Qbox)
---------------------------------------------------------------------------
function Bridge.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

function Bridge.IsPolice(src, requireDuty)
    local player = Bridge.GetPlayer(src)
    local job = player and player.PlayerData and player.PlayerData.job
    if not job then return false end
    local leo = job.type == Config.Police.jobType or Config.Police.jobs[job.name] == true
    if not leo then return false end
    if requireDuty ~= false and not job.onduty then return false end
    return true
end

local policeCache, policeCacheExpiry = {}, 0

function Bridge.GetOnDutyPolice()
    local now = GetGameTimer()
    if now < policeCacheExpiry then return policeCache end
    local list, seen = {}, {}
    local _, byType = exports.qbx_core:GetDutyCountType(Config.Police.jobType)
    for _, src in ipairs(byType or {}) do
        if not seen[src] then seen[src] = true; list[#list + 1] = src end
    end
    for jobName in pairs(Config.Police.jobs) do
        local _, byJob = exports.qbx_core:GetDutyCountJob(jobName)
        for _, src in ipairs(byJob or {}) do
            if not seen[src] then seen[src] = true; list[#list + 1] = src end
        end
    end
    policeCache, policeCacheExpiry = list, now + 3000
    return list
end

function Bridge.IsPlayerDown(src)
    local player = Bridge.GetPlayer(src)
    local meta = player and player.PlayerData and player.PlayerData.metadata
    if meta and (meta.isdead or meta.inlaststand) then return true end
    local ped = GetPlayerPed(src)
    return ped == 0 or GetEntityHealth(ped) <= 0
end

function Bridge.Notify(src, message, notifyType, duration)
    if Config.Notify == 'qbx' or Config.Notify == 'ox_lib' then
        exports.qbx_core:Notify(src, message, notifyType or 'inform', duration)
    else
        TriggerClientEvent('mozzy_hostage:client:notify', src, message, notifyType, duration)
    end
end

---------------------------------------------------------------------------
-- Dispatch bridge
---------------------------------------------------------------------------
local resolvedSystem
local brokenSystems = {} -- systems whose export failed; never retried this session

local function detect()
    if not brokenSystems['lb-tablet'] and GetResourceState('lb-tablet') == 'started' then return 'lb-tablet' end
    if not brokenSystems['ps-dispatch'] and GetResourceState('ps-dispatch') == 'started' then return 'ps-dispatch' end
    if not brokenSystems['cd_dispatch'] and GetResourceState('cd_dispatch') == 'started' then return 'cd_dispatch' end
    return 'builtin'
end

local function getSystem()
    if resolvedSystem then return resolvedSystem end
    local sys = Config.Dispatch.system
    if sys == 'auto' or brokenSystems[sys] then sys = detect() end
    resolvedSystem = sys
    debug('dispatch system:', sys)
    return sys
end

local function markBroken(sys, err)
    if brokenSystems[sys] then return end
    brokenSystems[sys] = true
    resolvedSystem = nil
    local fallback = getSystem()
    print(('^3[mozzy_hostage] dispatch system "%s" is unusable (%s). Falling back to "%s" for this session.^7'):format(sys, tostring(err), fallback))
    if sys == 'lb-tablet' then
        print('^3[mozzy_hostage] Your lb-tablet build has no AddDispatch export. Update lb-tablet to a version with the Police Dispatch API, or set Config.Dispatch.system to another system.^7')
    end
end

local alertCooldowns = {} -- [src..alert] = expiry

local function buildDescription(ctx)
    local parts = {}
    if ctx.gender then parts[#parts + 1] = ('Suspect: %s'):format(ctx.gender) end
    if ctx.weapon then parts[#parts + 1] = ('Weapon: %s'):format(ctx.weapon) end
    if ctx.vehicle then
        parts[#parts + 1] = ('Vehicle: %s%s%s'):format(ctx.vehicle,
            ctx.color and (' (' .. ctx.color .. ')') or '',
            ctx.plate and (' [' .. ctx.plate .. ']') or '')
    end
    if ctx.hostages and ctx.hostages > 0 then parts[#parts + 1] = ('Hostages: %d'):format(ctx.hostages) end
    return table.concat(parts, ' | ')
end

local senders = {}

senders['lb-tablet'] = function(alert, data)
    local fields = {}
    if data.gender then fields[#fields + 1] = { icon = 'user', label = 'Suspect', value = data.gender } end
    if data.weapon then fields[#fields + 1] = { icon = 'gun', label = 'Weapon', value = data.weapon } end
    if data.vehicle then fields[#fields + 1] = { icon = 'car', label = 'Vehicle', value = data.vehicle .. (data.plate and (' [' .. data.plate .. ']') or '') } end
    exports['lb-tablet']:AddDispatch({
        priority = alert.priority or 'high',
        code = alert.code,
        title = alert.title,
        description = data.description ~= '' and data.description or alert.title,
        location = { label = data.street or 'Unknown', coords = vec2(data.coords.x, data.coords.y) },
        time = alert.blip and alert.blip.time or 120,
        fields = fields,
    })
end

-- ps-dispatch / cd_dispatch are client-sided, so the suspect's client fires them
senders['ps-dispatch'] = function(alert, data)
    TriggerClientEvent('mozzy_hostage:client:clientDispatch', data.suspect, 'ps-dispatch', alert, data)
end

senders['cd_dispatch'] = function(alert, data)
    TriggerClientEvent('mozzy_hostage:client:clientDispatch', data.suspect, 'cd_dispatch', alert, data)
end

senders['builtin'] = function(alert, data)
    for _, cop in ipairs(Bridge.GetOnDutyPolice()) do
        TriggerClientEvent('mozzy_hostage:client:policeAlert', cop, alert, data)
    end
end

senders['custom'] = function(alert, data)
    if Config.Dispatch.custom then Config.Dispatch.custom(alert, data) end
end

---@param alertKey string key in Config.Dispatch.alerts
---@param src number suspect source
---@param extra? table { coords?, hostages? }
function Bridge.Dispatch(alertKey, src, extra)
    if not Config.Dispatch.enabled then return end
    local alert = Config.Dispatch.alerts[alertKey]
    if not alert or not alert.enabled then return end
    local sys = getSystem()
    if sys == 'none' then return end
    if math.random(100) > (alert.chance or 100) then return end

    local key = ('%s:%s'):format(src, alertKey)
    local now = os.time()
    if alertCooldowns[key] and alertCooldowns[key] > now then return end
    alertCooldowns[key] = now + (alert.cooldown or 60)

    extra = extra or {}
    local ped = GetPlayerPed(src)
    local coords = extra.coords or (ped ~= 0 and GetEntityCoords(ped)) or vec3(0, 0, 0)

    local sender = senders[sys] or senders.builtin
    local function send(ctx)
        ctx = type(ctx) == 'table' and ctx or {}
        local data = {
            suspect = src,
            coords = coords,
            street = type(ctx.street) == 'string' and ctx.street:sub(1, 80) or 'Unknown',
            gender = type(ctx.gender) == 'string' and ctx.gender:sub(1, 20) or nil,
            weapon = type(ctx.weapon) == 'string' and ctx.weapon:sub(1, 40) or nil,
            vehicle = type(ctx.vehicle) == 'string' and ctx.vehicle:sub(1, 40) or nil,
            plate = type(ctx.plate) == 'string' and ctx.plate:sub(1, 12) or nil,
            color = type(ctx.color) == 'string' and ctx.color:sub(1, 30) or nil,
            hostages = extra.hostages,
            jobs = Config.Dispatch.jobs,
        }
        data.description = buildDescription(data)
        if not GetPlayerName(src) and (sys == 'ps-dispatch' or sys == 'cd_dispatch') then
            sender = senders.builtin -- client-sided systems need the suspect online
        end
        local ok, err = pcall(sender, alert, data)
        if not ok then
            if sys ~= 'builtin' and sys ~= 'custom' then markBroken(sys, err) end
            local fallback = senders[getSystem()] or senders.builtin
            local ok2, err2 = pcall(fallback, alert, data)
            if not ok2 then
                print(('^1[mozzy_hostage] dispatch fallback failed: %s^7'):format(err2))
                senders.builtin(alert, data)
            end
        end
        debug('dispatch', alertKey, sys, data.street)
    end

    if not GetPlayerName(src) then return send({}) end
    -- Street/vehicle/description natives are client-only, ask the suspect asynchronously
    lib.callback('mozzy_hostage:client:alertContext', src, send)
end

AddEventHandler('playerDropped', function()
    local src = tostring(source)
    for key in pairs(alertCooldowns) do
        if key:sub(1, #src + 1) == src .. ':' then alertCooldowns[key] = nil end
    end
end)
