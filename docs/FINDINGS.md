# Dig Dug -- findings so far

`Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78`, 16K linear, no banking, no
POKEY declared -- audio is the TIA's own two voices. Everything below is
reproducible with the [a7800-toolkit](../../a7800-toolkit/README.md) against
`annotations.json` in this folder:

```
python3 ../a7800-toolkit/tools/disasm.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -c annotations.json -o src
python3 ../a7800-toolkit/tools/verify.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -d src
```

Static coverage is **44.3%** as traced code (7255/16384 bytes), plus 4446
bytes of declared data blocks -- **71.4%** accounted for overall, 4683
bytes left as an honest gap. Round-trip is byte-identical throughout
everything documented here. Three passes in: entry points and the
self-modifying NMI, a full display-list probe fix and the resulting
`$C000`-`$CFFF` graphics region, then the `$E000`-based character sheet.
A large chunk of `$E1FF`-`$EBEB` is still open -- sparse, not dense, so
likely a different kind of thing than the two confirmed sheets (see below).

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

## What's still open

* `$E1FF`-`$EBEB` (see above) -- sparse live evidence, real character but
  not yet pinned down; the next natural target given the tools now exist
  and are trusted.
* No gameplay logic (digging, the pump/harpoon stun, rock physics,
  ghost-phasing, the level-counter flower) has been traced yet.
* The `$C54A` bonus-digit graphics haven't been cross-checked against the
  manual's exact point-value table.
* Roughly a dozen small scattered gaps remain in `$D000`-`$FFFF`, not yet
  swept the way Centipede's small gaps were.
