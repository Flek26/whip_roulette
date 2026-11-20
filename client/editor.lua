-- ============================================
-- whip_roulette — client: /rledit, the layout editor
-- ============================================
--
-- At a table: put three chips on the middles of the board's numbers 1, 3 and 34, and every bet's place on the felt
-- follows (the whole board is drawn as you go, so you can see it line up with the printed one). Set where the dealer
-- stands, and which chair each seat is. Enter saves it for the table's model (Shift+Enter: every model).
-- Saving needs whip.devtools.

local SEATS = 4
local E = nil   -- { L, items, sel, data, ghosts, dirty, hint, warnExit }
local MARK_MODEL = 'vw_prop_chip_500dollar_st'

local function buildItems()
    local list = {
        { kind = 'mark', name = 'n1',  label = 'Board: the middle of number 1' },
        { kind = 'mark', name = 'n3',  label = 'Board: the middle of number 3' },
        { kind = 'mark', name = 'n34', label = 'Board: the middle of number 34' },
        { kind = 'mark', name = 'doz', label = 'Board: the middle of "1st 12"' },
        { kind = 'mark', name = 'low', label = 'Board: the middle of "1 to 18"' },
        { kind = 'dealer', label = 'Dealer: where he stands' },
    }
    for s = 1, SEATS do list[#list + 1] = { kind = 'chair', s = s, label = ('Seat %d: which chair'):format(s) } end
    return list
end

local function readNow(L)
    local base = GetEntityHeading(L.obj)
    local d = { chairs = {} }
    for s = 1, SEATS do d.chairs[tostring(s)] = RL.chairOf(L, s) end
    for _, n in ipairs({ 'n1', 'n3', 'n34' }) do
        local p = BoardMark(L, n)
        d[n] = { p.x, p.y, p.z, 0.0 }
    end
    -- Not set yet: where the board puts them now (the middles of "1st 12" and "1 to 18").
    local doz, low = BoardMark(L, 'doz') or BoardLocal(L, 2.0, -0.5), BoardMark(L, 'low') or BoardLocal(L, 1.0, -1.5)
    d.doz, d.low = { doz.x, doz.y, doz.z, 0.0 }, { low.x, low.y, low.z, 0.0 }
    local at, heading, lift = DealerSpot(L)
    local lp = RL.toLocal(L, at)
    d.dealer = { lp.x, lp.y, lift, ((heading - base + 540.0) % 360.0) - 180.0 }
    return d
end

local function spotOf(item)
    if item.kind == 'mark' then return E.data[item.name] end
    if item.kind == 'dealer' then return E.data.dealer end
end

-- The board as it stands in the editor (not yet saved): a point in board units, in the world.
local function boardWorld(bx, by)
    local L = E.L
    local function v(n) local t = E.data[n] return vector3(t[1], t[2], t[3]) end
    local p = BoardMath(v('n1'), v('n3'), v('n34'), v('doz'), v('low')).at(bx, by)
    return RL.world(L, p.x, p.y, p.z)
end

local function place(item)
    local L = E.L
    local v = spotOf(item)
    if not v then return end
    if item.kind == 'dealer' then
        if L.dealer and DoesEntityExist(L.dealer) then
            local at = RL.world(L, v[1], v[2], v[3])
            SetEntityCoordsNoOffset(L.dealer, at.x, at.y, at.z, false, false, false)
            SetEntityHeading(L.dealer, (GetEntityHeading(L.obj) + v[4]) % 360.0)
        end
        return
    end
    local ent = E.ghosts[item]
    if ent and DoesEntityExist(ent) then
        local at = RL.world(L, v[1], v[2], v[3])
        SetEntityCoordsNoOffset(ent, at.x, at.y, at.z, false, false, false)
    end
end

local function text3d(p, words, scale, r, g, b)
    SetDrawOrigin(p.x, p.y, p.z, 0)
    SetTextFont(4)
    SetTextScale(0.0, scale or 0.32)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(r or 255, g or 255, b or 255, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(words)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- Every number's middle, and the outside bets, as the board stands now.
local function drawBoard()
    for _, s in ipairs(Wheel.spots) do
        if s.w then
            local bx, by = Wheel.centre(s)
            local p = boardWorld(bx, by)
            local r, g, b = 255, 255, 255
            if s.colour == 'red' then r, g, b = 248, 113, 113 elseif s.colour == 'green' then r, g, b = 74, 222, 128 end
            DrawMarker(28, p.x, p.y, p.z + 0.004, 0, 0, 0, 0, 0, 0, 0.012, 0.012, 0.012, r, g, b, 200, false, false, 2, false, nil, nil, false)
            if s.kind ~= 'straight' or s.key == 'n1' or s.key == 'n3' or s.key == 'n34' or s.key == 'n0' or s.key == 'n00' then
                text3d(vector3(p.x, p.y, p.z + 0.03), s.label, 0.2, r, g, b)
            end
        end
    end
end

local function drawChairs()
    local L = E.L
    local sel = E.items[E.sel]
    for s = 1, SEATS do
        local c = E.data.chairs[tostring(s)] or s
        local p = L.frame.chairs[c]
        local at = RL.world(L, p.x, p.y, p.z)
        local lit = sel.kind == 'chair' and sel.s == s
        DrawMarker(1, at.x, at.y, at.z + 0.02, 0, 0, 0, 0, 0, 0, 0.45, 0.45, 0.04,
            lit and 96 or 255, lit and 165 or 255, lit and 250 or 255, lit and 200 or 90, false, false, 2, false, nil, nil, false)
        text3d(vector3(at.x, at.y, at.z + 1.25), ('Seat %d'):format(s), 0.38, lit and 96 or 255, lit and 165 or 255, lit and 250 or 255)
    end
end

local function drawSelected()
    local L = E.L
    local item = E.items[E.sel]
    local v = spotOf(item)
    local at
    if item.kind == 'chair' then
        local p = L.frame.chairs[E.data.chairs[tostring(item.s)] or item.s]
        at = RL.world(L, p.x, p.y, p.z + 1.0)
    elseif v then
        at = RL.world(L, v[1], v[2], v[3])
        DrawMarker(2, at.x, at.y, at.z + 0.12, 0, 0, 0, 180.0, 0, 0, 0.05, 0.05, 0.05, 96, 165, 250, 220, false, false, 2, false, nil, nil, false)
    end
    if at then
        local words = item.label
        if v then words = words .. ('~n~x %.3f  y %.3f  z %.3f'):format(v[1], v[2], v[3]) end
        text3d(vector3(at.x, at.y, at.z + 0.22), words, 0.3)
    end
end

local function hint()
    local item = E.items[E.sel]
    local moveWord = item.kind == 'chair' and '[Left][Right] Chair'
        or (item.kind == 'dealer' and '[Arrows] Move  |  [Q][E] Turn  |  [PgUp][PgDn] Height' or '[Arrows] Move  |  [PgUp][PgDn] Height')
    local text = ('%s  (%d/%d)  |  [Scroll] Next  |  %s  |  [Shift] Fine  |  [G] Reset  |  [Enter] Save  [Shift+Enter] All tables  |  [Backspace] Exit')
        :format(item.label, E.sel, #E.items, moveWord)
    if text ~= E.hint then
        E.hint = text
        exports.whip_core:ShowText(text, { icon = 'place' })
    end
end

local function held(c) return IsDisabledControlPressed(0, c) end
local function hit(c) return IsDisabledControlJustPressed(0, c) end

local function draftKey(m) return 'rldraft:' .. m end
local function keepDraft() if E then SetResourceKvp(draftKey(E.L.def.model), json.encode(E.data)) end end

local function save(all)
    keepDraft()
    local models = { [E.L.def.model] = true }
    if all then for _, T in ipairs(Config.Tables) do models[T.model] = true end end
    for m in pairs(models) do TriggerServerEvent('whip_roulette:saveLayout', m, E.data) end
    E.dirty, E.warnExit = false, false
end

local function stop()
    if not E then return end
    if E.dirty then keepDraft() end
    for _, ent in pairs(E.ghosts) do RL.gone(ent) end
    local L = E.L
    E = nil
    exports.whip_core:HideText()
    exports.whip_core:UnblockControls('whip_roulette_edit')
    if Live[L.id] == L then RL.refresh(L) end
end

local function frame()
    local L = E.L
    if Live[L.id] ~= L then return stop() end
    local fine = held(21)
    local dt = GetFrameTime()
    if hit(15) then E.sel = ((E.sel - 2) % #E.items) + 1 elseif hit(14) then E.sel = (E.sel % #E.items) + 1 end
    local item = E.items[E.sel]

    if item.kind == 'chair' then
        local dir = hit(174) and -1 or (hit(175) and 1 or 0)
        if dir ~= 0 then
            local key = tostring(item.s)
            local old = E.data.chairs[key] or item.s
            local new = ((old - 1 + dir) % SEATS) + 1
            for k, c in pairs(E.data.chairs) do if c == new then E.data.chairs[k] = old end end
            E.data.chairs[key] = new
            E.dirty = true
        end
    else
        local v = spotOf(item)
        local a = math.rad(GetGameplayCamRot(2).z - GetEntityHeading(L.obj))
        local fx, fy, rx, ry = -math.sin(a), math.cos(a), math.cos(a), math.sin(a)
        local speed = (fine and 0.02 or 0.2) * dt
        local mf = (held(172) and 1 or 0) - (held(173) and 1 or 0)
        local mr = (held(175) and 1 or 0) - (held(174) and 1 or 0)
        local turn = item.kind == 'dealer' and ((held(44) and 1 or 0) - (held(38) and 1 or 0)) or 0
        local up = (held(10) and 1 or 0) - (held(11) and 1 or 0)
        if mf ~= 0 or mr ~= 0 or turn ~= 0 or up ~= 0 then
            v[1] = v[1] + (fx * mf + rx * mr) * speed
            v[2] = v[2] + (fy * mf + ry * mr) * speed
            v[3] = v[3] + up * (fine and 0.01 or 0.1) * dt
            v[4] = ((v[4] + turn * (fine and 10.0 or 60.0) * dt + 540.0) % 360.0) - 180.0
            place(item)
            E.dirty = true
        end
        if hit(47) then
            local now = readNow(L)
            if item.kind == 'mark' then E.data[item.name] = now[item.name] else E.data.dealer = now.dealer end
            place(item)
        end
    end

    if hit(191) then save(fine) end
    if hit(194) then
        if E.dirty and not E.warnExit then
            E.warnExit = true
            exports.whip_core:Notify('Not saved: Backspace again to leave without saving, Enter to save', 'error')
        else
            return stop()
        end
    end

    drawBoard()
    drawChairs()
    drawSelected()
    hint()
end

RegisterCommand('rledit', function()
    if E then return stop() end
    local here = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, L in pairs(Live) do
        local d = #(here - GetEntityCoords(L.obj))
        if d < 6.0 and (not bestD or d < bestD) then best, bestD = L, d end
    end
    if not best then return exports.whip_core:Notify('Stand at a roulette table first', 'error') end
    if Seated then return exports.whip_core:Notify('Get up first', 'error') end

    E = { L = best, items = buildItems(), sel = 1, ghosts = {}, dirty = false }
    E.data = readNow(best)
    local raw = GetResourceKvpString(draftKey(best.def.model))
    if raw then
        local ok, draft = pcall(json.decode, raw)
        if ok and type(draft) == 'table' then
            for _, k in ipairs({ 'n1', 'n3', 'n34', 'doz', 'low', 'dealer' }) do if draft[k] then E.data[k] = draft[k] end end
            for k, v in pairs(draft.chairs or {}) do E.data.chairs[k] = v end
            exports.whip_core:Notify('Your last edit is back. Enter saves it.', 'inform')
        end
    end
    for _, item in ipairs(E.items) do
        if item.kind == 'mark' then
            local v = spotOf(item)
            E.ghosts[item] = RL.makeProp(best, MARK_MODEL, RL.world(best, v[1], v[2], v[3]), GetEntityHeading(best.obj))
        end
    end
    exports.whip_core:BlockControls('whip_roulette_edit', {
        all = true, except = { 0, 1, 2, 30, 31, 32, 33, 34, 35, 199, 200, 245, 249 }, mode = true,
    })
    CreateThread(function()
        while E do
            frame()
            Wait(0)
        end
    end)
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and E then
        for _, ent in pairs(E.ghosts) do RL.gone(ent) end
    end
end)
