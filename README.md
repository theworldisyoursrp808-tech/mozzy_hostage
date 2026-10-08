[README.md](https://github.com/user-attachments/files/33191586/README.md)
# Mozzy NPC Hostage System (`mozzy_hostage`)

NPC hostage, negotiation and robbery-integration system for **Qbox / QBX Core**.

## Requirements
- OneSync (Infinity) – Lua 5.4
- `qbx_core`, `ox_lib`, `ox_target`
- `ox_inventory` (recommended – used server-side to verify the weapon is loaded)
- Optional dispatch: `lb-tablet`, `ps-dispatch`, `cd_dispatch` (auto-detected), or the built-in fallback

## Install
1. Drop `mozzy_hostage` in your resources folder.
2. `ensure mozzy_hostage` **after** `qbx_core`, `ox_lib`, `ox_target`, `ox_inventory` and your dispatch resource.
3. Tweak `config.lua` (all text lives in `shared/lang.lua`).

## How players use it
| Action | How |
|---|---|
| Take hostage | Aim at an NPC and press **G**, or ox_target → *Take Hostage* |
| Command menu | **K** or `/hostages` (lists every hostage you control) |
| Quick grab | ox_target → *Grab Hostage* on a compliant/kneeling hostage |
| While holding | **RMB** aim (human shield) · **R** reload · **E** let go · **X** push away · **H** execute (walk-only, no hip-fire) |
| Police | ox_target → *Secure Civilian* (captor must be 8m+ away) · `/negotiations` |

All keys are rebindable in *Settings → Key Bindings → FiveM*.

## How it works (sync model)
- **Server is the authority.** Every take/action goes through `lib.callback` and is validated: ownership of the hostage, state transition, distance (server-side coords), weapon in hand + loaded (ox_inventory), cooldowns, rate limits, hostage limits, police counts.
- The server writes a replicated **entity statebag** (`mozzyHostage`) on the NPC. Whichever client network-owns the ped applies the anims/tasks, so every nearby player sees the same thing, and it survives ownership migration (a 2s adoption scan picks up peds that changed owner).
- The captor keeps network ownership while holding (`SetNetworkIdCanMigrate(false)`), and the server sets `SetEntityOrphanMode(2)` so the NPC isn't culled mid-scene. Both are reverted on release.
- Escape chances are rolled **on the server** every `Config.Escape.interval` seconds using server-known data (distances, captor's selected weapon, captor in vehicle, nearby on-duty cops) plus an "aiming" flag the client reports through a player statebag.

### States
`FREE → THREATENED → COMPLIANT (modes: handsup / stay / follow / cower / cry / moveto) ⇄ HELD ⇄ KNEELING → VEHICLE → RELEASED / ESCAPED / DEAD`

Transitions are enforced by `MH.Transitions` in `shared/states.lua`. Terminal records linger for `Config.Cleanup.linger` seconds so other scripts can still ask "was this hostage released?".

### Cleanup handled
Captor disconnects, logs out, dies/goes into last stand, NPC dies (owner-reported + server health), NPC despawns, escape, resource restart (statebags cleared, peds handed back, ox_target options removed).

## Limitations worth knowing
- **Line-of-sight** and **"is this a human"** are checked client-side (the server has no raycast or ped-type natives). The server still checks entity type, player/ped status, population type, blocked models, distance and network ownership, so the worst a cheater gets is taking a hostage they were already standing next to.
- The hold animation is built for one-handed weapons; `Config.Weapons.holdGroups` limits holding to pistols/SMGs by default (rifles can still take and command hostages).
- Script-spawned NPCs (population type 7) are blocked unless you flag them (see below).

## Developer API

### Server exports
```lua
exports.mozzy_hostage:HasHostage(src)                       -- bool
exports.mozzy_hostage:GetPlayerHostages(src)                -- { data, ... }
exports.mozzy_hostage:GetPlayerHostage(src)                 -- entity, data (held one preferred)
exports.mozzy_hostage:CountPlayerHostages(src, { 'HELD' })  -- optional state filter
exports.mozzy_hostage:GetNearbyHostages(coords, radius, { owner = src, states = { 'KNEELING' } })
exports.mozzy_hostage:CountHostagesInArea(coords, radius, owner?)
exports.mozzy_hostage:GetHostage(netIdOrEntity)             -- data table
exports.mozzy_hostage:GetHostageState(netIdOrEntity)        -- 'FREE' if not a hostage
exports.mozzy_hostage:GetHostageOwner(netIdOrEntity)
exports.mozzy_hostage:IsHostage(netIdOrEntity)
exports.mozzy_hostage:IsHostageAlive(netIdOrEntity)
exports.mozzy_hostage:IsHostageReleased(netIdOrEntity)      -- released OR escaped
exports.mozzy_hostage:ReleaseHostage(netIdOrEntity, reason?)
exports.mozzy_hostage:ForceEscape(netIdOrEntity, reason?)
exports.mozzy_hostage:ReleaseAllHostages(src, reason?)
exports.mozzy_hostage:SetHostageState(netIdOrEntity, state, mode?, force?)
exports.mozzy_hostage:RunAction(netIdOrEntity, 'kneel')     -- same validation as the menu
exports.mozzy_hostage:GetEscapeChance(netIdOrEntity)
exports.mozzy_hostage:CreateNegotiation(src, { 'safe_passage', 'no_spikes' }, customText?, label?)
exports.mozzy_hostage:GetNegotiation(id) / GetPlayerNegotiation(src) / CloseNegotiation(id, reason?)
```
Hostage data: `{ netId, entity, owner, state, mode, label, profile, courage, reaction, vehicle, seat, takenAt, alive, released, escaped, reason }`. Network ids are preferred over entity handles.

### Server events (local, `AddEventHandler`)
```lua
'mozzy_hostage:server:hostageTaken'     (src, netId, data)
'mozzy_hostage:server:stateChanged'     (data, oldState, reason)
'mozzy_hostage:server:hostageReleased'  (owner, netId, data, reason)
'mozzy_hostage:server:hostageEscaped'   (owner, netId, data, reason)
'mozzy_hostage:server:hostageKilled'    (owner, netId, data, reason)
'mozzy_hostage:server:hostageRescued'   (officerSrc, owner, netId)
'mozzy_hostage:server:negotiationCreated' / negotiationUpdated / negotiationClosed (negotiation[, reason])
```

### Client exports
```lua
exports.mozzy_hostage:HasHostage()
exports.mozzy_hostage:GetHostages()        -- { { netId, entity, state, mode, label } }
exports.mozzy_hostage:GetHeldHostage()     -- entity, netId
exports.mozzy_hostage:IsPedHostage(ped)
exports.mozzy_hostage:GetHostageState(ped) -- state, rawStatebag
exports.mozzy_hostage:TryTakeHostage(ped)
```

### Allow / protect specific peds
```lua
-- e.g. a store-clerk ped spawned by your robbery script (mission ped)
Entity(clerk).state:set('mozzyHostageAllowed', true, true)
-- protect a quest NPC from ever being taken
Entity(npc).state:set('mozzyHostageBlocked', true, true)
```

### Example: bank robbery that needs 2 hostages near the vault
```lua
local vault = vec3(253.3, 228.4, 101.7)

lib.callback.register('my_bankrobbery:canStartNegotiation', function(src)
    local count = exports.mozzy_hostage:CountHostagesInArea(vault, 25.0, src)
    if count < 2 then return false, ('You need 2 hostages inside (have %d)'):format(count) end
    return true
end)

AddEventHandler('mozzy_hostage:server:hostageKilled', function(owner, netId, data, reason)
    if reason == 'executed' then
        -- e.g. bump heat, lock the vault, notify crew...
    end
end)
```

## Commands
- `/hostages` – command menu
- `/negotiations` – police negotiation board
- `/hostagedebug` – admin: list hostages with live escape chance (set `Config.Debug = true` for 3D state text)
