Menu = {}
local T = true

-- Order here = order in the menu
local ACTIONS = {
    { key = 'grab',           icon = 'hand',              from = { COMPLIANT = T, KNEELING = T } },
    { key = 'letgo',          icon = 'hand-point-down',   from = { HELD = T } },
    { key = 'follow',         icon = 'person-walking',    from = { COMPLIANT = T, KNEELING = T }, hideMode = 'follow' },
    { key = 'stay',           icon = 'street-view',       from = { COMPLIANT = T }, hideMode = 'stay' },
    { key = 'handsup',        icon = 'hands',             from = { COMPLIANT = T, KNEELING = T }, hideMode = 'handsup' },
    { key = 'kneel',          icon = 'person-praying',    from = { COMPLIANT = T, HELD = T } },
    { key = 'stand',          icon = 'person',            from = { KNEELING = T } },
    { key = 'moveto',         icon = 'location-crosshairs', from = { COMPLIANT = T, KNEELING = T } },
    { key = 'threaten',       icon = 'gun',               from = { THREATENED = T, COMPLIANT = T, KNEELING = T, HELD = T, VEHICLE = T } },
    { key = 'vehicle_in',     icon = 'car',               from = { COMPLIANT = T, HELD = T, KNEELING = T }, enabled = function() return Config.Vehicle.enabled end },
    { key = 'vehicle_out',    icon = 'door-open',         from = { VEHICLE = T } },
    { key = 'vehicle_remove', icon = 'person-walking-arrow-right', from = { VEHICLE = T } },
    { key = 'push',           icon = 'hand-back-fist',    from = { HELD = T } },
    { key = 'release',        icon = 'unlock',            from = { THREATENED = T, COMPLIANT = T, HELD = T, KNEELING = T, VEHICLE = T } },
    { key = 'execute',        icon = 'skull',             from = { THREATENED = T, COMPLIANT = T, HELD = T, KNEELING = T }, enabled = function() return Config.Execute.enabled end, danger = true },
}

local function describe(h)
    local text = Lang.states[h.state] or h.state
    if h.state == 'COMPLIANT' or h.state == 'THREATENED' then
        if h.mode and Lang.modes[h.mode] then text = text .. ' · ' .. Lang.modes[h.mode] end
    end
    local ped = Utils.EntityFromNet(h.netId)
    if ped ~= 0 then
        text = text .. ' · ' .. Lang.menu.distance:format(#(GetEntityCoords(ped) - GetEntityCoords(cache.ped)))
    else
        text = text .. ' · ' .. Lang.menu.notNearby
    end
    return text
end

function Menu.OpenHostage(netId)
    local h = MyHostages[netId]
    if not h then return Utils.Error('not_your_hostage') end

    local options = {}
    for _, a in ipairs(ACTIONS) do
        if a.from[h.state] and (not a.enabled or a.enabled()) and not (a.hideMode and h.mode == a.hideMode and h.state == 'COMPLIANT') then
            options[#options + 1] = {
                title = Lang.actions[a.key] or a.key,
                icon = a.icon,
                iconColor = a.danger and '#e03131' or nil,
                onSelect = function() Client.Action(netId, a.key) end,
            }
        end
    end

    lib.registerContext({
        id = 'mozzy_hostage_one',
        title = ('%s — %s'):format(h.label or ('#' .. netId), Lang.states[h.state] or h.state),
        menu = 'mozzy_hostage_main',
        options = options,
    })
    lib.showContext('mozzy_hostage_one')
end

function Menu.OpenMain()
    local options = {}
    local list = {}
    for _, h in pairs(MyHostages) do list[#list + 1] = h end
    table.sort(list, function(a, b) return a.netId < b.netId end)

    for _, h in ipairs(list) do
        options[#options + 1] = {
            title = h.label or ('Hostage #' .. h.netId),
            description = describe(h),
            icon = h.state == 'HELD' and 'user-lock' or 'user',
            arrow = true,
            onSelect = function() Menu.OpenHostage(h.netId) end,
        }
    end

    if #options == 0 then
        options[1] = { title = Lang.menu.none, disabled = true, icon = 'circle-info' }
    end

    if Config.Negotiation.enabled and #list > 0 then
        options[#options + 1] = {
            title = Lang.menu.negView,
            description = Lang.menu.negStart,
            icon = 'handshake',
            arrow = true,
            onSelect = function() Negotiation.OpenCriminal() end,
        }
    end

    lib.registerContext({ id = 'mozzy_hostage_main', title = Lang.menu.title, options = options })
    lib.showContext('mozzy_hostage_main')
end

lib.addKeybind({
    name = 'mozzy_hostage_menu',
    description = 'Open hostage command menu',
    defaultKey = Config.Keybinds.menu,
    onPressed = function()
        if next(MyHostages) then Menu.OpenMain() end
    end,
})

RegisterCommand(Config.MenuCommand, function() Menu.OpenMain() end, false)
