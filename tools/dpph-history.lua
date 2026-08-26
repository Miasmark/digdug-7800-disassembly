-- dpph-history.lua -- log every (frame, DPPH, DPPL) pair transition across
-- the whole recording, to tell a real (recurring, stable) display-list base
-- apart from a transient/incidental write (e.g. a generic MARIA-register
-- clear loop at boot) -- see tools/live-slots-diag.lua's own header for why
-- this is needed.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/dpph-history.lua -str 600
--
-- Writes dpph-history-out.json: [{"frame":N,"dpph":N,"dppl":N}, ...] --
-- one entry every time EITHER register changes, so the sequence of distinct
-- pairs (and how long each one persists) is visible.

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local F, dpph, dppl = 0, 0, 0
local log = {}

local function record()
  log[#log + 1] = string.format('{"frame":%d,"dpph":%d,"dppl":%d}', F, dpph, dppl)
end

TAP_MARIA = mem:install_write_tap(0x20, 0x3F, "maria regs", function(offset, data)
  if offset == 0x2C and data ~= dpph then dpph = data record() end
  if offset == 0x30 and data ~= dppl then dppl = data record() end
  return data
end)

local function dump()
  local h = io.open("dpph-history-out.json", "w")
  if h then h:write("[" .. table.concat(log, ",") .. "]") h:close() end
  print(string.format("frame=%d transitions=%d", F, #log))
end

emu.register_frame_done(function()
  F = F + 1
  if F % 3000 == 0 then dump() end
  if F >= 30000 then dump() MACHINE:exit() end
end)
