-- NovOS Desktop Environment
-- /novos/bin/desktop.lua

local component = require("component")
local event     = require("event")
local fs        = require("filesystem")
local term      = require("term")
local unicode   = require("unicode")
local gpu       = component.gpu
local computer  = require("computer")

local W, H = gpu.getResolution()

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
  bg        = 0x0D1117,
  surface   = 0x161B22,
  surface2  = 0x21262D,
  border    = 0x30363D,
  accent    = 0x58A6FF,
  accent2   = 0x3FB950,
  warn      = 0xD29922,
  danger    = 0xF85149,
  text      = 0xE6EDF3,
  muted     = 0x8B949E,
  highlight = 0x1F6FEB,
  selected  = 0x1C3A5E,
}

-- ── Render Helpers ────────────────────────────────────────────────────────────
local function set(fg, bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function fill(x,y,w,h,c) gpu.fill(x,y,w,h,c or " ") end
local function put(x,y,s) gpu.set(x,y,s) end

local function box(x,y,w,h,title,bc,bg)
  bc = bc or C.border; bg = bg or C.surface
  set(bc, bg)
  put(x, y, "┌"..string.rep("─",w-2).."┐")
  for j=y+1,y+h-2 do
    put(x, j, "│"); fill(x+1,j,w-2,1); put(x+w-1,j,"│")
  end
  put(x, y+h-1, "└"..string.rep("─",w-2).."┘")
  if title then
    set(C.accent, bg)
    put(x+2, y, " "..title.." ")
  end
end

local function button(x,y,label,active)
  local bg = active and C.highlight or C.surface2
  local fg = active and C.white    or C.text
  set(fg, bg)
  put(x, y, " "..label.." ")
  return unicode.len(label)+2
end

-- ── App Registry ──────────────────────────────────────────────────────────────
local apps = {
  { id="terminal", name="Terminal",    icon="[>_]", script="shell"    },
  { id="files",    name="Files",       icon="[DIR]", script="files"   },
  { id="sysmon",   name="System Mon",  icon="[CPU]", script="sysmon"  },
  { id="editor",   name="Text Editor", icon="[ED ]", script="editor"  },
  { id="network",  name="Network",     icon="[NET]", script="network" },
  { id="settings", name="Settings",    icon="[CFG]", script="settings"},
}

-- ── Taskbar ───────────────────────────────────────────────────────────────────
local function drawTaskbar()
  set(C.text, C.surface2)
  fill(1, H, W, 1)
  -- NovOS badge
  set(C.accent, C.surface2)
  put(1, H, " NovOS ")
  set(C.border, C.surface2)
  put(8, H, "│")
  -- Clock
  local t = os.time and os.time() or computer.uptime()
  -- uptime display since in-game clock may differ
  local uptime = math.floor(computer.uptime())
  local hh = math.floor(uptime/3600)
  local mm = math.floor((uptime%3600)/60)
  local ss = uptime % 60
  local clock = string.format(" %02d:%02d:%02d ", hh, mm, ss)
  set(C.muted, C.surface2)
  put(W - #clock + 1, H, clock)
  -- Memory bar
  local used = computer.totalMemory() - computer.freeMemory()
  local pct  = math.floor(used / computer.totalMemory() * 100)
  set(C.muted, C.surface2)
  put(W - #clock - 12, H, string.format("MEM:%3d%%", pct))
end

-- ── App Launcher (dock) ───────────────────────────────────────────────────────
local function drawDock(selectedIdx)
  local dockY = H - 1
  local colW  = 14
  set(C.surface, C.bg)
  fill(1, dockY, W, 1)
  for i, app in ipairs(apps) do
    local x   = (i-1) * colW + 1
    local sel = (i == selectedIdx)
    local fg  = sel and C.accent   or C.muted
    local bg  = sel and C.surface2 or C.bg
    set(fg, bg)
    local lbl = app.icon .. " " .. app.name
    put(x, dockY, string.format(" %-12s", lbl:sub(1,12)))
  end
end

-- ── Welcome Panel ─────────────────────────────────────────────────────────────
local function drawWelcome()
  local px, py = 3, 2
  local pw, ph = W - 4, H - 4

  box(px, py, pw, ph, "NovOS Desktop", C.border, C.surface)

  -- Greeting
  set(C.accent, C.surface)
  put(px+2, py+2, "Welcome to NovOS " .. "v1.0")
  set(C.muted, C.surface)
  put(px+2, py+3, string.rep("─", pw-4))

  -- Stats
  local used = computer.totalMemory() - computer.freeMemory()
  local pct  = math.floor(used / computer.totalMemory() * 100)
  local stats = {
    {"Memory",  string.format("%d/%d KB (%d%%)", used//1024, computer.totalMemory()//1024, pct)},
    {"Uptime",  string.format("%.0fs",  computer.uptime())},
    {"Arch",    _OSVERSION or "OpenComputers"},
    {"Lua",     _VERSION},
  }
  for i, row in ipairs(stats) do
    set(C.muted,  C.surface); put(px+2, py+4+i, row[1]..": ")
    set(C.text,   C.surface); put(px+2+unicode.len(row[1])+2, py+4+i, row[2])
  end

  -- Quick help
  set(C.muted, C.surface)
  put(px+2, py+ph-4, string.rep("─", pw-4))
  set(C.muted, C.surface)
  put(px+2, py+ph-3, "Use the dock below to launch apps. Press Q to quit to shell.")
  put(px+2, py+ph-2, "Arrow keys: navigate dock   Enter: launch   R: refresh")

  -- App grid
  local gridX = px + 2
  local gridY = py + 9
  local cols  = 3
  set(C.accent2, C.surface)
  put(gridX, gridY-1, "── Applications ──")
  for i, app in ipairs(apps) do
    local row = math.floor((i-1) / cols)
    local col = (i-1) % cols
    local ax  = gridX + col * 22
    local ay  = gridY + row * 2
    set(C.surface2, C.surface)
    -- mini button
    set(C.muted, C.surface2)
    put(ax, ay,   "┌────────────────────┐")
    put(ax, ay+1, "│ " .. app.icon .. " " ..
        string.format("%-14s", app.name:sub(1,14)) .. "│")
    set(C.muted, C.surface2)
    put(ax, ay+2, "└────────────────────┘")
    set(C.muted, C.surface2)
    put(ax+2, ay+1, "")
  end
end

-- ── Run App ───────────────────────────────────────────────────────────────────
local function runApp(app)
  local path = "/novos/bin/" .. app.script .. ".lua"
  if fs.exists(path) then
    term.clear()
    local ok, err = pcall(loadfile(path))
    if not ok then
      gpu.setForeground(0xF85149)
      print("App error: " .. tostring(err))
      gpu.setForeground(0xE6EDF3)
      print("Press Enter to return to desktop.")
      io.read()
    end
  else
    -- Fallback: drop to shell with a message
    term.clear()
    gpu.setForeground(C.warn)
    print("App '" .. app.name .. "' not yet installed.")
    print("Script expected at: " .. path)
    gpu.setForeground(C.muted)
    print("Press Enter to return.")
    io.read()
  end
end

-- ── Main Loop ─────────────────────────────────────────────────────────────────
local function main()
  gpu.setResolution(gpu.maxResolution())
  W, H = gpu.getResolution()

  local selected = 1
  local running  = true

  while running do
    gpu.setBackground(C.bg)
    gpu.fill(1, 1, W, H, " ")

    drawWelcome()
    drawDock(selected)
    drawTaskbar()

    -- Event loop
    local ev = {event.pull(1)}
    local etype = ev[1]

    if etype == "key_down" then
      local code = ev[4]
      if code == 203 then -- left arrow
        selected = math.max(1, selected - 1)
      elseif code == 205 then -- right arrow
        selected = math.min(#apps, selected + 1)
      elseif code == 28 then -- enter
        runApp(apps[selected])
      elseif code == 16 then -- q
        running = false
      elseif code == 19 then -- r
        -- refresh / redraw
      end
    elseif etype == "interrupted" then
      running = false
    end
  end

  term.clear()
  gpu.setForeground(C.text)
  print("NovOS desktop exited. Type 'novos' to restart.")
end

main()
