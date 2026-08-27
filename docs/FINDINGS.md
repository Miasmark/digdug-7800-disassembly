# Dig Dug -- findings so far

`Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78`, 16K linear, no banking, no
POKEY declared -- audio is the TIA's own two voices. Everything below is
reproducible with the [a7800-toolkit](../../a7800-toolkit/README.md) against
`annotations.json` in this folder:

```
python3 ../a7800-toolkit/tools/disasm.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -c annotations.json -o src
python3 ../a7800-toolkit/tools/verify.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -d src
```

Static coverage is **51.7%** as traced code (8468/16384 bytes), and every
remaining byte is accounted for -- zero bytes left as an unclaimed gap
(`disasm.py --gaps` reports "none"). Round-trip is byte-identical
throughout everything documented here. Eleven passes in: entry points and
the self-modifying NMI, a full display-list probe fix and the resulting
`$C000`-`$CFFF` graphics region, the `$E000`-based character sheet,
lives/score/death, the terrain map with the actual dig action,
death/ghosts/(tentatively) rocks, the pump/harpoon stun end to end, a
second RAM-vector pattern (a computed jump table), the rock-settle/
veggie-appearance mechanism and the level-counter flower disambiguated and
confirmed, a systematic sweep of every remaining gap (small
already-referenced tables declared, more trial-entry code found by
hand-reading raw bytes past a dead `RTS`/`JMP`, a second `chr_rom_*`
character-sheet region declared across seven blocks, a fourth
indirect-addressing pattern found rather than left unexplained), and --
this pass -- live probes chasing down that sweep's open hedges: 4 of the 7
new graphics blocks upgraded to live-confirmed, the movement-script
mechanism verified to 93.5% against 15945 reconstructed table reads, and
the veggie-threshold/timer sequence traced from shape-match to causally
confirmed. Not every declared block is independently *live*-confirmed the
way the `$C000`/`$E000` sheets were -- 3 of the 7 `chr_rom_*` blocks are
still byte-signature/cross-reference only, the same standard
`chr_rom_E0DC` was already held to; see `annotations.json`'s own `blocks`
notes for which is which, and treat "gaps: none" as "every byte is claimed
by something with a stated reason," not as "everything is understood."

Vectors: `IRQ $EED8` `NMI $C15F` `RESET $D000`.

Manual (mechanics reference, scoring table, enemy behavior):
https://atariage.com/manual_html_page.php?SoftwareID=2126 -- 5 starting
lives, extra lives at 20,000 and 50,000 points then every 50,000 after,
digging = 10 points/chunk, monster kills 200-500 (400-1000 for Fygar from
the side), rock drops 1000-4000, veggies 400-8000, veggies appear after two
rocks have fallen in a round. Two enemy types (Pooka, Fygar -- the latter
breathes fire) that turn into wall-phasing ghosts if not dealt with quickly.

`run-01.inp` (the user's recording) covers "pretty much anything," explicitly
including the level-counter flowers growing into a bigger flower as levels
progress -- a detail worth remembering when that mechanism turns up in code.

## What's confirmed

**`CHARBASE = $E0`**, by code, not guess: both writers (`rom:D065`,
`rom:DD93`) load `#$E0` immediately before the write. See "The `$E000`
character sheet" below for how its extent was actually confirmed, once the
display-list probe was trustworthy enough to use.

**`ENTRY_Nmi` is self-modifying code, not a plain vector.** It reads
`JMP ram_1FBD` -- an absolute jump to a fixed RAM address, not an indirect
`JMP (ptr)`. Boot code (`rom:sub_D057`) writes `$4C` (the `JMP` opcode
itself) to `ram_1FBD`, then a target address's low/high bytes to
`ram_1FBE`/`ram_1FBF` -- assembling a literal `JMP $target` instruction in
RAM. Declaring `ram_vectors` on the `[ram_1FBE, ram_1FBF]` address pair (not
`ram_1FBD`) let the existing scanner find it without any tool changes: it
only needed the two address bytes, not the fixed opcode byte before them.
This found `VEC_EE57`, recovering ~517 bytes of real code (44.3% coverage,
up from init.py's initial 41.1%).

**`VEC_EE57` is a single self-contained multi-stage DLI handler**, not a
ping-pong chain between separate routines the way Centipede's was. Each
stage does a `WSYNC` then writes a MARIA palette-register pair (`P5C1/P5C2`,
`P6C1/P6C3`, `P7C1/P7C3` -- distinct color sets, presumably per screen band),
then re-arms *itself* at a different internal offset via a shared
`STA ram_1FBE / BNE` trampoline for the next interrupt. That's why the
`ram_vectors` scan only found one external target: every re-arm points back
inside code already being traced.

## The display-list probe: two real bugs, found and fixed

The first pass flagged `tools/live-slots.lua`'s output (~940 references
densely packed across `$B900`-`$CFFF`) as untrustworthy rather than write it
down as a finding -- a third of it sat below where this cart's ROM is even
mapped, and landed on already-confirmed real code under a same-offset
mirror theory. That distrust turned out to be correct, and chasing it down
found two distinct, real bugs, not one.

**Static reading narrowed the search first.** Both `DPPH` writers in
currently-traced code (`rom:sub_D1BE`, `rom:sub_D1CA`) only ever load `#$23`
or `#$25` -- both sensible RAM addresses. If the walker was landing on
`$1F84`-shaped garbage, that value wasn't coming from any code this project
had already read.

**Bug 1 -- boot takes far longer to settle than assumed.**
`tools/dpph-history.lua` (new: logs every `DPPH`/`DPPL` change with its
frame number, not just aggregate counts) showed `DPPH` sitting at a bogus
boot value (`$1F`, paired with one-off `DPPL` values `$84`/`$5D`) from frame
16 all the way to **frame 165**, before settling into the real, stable base
(`$23xx`, with `DPPL` alternating `$5D`/`$A2` *every single frame* -- a
genuine double-buffer, confirmed benign, not a bug). A first fix guessed a
2-second (120-frame) grace period was enough; it wasn't -- verified against
the same recording, walking past frame 120 still produced garbage (500 bad
references by frame 132, checked with a second new tool,
`tools/live-slots-diag.lua`, which tags every out-of-range reference with
the exact frame/`DPPH`/`DPPL`/zone that produced it). Reading the actual
per-frame history instead of assuming a round-number grace period was
enough is what found the real 165-frame settle point; the fix uses a
200-frame gate with margin.

**Bug 2 -- a smaller, ongoing torn-read artifact survives the settle fix.**
Even past frame 200, 340 of 1072 references still land below `$C000`,
several confirmed (the same way as the boot-time ones) to fall on
already-traced real code under the mirror theory. These aren't one-off --
some addresses recur across the whole recording -- so this isn't boot
garbage; it's most likely a genuine timing race between when the CPU
finishes updating a display-list entry and when the once-per-frame Lua
callback reads it, on some frames but not others. Not chased further into
MAME's own frame-timing internals -- that's a different, deeper kind of
investigation than this project needs. Instead, filtered rather than
trusted: every reference below `$C000` is discarded, on the same principle
as Centipede's PC-tagged DMA-misattribution filter -- an "impossible"
address is disqualifying regardless of what produced it. The remaining 732
references are the trustworthy dataset everything below is built on.

## What's confirmed (continued)

**`$C000`-`$CFFF` is one graphics/data resource**, confirmed by the filtered
live data (dense and consistent across every page `$C0` through `$CF`) and
checked the same way Centipede's `chr_rom_C000` boundary mistake taught
this project to check: grepped for any `JSR`/`JMP` landing on a `dat_`
label anywhere in this range before trusting it (none found), and confirmed
`ENTRY_Nmi` (`$C15F`, 3 bytes) and two small already-traced code stretches
(`sub_C24D`, and `sub_C300`-`L_C361`) sit as clean islands inside it rather
than being silently swallowed by too-broad a block declaration. Declared as
four pieces (`gfx_C000`, `gfx_C162`, `dat_C25C`, `gfx_C362`) around those
islands. This includes the `$C54A` bonus-digit graphics noted below, now
confirmed live rather than just a rendering hint.

## The `$E000` character sheet

Confirmed three independent ways, not just one: (1) `CHARBASE = $E0` by
code, already established; (2) `gfx.py`'s default indirect-mode render at
`--base 0xE000` shows legible "ATARI" text and a full 0-9 digit set -- a
direct visual check, the same technique that confirmed the other two
projects' character sheets; (3) the filtered live display-list data (30
references) lands entirely within `$E000`-`$E0A8`, cleanly avoiding
`sub_E0C4` (real code at `$E0C4`-`$E0DB`) rather than scattering across it
the way stale reads would -- real evidence the walker's indirect-mode
handling works here, addressing a worry raised while fixing the two bugs
above (the walker's address math was written for direct-mode MARIA
entries; whether it's even meaningful for indirect-mode ones was an open
question until this).

Checked for the exact bug that bit `chr_rom_C000` in the Centipede project
*before* declaring anything broad: grepped for `JSR`/`JMP` into any
`dat_E0`/`dat_E1` label (none found), then found `sub_E0C4` and
`sub_E1E9`/`sub_E1F7` sitting as real, already-traced code islands inside
what visually renders as legible graphics -- exactly the shape of the
earlier mistake, caught proactively this time instead of after the fact.
Declared as two blocks around those islands (`chr_rom_E000`,
`chr_rom_E0DC`), starting one byte early at `$DFFF` because that's where
the preceding code actually ends, not because of anything about `CHARBASE`
itself.

**Past `$E1E9`, the picture changes.** `$E1FF`-`$EBEB` (roughly 2540 bytes
across several gaps) has only 7 live references total, all plausible
individual-object widths (11-32) but nowhere near the density of the
confirmed sheets above. This reads as a different kind of region --
individually-referenced sprites (Pooka, Fygar, rocks, veggies -- each only
showing up when that specific thing is on screen, unlike the digging
graphics referenced continuously) rather than one dense, continuously-used
sheet. Not investigated further this pass; noted as the next lead rather
than guessed at.

## Gameplay logic: lives, score, and death

First pass at gameplay logic, using a new `tools/probe-ram-snapshots.lua`
(same shape as Centipede's -- periodic snapshots, not per-write logging)
scoped to zero page and the `$23xx`-`$27xx` object-table pages seen
referenced so far during boot init. Unlike Centipede/Ballblazer, this ROM's
boot code (`rom:sub_D057`) doesn't clear whole RAM pages in one sweep --
it clears specific, narrow ranges directly -- so there was no single
"boot-cleared pages" list to lean on for scoping the probe the way there
was for the other two; this is a starting guess based on what's already
been read, not a confirmed map of all game state.

**`LivesRemaining` ($009E, `+X` for the current player) -- confirmed live,
cleanly.** Counts 5->4->3->2->1->0 three separate times across the whole
recording, resetting to 5 each time (frames 1980, 12540, 24300) in exact
lockstep with `NewGameFlag` ($00A0) pulsing and `ScoreHi` resetting to 0 --
matches the manual's "5 starting lives" exactly. Static reading found both
directions: `rom:DF9E` increments it (capped at 10, from the extra-life
award path below), and `rom:DC6F` decrements it (from the death-handling
routine, `rom:DC41`).

**The death-handling routine (`rom:DC41`) is 2-player-aware**, even though
this project's own recording never exercised 2-player mode to confirm it
live: it plays a short death animation, decrements the current player's
`LivesRemaining`, and -- only if that hits zero -- checks the *other*
player's `LivesRemaining` (`Y = CurrentPlayer XOR 1`) before deciding the
game is really over. If either player still has lives, it falls through to
`sub_DD3B` instead of ending the game -- the same routine the extra-life
award path calls, suggesting a shared "life gained/still alive" 
notification rather than two separate mechanisms.

**Score (`ScoreLo`/`ScoreMid`/`ScoreHi`, `$00A2`/`$00A4`/`$00A6`, `+X`) and
the extra-life threshold check are one routine, confirmed by the arithmetic
itself** (`rom:DF7D`, `SED` at `rom:DF80`, BCD carry chained across all
three bytes) -- and its threshold check (`CMP #$02`, `AND #$0F`/`BEQ`,
`CMP #$05` against the new high digit) matches the manual's extra-life rule
(20,000 and 50,000, then every 50,000 after) closely enough by shape to be
convincing, though the exact digit-place arithmetic hasn't been traced
byte-by-byte the way `LivesRemaining` was live-confirmed.

## The terrain map, found -- the dig action itself, not yet

**`TerrainMap` ($2600, 256 bytes) is the dirt/tunnel grid**, one byte per
cell. Found by noticing `$26xx` used as a *direct-mode graphic page* in a
display-list-entry builder (`rom:sub_D16C`) -- an address below where this
cart's ROM is mapped, which only makes sense if MARIA is reading from a
RAM-resident tile buffer built dynamically by the CPU, the same idea
Centipede's mushroom field turned out to be (confirmed independently here,
not carried over as an assumption from that project). Confirmed by the
level-init code (`rom:D298`, `rom:sub_D2C0`): fills the map with one of
three fixed values (`$20`/`$22`/`$1E`) depending on a level number computed
mod 10, a `$24` border/edge fill, and a few `$4C`/`$4A` "already open" cells
at fixed starting-tunnel positions.

**`sub_D660` is the terrain-cell classifier**, confirmed by using the exact
same threshold values the init code fills the map with (`CMP #$24`,
`CMP #$1E`) to bucket a cell into "solid" / "open" / "packed dirt."

**`sub_F952` uses the classifier for movement clamping**, not digging --
it walks cells in a direction (from a 2-bit code in `ram_0080`) and
accumulates a distance counter (`ram_009D`, via the tiny `sub_E1F7`) for
each open cell until it hits something solid. This answers "how far can an
object move before it's blocked," which is necessary for digging but isn't
the dig action itself.

**Found the dig action itself, by tapping `TerrainMap` directly rather than
guessing further from static reading.** A new `tools/probe-terrain-writes.lua`
(PC-tagged write-tap, same idea as Centipede's `probe-mushroom-writes.lua`
-- MARIA never writes to RAM, so every hit is a genuine 6502 writer, no
DMA-misattribution filtering needed) pointed straight at it:

* **`sub_C30A`** converts a pixel `(X,Y)` position to a `TerrainMap` index
  and reads the cell -- `Y>>3` for the row, `X>>2` indexing a
  row-to-table lookup (`ram_2490,X`) that indexes the same per-row
  base-offset table (`dat_E7BF`) the display-list builder and level-init
  code both already used.
* **`sub_D8E2`** is the dig-check-and-erode routine: picks one of several
  erosion tables based on the current movement/turn state, computes the
  target cell's position (current position plus a per-direction offset),
  and -- only if that cell isn't already solid/border (`CMP #$24`) --
  calls `sub_FD43` to erode it. It checks a second, related cell the same
  way right after, consistent with a tunnel opening affecting more than
  one cell per step.
* **`sub_FD43`** is the actual write-back: `(old_value - $24) >> 1` indexes
  a small lookup table (chosen per-direction by the caller) to get the
  *new* terrain value, then stores it into `TerrainMap`. Digging a cell
  repeatedly walks it through a short sequence of intermediate
  "partially dug" values rather than clearing to open in one step --
  the exact table contents (how many steps, which values) aren't decoded
  yet, and neither is where the 10-points-per-chunk score award happens
  in this sequence, though `sub_DF7D` (the score-add/extra-life routine)
  is presumably the thing it eventually calls.

**Also found along the way**: the level-clear check (`rom:sub_DF33`) --
loops over `EnemyStatus` (`$00B2`, `+X`, an 8-slot status array); if none
are alive, plays a sound/animation, increments `LevelNumber` (this is what
`ram_009B,X` turned out to be, confirmed by this exact increment), and
re-runs the terrain-map init for the next level.

**A polarity correction, caught before it spread.** `sub_DF33`'s own logic
(exits early, level *not* clear, the instant it finds a slot with bit 7
*clear*) settles it directly: `EnemyStatus` bit 7 **set** (negative) means
DEAD/inactive, not alive -- backwards from the first, unchecked assumption
while reading it. Corrected at the source (`rom:DF33`'s own comment) rather
than left to propagate into the newer notes below.

## Death, ghosts, and (tentatively) rocks

**`sub_F71C` looks like the player-touched-by-an-enemy death trigger.** For
each active `EnemyStatus` slot, it checks the pixel distance between the
player and that enemy; on a close-range hit, it sets `ram_0084 = 1` (the
same flag that gates five of the main loop's subroutines -- so a hit
*pauses* ordinary gameplay updates), loads a death-animation graphic from
`dat_C155` (the exact table `rom:DC41`'s confirmed death routine also
cycles through), plays a sound, and resets the ghost-transition state (see
below). Everything about the shape matches death; the exact trigger-to-life-loss
wiring back to `LivesRemaining` hasn't been traced further than this.

**`sub_F760`, right after it, has the identical skeleton but checks
distance against a different reference point** (`ram_004E`/`ram_0061`, not
the player) and, on a hit, kills the enemy outright (zeroes its
`EnemyStatus`) rather than triggering player death. A plausible read given
the manual's "drop rocks on monsters" mechanic (1000-4000 points) is that
this is the rock-kill check and the reference point is a rock's position --
but that's not confirmed; the reference point's own identity hasn't been
traced.

**A multi-piece state machine live in `EnemyStatus` bits 1-2**
(`rom:sub_FA33`), first read as pure ghost-transition logic, **then
reinterpreted once the harpoon mechanic below tied directly into it.** Bit
1 set means "mid-sequence" -- a per-slot animation-stage counter advances
every time a per-slot timer counts down, and at stage 4 plays a sound and
clears bit 2. Only one enemy can be mid-sequence at a time, gated by a
specific slot index and a flag that -- now confirmed -- is the harpoon-hit
flag itself, not a separate ghost-specific one. Still open which of "now
ghosting" / "stun wearing off" / "fully digested" stage 4 represents, and
whether the ghost-conversion mechanic (a separate periodic countdown,
`ram_00B1`, kicked on first fire-button press) is really this same sequence
or a genuinely separate path that happens to share the plumbing.

## The pump/harpoon stun, found end to end

Followed the fire button forward from the input read to the actual hit
detection, rather than guessing at any one piece in isolation:

* **`sub_D6BA`** reads `INPT4,Y` (`Y = CurrentPlayer`) and builds
  `FireHoldTimer` -- a hold-duration counter that resets to 0 the instant
  the button releases and counts up while held, capping its behavior at
  exactly 24 frames. Matches the manual's "press and hold, or pump
  repeatedly" almost exactly.
* **`sub_F7F6`** grows `HarpoonLength` by 1 each frame the harpoon is
  extending -- but clamps it against `ram_009D`, the exact distance-so-far
  value `sub_F952` (found while tracing terrain movement-clamping, above)
  computes by walking `TerrainMap` cells in the facing direction. **The
  harpoon reuses the terrain movement-clamp code and literally cannot
  extend past a wall or solid dirt.** Resets `HarpoonLength` to a
  "retracted" sentinel when the button is released.
* **`sub_F901`/`sub_F90A`** compute the harpoon tip's screen position from
  the player's position and `HarpoonLength` (with a left/right branch for
  facing direction), then loop the 8 `EnemyStatus` slots checking each
  one's proximity to that computed tip. **On a hit**: records the target in
  `HarpoonTargetSlot`, sets `EnemyStatus,X = $07` (bits 0-2 all set -- the
  stun pattern), and sets the flag `sub_FA33`'s state machine (above)
  checks to start the stun-recovery sequence. This is the actual stun hit.

## A second RAM-vector pattern, and a rock/flower candidate

The user's own domain knowledge redirected this investigation productively:
the level-counter flower belongs with the end-of-level sequence, after the
jingle, and either a new flower appears per level or an existing one grows
bigger at some point. That pointed straight at the rare `$2500`-page DLL
`sub_D1BE` switches to right after `sub_DF33`'s level-clear jingle wait --
followed it and it led somewhere real, though not fully resolved.

**Found a second kind of RAM-vector -- a computed jump table, not a
scanner-visible one.** `tools/probe-flower-writes.lua` (a PC-tagged write-tap
on `$2500`-`$25FF`, same idea as the `TerrainMap` probe) caught real
execution inside what was, until now, a 506-byte untraced gap
(`$F522`-`$F71B`). The code there (`rom:F513`) builds a jump target from an
8-entry low/high table (`dat_E0B0`/`dat_E0B8`) indexed by `Y`, then
`JMP (ram_00D2)`. `disasm.py`'s `ram_vectors` scanner couldn't find this on
its own: the `LDA`/`STA` pair that seeds the vector is itself only reachable
*through* this same jump -- a chicken-and-egg the scanner has no way into
from outside. Computed all 8 targets by hand from the raw table bytes (2 of
the 8 land outside plausible code space and are presumably unused slots)
and added the 4 real, distinct ones to `entries` directly -- the same
trial-entry-point method this project has used before, just aimed with a
computed address instead of a guess. **Recovered 461 bytes of real code**
(44.3% -> 47.2%, gap 4668 -> 4207 bytes).

**One of the newly-recovered routines (`rom:sub_F5FB`) is a strong,
not-yet-fully-confirmed candidate for the rock-fall / flower-counter
mechanism.** It's a per-object loop (falling-object physics -- calls a
terrain-based settle check and updates position on a hit) that, the first
time a given object settles (gated by an `EnemyStatus` bit-6 latch so it
only fires once), writes a small value (live-observed: 3-4) into a specific
slot of the `$2500`-page RAM and plays a sound. Two readings both fit the
evidence and aren't disambiguated yet:

* The manual's "veggies appear after two rocks have fallen in a round" --
  this could be that counter.
* The level-counter flower itself, if the `$2500` page holds a strip of
  per-level icons that accumulate through play and are simply *displayed*
  (via `sub_D1BE`'s DLL switch) at level-end, rather than written all at
  once at the jingle. This reading fits the user's framing better -- the
  flower belongs to the end-of-level *moment* even if the underlying data
  updates earlier, during play.

Both may even be true at once (a rock settling could plausibly drive both a
veggie-spawn counter and a flower/round tally). At the time this was
written, not resolved which, or whether they're the same counter --
**superseded below.**

## The rock-settle / veggie-appearance gap, closed

Two more pieces of domain knowledge from the user turned this from "strong
lead" into a mostly-resolved finding: "I picked up a veggie once during the
session" (a single, findable event in `run-01.inp`), and "rockfall should
be just triggering the sound and disappearing" (a hint that `sub_F5FB`
above, which is more involved than that, probably isn't the rock's own
removal).

**Found the veggie pickup live.** Re-scanning the existing RAM-snapshot data
for a single isolated excursion (a value that sits at a common baseline the
entire recording except one brief run) turned up `$00C5`/`$00FD` both
activating for about 100 frames around frame ~4320-4440, immediately
followed by a score jump of 410 points (2830 -> 3240) nearby in time --
inside the manual's 400-8000 veggie range, and taken at the time as
confirmation. **That reading turned out to be wrong** -- see below, it was
almost certainly a monster kill that happened to land close by; the real
veggie value, decoded properly afterward, is exact. Neither
`$00C5`/`$00FD` address was in the disassembly yet. `tools/probe-veggie-writes.lua`
(PC-tagged, narrowed to exactly those two addresses after a too-wide first
attempt on `$00C0`-`$00FF` drowned in 300k+ hits/3000 frames) caught every
write: an 8-stage progression, `$00FD` counting up once per frame through
each stage and `$00C5` incrementing between stages, running frames
4289-4420 and ending at `$F6C6`.

That address landed inside the still-open 97-byte tail of the same
jump-table region (`$F6B8`-`$F718`) that `sub_F513`'s table pointed at
`sub_F6A3`, `sub_F668`, etc. earlier -- and along the way, a second missed
table target from the original recovery pass turned up too: `rom:F52A`
(computed correctly at the time but never actually added to `entries`),
sitting under part of this same live-observed sequence. Added both as
trial entry points (the same method used for the other table targets) --
both traced cleanly. `rom:F52A` closed a 36-byte hole first (47.2% ->
47.4%, gap 4207 -> 4171 bytes), then `rom:F6B8` closed the remaining
97-byte tail completely (47.4% -> 48.0%, gap 4171 -> 4074 bytes).

**Reading the recovered code disambiguates the whole family.** The jump
table at `rom:F513` isn't a per-object-*type* dispatch -- it's a per-*stage*
animation sequencer (`rom:sub_F50D` uses the stage value itself,
`ObjSlotStage,X`, as the table index) driving a small pool of 5 slots
(`rom:sub_F4EF` walks `X=4..0`, distinct from the 8 `EnemyStatus` enemy
slots). The live-observed `$00C5`/`$00FD` sequence is exactly
`ObjSlotStage`/`ObjSlotTimer` at slot 2, and it runs through **stages 2-9**,
not 2-7 as first assumed -- the lo/hi jump table (`dat_E0B0`/`dat_E0B8`) is
actually 10 entries wide, not 8: reading it at `Y=8`/`Y=9` walks past the
declared 8-byte tables into bytes that, by design or fortunate reuse, decode
to two more real targets (`rom:F6B8`, `rom:F6C4`), both live-confirmed and
now declared. See `docs/pitfalls.md` ("A computed jump table can be wider
than its first N entries suggest") for the general lesson. `rom:sub_F6C4`
(stage 9) is the actual finish: it unconditionally ends the slot's
animation, then loops the 8 `EnemyStatus` slots and, for whichever one
`RockOwnerSlot` points back at this ObjSlot, promotes its settle-latch (bit
6, set by `sub_F5FB`) into the confirmed dead/inactive bit (bit 7, from
`rom:F71C`) -- the actual rock removal.

So: **`sub_F5FB` was never the rock's disappearance** -- from the player's
seat that's exactly what it looks like ("just the sound and disappearing"),
but the removal is deferred and piggybacks on whichever ObjSlot animation
claimed the rock, which is the same machinery driving the veggie-appearance
animation just traced live.

**The veggie's point value is now decoded exactly, and it corrects the
earlier live-correlation guess.** The user reported the actual veggie they
picked up was worth 1000 points, not 410. Reading `sub_F6C4` further: when
`ObjSlotRockTally,X` is nonzero it awards `VeggieValueTable[2*(tally-1)]`
(a BCD lo/mid pair, renamed from `dat_E0F0`) into the score **twice in a
row** -- two back-to-back calls into the shared score-add routine
(`rom:sub_DF75` -> `rom:sub_DF7D`) with the identical value. For
`tally=1`, `VeggieValueTable[0..1]` decodes as 500 points by its own BCD
encoding; doubled by the repeated call, that's **exactly 1000** -- matching
the user's report precisely, not just plausibly. `tools/probe-score-writes.lua`
(new this round, PC- and *caller*-tagged -- every write to `ScoreLo`/
`ScoreMid`/`ScoreHi` happens from the same few `STA`s inside the shared
routine regardless of who called it, so the tap reads the JSR return
address back off the stack to recover the real caller) confirmed `sub_DF75`
is called from exactly the five sites this predicts, including `rom:F70A`/
`rom:F716` inside `sub_F6C4`. Later table entries (tally 2-5) decode to
2500, 4000, 6000, 8000 doubled -- a clean progression inside the manual's
400-8000 veggie range. The earlier "410, matching the manual's veggie
point range" note in this same document was a coincidental live-data
correlation, not a decoded value, and it was wrong -- most likely a nearby
monster kill (200-500/400-1000 per the manual). Left here rather than
deleted, per this project's own discipline: retract in place, don't erase.

**The level-counter flower is a separate mechanism, and it's now found.**
The user clarified directly: the flower is a static, non-interactable
per-level decoration -- one small flower added each level up to 9, then all
replaced by a single big flower from level 9 on -- and confirmed it is
*not* the veggie/ObjSlot family above. `rom:D3EC`, inside the level-init
routine (`rom:sub_D2C0`, itself called from `rom:sub_D244` -- which runs on
every level-clear *and* every death/respawn), reads `LevelNumber` and uses
it (1-based, capped at 18 levels) to index three parallel tables
(`dat_E8BD`/`dat_E8AA`/`dat_E8D0`), writing the result into three RAM
cells plus a fixed graphics pointer. A first live check, using the existing
coarse per-second RAM-snapshot data, found those three cells "never
changed" across the whole recording and read that as ruling the mechanism
out. That was the wrong conclusion from a real observation: those same
three cells are shared scratch space `rom:sub_F901`'s harpoon-position code
also writes constantly during normal play, so the level-driven value is
visible for only a couple of frames before being overwritten by unrelated
writes -- invisible to a once-a-second sample. A dedicated, unthrottled
PC-tagged write-tap on exactly those three addresses
(`tools/probe-flower-candidate.lua`) caught it cleanly: the write fires at
every one of the recording's eleven level transitions, at the right frame,
with the value exactly matching `dat_E8BD[LevelNumber-1]` decoded straight
from ROM -- and fires again with the same value on same-level respawns,
consistent with `sub_D244` running on both. The mechanism is confirmed;
what the byte values *mean* is not -- they don't show a clean monotonic
1-9-then-flat count by themselves (levels 1-3 are each unique, then values
repeat in pairs of levels from level 4 on, flattening to one constant value
from level 16 on), so whether the raw byte is a literal flower count, a
graphic-tile ID, or some other level attribute that only indirectly grows
the flower row hasn't been pinned down -- that would need an actual
video-frame comparison across levels, not attempted here. See
`docs/pitfalls.md` ("A periodic RAM snapshot can miss a real, frequent
write") for the general lesson.

## Sweeping every remaining gap

With the veggie/flower work done, the user asked to "hit the gaps" --
close out the remaining 20 unclaimed ranges (3936 bytes) rather than chase
another single mechanic. Worked from smallest to largest:

**Already-referenced data, just not block-declared.** Several gaps
(`dat_D579`, `dat_D6EF`-family, `dat_D74F`, `dat_E2C6`-family,
`dat_FD4B`) turned out to already be correctly rendered as data by
`disasm.py`'s default fallback, complete with real cross-references from
already-traced code -- they only showed as "gaps" because nothing had
declared a `blocks` entry to say so, the same situation `dat_C25C` was in
from an earlier pass. Declared each as a small block bounded by real code
on both sides. `dat_FD4B` (164 bytes, a repeating 4-byte-tuple structure)
reads like sound/music parameter data sitting next to `sub_FDEF`, this
project's shared sound-trigger call -- not decoded further; `tools/
audiotrace.py` in the toolkit is built for exactly this and hasn't been
run against this ROM yet.

**A byte-string signature, once: `FF76-FFFF` decodes as GCC's own
copyright.** The first 10 bytes spell `GCC(C)1984` in ASCII -- General
Computer Corporation, the developer this project already independently
confirmed via the (private, reference-only) leaked-source cross-check on
the Centipede project. The rest is unstructured filler ending in the
hardware vectors at `$FFFA`-`$FFFF` (byte-verified against `NMI/RESET/
IRQ` in `entries`) -- vector bytes are data, not code, so the tracer never
touched them even though they were fully known.

**More trial-entry code, found the same way as the veggie chase's `F52A`/
`F6B8`.** Several small gaps turned out to be real code reachable only by
hand-reading raw bytes past a dead-end `RTS` or unconditional `JMP` and
recognizing real opcodes -- `rom:EED9` (another self-modifying DLI-chain
stage, same family as the confirmed `VEC_EE57`, toggling `CTRL`/
`CHARBASE` between $50/$E0 and $4B/$39 -- a *second* character-sheet base
this project hasn't examined), and a chain in `$F07C`-`$F1E6` (`F07C`,
`F082`, `F109`, `F175`, `F192`) that turned out to all be part of the same
per-object dispatch family as `rom:sub_F280` -- which itself turned out to
be a **third indirect-jump pattern**: a stored function pointer per
object, built from two parallel RAM arrays (`ram_22F0,X`/`ram_2030,X`)
rather than a fixed ROM table or a self-modifying single vector.
`disasm.py`'s scanner cannot enumerate this kind at all, even in
principle -- the targets are runtime object state, not compile-time
constants. Recovered ~470 bytes this way.

**A second `chr_rom_*` region, `$E1FF`-`$EBEB`, declared across seven
blocks.** The byte pattern (dense `$00`/`$01`/`$40`/`$AA`/`$FF` runs) is
the exact signature already confirmed for the `$E000` character sheet,
and every block boundary lands exactly on a real, already-traced code
island (`sub_E2BF`, `sub_E3E0`, `sub_E4DB`, `sub_E5E8`, `sub_E6E5`,
`sub_E8F4`, `sub_E9F9`, `sub_EBEC`) with a script-swept check (every
`JSR`/`JMP` in the traced program, checked for a target landing inside
any of these ranges) confirming none of them swallow code -- the same
precaution `chr_rom_E0DC` used, run once across the whole span rather
than per-block. Several already-labeled small tables (including
`dat_E8AA`/`dat_E8BD`/`dat_E8D0`, the flower-candidate tables from
`rom:D3EC`) fold in cleanly at block tails. **Not live-verified** the way
`chr_rom_E000` was, though -- declared on byte-signature and
cross-reference strength, same standard as `chr_rom_E0DC` already used.

**The last gap, `$EC00`-`$EE56`, is not graphics -- found a fourth
indirect pattern instead of guessing.** The byte values here don't match
the bit-plane signature at all (small values, mostly `$00`-`$35`).
Instead of declaring it graphics on a hunch, searched for what actually
reads it: `rom:EF63` builds a pointer with a fixed high byte (`$EE`) and
a *runtime* low byte (`ram_2118,X`, per-object), walked with a
per-object saved index (`ram_2128,X`) that treats a zero byte as a
redirect/skip marker rather than data. Reads like a per-object movement/
behavior script interpreter (one step per call, feeding `ram_0067,X`) --
plausibly the Pooka/Fygar movement patterns the manual describes, but not
decoded further. Declared as plain data, not `gfx`, since the pattern
doesn't support that reading.

**Net result: every byte in the ROM is now either traced code or a
declared block with a stated reason** -- coverage moved 48.0% -> 51.7%
(7864 -> 8468 bytes) and the gap report goes from 3936 bytes in 18 ranges
to zero. Round-trip verified byte-identical throughout, and after every
single addition, not just at the end.

## Live-probing the new gaps' loose threads

The user asked to "hit the live probes" next -- turn the freshly-declared
blocks' open hedges into checked evidence instead of leaving them as
byte-pattern guesses. Three separate probes, three different outcomes.

**`tools/live-slots.lua`, rerun against `run-01.inp` after the
`chr_rom_E1FF`-family blocks existed.** 1072 total display-list references
walked (matching the count from before this project started declaring the
new blocks -- consistent, not a regression). 7 of them land inside the
newly-declared region: 4 of the 7 blocks (`chr_rom_E2FF`, `chr_rom_E500`,
`chr_rom_E5FF`, `chr_rom_EA00`) each got at least one real hit, upgrading
them from "byte-signature candidate" to "live-confirmed." The other 3
(`chr_rom_E1FF`, `chr_rom_E400`, `chr_rom_E700`, `chr_rom_E900`) got none
-- not evidence against them, the confirmed `$C000`/`$E000` sheets are
sparsely referenced too and one recording won't touch every tile, but
honestly flagged as still byte-signature-only. One correction fell out of
this: `dat_E6AA` (a small table folded into `chr_rom_E5FF`, previously
read as "position/pointer tuples, not pixel data" from its byte shape
alone) got 3 real display-list hits landing inside it -- it's genuinely
doing double duty, referenced both as a lookup table by name and as
graphics tile data directly, not a misclassification. One single, isolated
hit also landed inside `dat_EC00` (`$EE1F`) -- not enough on its own to
call that block graphics too (see its own note), given this project has
already documented a real minority torn-read artifact in this exact
live-walking method that can land on valid-looking ROM addresses, not just
the below-`$C000` garbage that's easy to filter.

**`tools/probe-movement-script.lua`, purpose-built for `dat_EC00`.**
PC/frame-tagged every write to the three per-object RAM arrays
`rom:EF63`'s read loop uses (`ram_0067,X` the consumed value,
`ram_2118,X` the per-object table base, `ram_2128,X` the per-object read
index), 24000 frames, 36086 events. Reconstructed 15945 (base, index,
value) triples from write order and checked each against the actual ROM
byte at `$EE00+((base+index)&$FF)`: **93.5% matched exactly**, and not one
of those matches reached past `$EE56` into `rom:VEC_EE57`'s own code,
despite base values observed as high as 255 that would, combined with an
unlucky index, land there in principle. The 6.5% mismatches all coincide
with a saved index of 0, consistent with an unwound zero-byte redirect
chain (the reconstruction only undoes one hop) rather than a broken
formula. This took `rom:EF63` from "confirmed shape" to "verified
mechanism, real numbers." The *values* consumed cluster tightly in a
narrow even band (`$7C`-`$92`, 124-146) centered near `$80` -- reads like
a small signed position/velocity delta biased by 128, not a discrete
compass-direction enum, though the exact semantics aren't pinned down.

**`ram_00C8`/`ram_00F1`, re-examined from data already on hand.** No new
probe needed -- the existing per-second `tools/probe-ram-snapshots.lua`
data already had the answer at finer grain than the earlier pass used.
`ram_00C8` does hit exactly 2 repeatedly across the recording (once per
level, occasionally reset early by a death via the same `rom:sub_D244`
path the flower mechanism shares), and `ram_00F1` visibly starts climbing
in the very same 60-frame sample window every time it happens -- e.g. `C8`
hits 2 at frame 7260, `F1` is 9 and climbing (28, 47, 66, 84, 103, 122,
141, 159, 178) over the next several samples, then drops to 0 around frame
7860 as it nears `$C0` -- matching `rom:sub_F2E6`'s own threshold checks
read earlier. A second full cycle at frames 11460-11700 shows the
identical shape. Causally confirmed now, not just shape-matched -- though
what the ~600-frame climb represents on screen (a veggie's visible
duration? a jingle playing through?) still isn't pinned down.

## Cross-checking against a private reference

Following the same discipline this session already used on a different
project: a privately-consulted, unlicensed historical source for this
game was used strictly as a check on what's been found or missed here --
never quoted, never copied into this repo, and every correction rederived
independently from this project's own disassembly and live probes before
being written down anywhere. Where the two disagreed, both readings are
recorded rather than silently picking one.

**Corroborated, not just matched:** the `ram_00C8`==2 / `ram_00F1`-climb
sequence documented above lines up with a conceptually identical mechanic
in that source, using the same two threshold constants (`$0E`/`$C0`) this
project already found independently by reading its own code earlier this
session -- settles what the ~600-frame climb most likely *is* (a
fruit/veggie display-then-remove timer) without needing to trust the
outside source for the constants themselves, since they were ours first.
Similarly, the 5-slot `ObjSlot` pool structurally matches a same-sized
falling-object pool concept in that source, reinforcing (not
originating) a finding already reached here through live probing alone.

**Genuinely disagreed, and left disagreeing:** that source describes its
equivalent of the movement-script table (`dat_EC00`/`rom:EF63`) and the
flower row (`rom:D3EC`) as computed differently than what this ROM's own
bytes show -- monster direction computed live rather than read from a
table, and the flower row computed arithmetically from the level number
rather than looked up. Checked this project's own disassembly for a
matching arithmetic routine and found only one relevant divide-by-10
computation anywhere in the traced code, already accounted for as
`rom:D298`'s terrain-pattern selector, serving a different purpose. Rather
than force either finding to match the other, both are left honestly
un-reconciled -- this project's own live-verified mechanisms stand as
confirmed, while their *identity* (is `dat_EC00` really movement? is
`rom:D3EC` really the flower row?) is downgraded back to open rather than
assumed resolved. This is plausibly a genuine difference between what
that source documents and this specific Atari 7800 port's own
implementation, not an error on either side -- see the veggie point-value
table below for the same pattern.

**Disagreed on absolute values, kept this project's own reading:** the
veggie point-value table (`VeggieValueTable`/`rom:F6C4`) decoded here is
indexed differently and holds different numbers than that source's
equivalent table. This project's own reading is independently
ROM-byte-derived, live-verified, *and* matches the user's own real
1000-point report exactly -- strictly stronger evidence than the outside
source can offer for this specific cartridge -- so it stands as-is, with
the mismatch noted as a probable scoring/indexing change this port's own
developers made, not a correction needed here.

**New, independently re-derived from this project's own code, prompted by
a cross-check hint but not copied from it:** re-examining `rom:sub_FA33`'s
stun-state machine (following a structural hint that it might not be
strictly one-directional) found a second, previously-missed branch that
*decrements* the same stage counter the original reading only ever saw
incrementing -- a real correction to this project's own prior
documentation, found by rereading this project's own bytes, not by
trusting the outside description of it.

**Lesson for the toolkit:** a private reference is exactly as useful for
finding what a project got *wrong* as for confirming what it got right --
and disagreement isn't automatically an error on either side, especially
across different ports of the same game. The discipline that mattered
here was re-deriving every claim from this project's own bytes before
writing anything down, corroborated-or-not.

## What's still open

* What the flower table's byte values actually encode on screen (count vs.
  graphic/tile ID), and now also whether `rom:D3EC` is even the right
  mechanism -- a cross-check raised doubt (see above) that this project's
  own code doesn't yet resolve either way.
* Whether `chr_rom_E1FF`/`E400`/`E700`/`E900` (the 3 of 7 new blocks with
  no live hit yet) are really graphics -- byte-signature and boundary
  evidence only; their 4 siblings now have real display-list hits.
* What the movement-script values in `dat_EC00` are actually *for* --
  the read mechanism and the actual table bytes are live-verified
  (`rom:EF63`, 93.5% of 15945 reconstructed reads matched exactly), but a
  cross-check raised doubt about whether "monster movement" is even the
  right subsystem (see above); the mechanism stands, its purpose doesn't.
* `rom:sub_FA33`'s stun state machine: now known to be bidirectional (a
  decrement branch was found alongside the original increment-only
  reading), but which condition actually selects each branch isn't
  traced.
* `dat_E0A9`'s role in `rom:sub_F6B8` (stage 8, a per-tally lookup used
  just before the final stage) isn't decoded.
* `sub_F760`'s reference point (rock position?) isn't confirmed.
* Which of the harpoon-stun state machine's stages means what (stunned /
  recovering / fully killed), and whether ghost-conversion is really the
  same sequence or a separate path sharing the same plumbing.
* `rom:sub_D622` (the fall/settle check `sub_F5FB` calls) hasn't been
  independently examined.
* Exactly where/how digging awards its 10-points-per-chunk score, and the
  contents of the erosion lookup tables (how many "partially dug" stages a
  cell walks through).
* The extra-life threshold check's exact digit-place arithmetic isn't
  traced byte-by-byte, unlike `LivesRemaining`'s clean live confirmation.
* The `$C54A` bonus-digit graphics haven't been cross-checked against the
  manual's exact point-value table.
* `dat_FD4B`'s sound/music data hasn't been run through `tools/
  audiotrace.py`.
