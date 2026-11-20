# whip_roulette

Casino roulette on whip. You sit at one of the casino's own roulette tables, put chips down on the felt itself with the mouse, and the dealer spins GTA's own wheel. Up to four players share a table. Every bet goes through whip's money, so it appears on the activity log.

## How it plays

1. **Sit down.** Walk up to a free chair and press **E** on *Sit down*.
2. **Bet, on the felt.** Press **Enter**: the camera moves over the board and a cursor appears. A chip follows the cursor onto whatever bet it's over. It snaps to a number or outside bet, or, near a line, to that split, corner, street or six line. The prompt at the top names the bet, what it pays and what you have on it.

   | Mouse or key | What it does |
   | --- | --- |
   | **Left click** | Put the chip down there |
   | **Right click** | Take your chips off that bet |
   | **Scroll** | Change the chip |
   | **Backspace** | Done: back to your seat's view (your bets stay down) |
3. **The spin.** The first chip down opens a 25 second window for the whole table. Then it's no more bets: the dealer spins, the ball goes round and drops.
4. **Pay.** Every winning bet is paid, and the felt is swept. The last twelve numbers show in your panel.

**E** watches the wheel up close, and **E** again goes back. The camera also moves to the wheel by itself when the spin starts, and comes back once the felt is cleared. Turn that off with `Config.WheelCamera.auto`.

**Backspace** takes your bets back while betting is open, or gets up. **C** toggles the camera over your shoulder, and **V** switches GTA's views, first person included.

## The bets (Config.Payouts)

GTA's wheel is American, with 0 and 00.

| Bet | Covers | Pays |
| --- | --- | --- |
| Straight | One number (0 and 00 too) | 35:1 |
| Split | Two side by side (or 0/00) | 17:1 |
| Street | A row of three | 11:1 |
| Corner | Four that meet | 8:1 |
| Basket | 0, 00, 1, 2, 3 | 6:1 |
| Six line | Two rows | 5:1 |
| Column, dozen | Twelve numbers | 2:1 |
| Red / black, odd / even, 1-18 / 19-36 | Eighteen | 1:1 |

**Limits:**
- `min` and `max` on a table apply to each bet.
- `maxTotal` is the most one player can have down on one spin (default 10 × `max`).

## Chips

Bets are in **Casino Chips**, `casino_chips`. That's **whip_blackjack**'s item: it registers the chips, and its cashier sells them and buys them back. Run whip_blackjack alongside, or set `Config.Money.currency = nil` to bet plain cash.

## Leaving, and what's safe

- **Before the spin:** getting up gives your bets back.
- **Once the bets have closed:** they ride, and are settled with everyone's. A win is paid to your character even if you've disconnected.
- **If the server or resource stops mid-spin,** every bet is refunded.

## Tables

`Config.Tables` contains k4mb1-casino's own roulette tables, read out of its map files: five on the main floor, one in the high limit room and one in the penthouse lounge.

The penthouse table belongs to k4mb1's lounge entity set `k4mb1_apart_lounge_room_05`, which k4mb1's `client2.lua` leaves off. It turns on `_01`, the blackjack lounge, instead.

If `sf-tcp` is running, stop it. It hides these roulette tables and puts poker tables in their place.

## Setting it up

1. Put `whip_roulette` in resources and `ensure whip_roulette` after whip_core and whip_blackjack.
2. **Line the board up:** stand at a table and run `/rledit` (see below). Until you do, the board is a guess, and the bet under the cursor won't match the felt. If the over-the-board camera sits wrong for your tables, tune `Config.BetCamera`.
3. **Check the wheel:** run `/rlspin 1` (any pocket from 1 to 38) beside a table. It spins in your game only, and tells you which number `Config.Pockets` expects.
   - **The ball lands on another number:** `Config.Pockets` (the wheel's numbers in pocket order) needs reordering. Tell me what pocket 1 and pocket 2 landed on.
   - **The ball runs off the wheel:** turn it with `Config.Layout.ballTurn`.
   - **The spin and the payout don't line up:** tune `Config.Timing` (`spinStartMs`, `loops`, `spinMs`).

## The layout editor: /rledit

The board on the felt is placed by five points. Put a chip on each, and every bet's spot follows.
- The middles of numbers **1**, **3** and **34** place the numbers.
- The middles of **1st 12** and **1 to 18** set how deep the two narrower strips below the numbers are. The editor draws every cell's middle on the felt as you go, so you can see it line up with the printed board.

| Key | What it does |
| --- | --- |
| **Scroll** | Next or previous item: numbers 1, 3 and 34, "1st 12", "1 to 18", the dealer, each seat's chair |
| **Arrows** | Move it, in the direction you're looking. On "which chair", **Left/Right** picks the chair |
| **PgUp / PgDn** | Raise or lower it |
| **Q / E** | Turn the dealer |
| **Shift** | Hold for fine movement |
| **G** | Put it back where it started |
| **Enter** | Save for this table's model. **Shift + Enter**: both models |
| **Backspace** | Leave. Press twice if you haven't saved |

Saving writes `layout.json` here (needs `whip.devtools`), and every game uses it at once.
