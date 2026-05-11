-- NovOS Settings
-- /novos/bin/settings.lua

local component = require("component")
local event     = require("event")
local fs        = require("filesystem")
local unicode   = require("unicode")
local gpu       = component.gpu

local W, H = gpu.getResolution()

local C = {
  bg=0x0D1117, surface=0x161B22, surface2=0x21262D,
  border=0x30363D, accent=0x58A6FF, accent2=0x3FB950,
  warn=0xD29922, danger=0xF85149, text=0xE6EDF3,
  muted=0x8B949E, selected=0x1C3A5E,
}

local function set(fg,bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function put(x,y,s) gpu.set(x,y,s) end
local function fill(x,y,w,h,c) gpu.fill(x,y,w,h,c or " ") end

local CONFIG_PATH = "/novos/cfg/novos.cfg"

local sections = {
  { name="Display",  icon="[DSP]" },
  { name="System",   icon="[SYS]" },
  { name="Network",  icon="[NET]" },
  { name="About",    icon="[NFO]" },
}

local settings = {
  display = {
    { key="resolution",  label="Resolution",    value="max",      options={"max","80x25","160x50"} },
    { key="colorscheme", label="Color Scheme",   value="dark",     options={"dark","darker","blue"} },
    { key="animations",  label="Boot animation", value="true",     options={"true","false"} },
  },
  system = {
    { key="autosave",    label="Autosave",       value="true",     options={"true","false"} },
    { key="shell",       label="Default Shell",  value="novos",    options={"novos","oc"} },
    { key="loglevel",    label="Log Level",      value="info",     options={"info","debug","warn"} },
  },
}

local state = {
  section  = 1,
  row      = 1,
  editing  = false,
  optIdx   = 1,
}

local function loadConfig()
  if not fs.exists(CONFIG_PATH) then return end
  local f = io.open(CONFIG_PATH,"r")
  if not f then return end
  for line in f:lines() do
    local k,v = line:match("^(%w+)%s*=%s*(.+)$")
    if k and v then
      for _,group in pairs(settings) do
        for _,row in ipairs(group) do
          if row.key == k then row.value = v end
        end
      end
    end
  end
  f:close()
end

local function saveConfig()
  fs.makeDirectory("/novos/cfg")
  local f = io.open(CONFIG_PATH,"w")
  if not f then return end
  for _, group in pairs(settings) do
    for _, row in ipairs(group) do
      f:write(row.key .. " = " .. row.value .. "\n")
    end
  end
  f:close()
end

local function currentGroup()
  local keys = {"display","system"}
  return settings[keys[state.section]] or {}
end

local function drawSidebar()
  local sw = 18
  set(C.surface2, C.surface2)
  fill(1, 2, sw, H-2)
  set(C.border, C.surface2)
  for j=2,H do put(sw,j,"│") end
  set(C.accent, C.surface2)
  put(2,2," SETTINGS")
  set(C.border,C.surface2)
  put(2,3,string.rep("─",sw-3))
  for i, sec in ipairs(sections) do
    local row = 4 + (i-1)*2
    local sel = (i == state.section)
    local bg  = sel and C.selected or C.surface2
    local fg  = sel and C.accent   or C.muted
    set(fg,bg)
    fill(1,row,sw-1,1)
    put(2,row, sec.icon .. " " .. sec.name)
  end
end

local function drawContent()
  local x, y = 20, 2
  local cw   = W - x - 1
  local group = currentGroup()
  local secName = sections[state.section].name

  set(C.surface, C.surface)
  fill(x,y,cw,H-2)
  set(C.accent, C.surface) put(x+1,y," "..secName.." Settings")
  set(C.border, C.surface) put(x+1,y+1,string.rep("─",cw-2))

  if state.section == 4 then
    -- About
    set(C.text,  C.surface) put(x+2,y+3,"NovOS v1.0.0")
    set(C.muted, C.surface) put(x+2,y+4,"Open-source OS for OpenComputers")
    put(x+2,y+5,"Lua 5.3 / OpenComputers API")
    put(x+2,y+6,"")
    put(x+2,y+7,"GitHub: github.com/yourusername/novos")
    set(C.accent2,C.surface)put(x+2,y+9,"Features:")
    set(C.muted,C.surface)
    local feats={
      "· Desktop environment with app dock",
      "· File manager with keyboard nav",
      "· System monitor with sparklines",
      "· Syntax-highlighted text editor",
      "· Enhanced shell with history",
      "· Configurable settings",
      "· Easy installer script",
    }
    for i,f in ipairs(feats) do put(x+4,y+9+i,f) end
    return
  end

  for i, row in ipairs(group) do
    local ry  = y + 2 + (i-1)*3
    local sel = (i == state.row) and not state.editing
    local edi = (i == state.row) and state.editing

    local bg = (sel or edi) and C.selected or C.surface
    set(C.muted, bg) fill(x+1,ry,cw-2,2)
    set(C.text,  bg) put(x+2,ry,   row.label)
    set(C.muted, bg) put(x+2,ry+1, "Key: "..row.key)

    -- value display
    local vbg = edi and C.highlight or (sel and C.selected or C.surface2)
    local vfg = edi and C.white     or C.accent
    set(vfg, vbg)
    local valStr = "  " .. row.value .. "  "
    put(x+cw-#valStr-4, ry, valStr)
    if sel and not edi then
      set(C.muted,bg)
      put(x+cw-#valStr-9, ry, "← →")
    end

    set(C.border,C.surface)
    put(x+1,ry+2,string.rep("─",cw-2))
  end

  -- instructions
  set(C.muted,C.surface)
  put(x+2,H-1,"↑↓:Navigate  ←→:Change value  S:Save  Q:Back")
end

local function cycleOption(row, dir)
  local opts = row.options
  if not opts then return end
  local idx = 1
  for i,o in ipairs(opts) do if o==row.value then idx=i break end end
  idx = ((idx-1+dir) % #opts) + 1
  row.value = opts[idx]
end

local function draw()
  gpu.setBackground(C.bg)
  fill(1,1,W,H)
  -- header
  set(C.text,C.surface2)
  fill(1,1,W,1)
  set(C.accent,C.surface2)  put(1,1," NovOS ")
  set(C.muted, C.surface2)  put(9,1,"Settings  —  use ↑↓ and ←→  Q to quit")

  drawSidebar()
  drawContent()
end

local function main()
  loadConfig()
  W, H = gpu.getResolution()
  local running = true
  while running do
    draw()
    local ev = {event.pull()}
    if ev[1] == "key_down" then
      local code = ev[4]
      local group = currentGroup()
      if code == 200 then -- up
        state.row = math.max(1, state.row-1)
      elseif code == 208 then -- down
        state.row = math.min(#group, state.row+1)
      elseif code == 203 then -- left
        if group[state.row] then cycleOption(group[state.row],-1) end
      elseif code == 205 then -- right
        if group[state.row] then cycleOption(group[state.row], 1) end
      elseif code == 15 then -- tab
        state.section = state.section % #sections + 1
        state.row = 1
      elseif code == 31 then -- s
        saveConfig()
      elseif code == 16 then -- q
        running = false
      end
    elseif ev[1] == "interrupted" then
      running = false
    end
  end
end

main()
