-- The wheel and the board: one set of rules for the server (which spins and pays) and each game (which draws the
-- board and the chips). Numbers are strings: '0', '00', '1' ... '36'.
--
-- Every bet that can be made is a spot, with a key ('n17', 's17-20', 'c17', 'red', ...), the numbers it covers,
-- what it pays, and where it is on the board. Board units are one number's cell: numbers 1-36 fill x 0-12, y 0-3
-- (1 at the bottom left, 3 above it, 34 at the bottom right); 0 and 00 sit at x -1; the columns' "2 to 1" at
-- x 12-13; the dozens below at y -1, the even-money bets below them at y -2.

Wheel = {}

local RED = {}
for _, n in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }) do RED[tostring(n)] = true end

function Wheel.colour(n)
    if n == '0' or n == '00' then return 'green' end
    return RED[n] and 'red' or 'black'
end

Wheel.spots = {}   -- in drawing order
Wheel.byKey = {}

local P = Config.Payouts

local function add(s)
    s.set = {}
    for i, n in ipairs(s.nums) do
        s.nums[i] = tostring(n)
        s.set[s.nums[i]] = true
    end
    s.pays = P[s.kind]
    Wheel.spots[#Wheel.spots + 1] = s
    Wheel.byKey[s.key] = s
end

local function at(col, row) return (col - 1) * 3 + row + 1 end   -- col 1-12, row 0-2

-- Cells: numbers, 0 and 00, the columns, dozens and even-money bets. x, y, w, h.
for col = 1, 12 do
    for row = 0, 2 do
        local n = at(col, row)
        add({ key = 'n' .. n, kind = 'straight', nums = { n }, x = col - 1, y = row, w = 1, h = 1, label = tostring(n),
              colour = Wheel.colour(tostring(n)) })
    end
end
add({ key = 'n0',  kind = 'straight', nums = { '0' },  x = -1, y = 0,   w = 1, h = 1.5, label = '0',  colour = 'green' })
add({ key = 'n00', kind = 'straight', nums = { '00' }, x = -1, y = 1.5, w = 1, h = 1.5, label = '00', colour = 'green' })
for row = 0, 2 do
    local nums = {}
    for col = 1, 12 do nums[#nums + 1] = at(col, row) end
    add({ key = 'col' .. (row + 1), kind = 'column', nums = nums, x = 12, y = row, w = 1, h = 1, label = '2 to 1' })
end
for d = 1, 3 do
    local nums = {}
    for n = (d - 1) * 12 + 1, d * 12 do nums[#nums + 1] = n end
    add({ key = 'doz' .. d, kind = 'dozen', nums = nums, x = (d - 1) * 4, y = -1, w = 4, h = 1,
          label = ({ '1st 12', '2nd 12', '3rd 12' })[d] })
end
local function evens(key, label, test, x)
    local nums = {}
    for n = 1, 36 do if test(n) then nums[#nums + 1] = n end end
    add({ key = key, kind = 'even', nums = nums, x = x, y = -2, w = 2, h = 1, label = label })
end
evens('low',   '1-18',  function(n) return n <= 18 end, 0)
evens('even',  'Even',  function(n) return n % 2 == 0 end, 2)
evens('red',   'Red',   function(n) return RED[tostring(n)] end, 4)
evens('black', 'Black', function(n) return not RED[tostring(n)] end, 6)
evens('odd',   'Odd',   function(n) return n % 2 == 1 end, 8)
evens('high',  '19-36', function(n) return n >= 19 end, 10)

-- Points between cells: splits, corners, streets, six lines, and the ones by 0 and 00. cx, cy.
for col = 1, 12 do
    for row = 0, 2 do
        local n = at(col, row)
        if row < 2 then add({ key = ('s%d-%d'):format(n, n + 1), kind = 'split', nums = { n, n + 1 }, cx = col - 0.5, cy = row + 1 }) end
        if col < 12 then add({ key = ('s%d-%d'):format(n, n + 3), kind = 'split', nums = { n, n + 3 }, cx = col, cy = row + 0.5 }) end
        if row < 2 and col < 12 then add({ key = 'c' .. n, kind = 'corner', nums = { n, n + 1, n + 3, n + 4 }, cx = col, cy = row + 1 }) end
    end
    local b = at(col, 0)
    add({ key = 't' .. b, kind = 'street', nums = { b, b + 1, b + 2 }, cx = col - 0.5, cy = 0 })
    if col < 12 then add({ key = 'l' .. b, kind = 'sixline', nums = { b, b + 1, b + 2, b + 3, b + 4, b + 5 }, cx = col, cy = 0 }) end
end
add({ key = 's0-00', kind = 'split',  nums = { '0', '00' }, cx = -0.5, cy = 1.5 })
add({ key = 'basket', kind = 'basket', nums = { '0', '00', '1', '2', '3' }, cx = 0, cy = 0 })

--- The middle of a spot, in board units.
function Wheel.centre(s)
    if s.cx then return s.cx, s.cy end
    return s.x + s.w / 2, s.y + s.h / 2
end

--- The bet at a point on the board (board units), as a chip put down there would be: near a line or a corner it's
--- that split, corner, street or six line; else the cell it's in. nil off the board.
local POINT_REACH = 0.22
function Wheel.hit(bx, by)
    local best, bestD = nil, POINT_REACH * POINT_REACH
    for _, s in ipairs(Wheel.spots) do
        if s.cx then
            local d = (s.cx - bx) ^ 2 + (s.cy - by) ^ 2
            if d < bestD then best, bestD = s, d end
        end
    end
    if best then return best end
    for _, s in ipairs(Wheel.spots) do
        if s.w and bx >= s.x and bx < s.x + s.w and by >= s.y and by < s.y + s.h then return s end
    end
    return nil
end

--- A short name for a spot: '17', 'Split 17/20', 'Red'.
function Wheel.name(s)
    if s.label and s.kind ~= 'column' then return s.label end
    local k = s.kind
    if k == 'column' then return ('Column %s'):format(s.key:sub(4)) end
    local words = { split = 'Split', corner = 'Corner', street = 'Street', sixline = 'Six line', basket = 'Basket' }
    return ('%s %s'):format(words[k] or k, table.concat(s.nums, '/'))
end

--- A bet as chips on the felt: { { model, count }, ... }, biggest first, at most `cap` chips in all.
function Wheel.chips(amount, cap)
    cap = cap or 12
    local out, left, n = {}, math.floor(tonumber(amount) or 0), 0
    for _, c in ipairs(Config.Chips) do
        local value, model = c[1], c[2]
        local k = math.floor(left / value)
        if k > 0 then
            k = math.min(k, cap - n)
            if k <= 0 then break end
            out[#out + 1] = { model = model, count = k }
            left, n = left - k * value, n + k
        end
    end
    if #out == 0 and amount and amount > 0 then out[1] = { model = Config.Chips[#Config.Chips][2], count = 1 } end
    return out
end

--- '$1,250'
function Wheel.money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return '$' .. out:gsub('^,', '')
end
