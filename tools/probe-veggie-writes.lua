-- Who writes $00C5 or $00FD specifically? Narrowed from an earlier, too-wide
-- $00C0-$00FF tap (that range is so hot -- 300k+ hits in 3000 frames -- the
-- event log filled before reaching the frame window of interest). PC- and
-- frame-tagged, every single write logged (not throttled) since these two
-- addresses alone are expected to be sparse.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-veggie-writes.lua -str 600
--
-- Writes veggie-writes-out.json: {"events":[{"frame":N,"pc":"$XXXX",
-- "addr":"$XXXX","val":N}, ...]}

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local events = {}
local F = 0

local function tap(offset, data)
  local pc = cpu.state["PC"].value
  events[#events + 1] = string.format(
    '{"frame":%d,"pc":"$%04X","addr":"$%04X","val":%d}', F, pc, offset, data)
  return data
end

TAP1 = mem:install_write_tap(0x00C5, 0x00C5, "veggie1", tap)
TAP2 = mem:install_write_tap(0x00FD, 0x00FD, "veggie2", tap)

emu.register_frame_done(function()
  F = F + 1
  if F % 3000 == 0 then
    print(string.format("progress frame %d: events=%d", F, #events))
  end
  if F >= 30000 then
    dump_final()
    MACHINE:exit()
  end
end)

function dump_final()
  print(string.format("FINAL: events=%d", #events))
  local h = io.open("veggie-writes-out.json", "w")
  if h then
    h:write(string.format('{"events":[%s]}', table.concat(events, ",")))
    h:close()
  end
end
