-- ============================================
-- whip_roulette — client: playing
-- ============================================
--
-- Sitting down (the casino's own seat animations, as networked scenes at the chair), the keys while seated, the
-- camera, and the panel (html/). Bets go down on the felt itself: Enter brings the camera over the board and a
-- cursor; a chip follows it onto whatever bet it's over, left click puts it down, right click takes yours back.
-- The server takes each chip, and says no when it can't.

local SEAT_DICT = 'anim_casino_b@amb@casino@games@shared@player@'
local BET_DICT = 'anim_casino_b@amb@casino@games@blackjack@player'
local K = Config.Keys

Seated = nil   -- { table, seat, chair, heading, hud, camera, hint, betting }

local function notify(msg, kind) exports.whip_core:Notify(msg, kind or 'inform') end
local function nui(msg) SendNUIMessage(msg) end

-- ============================================
-- The chair
-- ============================================

local function scene(dict, anim, loop)
    local S = Seated
    if not S then return end
    local c = S.chair
    local s = NetworkCreateSynchronisedScene(c.x, c.y, c.z, 0.0, 0.0, S.heading, 2, not loop, loop, 1.0, 0.0, 1.0)
    NetworkAddPedToSynchronisedScene(PlayerPedId(), s, dict, anim, 2.0, -2.0, 13, 16, 1000.0, 0)
    NetworkStartSynchronisedScene(s)
    return s
end

local function idle() if Seated then scene(SEAT_DICT, 'idle_cardgames', true) end end

local animToken = 0
local lastBet = 0
local function seatAnim(anim, dictKey)
    if not Seated then return end
    -- Chips go down a click at a time: the reach once a second at most, not restarted on every click.
    if dictKey == 'bet' then
        if GetGameTimer() - lastBet < 1200 then return end
        lastBet = GetGameTimer()
    end
    local dict = dictKey == 'shared' and SEAT_DICT or BET_DICT
    animToken = animToken + 1
    local mine = animToken
    CreateThread(function()
        if not exports.whip_core:LoadAnimDict(dict) or not Seated then return end
        scene(dict, anim, false)
        Wait(math.max(400, math.floor(GetAnimDuration(dict, anim) * 1000) - 100))
        if animToken == mine then idle() end
    end)
end

RegisterNetEvent('whip_roulette:anim', function(anim, dictKey) seatAnim(anim, dictKey) end)

-- ============================================
-- The cameras
-- ============================================

local function lookAt(pos, at, fov)
    local d = at - pos
    local pitch = math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y)))
    exports.whip_core:PlayCamera({
        pos = pos, rot = vector3(pitch, 0.0, GetHeadingFromVector_2d(d.x, d.y)), fov = fov,
        exitKey = false, async = true, transitionIn = 500, transitionOut = 500,
    })
end

-- Over your shoulder at the board.
local function cameraOn()
    local S = Seated
    local L = S and Live[S.table]
    if not L then return end
    S.wheel = false
    local h = math.rad(S.heading)
    local fx, fy = -math.sin(h), math.cos(h)
    lookAt(vector3(S.chair.x - fx * Config.Camera.back, S.chair.y - fy * Config.Camera.back, S.chair.z + Config.Camera.up),
        FeltMiddle(L), Config.Camera.fov)
    S.camera = true
end

local function cameraOff()
    if Seated and Seated.camera then
        exports.whip_core:StopCamera()
        Seated.camera = false
    end
    if Seated then Seated.wheel = false end
end

-- Over the wheel, looking down into it from the board's side.
local function wheelCamera()
    local S = Seated
    local L = S and Live[S.table]
    if not L then return end
    local idx = GetEntityBoneIndexByName(L.obj, Config.Layout.ballBone)
    local wheel = (idx ~= -1) and GetWorldPositionOfEntityBone(L.obj, idx) or GetEntityCoords(L.obj)
    local mid = FeltMiddle(L)
    local d = vector3(mid.x - wheel.x, mid.y - wheel.y, 0.0)
    d = d / math.max(0.001, #d)
    local W = Config.WheelCamera
    lookAt(vector3(wheel.x + d.x * W.back, wheel.y + d.y * W.back, wheel.z + W.up), wheel, W.fov)
    S.camera, S.wheel = true, true
end

--- Back from the wheel to your usual view.
local function wheelOff()
    local S = Seated
    if not S or not S.wheel then return end
    S.wheel, S.autoWheel = false, false
    if Config.Camera.enabled then cameraOn() else cameraOff() end
end

-- Nearly straight down over the board, squared up with it: the numbers running across the screen (1 towards 34),
-- the dozens strip along the bottom. For putting chips down.
local function boardCamera(L)
    local mid = BoardWorld(L, 6.0, 0.6)
    local rows = BoardWorld(L, 6.0, 1.6) - mid      -- towards the 3-6-9 row: up the screen
    local along = BoardWorld(L, 7.0, 0.6) - mid     -- towards 34: should be right on the screen
    local fwd = vector3(rows.x, rows.y, 0.0)
    fwd = fwd / math.max(0.001, #fwd)
    -- A mirrored board would put 34 on the left: then look the other way (the dozens at the top instead).
    if along.x * fwd.y - along.y * fwd.x < 0.0 then fwd = -fwd end
    local B = Config.BetCamera
    lookAt(vector3(mid.x - fwd.x * B.back, mid.y - fwd.y * B.back, mid.z + B.up), mid, B.fov)
end

-- ============================================
-- Betting on the felt
-- ============================================

local function open(H) return H.phase == nil or H.phase == 'idle' or H.phase == 'betting' end

local function chipValues(T)
    local out = {}
    for _, v in ipairs(Config.ChipValues) do
        if v >= T.min and v <= T.max then out[#out + 1] = v end
    end
    if #out == 0 then out[1] = T.min end
    return out
end

-- Which way a point on the screen (0-1 each way) looks out of the camera being drawn.
local function screenRay(sx, sy)
    local pos, rot, fov = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2), GetFinalRenderedCamFov()
    local p, y = math.rad(rot.x), math.rad(rot.z)
    local fwd = vector3(-math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p))
    local right = vector3(fwd.y, -fwd.x, 0.0)                                   -- fwd x up
    right = right / math.max(0.0001, #right)
    local up = vector3(right.y * fwd.z - right.z * fwd.y, right.z * fwd.x - right.x * fwd.z, right.x * fwd.y - right.y * fwd.x)
    local t = math.tan(math.rad(fov) / 2.0)                                     -- GTA's fov is the vertical one
    local dir = fwd + right * ((sx * 2.0 - 1.0) * t * GetAspectRatio(false)) + up * ((1.0 - sy * 2.0) * t)
    return pos, dir / #dir
end

local function chipModel(value)
    for _, c in ipairs(Config.Chips) do if value >= c[1] then return c[2] end end
    return Config.Chips[#Config.Chips][2]
end

local function placeChip(key, amount)
    CreateThread(function()
        local ok, why = exports.whip_core:Callback('whip_roulette:bet', key, amount)
        if not ok and why then notify(why, 'error') end
    end)
end

--- Betting mode: the camera over the board, a cursor, and a chip that follows it onto the bets.
local function betLoop(S)
    local L = Live[S.table]
    if not L then return end
    local T = Config.Tables[S.table]
    local values = chipValues(T)
    S.chip = math.min(S.chip or 1, #values)
    S.betting = true
    S.wheel, S.autoWheel = false, false
    boardCamera(L)
    local ghost, ghostModel, lastText = nil, nil, nil
    local function dropGhost()
        if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
        ghost, ghostModel = nil, nil
    end

    while Seated == S and S.betting and Live[S.table] == L do
        local H = S.hud or {}
        if not open(H) then break end
        SetMouseCursorActiveThisFrame()
        SetMouseCursorSprite(1)

        -- Scroll: the chip.
        if IsDisabledControlJustPressed(0, 15) then S.chip = math.min(#values, S.chip + 1)
        elseif IsDisabledControlJustPressed(0, 14) then S.chip = math.max(1, S.chip - 1) end
        local value = values[S.chip]

        -- Where the cursor meets the felt, and the bet there.
        local origin, dir = screenRay(GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240))
        local feltZ = BoardWorld(L, 6.0, 0.5).z
        local spot
        if dir.z < -0.01 then
            local hitAt = origin + dir * ((feltZ - origin.z) / dir.z)
            local bx, by = BoardAt(L, hitAt)
            if bx then spot = Wheel.hit(bx, by) end
        end

        -- The chip that follows the cursor.
        if spot then
            local m = chipModel(value)
            if ghostModel ~= m then
                dropGhost()
                ghost = RL.makeProp(L, m, BoardWorld(L, Wheel.centre(spot)), GetEntityHeading(L.obj))
                ghostModel = m
                if ghost then SetEntityAlpha(ghost, 190, false) end
            end
            local bx, by = Wheel.centre(spot)
            local mine = (H.bets or {})[spot.key] or 0
            local at = BoardWorld(L, bx, by)
            local stackTop = #Wheel.chips(mine) * Config.Layout.chipHeight
            if ghost then SetEntityCoordsNoOffset(ghost, at.x, at.y, at.z + stackTop + 0.01, false, false, false) end
            DrawMarker(25, at.x, at.y, at.z + 0.002, 0, 0, 0, 0, 0, 0, 0.07, 0.07, 0.07, 255, 255, 255, 150, false, false, 2, false, nil, nil, false)

            if IsDisabledControlJustPressed(0, 24) then placeChip(spot.key, value) end
            if IsDisabledControlJustPressed(0, 25) and mine > 0 then TriggerServerEvent('whip_roulette:unbet', spot.key) end
        elseif ghost then
            dropGhost()
        end

        local text = ('%s  |  [LMB] Chip %s  |  [RMB] Take back  |  [Scroll] Chip  |  [Backspace] Done'):format(
            spot and ('%s (%d to 1)%s'):format(Wheel.name(spot), spot.pays,
                ((H.bets or {})[spot.key] or 0) > 0 and (', yours ' .. Wheel.money(H.bets[spot.key])) or '')
                or 'Point at a bet', Wheel.money(value))
        if text ~= lastText then
            lastText = text
            exports.whip_core:ShowText(text, { icon = 'dollar' })
        end

        if IsDisabledControlJustPressed(0, K.leave.key) or IsDisabledControlJustPressed(0, K.leave.pad) then break end
        Wait(0)
    end

    dropGhost()
    if Seated == S then
        S.betting = false
        S.hint = nil
        if S.wantWheel or (Config.WheelCamera.auto and (S.hud or {}).phase == 'spinning') then
            -- The bets closed while putting chips down: straight to the wheel.
            S.wantWheel = false
            wheelCamera()
            S.autoWheel = true
        elseif Config.Camera.enabled then cameraOn()
        else exports.whip_core:StopCamera() S.camera = false end
    end
end

-- ============================================
-- What the keys say
-- ============================================

local function key(k) return exports.whip_core:KeyHint(k.text, k.button) end

local function refreshHint()
    local S = Seated
    if not S or S.betting then return end
    local H = S.hud or {}
    local parts = {}
    if open(H) then parts[#parts + 1] = key(K.board) .. ' Place chips' end
    parts[#parts + 1] = key(K.wheel) .. (S.wheel and ' Back to the table' or ' Watch the wheel')
    parts[#parts + 1] = key(K.leave) .. ((H.total or 0) > 0 and open(H) and ' Take bets back' or ' Leave')
    parts[#parts + 1] = key(K.camera) .. ' Table camera'
    local v = exports.whip_core:KeyHint('V', nil)
    if v ~= '' then parts[#parts + 1] = v .. ' View' end
    local text = table.concat(parts, '  |  ')
    if text ~= S.hint then
        S.hint = text
        exports.whip_core:ShowText(text, { icon = 'dollar' })
    end
end

local lastHud = nil

RegisterNetEvent('whip_roulette:hud', function(d)
    if type(d) ~= 'table' then return end
    lastHud = d
    local S = Seated
    if not S or d.table ~= S.table then return end
    local was = S.hud and S.hud.phase
    S.hud = d
    nui({ type = 'hud', hud = d })
    -- The spin starts: over to the wheel (if set to). Back once the felt is cleared, if it was us that went there.
    if Config.WheelCamera.auto and d.phase == 'spinning' and was ~= 'spinning' and not S.wheel then
        if S.betting then
            S.wantWheel = true   -- still putting chips down: betting mode closes itself, then goes to the wheel
        else
            wheelCamera()
            S.autoWheel = true
        end
    elseif S.autoWheel and d.phase == 'idle' then
        wheelOff()
    end
    refreshHint()
end)

-- ============================================
-- Up and down
-- ============================================

local function standUp(tell)
    local S = Seated
    if not S then return end
    S.betting = false
    if tell then TriggerServerEvent('whip_roulette:leave') end
    exports.whip_core:StopCamera()
    S.camera = false
    exports.whip_core:HideText()
    exports.whip_core:UnblockControls('whip_roulette')
    nui({ type = 'hide' })
    local ped = PlayerPedId()
    if not IsEntityDead(ped) and exports.whip_core:LoadAnimDict(SEAT_DICT) then
        local s = scene(SEAT_DICT, 'sit_exit_left', false)
        Seated = nil
        local t0 = GetGameTimer()
        local total = math.max(800, math.floor(GetAnimDuration(SEAT_DICT, 'sit_exit_left') * 1000))
        while GetGameTimer() - t0 < total * 0.75 do
            local phase = 0.0
            local loc = s and NetworkGetLocalSceneFromNetworkId(s) or -1
            if loc ~= -1 then phase = GetSynchronizedScenePhase(loc) end
            if phase >= 0.7 then break end
            local moving = math.abs(GetControlNormal(0, 30)) > 0.3 or math.abs(GetControlNormal(0, 31)) > 0.3
            if moving and GetGameTimer() - t0 > total * 0.35 then break end
            Wait(0)
        end
        if s then NetworkStopSynchronisedScene(s) end
    end
    Seated = nil
    ClearPedTasks(ped)
end

RegisterNetEvent('whip_roulette:stand', function() standUp(false) end)

local function controls(S)
    local function pressed(k) return exports.whip_core:IsKeyPressed(k.key, k.pad) end
    while Seated == S do
        local H = S.hud or {}
        if not S.betting then
            if pressed(K.wheel) then
                if S.wheel then wheelOff() else wheelCamera() end
                S.autoWheel = false
                refreshHint()
            end
            if pressed(K.camera) then
                if S.camera and not S.wheel then cameraOff() else cameraOn() end
                refreshHint()
            end
            if S.camera and IsControlJustPressed(0, 0) then cameraOff() end
            if pressed(K.board) then
                if open(H) then
                    -- Run right here: these keys aren't read again until betting mode is done.
                    betLoop(S)
                    refreshHint()
                else
                    notify('No more bets: wait for the next spin', 'error')
                end
            elseif pressed(K.leave) then
                if open(H) and (H.total or 0) > 0 then
                    TriggerServerEvent('whip_roulette:unbet', 'all')
                else
                    if not open(H) and (H.total or 0) > 0 then notify('Your bets ride: they\'re settled with the spin', 'inform') end
                    standUp(true)
                end
            end
        end
        if Seated == S and #(GetEntityCoords(PlayerPedId()) - S.chair) > Config.LeaveDistance then standUp(true) end
        Wait(0)
    end
end

function SitDown(tableId, seat)
    if Seated then return end
    local L = Live[tableId]
    if not L then return notify('The table isn\'t ready yet', 'error') end
    local res, why = exports.whip_core:Callback('whip_roulette:sit', tableId, seat)
    if not res then return notify(why or 'You can\'t sit here', 'error') end

    local chair, heading = ChairSpot(L, res.seat)
    local ped = PlayerPedId()
    if exports.whip_core:LoadAnimDict(SEAT_DICT) then
        local start = GetAnimInitialOffsetPosition(SEAT_DICT, 'sit_enter_left', chair.x, chair.y, chair.z, 0.0, 0.0, heading, 0.0, 2)
        local turn = GetAnimInitialOffsetRotation(SEAT_DICT, 'sit_enter_left', chair.x, chair.y, chair.z, 0.0, 0.0, heading, 0.0, 2)
        if #(GetEntityCoords(ped) - start) > 0.35 then
            TaskGoStraightToCoord(ped, start.x, start.y, start.z, 1.0, 3000, turn.z, 0.05)
            local t0, best, still = GetGameTimer(), math.huge, 0
            while GetGameTimer() - t0 < 3000 do
                Wait(100)
                local d = #(GetEntityCoords(ped).xy - start.xy)
                if d < 0.3 then break end
                if d < best - 0.02 then best, still = d, 0 else still = still + 1 end
                if still >= 4 then break end
            end
        end
    end

    local T = Config.Tables[tableId]
    if lastHud and lastHud.table ~= tableId then lastHud = nil end
    Seated = { table = tableId, seat = res.seat, chair = chair, heading = heading }
    local S = Seated
    -- Left free: looking (1, 2), GTA's views on V (0), pause, chat, push-to-talk. The mouse buttons, the wheel
    -- and the cursor are read as disabled controls.
    exports.whip_core:BlockControls('whip_roulette', { all = true, except = { 0, 1, 2, 199, 200, 245, 249 }, mode = true })
    if exports.whip_core:LoadAnimDict(SEAT_DICT) then
        scene(SEAT_DICT, 'sit_enter_left', false)
        Wait(math.max(1000, math.floor(GetAnimDuration(SEAT_DICT, 'sit_enter_left') * 1000) - 150))
    end
    if Seated ~= S then return end
    idle()
    nui({ type = 'show', label = T.label or 'Roulette', min = T.min, max = T.max })
    if lastHud and lastHud.table == tableId then
        S.hud = lastHud
        nui({ type = 'hud', hud = lastHud })
    end
    if Config.Camera.enabled then cameraOn() end
    refreshHint()
    CreateThread(function() controls(S) end)
end

AddEventHandler('whip_core:player:died', function() if Seated then standUp(true) end end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Seated then return end
    exports.whip_core:StopCamera()
    exports.whip_core:HideText()
    ClearPedTasks(PlayerPedId())
end)
