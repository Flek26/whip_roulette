Config = {}

-- ============================================
-- Money
-- ============================================
-- Bets are taken with whip's ChargePlayer and paid with PayPlayer, so every one is on the activity log.
--   method:   'cash', 'bank' or 'auto' (cash if they carry enough, else the bank)
--   currency: an item that counts as money instead of cash. 'casino_chips' is whip_blackjack's chips item, bought
--             and cashed in at its cashier: run whip_blackjack too. nil = plain cash.
Config.Money = {
    method   = 'cash',
    currency = 'casino_chips',
}

-- ============================================
-- The wheel
-- ============================================
-- GTA's roulette is American: 0 and 00. Its ball animations end in one of 38 pockets (exit_1_ball ... exit_38_ball);
-- this is the number each pocket is, round the wheel. /rlspin <1-38> (dev) spins one so you can check: if the
-- ball stops on another number, this is the list to fix.
-- Checked in game: with ballTurn 4.74, exit_1 drops in 18, exit_2 in 6, and on round the wheel.
Config.Pockets = {
    '18', '6', '21', '33', '16', '4', '23', '35', '14', '2', '0', '28', '9', '26', '30', '11', '7', '20', '32',
    '17', '5', '22', '34', '15', '3', '24', '36', '13', '1', '00', '27', '10', '25', '29', '12', '8', '19', '31',
}

-- What each bet pays, to 1.
Config.Payouts = {
    straight = 35,  -- one number
    split    = 17,  -- two side by side
    street   = 11,  -- a row of three
    corner   = 8,   -- four that meet
    basket   = 6,   -- 0, 00, 1, 2, 3
    sixline  = 5,   -- two rows of three
    column   = 2,   -- "2 to 1"
    dozen    = 2,   -- 1st, 2nd, 3rd 12
    even     = 1,   -- red / black, odd / even, 1-18 / 19-36
}

-- The chips you pick from on the board (only those within the table's limits are offered).
Config.ChipValues = { 10, 50, 100, 500, 1000, 5000, 10000 }

-- ============================================
-- Timing (seconds, or ms where it says)
-- ============================================
Config.Timing = {
    betSeconds = 25,     -- the betting window, from the first chip down
    -- The spin, as each game plays it: the dealer's spin, the ball going in, round loops times, then dropping.
    spinStartMs = 1500,  -- into the dealer's spin, when the ball goes in
    loops       = 3,
    -- The server holds the result until the ball is at rest: the seated players' games tell it how long their spin
    -- runs. This is only used if none does.
    spinMs      = 22000,
    clearMs     = 3500,  -- the dealer sweeps the chips
}

-- ============================================
-- Tables
-- ============================================
-- coords is the table's origin (on the floor), heading which way it faces.
-- spawn = true: we place the table. false: it's already in the map (an MLO's own table), and we find it there.
-- model: 'vw_prop_casino_roulette_01' or 'vw_prop_casino_roulette_01b'.
-- texture: the felt, 0 green, 1 red, 2 blue, 3 purple. Leave it out to keep the map's.
-- min / max: for one bet (one spot on the board). maxTotal: all of one player's bets on one spin (default 10 x max).
--
-- These are k4mb1-casino's own tables, read out of its map files (stream/casino2/k4mb1_casino2.ytyp; the
-- penthouse's from vw_vwdlc_int_02.ytyp). The penthouse one is in k4mb1's lounge entity set 05 (Roulette), which
-- k4mb1's client2.lua leaves off (set 01, Blackjack, is on): turn 05 on there for it to appear.
Config.Tables = {
    -- The main floor
    { label = 'Roulette',            coords = vec3(997.985, 64.196, 79.993), heading = 238.0, model = 'vw_prop_casino_roulette_01b', spawn = false, min = 10,  max = 2500 },
    { label = 'Roulette',            coords = vec3(995.150, 59.660, 79.993), heading = 238.0, model = 'vw_prop_casino_roulette_01',  spawn = false, min = 10,  max = 2500 },
    { label = 'Roulette',            coords = vec3(992.331, 55.148, 79.993), heading = 238.0, model = 'vw_prop_casino_roulette_01b', spawn = false, min = 10,  max = 2500 },
    { label = 'Roulette',            coords = vec3(979.283, 53.806, 79.999), heading = 328.0, model = 'vw_prop_casino_roulette_01b', spawn = false, min = 10,  max = 2500 },
    { label = 'Roulette',            coords = vec3(973.683, 57.305, 79.999), heading = 328.0, model = 'vw_prop_casino_roulette_01b', spawn = false, min = 10,  max = 2500 },
    -- The high limit room
    { label = 'High Limit Roulette', coords = vec3(939.290, 39.517, 80.000), heading = 328.0, model = 'vw_prop_casino_roulette_01b', spawn = false, min = 500, max = 25000 },
    -- The penthouse lounge (entity set k4mb1_apart_lounge_room_05, see above)
    { label = 'Penthouse Roulette',  coords = vec3(967.314, 32.215, 115.172), heading = 58.0, model = 'vw_prop_casino_roulette_01',  spawn = false, min = 500, max = 25000 },
}

-- The dealers: each restart, every table gets one of these at random, with its own face and hair (every player
-- sees the same one). female = true uses the female dealer moves where the game has them.
Config.Dealers = {
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_WHITE_01' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_WHITE_02' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_ASIAN_01' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_ASIAN_02' },
    { model = 's_m_y_casino_01', voice = 'S_M_Y_CASINO_01_LATINO_01' },
    { model = 's_f_y_casino_01', voice = 'S_F_Y_CASINO_01_ASIAN_01',  female = true },
    { model = 's_f_y_casino_01', voice = 'S_F_Y_CASINO_01_LATINA_01', female = true },
    { model = 's_f_y_casino_01', voice = 'S_F_Y_CASINO_01_WHITE_01',  female = true },
}

-- ============================================
-- Where things go
-- ============================================
-- Only until /rledit has set them: the editor's layout (layout.json) wins. In metres, in the table's own frame.
Config.Layout = {
    surface     = 0.95,   -- the felt's height above the origin
    dealerStand = 0.82,   -- the dealer stands this far behind the middle of the chairs' arc
    dealerLift  = 1.0,    -- the dealer's hips above the floor
    -- The betting board on the felt, by where the middles of three of its numbers are. /rledit sets these, and the
    -- middles of "1st 12" and "1 to 18" (which say how deep the two strips below the numbers are).
    board = {
        n1  = vec3(-0.30, -0.10, 0.95),
        n3  = vec3(-0.30,  0.14, 0.95),
        n34 = vec3( 0.70, -0.10, 0.95),
        dozenRows = 0.55,   -- until /rledit sets them: the dozens strip, as deep as this many number rows
        evenRows  = 0.55,   --                          the 1-18 / Even / Red ... strip
    },
    chipHeight = 0.0072,  -- one chip's thickness, for stacking
    seatTurn   = 0.0,     -- degrees: turn a seated player if the chairs face off
    ballTurn   = 4.74,    -- degrees: the ball's path round the wheel (half a pocket: it drops into pockets, not on the frets)
    ballBone   = 'Roulette_Wheel',   -- the table's wheel bone, where the ball starts
}

-- Chips on the felt for a bet: the biggest that fit, stacked. Value -> model.
Config.Chips = {
    { 10000, 'vw_prop_chip_10kdollar_x1' },
    { 5000,  'vw_prop_chip_5kdollar_x1' },
    { 1000,  'vw_prop_chip_1kdollar_x1' },
    { 500,   'vw_prop_chip_500dollar_x1' },
    { 100,   'vw_prop_chip_100dollar_x1' },
    { 50,    'vw_prop_chip_50dollar_x1' },
    { 10,    'vw_prop_chip_10dollar_x1' },
}

-- ============================================
-- At the table
-- ============================================
-- The camera over your shoulder while seated (C turns it on and off; V is GTA's views, first person among them).
Config.Camera = {
    enabled = true,
    back    = 0.55,
    up      = 1.45,
    fov     = 55.0,
}

-- Putting chips down (Enter): the camera nearly straight down over the board, squared up with it.
Config.BetCamera = {
    back = 0.20,   -- back from the middle of the board, towards the dozens (a touch of slope, so it reads as a table)
    up   = 1.25,   -- above the felt: higher shows more of the board
    fov  = 50.0,
}

-- Watching the wheel (E while seated): the camera over the wheel, looking down into it from the board's side.
Config.WheelCamera = {
    auto = true,   -- switch to it by itself when the spin starts, and back once the felt is cleared
    back = 0.40,   -- from the wheel towards the board
    up   = 0.80,   -- above the wheel
    fov  = 45.0,
}

-- Keys while seated. Putting chips down is the mouse: see the README.
Config.Keys = {
    wheel  = { key = 38,  pad = 205, text = 'E',         button = 'lb' },    -- watch the wheel, or back
    board  = { key = 191, pad = 201, text = 'Enter',     button = 'a' },     -- put chips down
    camera = { key = 26,  pad = 217, text = 'C',         button = 'view' },
    -- 194 is Backspace alone (177 is Backspace, right mouse and Esc all at once).
    leave  = { key = 194, pad = 202, text = 'Backspace', button = 'b' },
}

Config.DrawRange = 45.0
Config.SyncRange = 60.0
Config.LeaveDistance = 3.5
