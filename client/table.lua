-- ============================================
-- whip_roulette — client: the tables as this game draws them
-- ============================================
--
-- Every table near you is drawn here, in this game only: its dealer, the chips on the felt, the ball. The server
-- sends what happens (fx) and this game shows it, so nothing is networked and every game agrees. The spin is the
-- casino's own: the wheel and ball animations on the table, ending in the pocket the server picked.
--
-- The board on the felt is placed by where three of its numbers are (1, 3 and 34: /rledit sets them), and every
-- bet's chips go where that bet is on it.

local DICT = {
    dealer = 'anim_casino_b@amb@casino@games@roulette@dealer',
    shared = 'anim_casino_b@amb@casino@games@shared@dealer@',
}
local FEMALE = {
    dealer = 'anim_casino_b@amb@casino@games@roulette@dealer_female',
    shared = 'anim_casino_b@amb@casino@games@shared@dealer@female',
}
local TABLE_DICT = 'anim_casino_b@amb@casino@games@roulette@table'
local BALL_MODEL = 'vw_prop_roulette_ball'
local SEATS = 4
local LY = Config.Layout

Live = {}      -- [tableId] = L: { id, def, obj, owned, dealer, voice, dicts, frame, model, chips, ball, ready, queue }
Layouts = {}   -- [model] = the saved layout (/rledit)

-- ============================================
-- The table's frame
-- ============================================

local function norm(x, y)
    local l = math.sqrt(x * x + y * y)
    if l < 0.0001 then return 0.0, 1.0, 0.0 end
    return x / l, y / l, l
end

local function buildFrame(L)
    local obj = L.obj
    local chairs, bones, mx, my = {}, {}, 0.0, 0.0
    for c = 1, SEATS do
        local idx = GetEntityBoneIndexByName(obj, ('Chair_Base_0%d'):format(c))
        local lp
        if idx ~= -1 then
            bones[c] = idx
            lp = GetOffsetFromEntityGivenWorldCoords(obj, GetWorldPositionOfEntityBone(obj, idx))
        else
            local a = math.rad(-60 + (c - 1) * 40)
            lp = vector3(math.sin(a) * 1.05, -math.cos(a) * 1.05, 0.0)
        end
        chairs[c] = lp
        mx, my = mx + lp.x, my + lp.y
    end
    local dx, dy = norm(-mx, -my)
    L.frame = { chairs = chairs, bones = bones, dx = dx, dy = dy }
    if not next(bones) then print(('[whip_roulette] table %d: no chair bones on its model, seats are guessed'):format(L.id)) end
end

local function lay(L) return Layouts[L.def.model] end

local function chairOf(L, s)
    local t = lay(L)
    if t and t.chairs and t.chairs[tostring(s)] then return t.chairs[tostring(s)] end
    return s
end

local boneRotation = GetEntityBoneRotation or GetWorldRotationOfEntityBone

local function world(L, x, y, z) return GetOffsetFromEntityInWorldCoords(L.obj, x, y, z) end
local function toLocal(L, p) return GetOffsetFromEntityGivenWorldCoords(L.obj, p.x, p.y, p.z) end
local function headingOf(L, dx, dy) return (GetEntityHeading(L.obj) + math.deg(math.atan(-dx, dy))) % 360.0 end

--- One of the board's marks in the table's frame: n1, n3, n34 (the middles of those numbers), doz and low (the
--- middles of "1st 12" and "1 to 18"). nil for doz / low when neither the layout nor the config has them.
function BoardMark(L, name)
    local t = lay(L)
    local v = t and t[name]
    if v then return vector3(v[1], v[2], v[3]) end
    return LY.board[name]
end

-- Below the numbers, the felt's two strips (the dozens, then 1-18 / Even / Red ...) are narrower than a number.
-- Board units keep them a row deep each (y 0 to -1, -1 to -2: shared/wheel.lua); on the felt they're dz and ev rows.
local function warp(by, dz, ev)
    if by >= 0 then return by end
    if by >= -1 then return by * dz end
    return -dz + (by + 1) * ev
end

local function unwarp(fy, dz, ev)
    if fy >= 0 then return fy end
    if fy >= -dz then return fy / dz end
    return -1 + (fy + dz) / ev
end

--- The board's sums from its marks (vector3s in the table's frame; doz and low may be nil):
--- at(bx, by) -> a point in the table's frame; from(point) -> bx, by (or nil).
function BoardMath(p1, p3, p34, doz, low)
    local u = (p34 - p1) / 11.0     -- one column along
    local v = (p3 - p1) / 2.0       -- one row up
    local o = p1 - u * 0.5 - v * 0.5
    local det = u.x * v.y - u.y * v.x
    local function raw(p)
        if math.abs(det) < 1e-9 then return nil end
        local dx, dy = p.x - o.x, p.y - o.y
        return (dx * v.y - dy * v.x) / det, (u.x * dy - u.y * dx) / det
    end
    local dz, ev = LY.board.dozenRows or 0.55, LY.board.evenRows or 0.55
    if doz then
        local _, y = raw(doz)
        if y and y < -0.05 then dz = -2.0 * y end
    end
    dz = math.max(0.15, dz)
    if low then
        local _, y = raw(low)
        if y and y < -dz - 0.05 then ev = -2.0 * (y + dz) end
    end
    ev = math.max(0.15, ev)
    return {
        at = function(bx, by) return o + u * bx + v * warp(by, dz, ev) end,
        from = function(p)
            local x, y = raw(p)
            if not x then return nil end
            return x, unwarp(y, dz, ev)
        end,
    }
end

local function boardOf(L)
    return BoardMath(BoardMark(L, 'n1'), BoardMark(L, 'n3'), BoardMark(L, 'n34'), BoardMark(L, 'doz'), BoardMark(L, 'low'))
end

--- A point on the board (in board units: see shared/wheel.lua) in the table's frame.
function BoardLocal(L, bx, by) return boardOf(L).at(bx, by) end

--- The same, in the world.
function BoardWorld(L, bx, by)
    local p = BoardLocal(L, bx, by)
    return world(L, p.x, p.y, p.z)
end

--- A point in the world (on the felt) as board units, or nil.
function BoardAt(L, p) return boardOf(L).from(toLocal(L, p)) end

function DealerSpot(L)
    local t = lay(L)
    if t and t.dealer then
        local d = t.dealer
        return world(L, d[1], d[2], 0.0), (GetEntityHeading(L.obj) + d[4]) % 360.0, d[3]
    end
    local f = L.frame
    return world(L, f.dx * LY.dealerStand, f.dy * LY.dealerStand, 0.0), headingOf(L, -f.dx, -f.dy), LY.dealerLift
end

function ChairSpot(L, s)
    local c = chairOf(L, s)
    local p = L.frame.chairs[c]
    local at = world(L, p.x, p.y, p.z)
    local idx = L.frame.bones[c]
    local bone = (idx and boneRotation) and boneRotation(L.obj, idx) or nil
    local heading
    if bone then heading = bone.z
    else
        local d = DealerSpot(L)
        heading = GetHeadingFromVector_2d(d.x - at.x, d.y - at.y)
    end
    return at, (heading + LY.seatTurn) % 360.0
end

--- What the seated camera looks at: the middle of the board.
function FeltMiddle(L)
    local p = BoardLocal(L, 6.0, 0.5)
    return world(L, p.x, p.y, p.z)
end

-- ============================================
-- Props
-- ============================================

local function model(name) return exports.whip_core:LoadModel(name) end

local function intoRoom(L, ent)
    local interior = GetInteriorFromEntity(L.obj)
    if interior ~= 0 then ForceRoomForEntity(ent, interior, GetRoomKeyFromEntity(L.obj)) end
end

local function makeProp(L, name, at, heading)
    local hash = model(name)
    if not hash then return nil end
    local ent = CreateObject(hash, at.x, at.y, at.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    intoRoom(L, ent)
    SetEntityCollision(ent, false, false)
    FreezeEntityPosition(ent, true)
    SetEntityRotation(ent, 0.0, 0.0, heading or 0.0, 2, true)
    return ent
end

local function gone(ent)
    if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
end

-- ============================================
-- Chips
-- ============================================
-- L.chips['seat:key'] = { ents }. A stack sits in the middle of its bet; only when two or more players are on the same
-- bet do their stacks move apart (along the columns), so each is seen.

local function stack(L, s, key, amount)
    local id = s .. ':' .. key
    for _, e in ipairs(L.chips[id] or {}) do gone(e) end
    L.chips[id] = nil
    if not amount or amount <= 0 then return end
    local spot = Wheel.byKey[key]
    if not spot then return end
    local bx, by = Wheel.centre(spot)
    local on, mine = 0, 0
    for k = 1, SEATS do
        if L.model.chips[k .. ':' .. key] then
            on = on + 1
            if k == s then mine = on end
        end
    end
    local nudge = on > 1 and (mine - (on + 1) / 2) * 0.3 or 0.0   -- board units
    local p = BoardLocal(L, bx + nudge, by)
    local list = {}
    local n = 0
    for _, st in ipairs(Wheel.chips(amount)) do
        for _ = 1, st.count do
            local e = makeProp(L, st.model, world(L, p.x, p.y, p.z + n * LY.chipHeight), GetEntityHeading(L.obj))
            if e then list[#list + 1] = e end
            n = n + 1
        end
    end
    L.chips[id] = list
end

local function clearChips(L)
    for id, list in pairs(L.chips) do
        for _, e in ipairs(list) do gone(e) end
        L.chips[id] = nil
    end
    L.model.chips = {}
end

local function refresh(L)
    for id, amount in pairs(L.model.chips) do
        local s, key = id:match('^(%d+):(.+)$')
        if s then stack(L, tonumber(s), key, amount) end
    end
    if L.dealer and DoesEntityExist(L.dealer) then
        local at, heading, lift = DealerSpot(L)
        SetEntityCoordsNoOffset(L.dealer, at.x, at.y, at.z + lift, false, false, false)
        SetEntityHeading(L.dealer, heading)
    end
end

Whip.register(function()
    CreateThread(function()
        -- Asked again if the server wasn't ready (both restarting at once).
        for _ = 1, 10 do
            local all = exports.whip_core:Callback('whip_roulette:layouts')
            if type(all) == 'table' then
                for m, data in pairs(all) do Layouts[m] = data end
                for _, L in pairs(Live) do refresh(L) end
                return
            end
            Wait(3000)
        end
    end)
end)

RegisterNetEvent('whip_roulette:layout', function(m, data)
    if type(m) ~= 'string' then return end
    Layouts[m] = type(data) == 'table' and data or nil
    for _, L in pairs(Live) do if L.def.model == m then refresh(L) end end
end)

-- ============================================
-- The spin
-- ============================================

local function animMs(dict, anim) return math.max(400, math.floor(GetAnimDuration(dict, anim) * 1000)) end

--- The ball in, round, and down into `pocket` (1-38), with the wheel turning under it. Played in this game only.
--- report: tell the server how long this spin will take (it holds the result until the ball is at rest).
function Spin(L, pocket, startDelay, turn, report)
    L.spinToken = (L.spinToken or 0) + 1
    local mine = L.spinToken
    CreateThread(function()
        if not exports.whip_core:LoadAnimDict(TABLE_DICT) then return end
        if report then
            local total = (startDelay or 0) + animMs(TABLE_DICT, 'intro_ball')
                + animMs(TABLE_DICT, 'loop_ball') * Config.Timing.loops + animMs(TABLE_DICT, ('exit_%d_ball'):format(pocket))
            TriggerServerEvent('whip_roulette:spinLength', L.id, math.floor(total))
        end
        Wait(startDelay or 0)
        if L.spinToken ~= mine or Live[L.id] ~= L then return end
        gone(L.ball)
        local idx = GetEntityBoneIndexByName(L.obj, LY.ballBone)
        local at = (idx ~= -1) and GetWorldPositionOfEntityBone(L.obj, idx) or GetEntityCoords(L.obj)
        local ball = makeProp(L, BALL_MODEL, at, GetEntityHeading(L.obj) + (turn or LY.ballTurn))
        if not ball then return end
        FreezeEntityPosition(ball, false)
        L.ball = ball
        local startRot = GetEntityRotation(ball, 2)
        local function both(part)
            -- Every clip is made round the same spot: back to it first, or each one carries on from where the
            -- last ended and the ball wanders off the wheel.
            SetEntityCoordsNoOffset(ball, at.x, at.y, at.z, false, false, false)
            SetEntityRotation(ball, startRot.x, startRot.y, startRot.z, 2, true)
            PlayEntityAnim(ball, part .. '_ball', TABLE_DICT, 1000.0, false, true, true, 0, 136704)
            PlayEntityAnim(L.obj, part .. '_wheel', TABLE_DICT, 1000.0, false, true, true, 0, 136704)
            return animMs(TABLE_DICT, part .. '_ball')
        end
        local steps = { 'intro' }
        for _ = 1, Config.Timing.loops do steps[#steps + 1] = 'loop' end
        steps[#steps + 1] = ('exit_%d'):format(pocket)
        for _, part in ipairs(steps) do
            local ms = both(part)
            local t0 = GetGameTimer()
            while GetGameTimer() - t0 < ms - 30 do
                if L.spinToken ~= mine or not DoesEntityExist(ball) then return end
                Wait(0)
            end
        end
    end)
end

-- ============================================
-- The dealer
-- ============================================

local function dictsFor(female)
    local d = { dealer = DICT.dealer, shared = DICT.shared }
    if female then
        for k, name in pairs(FEMALE) do if DoesAnimDictExist(name) then d[k] = name end end
    end
    return d
end

local function playDealer(L, anim, loop)
    local ped = L.dealer
    if not ped or not DoesEntityExist(ped) then return end
    local D = L.dicts or DICT
    L.token = (L.token or 0) + 1
    local mine = L.token
    CreateThread(function()
        local dict = D.dealer
        if anim == 'idle' then loop = true end
        if not exports.whip_core:LoadAnimDict(dict) then return end
        if L.token ~= mine or not DoesEntityExist(ped) then return end
        -- A move this dictionary doesn't have: the shared casino idle instead of standing stiff.
        if GetAnimDuration(dict, anim) <= 0.0 then
            if not loop or not exports.whip_core:LoadAnimDict(D.shared) then return end
            dict, anim = D.shared, 'dealer_idle'
        end
        TaskPlayAnim(ped, dict, anim, 3.0, -3.0, -1, loop and 1 or 0, 0.0, false, false, false)
        if loop then return end
        Wait(math.max(500, animMs(dict, anim) - 150))
        if L.token ~= mine or not DoesEntityExist(ped) then return end
        if GetAnimDuration(dict, 'idle') > 0.0 then
            TaskPlayAnim(ped, dict, 'idle', 3.0, -3.0, -1, 1, 0.0, false, false, false)
        elseif exports.whip_core:LoadAnimDict(D.shared) then
            TaskPlayAnim(ped, D.shared, 'dealer_idle', 3.0, -3.0, -1, 1, 0.0, false, false, false)
        end
    end)
end

local function speak(L, line)
    if L.dealer and DoesEntityExist(L.dealer) then
        PlayPedAmbientSpeechWithVoiceNative(L.dealer, line, L.voice, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR', false)
    end
end

local function seeded(seed)
    local state = (tonumber(seed) or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 48271) % 2147483647
        return (state % n) + 1
    end
end

local function dress(ped, seed)
    SetPedDefaultComponentVariation(ped)
    local roll = seeded(seed)
    for _, c in ipairs({ 0, 2 }) do
        local n = GetNumberOfPedDrawableVariations(ped, c)
        if n > 0 then
            local d = roll(n) - 1
            local t = GetNumberOfPedTextureVariations(ped, c, d)
            SetPedComponentVariation(ped, c, d, t > 0 and (roll(t) - 1) or 0, 0)
        end
    end
    for _, c in ipairs({ 3, 4 }) do
        local d = GetPedDrawableVariation(ped, c)
        local t = GetNumberOfPedTextureVariations(ped, c, d)
        if t > 1 then SetPedComponentVariation(ped, c, d, roll(t) - 1, 0) end
    end
end

local function makeDealer(L, look)
    look = type(look) == 'table' and look or { pick = ((L.id - 1) % #Config.Dealers) + 1, seed = L.id }
    local pick = Config.Dealers[look.pick] or Config.Dealers[1]
    local hash = model(pick.model)
    if not hash then return print(('[whip_roulette] table %d: the dealer model %s would not load'):format(L.id, pick.model)) end
    local at, heading, lift = DealerSpot(L)
    local z = at.z + lift
    local ped = CreatePed(4, hash, at.x, at.y, z, heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return end
    intoRoom(L, ped)
    SetEntityCoordsNoOffset(ped, at.x, at.y, z, false, false, false)
    SetEntityHeading(ped, heading)
    dress(ped, look.seed)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    L.dealer, L.voice = ped, pick.voice
    L.dicts = dictsFor(pick.female)
    playDealer(L, 'idle')
end

-- ============================================
-- What the server says
-- ============================================

local function apply(L, kind, d, live)
    if kind == 'seat' then
        L.model.taken[d.seat] = d.src or nil
    elseif kind == 'chips' then
        L.model.chips[d.seat .. ':' .. d.key] = (d.amount and d.amount > 0) and d.amount or nil
        stack(L, d.seat, d.key, d.amount)
        -- Everyone else on that bet moves over (or back to the middle).
        for k = 1, SEATS do
            local other = L.model.chips[k .. ':' .. d.key]
            if k ~= d.seat and other then stack(L, k, d.key, other) end
        end
    elseif kind == 'spin' then
        if live then Spin(L, d.pocket, Config.Timing.spinStartMs, nil, Seated ~= nil and Seated.table == L.id) end
    elseif kind == 'result' then
        L.model.last = d.number
    elseif kind == 'clear' then
        -- The chips go; the ball stays in its pocket until the next spin takes it out.
        clearChips(L)
    elseif kind == 'dealer' then
        playDealer(L, d.anim, d.loop)
    elseif kind == 'speech' then
        speak(L, d.line)
    end
end

RegisterNetEvent('whip_roulette:fx', function(id, kind, d)
    local L = Live[id]
    if not L or type(d) ~= 'table' then return end
    if not L.ready then
        L.queue[#L.queue + 1] = { kind, d }
        return
    end
    apply(L, kind, d, true)
end)

-- ============================================
-- Near and far
-- ============================================

local function findTable(def)
    if def.spawn then
        local h = model(def.model)
        if not h then return nil end
        local obj = CreateObject(h, def.coords.x, def.coords.y, def.coords.z, false, false, false)
        SetModelAsNoLongerNeeded(h)
        SetEntityHeading(obj, def.heading or 0.0)
        FreezeEntityPosition(obj, true)
        if def.texture then SetObjectTextureVariation(obj, def.texture) end
        return obj, true
    end
    local map = GetClosestObjectOfType(def.coords.x, def.coords.y, def.coords.z, 1.5, joaat(def.model), false, false, false)
    if map == 0 then return nil end
    -- A map's own table can't play animations, so its wheel would never turn. Ours goes in its exact place (the
    -- same model, spot, turn and felt, so the layout still fits), and the map's is hidden while we're near.
    local h = model(def.model)
    if not h then return nil end
    local pos, rot = GetEntityCoords(map), GetEntityRotation(map, 2)
    local felt = GetObjectTextureVariation and GetObjectTextureVariation(map) or nil
    local obj = CreateObjectNoOffset(h, pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(h)
    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    local interior = GetInteriorFromEntity(map)
    if interior ~= 0 then ForceRoomForEntity(obj, interior, GetRoomKeyFromEntity(map)) end
    if def.texture then SetObjectTextureVariation(obj, def.texture)
    elseif felt then SetObjectTextureVariation(obj, felt) end
    SetEntityVisible(map, false, false)
    return obj, true, map
end

local function seatAtChair(L, c)
    for s = 1, SEATS do if chairOf(L, s) == c then return s end end
    return c
end

local function chairPrompts(L)
    for c = 1, SEATS do
        local p = L.frame.chairs[c]
        exports.whip_core:AddAction({
            id = ('roulette_%d_%d'):format(L.id, c),
            group = 'roulette_' .. L.id,
            at = { coords = world(L, p.x, p.y, p.z + 0.85) },
            label = 'Sit down',
            icon = 'dollar',
            reach = 1.6,
            focusMode = 'aim',
            canInteract = function() return Seated == nil and not L.model.taken[seatAtChair(L, c)] end,
            onSelect = function() SitDown(L.id, seatAtChair(L, c)) end,
        })
    end
end

local function goLive(id, def)
    local obj, owned, map = findTable(def)
    if not obj then return end
    local L = {
        id = id, def = def, obj = obj, owned = owned, map = map,
        model = { taken = {}, chips = {} }, chips = {}, ready = false, queue = {},
    }
    Live[id] = L
    buildFrame(L)
    chairPrompts(L)
    local snap = exports.whip_core:Callback('whip_roulette:snapshot', id)
    if Live[id] ~= L then return end
    if type(snap) == 'table' and type(snap.layout) == 'table' then Layouts[def.model] = snap.layout end
    makeDealer(L, type(snap) == 'table' and snap.look or nil)
    if type(snap) == 'table' then
        for _, e in ipairs(snap.seats or {}) do L.model.taken[e.seat] = e.src end
        for _, c in ipairs(snap.chips or {}) do apply(L, 'chips', c, false) end
    end
    L.ready = true
    for _, q in ipairs(L.queue) do apply(L, q[1], q[2], false) end
    L.queue = {}
end

local function goDark(id)
    local L = Live[id]
    if not L then return end
    Live[id] = nil
    exports.whip_core:RemoveActionGroup('roulette_' .. id)
    clearChips(L)
    gone(L.ball)
    gone(L.dealer)
    if L.owned then gone(L.obj) end
    if L.map and DoesEntityExist(L.map) then SetEntityVisible(L.map, true, false) end
end

CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        for id, def in ipairs(Config.Tables) do
            local d = #(here - vector3(def.coords.x, def.coords.y, def.coords.z))
            if d <= Config.DrawRange and not Live[id] then
                goLive(id, def)
            elseif d > Config.DrawRange + 10.0 and Live[id] and not (Seated and Seated.table == id) then
                goDark(id)
            elseif Live[id] and Live[id].map and DoesEntityExist(Live[id].map) then
                -- The map can stream its table back in: kept hidden.
                SetEntityVisible(Live[id].map, false, false)
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(Live) do goDark(id) end
end)

-- /rlspin [1-38] [turn] (dev): spin the nearest wheel in this game only, to check where each pocket lands. turn:
-- try a ballTurn (degrees) for this spin, without restarting.
RegisterCommand('rlspin', function(_, args)
    local here = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, L in pairs(Live) do
        local d = #(here - GetEntityCoords(L.obj))
        if d < 6.0 and (not bestD or d < bestD) then best, bestD = L, d end
    end
    if not best then return exports.whip_core:Notify('Stand at a roulette table first', 'error') end
    local pocket = math.floor(tonumber(args[1]) or math.random(#Config.Pockets))
    if pocket < 1 or pocket > #Config.Pockets then return exports.whip_core:Notify('A pocket from 1 to 38', 'error') end
    local turn = tonumber(args[2])
    -- How long a real spin takes here, from "no more bets" to the ball at rest: Config.Timing.spinMs should be a
    -- little more, or the payout is told before the ball lands.
    local total = Config.Timing.spinStartMs
    if exports.whip_core:LoadAnimDict(TABLE_DICT) then
        total = total + animMs(TABLE_DICT, 'intro_ball') + animMs(TABLE_DICT, 'loop_ball') * Config.Timing.loops
            + animMs(TABLE_DICT, ('exit_%d_ball'):format(pocket))
    end
    exports.whip_core:Notify(('Pocket %d: Config.Pockets says %s%s. A real spin takes %d ms (spinMs is %d)'):format(
        pocket, Config.Pockets[pocket], turn and (', ball turned %.2f'):format(turn) or '', total, Config.Timing.spinMs), 'inform')
    print(('[whip_roulette] spin to pocket %d takes %d ms; Config.Timing.spinMs is %d'):format(pocket, total, Config.Timing.spinMs))
    Spin(best, pocket, 0, turn)
end, false)

-- For client/editor.lua.
RL = { world = world, toLocal = toLocal, makeProp = makeProp, gone = gone, chairOf = chairOf, refresh = refresh }
