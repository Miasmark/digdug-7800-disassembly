# Dig Dug -- findings so far

`Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78`, 16K linear, no banking, no
POKEY declared -- audio is the TIA's own two voices. Everything below is
reproducible with the [a7800-toolkit](../../a7800-toolkit/README.md) against
`annotations.json` in this folder:

```
python3 ../a7800-toolkit/tools/disasm.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -c annotations.json -o src
python3 ../a7800-toolkit/tools/verify.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -d src
```

Static coverage is **44.3%** as traced code (7255/16384 bytes). Round-trip
is byte-identical throughout everything documented here. This is day one --
one recording processed, the memory map is nowhere near settled yet.

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
`rom:DD93`) load `#$E0` immediately before the write. The large gap around
`$DFFF`-`$EBEB` (scattered, not yet one clean block) is consistent with this
being the indirect-mode character/tile sheet, but that's still a hypothesis
-- no live display-list evidence has been trusted for this ROM yet (see
below for why).

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

## What's a hint, not a finding yet

**A likely bonus-digit graphics sheet around `$C54A`.** Rendered with
`gfx.py --direct 22 --lines 16`, it shows legible point-value digits
(readable "...000" numbers) -- plausibly the pop-up bonus values for kills,
rock drops, or veggies from the manual's scoring table. Not cross-checked
against the manual's exact numbers yet, and critically **not confirmed
live** -- see below for why that matters more here than it did on the last
two projects.

**A large, dense live-display-list reference set across `$B900`-`$CFFF`
(~940 addresses) that should NOT be trusted yet.** `tools/live-slots.lua`
was carried over verbatim from Centipede and pointed at `run-01.inp`. The
portion in `$B900`-`$BFFF` is a red flag on its face: those addresses sit
*below* where this cartridge's ROM is even mapped (`$C000`-`$FFFF`), and
several of them land on bytes that are already traced as real, working code
(`$B965`, for instance, would only make sense under a same-offset ROM-mirror
theory as `$F965` -- which is `LDA ram_0080`, ordinary game logic, nothing
graphics-shaped about it). The likely explanation is that the walker read a
stale or torn display list -- leftover/uninitialized RAM content, not a
frame MARIA ever actually displayed -- rather than anything about this ROM's
real memory map. The `$C000`-`$CFFF` portion is more plausible (it lines up
with an otherwise-unclaimed gap, and `$C54A` above renders cleanly) but
isn't independently confirmed by anything live yet either.

**Before trusting this probe's output the way it was trusted on Centipede
and Ballblazer**, the next step is checking whether `walk_dl`/`walk_dll`'s
assumptions (MARIA's DLL/DL entry format is a hardware constant, so that
part should be safe; the *zone count* and *per-zone object count* loop
bounds borrowed from the previous project are not) actually match this
game's real display-list layout, or building a version that also captures
which frame each reference came from so a suspiciously-early or
suspiciously-late cluster is easy to spot and discount.

## What's still open

Everything else. This is the first pass: entry points, the self-modifying
NMI, one graphics hint, and one probe result flagged as unreliable rather
than trusted. No gameplay logic (digging, the pump/harpoon stun, rock
physics, ghost-phasing, the level-counter flower) has been traced yet, and
the memory map's two large candidate-graphics regions
(`$C000`-`$CFFF`, `$DFFF`-`$EBEB`) are unconfirmed hypotheses, not
declared blocks.
