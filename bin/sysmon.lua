-- NovOS System Monitor
-- /novos/bin/sysmon.lua

local component = require("component")
local event     = require("event")
local computer  = require("computer")
local unicode   = require("unicode")
local gpu       = component.gpu

local W, H = gpu.getResolution()

local C = {
  bg      = 0x0D1117, surface = 0x161B22, surface2 = 0x21262D,
  border  = 0x30363D, accent  = 0x58A6FF, accent2  = 0x3FB950,
  warn    = 0xD29922, danger  = 0xF85149, text     = 0xE6EDF3,
  muted   = 0x8B949E,
}

local function set(fg,bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function put(x,y,s) gpu.set(x,y,s) end
local function fill(x,y,w,h,c) gpu.fill(x,y,w,h,c or " ") end

local function box(x,y,w,h,title)
  set(C.border, C.surface)
  put(x,y,"┌"..string.rep("─",w-2).."┐")
  for j=y+1,y+h-2 do put(x,j,"│") fill(x+1,j,w-2,1) put(x+w-1,j,"│") end
  put(x,y+h-1,"└"..string.rep("─",w-2).."┘")
  if title then set(C.accent,C.surface) put(x+2,y," "..title.." ") end
end

local function bar(x, y, w, value, max, fg)
  local filled = math.floor(w * value / math.max(max,1))
  filled = math.min(filled, w)
  fg = fg or C.accent
  set(C.border, C.surface) put(x,y,"[") put(x+w+1,y,"]")
  set(fg, C.surface) put(x+1,y,string.rep("█", filled))
  set(C.surface2, C.surface) put(x+1+filled, y, string.rep("░", w-filled))
end

local function pctColor(p)
  if p > 80 then return C.danger
  elseif p > 55 then return C.warn
  else return C.accent2 end
end

-- Memory history for sparkline
local memHistory = {}
local MAX_HIST = 30

local function updateHistory()
  local used = computer.totalMemory() - computer.freeMemory()
  local pct  = used / computer.totalMemory() * 100
  table.insert(memHistory, pct)
  if #memHistory > MAX_HIST then table.remove(memHistory, 1) end
end

local SPARK = {" ", "▁","▂","▃","▄","▅","▆","▇","█"}
local function sparkline(x, y, hist, maxV)
  maxV = maxV or 100
  for i, v in ipairs(hist) do
    local idx = math.max(1, math.floor(v/maxV * 8) + 1)
    local fg  = pctColor(v)
    set(fg, C.surface)
    put(x+i-1, y, SPARK[idx])
  end
end

local function drawHeader()
  set(C.bg, C.bg)
  fill(1,1,W,1)
  set(C.accent, C.bg)
  put(1,1," NovOS System Monitor ")
  set(C.muted, C.bg)
  local uptime = math.floor(computer.uptime())
  local h = math.floor(uptime/3600); local m = math.floor((uptime%3600)/60); local s = uptime%60
  put(W-18,1,string.format("Up %02d:%02d:%02d  Q:quit",h,m,s))
end

local function drawMemory(x,y,w,h)
  box(x,y,w,h,"Memory")
  local total = computer.totalMemory()
  local free  = computer.freeMemory()
  local used  = total - free
  local pct   = math.floor(used/total*100)

  set(C.text, C.surface)
  put(x+2,y+2,string.format("Total : %5d KB", total//1024))
  put(x+2,y+3,string.format("Used  : %5d KB", used//1024))
  put(x+2,y+4,string.format("Free  : %5d KB", free//1024))

  set(pctColor(pct), C.surface)
  put(x+2,y+5,string.format("Usage : %d%%", pct))
  bar(x+2,y+6, w-5, pct, 100, pctColor(pct))

  -- Sparkline
  set(C.muted,C.surface) put(x+2,y+8,"History:")
  sparkline(x+2, y+9, memHistory, 100)
end

local function drawComponents(x,y,w,h)
  box(x,y,w,h,"Components")
  local comps = {}
  for addr, ctype in component.list() do
    table.insert(comps, {addr=addr:sub(1,8), ctype=ctype})
  end
  table.sort(comps, function(a,b) return a.ctype < b.ctype end)
  local row = y+2
  local shown = 0
  for _, c in ipairs(comps) do
    if row > y+h-2 then break end
    set(C.accent2, C.surface) put(x+2, row, c.ctype)
    set(C.muted,   C.surface) put(x+2+unicode.len(c.ctype)+1, row, c.addr)
    row = row + 1
    shown = shown + 1
  end
  if #comps > shown then
    set(C.muted,C.surface)
    put(x+2,y+h-2,string.format("... and %d more", #comps-shown))
  end
end

local function drawEnergy(x,y,w,h)
  box(x,y,w,h,"Energy")
  -- Try to get energy info
  local cap, stored = 0, 0
  local found = false
  for addr, ctype in component.list() do
    if ctype == "capacitor_bank" or ctype == "energy_cell" then
      local c = component.proxy(addr)
      if c and c.getCapacity then
        cap    = cap    + (c.getCapacity()   or 0)
        stored = stored + (c.getStored()     or 0)
        found  = true
      end
    end
  end
  if not found then
    set(C.muted,C.surface) put(x+2,y+2,"No energy storage")
    put(x+2,y+3,"detected.")
    return
  end
  local pct = math.floor(stored/math.max(cap,1)*100)
  set(C.text,C.surface)
  put(x+2,y+2,string.format("Stored   : %8.0f RF", stored))
  put(x+2,y+3,string.format("Capacity : %8.0f RF", cap))
  set(pctColor(100-pct),C.surface)
  put(x+2,y+4,string.format("Charge   : %d%%", pct))
  bar(x+2,y+5,w-5,pct,100,pctColor(pct))
end

local function drawFilesystem(x,y,w,h)
  local fs = require("filesystem")
  box(x,y,w,h,"Filesystem")
  local mounts = {}
  for path, dev in fs.mounts() do
    table.insert(mounts,{path=path, dev=dev})
  end
  local row = y+2
  for _, m in ipairs(mounts) do
    if row > y+h-2 then break end
    -- try to get space
    local ok, total = pcall(function() return m.dev.spaceTotal() end)
    local ok2, used = pcall(function() return total - m.dev.spaceUsed() end)
    set(C.accent2, C.surface)
    put(x+2,row, m.path == "" and "/" or m.path)
    if ok and total and total > 0 then
      set(C.muted,C.surface)
      put(x+14,row,string.format("%dKB", total//1024))
    end
    row = row+1
  end
end

local function draw()
  gpu.setBackground(C.bg)
  fill(1,1,W,H)
  drawHeader()

  local col1 = math.floor(W/2)
  local col2 = W - col1

  drawMemory    (1,      2,  col1,      14)
  drawComponents(col1+1, 2,  col2,      14)
  drawEnergy    (1,      16, col1,      8)
  drawFilesystem(col1+1, 16, col2,      8)

  set(C.muted,C.bg)
  put(1,H," Press Q to exit │ Auto-refreshes every 2s")
end

local function main()
  W, H = gpu.getResolution()
  local running = true
  while running do
    updateHistory()
    draw()
    local ev = {event.pull(2)}
    if ev[1] == "key_down" then
      local code = ev[4]
      if code == 16 then running = false end -- q
    elseif ev[1] == "interrupted" then
      running = false
    end
  end
end

main()
