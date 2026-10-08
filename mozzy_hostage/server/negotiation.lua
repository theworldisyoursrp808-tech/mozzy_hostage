local Fail = MH.Fail
Negotiations = {}          -- [id] = negotiation
local PlayerNegotiation = {} -- [src] = id
local nextId = 0

local demandLookup = {}
for _, d in ipairs(Config.Negotiation.demands) do demandLookup[d.key] = d end

local POLICE_STATUSES = { Accepted = true, Denied = true, Countered = true }

local function sanitize(text, maxLen)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return nil end
    return text:sub(1, maxLen)
end

local function charName(src)
    local player = Bridge.GetPlayer(src)
    local info = player and player.PlayerData and player.PlayerData.charinfo
    if info then return ('%s %s'):format(info.firstname or '', info.lastname or '') end
    return GetPlayerName(src) or 'Unknown'
end

local function view(neg)
    return {
        id = neg.id,
        label = neg.label,
        owner = neg.owner,
        street = neg.street,
        coords = neg.coords,
        demands = neg.demands,
        hostages = MH.ActiveCount(neg.owner),
        createdAt = neg.createdAt,
        closed = neg.closed,
    }
end

local function broadcast(neg, notifyOwner, notifyPolice, policeMsg)
    local data = view(neg)
    if GetPlayerName(neg.owner) then
        TriggerClientEvent('mozzy_hostage:client:negUpdated', neg.owner, data, notifyOwner)
    end
    for _, cop in ipairs(Bridge.GetOnDutyPolice()) do
        TriggerClientEvent('mozzy_hostage:client:negUpdated', cop, data, notifyPolice and policeMsg or nil)
    end
    TriggerEvent('mozzy_hostage:server:negotiationUpdated', data)
end

---@param src number criminal
---@param demandKeys string[]
---@param custom? string
---@param label? string
---@return table|nil negotiation, string|nil err
function MH.CreateNegotiation(src, demandKeys, custom, label)
    if not Config.Negotiation.enabled then return nil, 'disabled' end
    if PlayerNegotiation[src] and Negotiations[PlayerNegotiation[src]] then return nil, 'neg_exists' end
    if MH.ActiveCount(src) < Config.Negotiation.minHostages then return nil, 'need_hostages' end

    local demands, seen = {}, {}
    for _, key in ipairs(type(demandKeys) == 'table' and demandKeys or {}) do
        local def = demandLookup[key]
        if def and not seen[key] then
            seen[key] = true
            demands[#demands + 1] = { id = #demands + 1, key = key, label = def.label, icon = def.icon, status = 'pending' }
        end
    end
    if Config.Negotiation.allowCustom then
        local text = sanitize(custom, Config.Negotiation.maxCustomLength)
        if text then
            demands[#demands + 1] = { id = #demands + 1, key = 'custom', label = text, icon = 'comment', status = 'pending' }
        end
    end
    if #demands == 0 then return nil, 'no_demands' end

    nextId = nextId + 1
    local ped = GetPlayerPed(src)
    local neg = {
        id = nextId,
        owner = src,
        ownerName = charName(src),
        label = sanitize(label, 60) or ('Hostage Situation #%d'):format(nextId),
        coords = ped ~= 0 and GetEntityCoords(ped) or vec3(0, 0, 0),
        demands = demands,
        createdAt = os.time(),
        closed = false,
    }
    Negotiations[neg.id] = neg
    PlayerNegotiation[src] = neg.id

    broadcast(neg, Lang.neg.created, true, Lang.neg.newForPolice:format(neg.label))
    TriggerEvent('mozzy_hostage:server:negotiationCreated', view(neg))
    return view(neg)
end

function MH.CloseNegotiation(id, reason)
    local neg = Negotiations[id]
    if not neg or neg.closed then return false end
    neg.closed = true
    neg.closeReason = reason
    broadcast(neg, Lang.neg.closed, true, Lang.neg.closed)
    if PlayerNegotiation[neg.owner] == id then PlayerNegotiation[neg.owner] = nil end
    Negotiations[id] = nil
    TriggerEvent('mozzy_hostage:server:negotiationClosed', view(neg), reason)
    return true
end

function MH.GetNegotiation(id)
    local neg = Negotiations[id]
    return neg and view(neg) or nil
end

function MH.GetPlayerNegotiation(src)
    local id = PlayerNegotiation[src]
    return id and MH.GetNegotiation(id) or nil
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
lib.callback.register('mozzy_hostage:server:negCreate', function(src, demandKeys, custom, label)
    if MH.RateLimited(src, 'neg', 1000) then return Fail('slow_down') end
    local neg, err = MH.CreateNegotiation(src, demandKeys, custom, label)
    if not neg then return Fail(err) end
    return { ok = true, negotiation = neg }
end)

lib.callback.register('mozzy_hostage:server:negMine', function(src)
    return MH.GetPlayerNegotiation(src)
end)

lib.callback.register('mozzy_hostage:server:negList', function(src)
    if not Bridge.IsPolice(src) then return Fail('not_police') end
    local list = {}
    for _, neg in pairs(Negotiations) do
        if not neg.closed then list[#list + 1] = view(neg) end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    return { ok = true, list = list }
end)

lib.callback.register('mozzy_hostage:server:negGet', function(src, id)
    local neg = Negotiations[tonumber(id) or -1]
    if not neg then return Fail('no_negotiation') end
    if neg.owner ~= src and not Bridge.IsPolice(src) then return Fail('not_police') end
    return { ok = true, negotiation = view(neg) }
end)

-- Police respond: Accepted / Denied / Countered (+ counter text)
lib.callback.register('mozzy_hostage:server:negRespond', function(src, id, demandId, status, counter)
    if MH.RateLimited(src, 'negRespond', 500) then return Fail('slow_down') end
    if not Bridge.IsPolice(src) then return Fail('not_police') end
    local neg = Negotiations[tonumber(id) or -1]
    if not neg then return Fail('no_negotiation') end
    local demand = neg.demands[tonumber(demandId) or -1]
    if not demand or not POLICE_STATUSES[status] then return Fail('invalid') end

    demand.status = status
    demand.counter = status == 'Countered' and sanitize(counter, Config.Negotiation.maxCounterLength) or nil
    demand.respondedBy = charName(src)
    demand.respondedAt = os.time()

    broadcast(neg, Lang.neg.updated, false)
    return { ok = true, negotiation = view(neg) }
end)

-- Criminal answers a counter offer
lib.callback.register('mozzy_hostage:server:negCounterReply', function(src, id, demandId, accept)
    if MH.RateLimited(src, 'negReply', 500) then return Fail('slow_down') end
    local neg = Negotiations[tonumber(id) or -1]
    if not neg or neg.owner ~= src then return Fail('no_negotiation') end
    local demand = neg.demands[tonumber(demandId) or -1]
    if not demand or demand.status ~= 'Countered' then return Fail('invalid') end

    demand.status = accept and 'CounterAccepted' or 'CounterRejected'
    local statusLabel = Lang.neg.statuses[demand.status]
    broadcast(neg, nil, true, Lang.neg.criminalReplied:format(statusLabel))
    return { ok = true, negotiation = view(neg) }
end)

lib.callback.register('mozzy_hostage:server:negClose', function(src, id)
    local neg = Negotiations[tonumber(id) or -1]
    if not neg then return Fail('no_negotiation') end
    if neg.owner ~= src and not Bridge.IsPolice(src) then return Fail('not_police') end
    MH.CloseNegotiation(neg.id, neg.owner == src and 'closed_by_suspect' or 'closed_by_police')
    return { ok = true }
end)

---------------------------------------------------------------------------
-- Auto-close: owner left, no hostages left, or timed out
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for id, neg in pairs(Negotiations) do
            if not GetPlayerName(neg.owner) then
                MH.CloseNegotiation(id, 'owner_left')
            elseif MH.ActiveCount(neg.owner) == 0 then
                MH.CloseNegotiation(id, 'no_hostages')
            elseif now - neg.createdAt > Config.Negotiation.autoCloseMinutes * 60 then
                MH.CloseNegotiation(id, 'timeout')
            end
        end
    end
end)
