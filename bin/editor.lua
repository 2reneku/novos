-- NovOS Text Editor
-- /novos/bin/editor.lua
-- Usage: editor.lua [filename]

local component = require("component")
local event     = require("event")
local fs        = require("filesystem")
local unicode   = require("unicode")
local gpu       = component.gpu
local keyboard  = require("keyboard")

local W, H = gpu.getResolution()

local C = {
  bg=0x0D1117, surface=0x161B22, gutter=0x21262D,
  border=0x30363D, accent=0x58A6FF, accent2=0x3FB950,
  warn=0xD29922, danger=0xF85149, text=0xE6EDF3,
  muted=0x8B949E, cursor=0xFFFFFF, curLine=0x1C2B3A,
  keyword=0xFF7B72, string_c=0xA5D6FF, comment=0x8B949E,
  number=0xD2A8FF,
}

local function set(fg,bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function put(x,y,s) gpu.set(x,y,s) end
local function fill(x,y,w,h,c) gpu.fill(x,y,w,h,c or " ") end

-- ── Editor State ──────────────────────────────────────────────────────────────
local ed = {
  lines    = {""},
  cursor   = {row=1, col=1},
  scroll   = {row=0, col=0},
  filename = nil,
  modified = false,
  message  = "",
}

local GUTTER   = 5
local TEXT_X   = GUTTER + 2
local TEXT_W   = W - GUTTER - 1
local TEXT_H   = H - 2

-- ── File ops ──────────────────────────────────────────────────────────────────
local function loadFile(path)
  if not fs.exists(path) then
    ed.lines = {""}
    ed.filename = path
    ed.message = "New file: " .. path
    return
  end
  local f = io.open(path,"r")
  if not f then ed.message = "Cannot open: "..path return end
  ed.lines = {}
  for line in f:lines() do table.insert(ed.lines, line) end
  f:close()
  if #ed.lines == 0 then ed.lines = {""} end
  ed.filename = path
  ed.modified = false
  ed.message  = "Opened: " .. path
end

local function saveFile()
  if not ed.filename then
    -- prompt for name
    set(C.accent,C.bg)
    put(1,H," Save as: ")
    set(C.text,C.bg)
    local name = io.read()
    if not name or name=="" then ed.message="Save cancelled" return end
    ed.filename = name
  end
  local f = io.open(ed.filename,"w")
  if not f then ed.message="Cannot write: "..ed.filename return end
  for i,line in ipairs(ed.lines) do
    f:write(line)
    if i < #ed.lines then f:write("\n") end
  end
  f:close()
  ed.modified = false
  ed.message  = "Saved: " .. ed.filename
end

-- ── Syntax highlight (Lua) ────────────────────────────────────────────────────
local LUA_KEYS = {
  "and","break","do","else","elseif","end","false","for","function",
  "goto","if","in","local","nil","not","or","repeat","return","then",
  "true","until","while",
}
local LUA_KEY_SET = {}
for _,k in ipairs(LUA_KEYS) do LUA_KEY_SET[k] = true end

local function renderLine(x, y, line, maxW)
  -- very simple tokenizer
  local out = {}
  local i = 1
  local s = line
  while i <= #s do
    -- comment
    if s:sub(i,i+1) == "--" then
      table.insert(out, {color=C.comment, text=s:sub(i)})
      break
    end
    -- string
    if s:sub(i,i) == '"' or s:sub(i,i) == "'" then
      local q = s:sub(i,i)
      local j = i+1
      while j <= #s and s:sub(j,j) ~= q do j=j+1 end
      table.insert(out, {color=C.string_c, text=s:sub(i,j)})
      i = j+1
    -- number
    elseif s:sub(i,i):match("%d") then
      local j = i
      while j <= #s and s:sub(j,j):match("[%d%.xXa-fA-F]") do j=j+1 end
      table.insert(out, {color=C.number, text=s:sub(i,j-1)})
      i = j
    -- identifier / keyword
    elseif s:sub(i,i):match("[%a_]") then
      local j = i
      while j <= #s and s:sub(j,j):match("[%w_]") do j=j+1 end
      local word = s:sub(i,j-1)
      local col  = LUA_KEY_SET[word] and C.keyword or C.text
      table.insert(out, {color=col, text=word})
      i = j
    else
      local ch = s:sub(i,i)
      table.insert(out, {color=C.text, text=ch})
      i = i+1
    end
  end

  -- render
  local cx = x
  for _, tok in ipairs(out) do
    local remaining = maxW - (cx - x)
    if remaining <= 0 then break end
    local disp = tok.text:sub(1, remaining)
    set(tok.color, (y == ed.cursor.row + ed.scroll.row and C.curLine or C.bg))
    gpu.set(cx, y, disp)
    cx = cx + #disp
  end
  -- fill rest of line
  if cx <= x + maxW - 1 then
    local bg = (y == ed.cursor.row + ed.scroll.row) and C.curLine or C.bg
    set(C.bg, bg)
    fill(cx, y, x+maxW-cx, 1)
  end
end

-- ── Draw ──────────────────────────────────────────────────────────────────────
local function draw()
  gpu.setBackground(C.bg)
  fill(1,1,W,H)

  -- Header bar
  set(C.text, C.surface)
  fill(1,1,W,1)
  set(C.accent, C.surface)
  put(1,1," NovOS Editor ")
  local fname = (ed.filename or "[no name]") .. (ed.modified and " *" or "")
  set(C.text, C.surface)
  put(16,1,fname)
  set(C.muted, C.surface)
  put(W-24,1,string.format(" Ln %d, Col %d", ed.cursor.row, ed.cursor.col))

  -- Lines
  local isLua = ed.filename and (ed.filename:match("%.lua$") ~= nil)
  for screenRow = 1, TEXT_H do
    local lineIdx = screenRow + ed.scroll.row
    local y       = screenRow + 1

    -- Gutter
    local gutBG = (lineIdx == ed.cursor.row) and C.curLine or C.gutter
    set(lineIdx == ed.cursor.row and C.accent or C.muted, gutBG)
    fill(1,y,GUTTER,1)
    if lineIdx <= #ed.lines then
      put(1, y, string.format("%"..GUTTER.."d", lineIdx))
    end
    put(GUTTER+1,y,"│")

    -- Text
    if lineIdx <= #ed.lines then
      local line = ed.lines[lineIdx]
      -- horizontal scroll
      local dispLine = line:sub(1 + ed.scroll.col)
      if isLua then
        renderLine(TEXT_X, y, dispLine, TEXT_W)
      else
        local bg = (lineIdx == ed.cursor.row) and C.curLine or C.bg
        set(C.text, bg)
        fill(TEXT_X, y, TEXT_W, 1)
        put(TEXT_X, y, dispLine:sub(1, TEXT_W))
      end
    end
  end

  -- Cursor
  local cy = ed.cursor.row - ed.scroll.row + 2
  local cx = TEXT_X + ed.cursor.col - 1 - ed.scroll.col
  if cy >= 2 and cy < H and cx >= TEXT_X and cx < TEXT_X+TEXT_W then
    local line = ed.lines[ed.cursor.row] or ""
    local ch   = line:sub(ed.cursor.col, ed.cursor.col)
    if ch == "" then ch = " " end
    set(C.bg, C.cursor)
    put(cx, cy, ch)
  end

  -- Status bar
  set(C.text, C.surface)
  fill(1,H,W,1)
  set(C.muted, C.surface)
  put(1,H," Ctrl+S:Save  Ctrl+Q:Quit  Ctrl+G:GoToLine  "
       .. "#lines:"..#ed.lines)
  if ed.message ~= "" then
    set(C.accent2, C.surface)
    put(W - unicode.len(ed.message) - 1, H, ed.message)
  end
end

-- ── Cursor movement ────────────────────────────────────────────────────────────
local function clampCursor()
  ed.cursor.row = math.max(1, math.min(ed.cursor.row, #ed.lines))
  local lineLen = #(ed.lines[ed.cursor.row] or "")
  ed.cursor.col = math.max(1, math.min(ed.cursor.col, lineLen+1))
  -- scroll
  if ed.cursor.row > ed.scroll.row + TEXT_H then
    ed.scroll.row = ed.cursor.row - TEXT_H
  elseif ed.cursor.row <= ed.scroll.row then
    ed.scroll.row = ed.cursor.row - 1
  end
  if ed.cursor.col > ed.scroll.col + TEXT_W then
    ed.scroll.col = ed.cursor.col - TEXT_W
  elseif ed.cursor.col <= ed.scroll.col then
    ed.scroll.col = math.max(0, ed.cursor.col - 1)
  end
end

-- ── Input handling ─────────────────────────────────────────────────────────────
local function handleKey(char, code, ctrl)
  ed.message = ""

  if ctrl then
    if code == 31 then saveFile()         -- Ctrl+S
    elseif code == 16 then return false   -- Ctrl+Q
    elseif code == 34 then                -- Ctrl+G goto line
      set(C.accent,C.bg) put(1,H," Go to line: ")
      set(C.text,C.bg)
      local n = tonumber(io.read())
      if n then ed.cursor.row = n end
    end
    return true
  end

  local r,c  = ed.cursor.row, ed.cursor.col
  local line = ed.lines[r]

  if code == 200 then ed.cursor.row = r-1                           -- up
  elseif code == 208 then ed.cursor.row = r+1                       -- down
  elseif code == 203 then ed.cursor.col = c-1                       -- left
  elseif code == 205 then ed.cursor.col = c+1                       -- right
  elseif code == 199 then ed.cursor.col = 1                         -- home
  elseif code == 207 then ed.cursor.col = #line+1                   -- end
  elseif code == 201 then ed.cursor.row = r - TEXT_H                -- pgup
  elseif code == 209 then ed.cursor.row = r + TEXT_H                -- pgdn

  elseif code == 28 then  -- enter
    local before = line:sub(1,c-1)
    local after  = line:sub(c)
    ed.lines[r] = before
    table.insert(ed.lines, r+1, after)
    ed.cursor.row = r+1; ed.cursor.col = 1
    ed.modified = true

  elseif code == 14 then  -- backspace
    if c > 1 then
      ed.lines[r] = line:sub(1,c-2)..line:sub(c)
      ed.cursor.col = c-1
    elseif r > 1 then
      local prev = ed.lines[r-1]
      ed.cursor.col = #prev+1
      ed.lines[r-1] = prev .. line
      table.remove(ed.lines, r)
      ed.cursor.row = r-1
    end
    ed.modified = true

  elseif code == 211 then -- delete
    if c <= #line then
      ed.lines[r] = line:sub(1,c-1)..line:sub(c+1)
    elseif r < #ed.lines then
      ed.lines[r] = line .. ed.lines[r+1]
      table.remove(ed.lines, r+1)
    end
    ed.modified = true

  elseif char and char >= 32 then  -- printable
    local ch_s = unicode.char(char)
    ed.lines[r] = line:sub(1,c-1)..ch_s..line:sub(c)
    ed.cursor.col = c + 1
    ed.modified = true
  end

  return true
end

-- ── Main ──────────────────────────────────────────────────────────────────────
local function main()
  W, H = gpu.getResolution()
  TEXT_H = H-2

  local arg = {...}
  if arg[1] then loadFile(arg[1]) end

  local running = true
  while running do
    clampCursor()
    draw()
    local ev = {event.pull()}
    if ev[1] == "key_down" then
      local char  = ev[3]
      local code  = ev[4]
      local ctrl  = keyboard.isControlDown()
      running = handleKey(char, code, ctrl)
    elseif ev[1] == "interrupted" then
      running = false
    end
  end
end

main()
