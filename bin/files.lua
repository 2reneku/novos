-- NovOS File Manager
-- /novos/bin/files.lua

local component = require("component")
local event     = require("event")
local fs        = require("filesystem")
local shell     = require("shell")
local unicode   = require("unicode")
local gpu       = component.gpu

local W, H = gpu.getResolution()

local C = {
  bg=0x0D1117, surface=0x161B22, surface2=0x21262D,
  border=0x30363D, accent=0x58A6FF, accent2=0x3FB950,
  warn=0xD29922, danger=0xF85149, text=0xE6EDF3,
  muted=0x8B949E, selected=0x1C3A5E, seltext=0xFFFFFF,
}

local function set(fg,bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function put(x,y,s) gpu.set(x,y,s) end
local function fill(x,y,w,h,c) gpu.fill(x,y,w,h,c or " ") end

local state = {
  cwd      = "/",
  entries  = {},
  selected = 1,
  scroll   = 0,
  message  = "",
  panel    = "left",  -- future: dual-pane
}

local function getEntries(path)
  local list = {}
  if path ~= "/" then
    table.insert(list, {name="..", isDir=true, size=0})
  end
  for name in fs.list(path) do
    local full = fs.concat(path, name)
    local isDir = fs.isDirectory(full)
    local size  = 0
    if not isDir then
      size = fs.size(full) or 0
    end
    table.insert(list, {name=name, isDir=isDir, size=size})
  end
  table.sort(list, function(a,b)
    if a.name == ".." then return true end
    if b.name == ".." then return false end
    if a.isDir ~= b.isDir then return a.isDir end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

local function formatSize(n)
  if n > 1048576 then return string.format("%.1fM", n/1048576)
  elseif n > 1024 then return string.format("%.1fK", n/1024)
  else return tostring(n).."B" end
end

local PANEL_X, PANEL_Y = 1, 2
local PANEL_W, PANEL_H  -- set in draw

local function drawStatusBar()
  set(C.text, C.surface2)
  fill(1,H,W,1)
  set(C.accent,C.surface2) put(1,H,"  Files  ")
  set(C.muted, C.surface2)
  put(12,H, "↑↓:Nav  Enter:Open  D:Delete  N:NewDir  C:Copy  R:Rename  Q:Quit")
  if state.message ~= "" then
    set(C.warn, C.surface2)
    put(W - unicode.len(state.message) - 1, H, state.message)
  end
end

local function drawHeader()
  set(C.bg,C.bg) fill(1,1,W,1)
  set(C.accent,C.bg) put(1,1," File Manager ")
  set(C.muted,C.bg)
  put(16,1,"› " .. state.cwd)
end

local function drawPane()
  PANEL_W = W
  PANEL_H = H - 2

  -- Border
  set(C.border, C.surface)
  put(PANEL_X, PANEL_Y, "┌"..string.rep("─",PANEL_W-2).."┐")
  for j=PANEL_Y+1, PANEL_Y+PANEL_H-1 do
    put(PANEL_X,j,"│") fill(PANEL_X+1,j,PANEL_W-2,1) put(PANEL_X+PANEL_W-1,j,"│")
  end
  put(PANEL_X,PANEL_Y+PANEL_H,"└"..string.rep("─",PANEL_W-2).."┘")

  -- Column headers
  set(C.muted, C.surface)
  put(PANEL_X+1, PANEL_Y+1, string.format(" %-4s %-40s %8s  %s",
    "Type", "Name", "Size", "Info"))
  set(C.border,C.surface)
  put(PANEL_X+1, PANEL_Y+2, string.rep("─", PANEL_W-2))

  local visRows = PANEL_H - 4
  local entries = state.entries
  local scroll  = state.scroll

  for i = 1, visRows do
    local idx = i + scroll
    if idx > #entries then break end
    local e   = entries[idx]
    local row = PANEL_Y + 2 + i
    local sel = (idx == state.selected)

    local bg = sel and C.selected or C.surface
    local fg = sel and C.seltext  or C.text

    fill(PANEL_X+1, row, PANEL_W-2, 1)

    local icon = e.isDir and "DIR" or "   "
    local name = e.name
    if e.isDir and e.name ~= ".." then name = name .. "/" end
    local nameDisp = name:sub(1,40)

    local sizeStr = e.isDir and "      --" or string.format("%8s", formatSize(e.size))

    set(e.isDir and C.accent or C.text, bg)
    put(PANEL_X+2, row, string.format("[%s] %-40s %8s", icon, nameDisp, sizeStr))
  end
end

local function navigate(entry)
  if entry.name == ".." then
    state.cwd = fs.path(state.cwd:gsub("/$","")) or "/"
  elseif entry.isDir then
    state.cwd = fs.concat(state.cwd, entry.name)
  else
    return false -- not a dir
  end
  if not state.cwd or state.cwd == "" then state.cwd = "/" end
  state.entries = getEntries(state.cwd)
  state.selected = 1
  state.scroll = 0
  return true
end

local function openEntry(entry)
  if entry.isDir then
    navigate(entry)
  else
    -- Try to open with editor
    local path = fs.concat(state.cwd, entry.name)
    local ext  = entry.name:match("%.(%w+)$") or ""
    if ext == "lua" or ext == "txt" or ext == "cfg" or ext == "md" then
      -- launch editor with the file
      os.execute("edit " .. path)
    else
      state.message = "No viewer for ." .. ext
    end
  end
end

local function deleteEntry(entry)
  if entry.name == ".." then return end
  local path = fs.concat(state.cwd, entry.name)
  local ok, err = pcall(function()
    if entry.isDir then fs.remove(path)
    else fs.remove(path) end
  end)
  if ok then state.message = "Deleted: "..entry.name
  else state.message = "Error: "..(err or "?") end
  state.entries = getEntries(state.cwd)
  state.selected = math.min(state.selected, #state.entries)
end

local function newDir()
  term = require("term")
  term.setCursor(1,H-1)
  gpu.setForeground(C.accent) gpu.setBackground(C.bg)
  io.write("New folder name: ")
  gpu.setForeground(C.text)
  local name = io.read()
  if name and name ~= "" then
    local path = fs.concat(state.cwd, name)
    local ok, err = pcall(fs.makeDirectory, path)
    state.message = ok and ("Created: "..name) or ("Error: "..(err or "?"))
    state.entries = getEntries(state.cwd)
  end
end

local function renameEntry(entry)
  if entry.name == ".." then return end
  local term = require("term")
  term.setCursor(1,H-1)
  gpu.setForeground(C.accent) gpu.setBackground(C.bg)
  io.write("Rename '"..entry.name.."' to: ")
  gpu.setForeground(C.text)
  local newname = io.read()
  if newname and newname ~= "" then
    local src = fs.concat(state.cwd, entry.name)
    local dst = fs.concat(state.cwd, newname)
    local ok, err = pcall(fs.rename, src, dst)
    state.message = ok and ("Renamed to: "..newname) or ("Error: "..(err or "?"))
    state.entries = getEntries(state.cwd)
  end
end

local function copyEntry(entry)
  if entry.isDir or entry.name == ".." then
    state.message = "Cannot copy directories yet"
    return
  end
  local src = fs.concat(state.cwd, entry.name)
  local term = require("term")
  term.setCursor(1,H-1)
  gpu.setForeground(C.accent) gpu.setBackground(C.bg)
  io.write("Copy to path: ")
  gpu.setForeground(C.text)
  local dst = io.read()
  if dst and dst ~= "" then
    local ok, err = pcall(function()
      local fin  = io.open(src,"rb")
      local fout = io.open(dst,"wb")
      if not fin or not fout then error("open failed") end
      fout:write(fin:read("*a"))
      fin:close(); fout:close()
    end)
    state.message = ok and "Copied!" or ("Error: "..(err or "?"))
    state.entries = getEntries(state.cwd)
  end
end

local function adjustScroll()
  local visRows = PANEL_H - 4
  if state.selected > state.scroll + visRows then
    state.scroll = state.selected - visRows
  elseif state.selected <= state.scroll then
    state.scroll = state.selected - 1
  end
  state.scroll = math.max(0, state.scroll)
end

local function draw()
  PANEL_H = H - 2
  gpu.setBackground(C.bg)
  fill(1,1,W,H)
  drawHeader()
  drawPane()
  drawStatusBar()
end

local function main()
  W, H = gpu.getResolution()
  PANEL_H = H-2
  state.entries = getEntries(state.cwd)

  local running = true
  while running do
    adjustScroll()
    draw()

    local ev = {event.pull()}
    if ev[1] == "key_down" then
      local code = ev[4]
      local e    = state.entries[state.selected]
      state.message = ""

      if code == 200 then -- up
        state.selected = math.max(1, state.selected - 1)
      elseif code == 208 then -- down
        state.selected = math.min(#state.entries, state.selected + 1)
      elseif code == 201 then -- page up
        state.selected = math.max(1, state.selected - 10)
      elseif code == 209 then -- page down
        state.selected = math.min(#state.entries, state.selected + 10)
      elseif code == 199 then -- home
        state.selected = 1
      elseif code == 207 then -- end
        state.selected = #state.entries
      elseif code == 28 and e then -- enter
        openEntry(e)
      elseif code == 32 and e then -- d
        deleteEntry(e)
      elseif code == 49 and e then -- n
        newDir()
      elseif code == 46 and e then -- c
        copyEntry(e)
      elseif code == 19 and e then -- r
        renameEntry(e)
      elseif code == 16 then -- q
        running = false
      end
    elseif ev[1] == "interrupted" then
      running = false
    end
  end
end

main()
