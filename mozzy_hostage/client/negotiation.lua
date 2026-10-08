Negotiation = {}
if not Config.Negotiation.enabled then return end

local N = Lang.neg

local statusColor = {
    pending = '#868e96', Accepted = '#2f9e44', Denied = '#e03131', Countered = '#f08c00',
    CounterAccepted = '#2f9e44', CounterRejected = '#e03131',
}

local function statusText(d)
    local text = N.statuses[d.status] or d.status
    if d.counter then text = ('%s — "%s"'):format(text, d.counter) end
    if d.respondedBy then text = text .. ('\n%s'):format(d.respondedBy) end
    return text
end

---------------------------------------------------------------------------
-- Criminal side
---------------------------------------------------------------------------
local function createDialog()
    local rows = { { type = 'input', label = N.label, placeholder = 'Fleeca Bank - Legion Square', max = 60 } }
    for _, d in ipairs(Config.Negotiation.demands) do
        rows[#rows + 1] = { type = 'checkbox', label = d.label }
    end
    if Config.Negotiation.allowCustom then
        rows[#rows + 1] = { type = 'textarea', label = N.custom, max = Config.Negotiation.maxCustomLength, autosize = true }
    end

    local input = lib.inputDialog(N.title, rows)
    if not input then return end

    local keys = {}
    for i, d in ipairs(Config.Negotiation.demands) do
        if input[i + 1] then keys[#keys + 1] = d.key end
    end
    local custom = Config.Negotiation.allowCustom and input[#Config.Negotiation.demands + 2] or nil

    local res = lib.callback.await('mozzy_hostage:server:negCreate', false, keys, custom, input[1])
    if not res or not res.ok then return Utils.Error(res and res.err or 'invalid') end
    Negotiation.ShowCriminal(res.negotiation)
end

function Negotiation.ShowCriminal(neg)
    local options = {}
    for _, d in ipairs(neg.demands) do
        local opt = {
            title = d.label,
            description = statusText(d),
            icon = d.icon or 'comment',
            iconColor = statusColor[d.status],
        }
        if d.status == 'Countered' then
            opt.arrow = true
            opt.onSelect = function()
                local choice = lib.alertDialog({
                    header = N.counter,
                    content = d.counter or '',
                    centered = true,
                    cancel = true,
                    labels = { confirm = N.acceptCounter, cancel = N.rejectCounter },
                })
                local res = lib.callback.await('mozzy_hostage:server:negCounterReply', false, neg.id, d.id, choice == 'confirm')
                if res and res.ok then Negotiation.ShowCriminal(res.negotiation) else Utils.Error(res and res.err) end
            end
        end
        options[#options + 1] = opt
    end
    options[#options + 1] = {
        title = N.close, icon = 'xmark', iconColor = '#e03131',
        onSelect = function()
            lib.callback.await('mozzy_hostage:server:negClose', false, neg.id)
        end,
    }
    lib.registerContext({ id = 'mozzy_neg_criminal', title = ('%s — %s'):format(N.title, neg.label), menu = 'mozzy_hostage_main', options = options })
    lib.showContext('mozzy_neg_criminal')
end

function Negotiation.OpenCriminal()
    local neg = lib.callback.await('mozzy_hostage:server:negMine', false)
    if neg then return Negotiation.ShowCriminal(neg) end
    createDialog()
end

---------------------------------------------------------------------------
-- Police side
---------------------------------------------------------------------------
local function respondDialog(neg, d)
    local input = lib.inputDialog(('%s — %s'):format(N.title, d.label), {
        { type = 'select', label = N.status, required = true, default = d.status ~= 'pending' and d.status or nil, options = {
            { value = 'Accepted', label = N.statuses.Accepted },
            { value = 'Denied', label = N.statuses.Denied },
            { value = 'Countered', label = N.statuses.Countered },
        } },
        { type = 'textarea', label = N.counter, max = Config.Negotiation.maxCounterLength, autosize = true },
    })
    if not input then return Negotiation.ShowPolice(neg.id) end
    local res = lib.callback.await('mozzy_hostage:server:negRespond', false, neg.id, d.id, input[1], input[2])
    if not res or not res.ok then return Utils.Error(res and res.err or 'invalid') end
    Negotiation.ShowPolice(neg.id)
end

function Negotiation.ShowPolice(id)
    local res = lib.callback.await('mozzy_hostage:server:negGet', false, id)
    if not res or not res.ok then return Utils.Error(res and res.err or 'no_negotiation') end
    local neg = res.negotiation

    local options = {
        {
            title = neg.label,
            description = ('Hostages: %d'):format(neg.hostages or 0),
            icon = 'circle-info',
            onSelect = function()
                SetNewWaypoint(neg.coords.x, neg.coords.y)
                Negotiation.ShowPolice(id)
            end,
        },
    }
    for _, d in ipairs(neg.demands) do
        options[#options + 1] = {
            title = d.label,
            description = statusText(d),
            icon = d.icon or 'comment',
            iconColor = statusColor[d.status],
            arrow = true,
            onSelect = function() respondDialog(neg, d) end,
        }
    end
    options[#options + 1] = {
        title = N.close, icon = 'xmark', iconColor = '#e03131',
        onSelect = function() lib.callback.await('mozzy_hostage:server:negClose', false, neg.id) end,
    }
    lib.registerContext({ id = 'mozzy_neg_police', title = N.title, menu = 'mozzy_neg_list', options = options })
    lib.showContext('mozzy_neg_police')
end

function Negotiation.OpenPoliceList()
    local res = lib.callback.await('mozzy_hostage:server:negList', false)
    if not res or not res.ok then return Utils.Error(res and res.err or 'not_police') end
    local options = {}
    for _, neg in ipairs(res.list) do
        local pending = 0
        for _, d in ipairs(neg.demands) do if d.status == 'pending' then pending = pending + 1 end end
        options[#options + 1] = {
            title = neg.label,
            description = ('Hostages: %d · Pending demands: %d'):format(neg.hostages or 0, pending),
            icon = 'handshake',
            arrow = true,
            onSelect = function() Negotiation.ShowPolice(neg.id) end,
        }
    end
    if #options == 0 then options[1] = { title = N.none, disabled = true } end
    lib.registerContext({ id = 'mozzy_neg_list', title = N.title, options = options })
    lib.showContext('mozzy_neg_list')
end

RegisterCommand(Config.Negotiation.policeCommand, function()
    Negotiation.OpenPoliceList()
end, false)

-- Live updates for both sides
RegisterNetEvent('mozzy_hostage:client:negUpdated', function(neg, message)
    if message then
        lib.notify({ title = ('%s — %s'):format(N.title, neg.label), description = message, type = 'inform', icon = 'handshake', duration = 7000 })
    end
    local open = lib.getOpenContextMenu()
    if neg.closed then
        if open == 'mozzy_neg_criminal' or open == 'mozzy_neg_police' then lib.hideContext(false) end
        return
    end
    if open == 'mozzy_neg_criminal' and neg.owner == cache.serverId then
        Negotiation.ShowCriminal(neg)
    end
end)
