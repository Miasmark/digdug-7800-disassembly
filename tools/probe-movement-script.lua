-- PC+frame-tagged write-tap on the three per-object RAM arrays that drive
-- rom:sub_EF3E's movement-script reader (rom:EF63): ram_0067,X (the
-- decoded step value consumed by the caller), ram_2118,X (the per-object
-- table low-byte, i.e. which script this object is running), and
-- ram_2128,X (the per-object read index into that script, i.e. which
-- byte of dat_EC00/$EE00-page was just consumed). Logging all three
-- together, per write, lets the (index, value) pairs be read back
-- against the raw dat_EC00 bytes to see what a step's value means.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-movement-script.lua -str 600
--
-- Writes movement-script-out.json: {"events":[{"frame":N,"pc":"$XXXX",
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

-- 8 object slots each, matching EnemyStatus's 8-slot layout
TAP1 = mem:install_write_tap(0x0067, 0x006E, "ram_0067", tap)
TAP2 = mem:install_write_tap(0x2118, 0x211F, "ram_2118", tap)
TAP3 = mem:install_write_tap(0x2128, 0x212F, "ram_2128", tap)

emu.register_frame_done(function()
  F = F + 1
  if F % 3000 == 0 then
    print(string.format("progress frame %d: events=%d", F, #events))
  end
  if F >= 24000 then
    dump_final()
    MACHINE:exit()
  end
end)

function dump_final()
  print(string.format("FINAL: events=%d", #events))
  local h = io.open("movement-script-out.json", "w")
  if h then
    h:write(string.format('{"events":[%s]}', table.concat(events, ",")))
    h:close()
  end
end
