-- Who writes $2500-$25FF during actual gameplay, and when? This RAM page
-- backs a DLL used only ~18 times across a whole recording (per
-- tools/dpph-history.lua's own data) -- rare enough to line up with level
-- transitions, not ordinary per-frame play. Candidate for the level-counter
-- flower row (see docs/FINDINGS.md). PC-tagged AND frame-tagged so the
-- writer(s) can be found directly and correlated to level-clear timing,
-- rather than guessed at from the boot-time init alone.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-flower-writes.lua -str 600
--
-- Writes flower-writes-out.json: {"pcs":{"$XXXX":count,...},
-- "addrs":{"$XXXX":count,...}, "events":[{"frame":N,"pc":"$XXXX",
-- "addr":"$XXXX","val":N}, ...]} -- events only for the first write at each
-- PC after a gap of 60+ frames since that PC last fired, to catch
-- per-level-transition writes without an unworkable full per-write log.

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local pcs = {}
local addrs = {}
local total = 0
local last_frame_for_pc = {}
local events = {}
local F = 0

TAP = mem:install_write_tap(0x2500, 0x25FF, "flower", function(offset, data)
  local pc = cpu.state["PC"].value
  local pk = string.format("$%04X", pc)
  local ak = string.format("$%04X", offset)
  pcs[pk] = (pcs[pk] or 0) + 1
  addrs[ak] = (addrs[ak] or 0) + 1
  total = total + 1
  local lf = last_frame_for_pc[pk]
  if (not lf or F - lf >= 60) and #events < 500 then
    events[#events + 1] = string.format(
      '{"frame":%d,"pc":"%s","addr":"%s","val":%d}', F, pk, ak, data)
  end
  last_frame_for_pc[pk] = F
  return data
end)

emu.register_frame_done(function()
  F = F + 1
  if F % 3000 == 0 then
    print(string.format("progress frame %d: hits=%d", F, total))
  end
  if F >= 30000 then
    dump_final()
    MACHINE:exit()
  end
end)

function dump_final()
  print(string.format("FINAL: hits=%d", total))
  local pk = {}
  for k in pairs(pcs) do pk[#pk+1] = k end
  table.sort(pk, function(a,b) return pcs[a] > pcs[b] end)
  print("top PCs:")
  for i = 1, math.min(#pk, 20) do
    print(string.format("  %s x%d", pk[i], pcs[pk[i]]))
  end
  local h = io.open("flower-writes-out.json", "w")
  if h then
    local pparts = {}
    for k,v in pairs(pcs) do pparts[#pparts+1] = string.format('"%s":%d', k, v) end
    local aparts = {}
    for k,v in pairs(addrs) do aparts[#aparts+1] = string.format('"%s":%d', k, v) end
    h:write(string.format('{"pcs":{%s},"addrs":{%s},"events":[%s]}',
      table.concat(pparts, ","), table.concat(aparts, ","), table.concat(events, ",")))
    h:close()
  end
end
