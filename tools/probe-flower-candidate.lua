-- PC+frame-tagged write-tap on the three RAM cells rom:D3EC's LevelNumber-
-- indexed table lookup writes into ($23EF/$23F0/$231E) -- checking whether
-- they really get rewritten every level (the flower hypothesis) or just
-- once (at boot/death), against the whole of run-01.inp, unthrottled.
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

TAP1 = mem:install_write_tap(0x23EF, 0x23EF, "f1", tap)
TAP2 = mem:install_write_tap(0x23F0, 0x23F0, "f2", tap)
TAP3 = mem:install_write_tap(0x231E, 0x231E, "f3", tap)

emu.register_frame_done(function()
  F = F + 1
  if F % 5000 == 0 then
    print(string.format("progress frame %d: events=%d", F, #events))
  end
  if F >= 30000 then
    print(string.format("FINAL: events=%d", #events))
    local h = io.open("flower-candidate-out.json", "w")
    h:write(string.format('{"events":[%s]}', table.concat(events, ",")))
    h:close()
    MACHINE:exit()
  end
end)
