MH = MH or {}

MH.StateKey = 'mozzyHostage'          -- entity statebag (replicated)
MH.AllowKey = 'mozzyHostageAllowed'   -- other scripts can set true on mission peds to allow them
MH.BlockKey = 'mozzyHostageBlocked'   -- other scripts can set true to protect a ped

MH.States = {
    FREE = 'FREE',
    THREATENED = 'THREATENED',
    COMPLIANT = 'COMPLIANT',
    HELD = 'HELD',
    KNEELING = 'KNEELING',
    VEHICLE = 'VEHICLE',
    RELEASED = 'RELEASED',
    ESCAPED = 'ESCAPED',
    DEAD = 'DEAD',
}

MH.Active = { THREATENED = true, COMPLIANT = true, HELD = true, KNEELING = true, VEHICLE = true }
MH.Terminal = { RELEASED = true, ESCAPED = true, DEAD = true }

local T = true
MH.Transitions = {
    FREE       = { THREATENED = T },
    THREATENED = { THREATENED = T, COMPLIANT = T, RELEASED = T, ESCAPED = T, DEAD = T },
    COMPLIANT  = { COMPLIANT = T, HELD = T, KNEELING = T, VEHICLE = T, RELEASED = T, ESCAPED = T, DEAD = T },
    HELD       = { COMPLIANT = T, KNEELING = T, VEHICLE = T, RELEASED = T, ESCAPED = T, DEAD = T },
    KNEELING   = { COMPLIANT = T, HELD = T, VEHICLE = T, RELEASED = T, ESCAPED = T, DEAD = T },
    VEHICLE    = { COMPLIANT = T, RELEASED = T, ESCAPED = T, DEAD = T },
    RELEASED   = {},
    ESCAPED    = {},
    DEAD       = {},
}

function MH.CanTransition(from, to)
    local t = MH.Transitions[from or 'FREE']
    return t ~= nil and t[to] == true
end

-- Signed 32-bit normalisation so hashes compare equally on client/server
function MH.Hash(value)
    local h = type(value) == 'string' and joaat(value) or value
    if not h then return 0 end
    h = math.tointeger(h) or 0
    h = h & 0xFFFFFFFF
    if h > 0x7FFFFFFF then h = h - 0x100000000 end
    return h
end

function MH.HashSet(list)
    local set = {}
    for _, v in ipairs(list or {}) do set[MH.Hash(v)] = true end
    return set
end
