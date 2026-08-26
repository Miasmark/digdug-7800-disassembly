-- Periodic full snapshots (not per-write logging -- see the Centipede
-- project's own note on why that doesn't scale) of the game-state RAM
-- pages seen referenced so far: zero page/stack ($0000, $0100) and the
-- object-table pages ($2300-$27FF, seen via ram_2337, ram_23E8, ram_2400,
-- ram_24C0-24D2, ram_2600 in the boot init). Dig Dug's boot code doesn't
-- clear whole pages the way Centipede/Ballblazer's does (it clears small,
-- specific ranges directly), so there's no single "boot-cleared pages"
-- list to lean on the way there was for those two -- this range is a
-- starting guess based on what's already been read, not a confirmed map.
-- Taken every 60 frames (1 second), so gameplay events (lives lost/gained,
-- score, digging state, rock drops, veggie spawns, ghost transitions) can
-- be spotted as step changes in a specific byte's value over time.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-ram-snapshots.lua -str 600
--
-- Writes ram-snapshots-out.json: {frames:[60,120,...], pages:{"0000":[[a,v],...], ...}}
-- where each page's list only records BYTES THAT EVER CHANGED (constant
-- bytes dropped to keep the file small).

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local PAGES = {0x0000, 0x0100, 0x2300, 0x2400, 0x2500, 0x2600, 0x2700}
local F = 0
local frames = {}
local series = {}
for _, p in ipairs(PAGES) do series[p] = {} end

local function snapshot()
  frames[#frames + 1] = F
  for _, p in ipairs(PAGES) do
    local s = series[p]
    for a = p, p + 255 do
      local v = mem:read_u8(a)
      local rec = s[a]
      if not rec then rec = {} s[a] = rec end
      rec[#frames] = v
    end
  end
end

local function dump()
  local parts = {}
  for _, p in ipairs(PAGES) do
    local rows = {}
    for a, rec in pairs(series[p]) do
      local changed = false
      local first = rec[1]
      for i = 1, #frames do
        if rec[i] ~= first then changed = true break end
      end
      if changed then
        local vs = {}
        for i = 1, #frames do vs[i] = tostring(rec[i] or 0) end
        rows[#rows + 1] = string.format('"%d":[%s]', a, table.concat(vs, ","))
      end
    end
    parts[#parts + 1] = string.format('"%04X":{%s}', p, table.concat(rows, ","))
  end
  local h = io.open("ram-snapshots-out.json", "w")
  if h then
    h:write(string.format('{"frames":[%s],"pages":{%s}}',
      table.concat(frames, ","), table.concat(parts, ",")))
    h:close()
    print(string.format("wrote ram-snapshots-out.json: frame=%d checkpoints=%d", F, #frames))
  end
end

emu.register_frame_done(function()
  F = F + 1
  if F % 60 == 0 then snapshot() end
  if F % 6000 == 0 then dump() end
  if F >= 30000 then
    dump()
    MACHINE:exit()
  end
end)
