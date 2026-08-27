-- PC- and frame-tagged write-tap on ScoreLo/ScoreMid/ScoreHi ($A2-$A7, both
-- player slots), plus the JSR *caller* address recovered off the stack --
-- every write into these bytes happens from inside sub_DF7D (rom:DF7D),
-- always from the same three STA instructions ($DF83/$DF88/$DF90), so the
-- PC alone can't tell us *who* awarded the points. The 6502 return address
-- JSR pushed is still sitting at $0100+S+1/+2 (as retaddr-1) when the tap
-- fires, since nothing else touches the stack between entry and these
-- writes -- reading it back recovers the actual JSR sub_DF7D call site.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-score-writes.lua -str 600
--
-- Writes score-writes-out.json: {"events":[{"frame":N,"pc":"$XXXX",
-- "addr":"$XXXX","val":N,"x":N,"caller":"$XXXX"}, ...]}

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local events = {}
local F = 0

local function tap(offset, data)
  local pc = cpu.state["PC"].value
  local x = cpu.state["X"].value
  local s = cpu.state["SP"].value
  local lo = mem:read_u8(0x100 + ((s + 1) & 0xFF))
  local hi = mem:read_u8(0x100 + ((s + 2) & 0xFF))
  local caller = ((hi * 256 + lo) + 1) & 0xFFFF
  events[#events + 1] = string.format(
    '{"frame":%d,"pc":"$%04X","addr":"$%04X","val":%d,"x":%d,"caller":"$%04X"}',
    F, pc, offset, data, x, caller)
  return data
end

TAP1 = mem:install_write_tap(0xA2, 0xA2, "scoreA2", tap)
TAP2 = mem:install_write_tap(0xA3, 0xA3, "scoreA3", tap)
TAP3 = mem:install_write_tap(0xA4, 0xA4, "scoreA4", tap)
TAP4 = mem:install_write_tap(0xA5, 0xA5, "scoreA5", tap)
TAP5 = mem:install_write_tap(0xA6, 0xA6, "scoreA6", tap)
TAP6 = mem:install_write_tap(0xA7, 0xA7, "scoreA7", tap)

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
  local h = io.open("score-writes-out.json", "w")
  if h then
    h:write(string.format('{"events":[%s]}', table.concat(events, ",")))
    h:close()
  end
end
