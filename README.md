# Dig Dug (Atari 7800) disassembly

A byte-identical disassembly and memory-map investigation of *Dig Dug*
(NTSC, Atari, 1987), built with
[a7800-toolkit](https://github.com/) and MAME as a live-verification
instrument, not just a static reader.

**This repo does not contain the ROM.** Supply your own legally-owned dump
(`Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78`, alongside a 7800 BIOS) to
reproduce anything here. The disassembly listing itself (`src/rom.asm`)
isn't committed either -- it's fully generated from
[`annotations.json`](annotations.json) plus the ROM, and regenerating it is
one command (below).

## Start here

[`docs/FINDINGS.md`](docs/FINDINGS.md) is the real deliverable: a narrative
of what's been confirmed live in MAME, what's still just a hint, and what
was actively distrusted and flagged rather than assumed. This is day one of
the project, so read it as a starting map, not a finished one.
[`annotations.json`](annotations.json) is the machine-readable form of the
same knowledge.

Working discipline, if you're picking this up: every claim about what a
byte range does should be checked live before it's trusted, not just
pattern-matched from a probe script carried over from a previous project --
`docs/FINDINGS.md` documents a case (the original `$B900`-`$CFFF`
live-slots data) where a borrowed script's assumptions were noticed to be
suspect, its output deliberately *not* trusted, and the actual bugs (two of
them -- a boot-settle timing issue and a smaller ongoing torn-read
artifact) tracked down and fixed rather than worked around. Every
`annotations.json` change is followed by JSON validation, `disasm.py`
regeneration, and a `verify.py` byte-identical round-trip check.

## Reproducing it

```
# from this directory, with the toolkit checked out as a sibling (adjust
# the path below to wherever you have it) and your own ROM copy dropped in:

python3 ../a7800-toolkit/tools/disasm.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -c annotations.json -o src
python3 ../a7800-toolkit/tools/verify.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -d src
# -> ROUND-TRIP PASSED
```

`src/rom.asm` is then a full listing, byte-identical when reassembled.

Add `--gaps` for a text report of every byte reached as neither code nor a
declared data block, or `--map` for the same picture as a heatmap (green
code, blue declared data, red gap -- needs Pillow):

```
python3 ../a7800-toolkit/tools/disasm.py "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" -c annotations.json -o src --gaps --map
```

![Coverage map](docs/img/coverage-map.png)

Two graphics regions are live-confirmed and declared (`$C000`-`$CFFF`, and
the `$E000` `CHARBASE` character sheet); a further stretch past it
(`$E1FF`-`$EBEB`, declared as seven blocks) is now live-confirmed in part
too -- 4 of the 7 blocks got real display-list hits from a
`tools/live-slots.lua` rerun, the other 3 are still byte-signature-only --
see `docs/FINDINGS.md`. Every byte in the ROM is either traced code or a
declared block (`disasm.py --gaps` reports none left).

## Reproducing the live findings

`run-01.inp` is a MAME input recording -- a deterministic button-press log,
not video, and not copyrighted content -- covering, per the user who
recorded it, "pretty much anything," including the level-counter flowers
growing into a bigger flower as levels progress. Replay it with:

```
./"Play Recording.command" run-01
```

or drive it headless with a Lua probe:

```
mame a7800 -rompath /path/to/bios -input_directory . \
  -cart "Dig Dug (NTSC) (Atari) (1987) (50CB13F3).a78" \
  -playback run-01.inp -autoboot_script your-probe.lua \
  -video none -sound none -nothrottle -str 600
```

* `tools/live-slots.lua` walks the live display list to confirm graphics
  addresses -- carried over from the Centipede project as a starting point;
  its two real bugs on this ROM (a boot-settle timing issue, and a smaller
  ongoing torn-read artifact) are fixed -- see `docs/FINDINGS.md`.
* `tools/dpph-history.lua` logs every `DPPH`/`DPPL` register change with its
  frame number -- built to find *when* a display-list base actually
  settles, since aggregate occurrence counts alone don't show timing.
* `tools/live-slots-diag.lua` tags every out-of-range graphics reference
  with the exact frame/`DPPH`/`DPPL`/zone that produced it -- the tool that
  actually pinned down both bugs above.
* `tools/probe-ram-snapshots.lua` snapshots RAM (zero page plus the
  `$23xx`-`$27xx` object-table pages seen so far) once a second across a
  whole recording, keeping only bytes that ever change -- this is how
  `LivesRemaining`/`Score*`/death handling were confirmed. Unlike
  Centipede's version, this ROM doesn't clear whole pages at boot, so the
  page list here is a starting guess, not a confirmed map.
* `tools/probe-terrain-writes.lua` PC-tags every write to `TerrainMap`
  (`$2600`-`$26FF`) -- this is what actually found the dig action
  (`sub_D8E2`/`sub_FD43`), by pointing straight at the code instead of
  guessing further from static reading. Writes to ordinary RAM can't be
  MARIA DMA misattribution, so every PC found this way is a real writer.
* `tools/probe-flower-writes.lua` PC-tags every write to `$2500`-`$25FF`
  (frame-tagged too) -- caught real execution inside a 506-byte untraced
  gap, leading to a second RAM-vector pattern (a computed jump table
  `disasm.py`'s scanner couldn't find on its own) and a strong lead on the
  level-counter flower / rock-fall counter.
* `tools/probe-veggie-writes.lua` PC-tags every write to two specific
  zero-page addresses (`$00C5`/`$00FD`, narrowed down from an earlier,
  too-hot `$00C0`-`$00FF` sweep) -- caught a live 8-stage animation that,
  cross-referenced against a known single veggie pickup in `run-01.inp`,
  closed the last gap in the jump-table dispatch above and tied it
  together with the rock-settle finding -- see `docs/FINDINGS.md`.
* `tools/probe-score-writes.lua` PC-, frame-, and *caller*-tags every write
  to `ScoreLo`/`ScoreMid`/`ScoreHi` (both player slots) -- since every such
  write happens from inside the same shared score-add routine regardless of
  who called it, the tap also reads the JSR return address back off the
  stack (still sitting at `$0100+SP+1/+2` when the tap fires) to recover
  the real call site. This is what pinned the veggie's exact point value
  against the user's own report.
* `tools/probe-flower-candidate.lua` PC-tags every write to three specific
  RAM cells a level-indexed table lookup writes into -- built to check a
  candidate for the level-counter flower against real level-transition
  frames, unthrottled, after a coarse per-second snapshot's silence on
  those same three cells initially (and wrongly) looked like it ruled the
  candidate out -- see `docs/pitfalls.md` for what actually happened.
* `tools/probe-movement-script.lua` PC/frame-tags writes to the three
  per-object RAM arrays driving the movement-script reader found at
  `rom:EF63` -- reconstructs (table-base, index, value) triples from
  write order and checks each against the actual ROM byte, which is how
  that mechanism went from "confirmed shape" to "93.5% of 15945
  reconstructed reads verified exactly."

## Layout

| | |
|---|---|
| `annotations.json` | The recipe. Feed it to `disasm.py` to get the listing. |
| `docs/FINDINGS.md` | The narrative -- read this first. |
| `docs/img/` | `coverage-map.png` (regenerate with `disasm.py --map`). |
| `run-01.inp` | The MAME input recording the live findings were checked against. |
| `tools/` | This project's own probe scripts. |
| `Play Recording.command`, `Record Session.command` | Double-click launchers for replaying/recording a session (macOS + MAME on `PATH`). |

Not committed (see `.gitignore`): the ROM, the generated `src/rom.asm` and
`build/`, and the probe scripts' regeneratable output manifests -- all
reproducible from the ROM and the recording above.
