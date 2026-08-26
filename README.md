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
`docs/FINDINGS.md` documents a case (the `$B900`-`$CFFF` live-slots data)
where a borrowed script's assumptions were noticed to be suspect and its
output was deliberately *not* trusted rather than written down as a
finding. Every `annotations.json` change is followed by JSON validation,
`disasm.py` regeneration, and a `verify.py` byte-identical round-trip check.

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

Two large candidate-graphics regions remain unclaimed (`$C000`-`$CFFF`,
`$DFFF`-`$EBEB`) -- neither is declared as a block yet, on purpose, until
there's live evidence trustworthy enough to pin down real boundaries. See
`docs/FINDINGS.md`.

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

`tools/live-slots.lua` walks the live display list to confirm graphics
addresses -- carried over from the Centipede project as a starting point,
but its output for this ROM is currently flagged as unreliable rather than
trusted; see `docs/FINDINGS.md` before using it as evidence for anything.

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
