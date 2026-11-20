-- ============================================
-- whip_roulette — server: tables, seats, bets, the spin, paying
-- ============================================
--
-- The server takes the bets, picks the pocket and pays. Games near a table are told what to show (fx): chips on
-- the felt, the spin (which pocket the ball ends in, so every game plays the same drop), the sweep. Each seated
-- player is told what's theirs (hud). The pocket is only sent when the spin starts, after the bets have closed.

Tables = {}   -- [id] = T: { id, def, pos, seats, phase, deadline, span, history, look, running }
BySrc  = {}   -- [source] = P: { src, charId, name, table, seat, bets = { [key] = { amount, receipts } }, total, gone, dropped }

local SEATS = 4
local TM = Config.Timing

local function now() return GetGameTimer() end

for id, def in ipairs(Config.Tables) do
    Tables[id] = {
        id = id, def = def, pos = vector3(def.coords.x, def.coords.y, def.coords.z),
        maxTotal = def.maxTotal or def.max * 10,
        seats = {}, phase = 'idle', deadline = 0, span = 0,
        history = {},   -- the last numbers, newest first
        look = { pick = math.random(#Config.Dealers), seed = math.random(1, 2147483646) },
        running = false,
    }
end

-- ============================================
-- Telling games
-- ============================================

function Fx(T, kind, data)
    for _, s in ipairs(Whip.core:GetPlayersInRange(T.pos, Config.SyncRange) or {}) do
        TriggerClientEvent('whip_roulette:fx', s, T.id, kind, data)
    end
end

local function speech(T, line) Fx(T, 'speech', { line = line }) end
local function dealerAnim(T, anim, loop) Fx(T, 'dealer', { anim = anim, loop = loop }) end

local function betsOf(P)
    local out = {}
    for key, b in pairs(P.bets) do out[key] = b.amount end
    return out
end

function Hud(P)
    if P.gone or P.dropped then return end
    local T = Tables[P.table]
    local d = {
        table = T.id, seat = P.seat, label = T.def.label or 'Roulette',
        min = T.def.min, max = T.def.max, maxTotal = T.maxTotal,
        phase = T.phase, bets = betsOf(P), total = P.total,
        history = T.history, result = P.result, net = P.net, won = P.won,
    }
    if T.phase == 'betting' then
        d.endsIn = math.max(0, T.deadline - now())
        d.span = T.span
    end
    TriggerClientEvent('whip_roulette:hud', P.src, d)
end

function HudAll(T)
    for s = 1, SEATS do if T.seats[s] then Hud(T.seats[s]) end end
end

local function snapshot(T)
    local seats, chips = {}, {}
    local function add(P)
        for key, b in pairs(P.bets) do chips[#chips + 1] = { seat = P.seat, key = key, amount = b.amount } end
    end
    for s = 1, SEATS do
        local P = T.seats[s]
        if P then seats[#seats + 1] = { seat = s, src = P.src } add(P) end
    end
    for _, P in pairs(T.inSpin or {}) do if T.seats[P.seat] ~= P then add(P) end end
    -- The table's layout comes with it: a game never draws a table without the saved spots.
    return { seats = seats, chips = chips, look = T.look, history = T.history, layout = LayoutOf(T.def.model) }
end

-- ============================================
-- Money
-- ============================================

local function moneyOpts(reason, P)
    local o = { reason = reason }
    if Config.Money.currency then o.currency = Config.Money.currency end
    if not (P and P.dropped) then o.method = Config.Money.method end
    return o
end

local function charge(P, amount, reason)
    if P.dropped then return false, 'gone' end
    return Whip.core:ChargePlayer(P.src, amount, moneyOpts(reason, P))
end

local function pay(P, amount, reason)
    if amount <= 0 then return true end
    local who = P.dropped and { charId = P.charId } or P.src
    local ok, why = Whip.core:PayPlayer(who, amount, moneyOpts(reason, P))
    if not ok then
        print(('[whip_roulette] CRITICAL: could not pay %s (char %s) %d: %s'):format(P.name, tostring(P.charId), amount, tostring(why)))
    end
    return ok
end

local function refund(receipt)
    if not receipt then return end
    local ok, why = Whip.core:RefundPlayer(receipt)
    if not ok then print(('[whip_roulette] CRITICAL: refund failed: %s'):format(tostring(why))) end
end

--- Takes a bet off the felt and gives its money back. key nil: all of them.
local function giveBack(T, P, key)
    for k, b in pairs(P.bets) do
        if not key or k == key then
            for _, r in ipairs(b.receipts) do refund(r) end
            P.total = P.total - b.amount
            P.bets[k] = nil
            Fx(T, 'chips', { seat = P.seat, key = k, amount = 0 })
        end
    end
end

local function notify(P, msg, kind)
    if P.gone or P.dropped then return end
    Whip.core:NotifyPlayer(P.src, msg, kind or 'inform')
end

-- ============================================
-- The spin
-- ============================================

local function react(P, how)
    if not P.gone then
        TriggerClientEvent('whip_roulette:anim', P.src, 'reaction_' .. how .. '_var_0' .. math.random(1, 4), 'shared')
    end
end

local function settle(T, P, number)
    local staked, back, wins = 0, 0, {}
    for key, b in pairs(P.bets) do
        staked = staked + b.amount
        local s = Wheel.byKey[key]
        if s and s.set[number] then
            back = back + b.amount * (s.pays + 1)
            wins[#wins + 1] = Wheel.name(s)
        end
    end
    if back > 0 then pay(P, back, 'Roulette winnings') end
    P.net, P.won = back - staked, wins
    local colour = Wheel.colour(number)
    local said = ('%s %s'):format(number, colour)
    if P.net > 0 then
        P.result = 'won'
        notify(P, ('%s: you won %s (%s)'):format(said, Wheel.money(P.net), table.concat(wins, ', ')), 'success')
        react(P, P.net >= staked * 5 and 'great' or 'good')
    elseif P.net < 0 then
        P.result = back > 0 and 'some' or 'lost'
        notify(P, back > 0 and ('%s: %s back on %s'):format(said, Wheel.money(back), table.concat(wins, ', '))
            or ('%s: you lost %s'):format(said, Wheel.money(-P.net)), back > 0 and 'inform' or 'error')
        react(P, back > 0 and 'impartial' or (-P.net > 1000 and 'terrible' or 'bad'))
    else
        P.result = 'push'
        notify(P, ('%s: your bets are back'):format(said), 'inform')
        react(P, 'impartial')
    end
    P.bets, P.total = {}, 0
end

local function play(T)
    -- Bets open.
    T.phase = 'betting'
    T.deadline = now() + TM.betSeconds * 1000
    T.span = TM.betSeconds * 1000
    speech(T, 'MINIGAME_DEALER_PLACE_CHIPS')
    HudAll(T)
    while now() < T.deadline do
        Wait(250)
        local any = false
        for s = 1, SEATS do if T.seats[s] and next(T.seats[s].bets) then any = true end end
        if not any then return end   -- everyone took their chips back, or left
    end

    -- No more bets: who's in.
    T.phase = 'spinning'
    T.inSpin = {}
    for s = 1, SEATS do
        local P = T.seats[s]
        if P and next(P.bets) then T.inSpin[s] = P end
    end
    speech(T, 'MINIGAME_DEALER_CLOSED_BETS')
    HudAll(T)

    local pocket = math.random(#Config.Pockets)
    local number = Config.Pockets[pocket]
    T.spinning = { pocket = pocket, at = now() }
    dealerAnim(T, 'spin_wheel')
    Fx(T, 'spin', { pocket = pocket })
    -- Nothing is told until the ball is at rest. The seated players' games say how long their spin runs (the
    -- casino's own animations, so it's the same in each); spinMs only if none says.
    local started = now()
    Wait(1500)
    while now() < started + (T.spinning.length or TM.spinMs) + 500 do Wait(100) end
    T.spinning = nil

    table.insert(T.history, 1, number)
    while #T.history > 12 do table.remove(T.history) end
    Fx(T, 'result', { number = number, colour = Wheel.colour(number) })
    T.phase = 'payout'
    for _, P in pairs(T.inSpin) do settle(T, P, number) end
    HudAll(T)
    Wait(1500)

    -- The sweep.
    dealerAnim(T, 'clear_chips_intro')
    Wait(800)
    Fx(T, 'clear', {})
    Wait(math.max(0, TM.clearMs - 800))
end

function StartRound(T)
    if T.running then return end
    T.running = true
    CreateThread(function()
        local ok, err = pcall(play, T)
        if not ok then
            print(('[whip_roulette] table %d: the spin failed: %s'):format(T.id, tostring(err)))
            for _, P in pairs(T.inSpin or {}) do giveBack(T, P) end
            Fx(T, 'clear', {})
        end
        T.inSpin, T.spinning = nil, nil
        T.phase = 'idle'
        T.running = false
        dealerAnim(T, 'idle')
        HudAll(T)
        for s = 1, SEATS do
            local P = T.seats[s]
            if P and next(P.bets) then StartRound(T) break end
        end
    end)
end

-- ============================================
-- Seats and bets
-- ============================================

local function greet(T, P)
    local model = GetEntityModel(GetPlayerPed(P.src))
    local lines = { 'MINIGAME_DEALER_GREET' }
    if model == `mp_f_freemode_01` then lines[2] = 'MINIGAME_DEALER_GREET_FEMALE'
    elseif model == `mp_m_freemode_01` then lines[2] = 'MINIGAME_DEALER_GREET_MALE' end
    speech(T, lines[math.random(#lines)])
end

local function sit(src, player, tableId, seat)
    local T = Tables[tableId]
    if not T then return false, 'No such table' end
    if BySrc[src] then return false, 'You are already at a table' end
    if #(GetEntityCoords(GetPlayerPed(src)) - T.pos) > 3.5 then return false, 'Too far from the table' end
    if T.seats[seat] then return false, 'Someone is sitting there' end
    if T.inSpin and T.inSpin[seat] then return false, 'That seat is still in the spin, wait for it to finish' end
    local P = {
        src = src, charId = player.charId, name = player.fullName or GetPlayerName(src),
        table = tableId, seat = seat, bets = {}, total = 0,
    }
    T.seats[seat], BySrc[src] = P, P
    Fx(T, 'seat', { seat = seat, src = src })
    greet(T, P)
    CreateThread(function() Wait(250) Hud(P) end)
    return { seat = seat }
end

--- Off the table. Bets not yet spun on go back; bets on a spin already going are settled with everyone's.
local function leave(P, why)
    local T = Tables[P.table]
    if not T or T.seats[P.seat] ~= P then return end
    T.seats[P.seat] = nil
    BySrc[P.src] = nil
    if T.inSpin and T.inSpin[P.seat] == P then
        P.gone = true
    else
        giveBack(T, P)
    end
    Fx(T, 'seat', { seat = P.seat, src = false })
    speech(T, P.result == 'won' and 'MINIGAME_DEALER_LEAVE_GOOD_GAME'
        or (P.result == 'lost' and 'MINIGAME_DEALER_LEAVE_BAD_GAME' or 'MINIGAME_DEALER_LEAVE_NEUTRAL_GAME'))
    if not P.dropped and why ~= 'asked' then TriggerClientEvent('whip_roulette:stand', P.src) end
end

local function open(T) return T.phase == 'idle' or T.phase == 'betting' end

local function bet(src, key, amount)
    local P = BySrc[src]
    if not P then return false, 'You are not at a table' end
    local T = Tables[P.table]
    local s = Wheel.byKey[key]
    if not s then return false, 'No such bet' end
    if not open(T) then return false, 'No more bets' end
    local on = P.bets[key] and P.bets[key].amount or 0
    if on + amount < T.def.min then return false, ('A bet here is at least %s'):format(Wheel.money(T.def.min)) end
    if on + amount > T.def.max then return false, ('At most %s on one bet'):format(Wheel.money(T.def.max)) end
    if P.total + amount > T.maxTotal then return false, ('At most %s on one spin'):format(Wheel.money(T.maxTotal)) end

    local receipt, why = charge(P, amount, 'Roulette bet')
    if not receipt then return false, why end
    if not open(T) or T.seats[P.seat] ~= P then
        refund(receipt)
        return false, 'No more bets'
    end
    local b = P.bets[key] or { amount = 0, receipts = {} }
    b.amount = b.amount + amount
    b.receipts[#b.receipts + 1] = receipt
    P.bets[key] = b
    P.total = P.total + amount
    P.result, P.net, P.won = nil, nil, nil
    TriggerClientEvent('whip_roulette:anim', src, 'place_bet_small', 'bet')
    Fx(T, 'chips', { seat = P.seat, key = key, amount = b.amount })
    StartRound(T)
    Hud(P)
    return true
end

local function unbet(src, key)
    local P = BySrc[src]
    if not P then return end
    local T = Tables[P.table]
    if not open(T) then return end
    giveBack(T, P, key ~= 'all' and key or nil)   -- 'all': every bet
    Hud(P)
end

Whip.register(function()
    Whip.core:SecureCallback('whip_roulette:sit', {
        rateLimit = 1000, params = { { 'table', 'id', 1, #Config.Tables }, { 'seat', 'id', 1, SEATS } },
    }, sit)

    Whip.core:SecureCallback('whip_roulette:snapshot', {
        rateLimit = 500, burst = 6, params = { { 'table', 'id', 1, #Config.Tables } },
    }, function(_, _, tableId) return snapshot(Tables[tableId]) end)

    -- A chip on a spot: answered, so the board can say why not straight away.
    Whip.core:SecureCallback('whip_roulette:bet', {
        rateLimit = 120, burst = 10, params = { { 'key', 'key', 12 }, { 'amount', 'amount', 100000000 } },
    }, function(source, _, key, amount) return bet(source, key, amount) end)

    Whip.core:SecureEvent('whip_roulette:unbet', {
        rateLimit = 150, burst = 10, params = { { 'key', 'key', 12 } },
    }, function(source, _, key) unbet(source, key) end)

    -- How long the spin runs in a seated player's game. Only from someone at that table, only while it spins, and
    -- only within sane bounds: the most it can do is hold the result a little.
    Whip.core:SecureEvent('whip_roulette:spinLength', {
        rateLimit = 1000, params = { { 'table', 'id', 1, #Config.Tables }, { 'ms', 'int', 3000, 45000 } },
    }, function(source, _, tableId, ms)
        local P = BySrc[source]
        local T = Tables[tableId]
        if not P or P.table ~= tableId or not T.spinning then return end
        T.spinning.length = math.max(T.spinning.length or 0, ms)
    end)

    Whip.core:SecureEvent('whip_roulette:leave', { rateLimit = 500, whileDead = true }, function(source)
        local P = BySrc[source]
        if P then leave(P, 'asked') end
    end)

    SetTimeout(15000, function()
        local cur = Config.Money.currency
        if cur and not Whip.core:GetItemDef(cur) then
            print(('[whip_roulette] the bets are in "%s", but no such item exists: start whip_blackjack (it has the casino chips and the cashier), or set Config.Money.currency = nil to bet cash.'):format(cur))
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local P = BySrc[source]
    if P then
        P.dropped = true
        leave(P, 'dropped')
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for src, P in pairs(BySrc) do
            local T = Tables[P.table]
            local ped = GetPlayerPed(src)
            if ped == 0 or #(GetEntityCoords(ped) - T.pos) > Config.LeaveDistance + 2.0 or Whip.core:IsPlayerDead(src) == true then
                leave(P, 'away')
            end
        end
    end
end)

-- Stopping mid-spin: every bet still on the felt goes back.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, T in pairs(Tables) do
        local seen = {}
        for s = 1, SEATS do if T.seats[s] then seen[T.seats[s]] = true end end
        for _, P in pairs(T.inSpin or {}) do seen[P] = true end
        for P in pairs(seen) do
            for _, b in pairs(P.bets) do for _, r in ipairs(b.receipts) do refund(r) end end
            P.bets = {}
        end
    end
end)

-- ============================================
-- The layout (/rledit), per table model, in layout.json
-- ============================================
--   { chairs = { ['1'] = chair }, dealer = { x, y, hips, turn }, n1 / n3 / n34 = { x, y, z, 0 } }

local LAYOUT_FILE = 'layout.json'
local Layouts = {}
do
    local raw = LoadResourceFile(GetCurrentResourceName(), LAYOUT_FILE)
    if raw and raw ~= '' then
        local ok, v = pcall(json.decode, raw)
        if ok and type(v) == 'table' then Layouts = v
        else print('[whip_roulette] layout.json could not be read: ' .. tostring(v)) end
    end
end

function LayoutOf(model) return Layouts[model] end

local dropped = 0
local function cleanSpot(v)
    if type(v) ~= 'table' then dropped = dropped + 1 return nil end
    local out = {}
    for i = 1, 4 do
        local x = tonumber(v[i])
        local limit = (i == 4) and 720 or 50
        if not x or x ~= x or math.abs(x) > limit then dropped = dropped + 1 return nil end
        out[i] = math.floor(x * 10000 + 0.5) / 10000
    end
    return out
end

local function cleanLayout(d)
    if type(d) ~= 'table' then return nil end
    local out = { chairs = {} }
    for k, v in pairs(type(d.chairs) == 'table' and d.chairs or {}) do
        local s, c = tonumber(k), tonumber(v)
        if s and c and s >= 1 and s <= SEATS and c >= 1 and c <= SEATS then out.chairs[tostring(s)] = math.floor(c) end
    end
    for _, k in ipairs({ 'dealer', 'n1', 'n3', 'n34' }) do out[k] = cleanSpot(d[k]) end
    for _, k in ipairs({ 'doz', 'low' }) do if d[k] ~= nil then out[k] = cleanSpot(d[k]) end end
    return out
end

Whip.register(function()
    Whip.core:SecureCallback('whip_roulette:layouts', { rateLimit = 2000, requirePlayer = false }, function() return Layouts end)

    Whip.core:SecureEvent('whip_roulette:saveLayout', {
        rateLimit = 2000, params = { { 'model', 'key', 64 }, { 'data', 'any' } },
    }, function(source, _, model, data)
        if not IsPlayerAceAllowed(source, 'whip.devtools') then return false, 'Dev only' end
        local known = false
        for _, def in ipairs(Config.Tables) do if def.model == model then known = true break end end
        if not known then return false, 'No table uses that model' end
        dropped = 0
        local clean = cleanLayout(data)
        if not clean then return false, 'Bad layout' end
        if dropped > 0 then Whip.core:NotifyPlayer(source, ('%d spot(s) were not valid and were not saved'):format(dropped), 'error') end
        Layouts[model] = clean
        SaveResourceFile(GetCurrentResourceName(), LAYOUT_FILE, json.encode(Layouts, { indent = true }), -1)
        TriggerClientEvent('whip_roulette:layout', -1, model, clean)
        print(('[whip_roulette] %s saved the layout for %s'):format(GetPlayerName(source), model))
        Whip.core:NotifyPlayer(source, 'Layout saved for every ' .. model, 'success')
    end)
end)

local function suggestions(src)
    if not IsPlayerAceAllowed(src, 'whip.devtools') then return end
    TriggerClientEvent('chat:addSuggestions', src, {
        { name = '/rledit', help = 'Roulette: set the board, dealer and chairs at the table you stand at' },
        { name = '/rlspin', help = 'Roulette: spin the nearest wheel here only, to check where pockets land', params = { { name = 'pocket', help = '1-38, or empty for a random one' } } },
    })
end
AddEventHandler('whip_core:player:loaded', function(e) if type(e) == 'table' and e.source then suggestions(e.source) end end)
CreateThread(function() for _, s in ipairs(GetPlayers()) do suggestions(tonumber(s)) end end)

Whip.sayStarted()
