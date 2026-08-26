-- live-slots-diag.lua -- diagnostic version of live-slots.lua, built to find
-- out WHY the plain version reported ~940 graphics references across
-- $B900-$CFFF, a third of which sit below where this cart's ROM is even
-- mapped. Confirmed by static reading: DPPH only ever takes the values $23
-- or $25 (rom:sub_D1BE, rom:sub_D1CA) -- both sensible RAM addresses -- so
-- if the walk is landing on $B9xx/$C0xx-ish "graphics" pointers, either the
-- DLL/DL walk is running past its real terminator into unrelated memory, or
-- it's reading a torn/uninitialized display list. This version logs enough
-- to tell which.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/live-slots-diag.lua -str 600
--
-- Writes live-slots-diag-out.json:
--   dpph_seen:   distinct DPPH byte values ever written, with counts
--   dppl_seen:   distinct DPPL byte values ever written, with counts
--   zone_counts: histogram of how many DLL zones got walked before the
--                terminator fired, per call (should cluster low and tight;
--                a long tail all the way to the 32-zone cap means the
--                terminator isn't firing and the walk is running off the end)
--   bad_refs:    up to 200 samples of {frame, dpph, dppl, zone, gfx, width}
--                for every reference this run computed as < $C000 (the
--                suspect range from the plain probe) -- enough to see
--                exactly which (dpph,dppl,zone) combination produces one

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local F, dpph, dppl = 0, nil, nil
local dpph_seen, dppl_seen = {}, {}
local zone_counts = {}
local bad_refs = {}

TAP_MARIA = mem:install_write_tap(0x20, 0x3F, "maria regs", function(offset, data)
  if offset == 0x2C then
    dpph = data
    dpph_seen[data] = (dpph_seen[data] or 0) + 1
  end
  if offset == 0x30 then
    dppl = data
    dppl_seen[data] = (dppl_seen[data] or 0) + 1
  end
  return data
end)

local function byte(a) return mem:read_u8(a) end

local function walk_dl(addr, zone)
  for _ = 1, 48 do
    local b0, b1 = byte(addr), byte(addr + 1)
    if b1 == 0 then return end
    local gfx, width, len
    if (b1 & 0x1F) == 0 then
      local b2, b3 = byte(addr + 2), byte(addr + 3)
      gfx, width, len = b0 | (b2 << 8), (~b3 & 0x1F) + 1, 5
    else
      local b2 = byte(addr + 2)
      gfx, width, len = b0 | (b2 << 8), (~b1 & 0x1F) + 1, 4
    end
    if gfx < 0xC000 and #bad_refs < 500 then
      bad_refs[#bad_refs + 1] = string.format(
        '{"frame":%d,"dpph":%d,"dppl":%d,"zone":%d,"gfx":%d,"width":%d}',
        F, dpph or -1, dppl or -1, zone, gfx, width)
    end
    addr = addr + len
  end
end

local function walk_dll(base)
  local z
  for zz = 0, 31 do
    z = zz
    local a = base + 3 * zz
    local b0, b1, b2 = byte(a), byte(a + 1), byte(a + 2)
    local dl = (b1 << 8) | b2
    if dl == 0 or (b1 == 0 and b2 == 0) then break end
    walk_dl(dl, zz)
    if b1 >= 0x80 then break end
  end
  zone_counts[z] = (zone_counts[z] or 0) + 1
end

local function dump()
  local function tbl(t)
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = string.format('"%d":%d', k, v) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  local out = string.format(
    '{"frame":%d,"dpph_seen":%s,"dppl_seen":%s,"zone_counts":%s,"bad_refs":[%s]}',
    F, tbl(dpph_seen), tbl(dppl_seen), tbl(zone_counts), table.concat(bad_refs, ","))
  local h = io.open("live-slots-diag-out.json", "w")
  if h then h:write(out) h:close() print("wrote live-slots-diag-out.json") end
  print(string.format("frame=%d bad_refs=%d", F, #bad_refs))
end

local SETTLE_FRAMES = 120

emu.register_frame_done(function()
  F = F + 1
  if F > SETTLE_FRAMES and dpph and dppl then walk_dll((dpph << 8) | dppl) end
  if F % 300 == 0 then dump() end
  if #bad_refs >= 500 then dump() MACHINE:exit() end
end)
