-- NovOS Enhanced Shell
-- /novos/bin/shell.lua

local component = require("component")
local event     = require("event")
local fs        = require("filesystem")
local shell     = require("shell")
local computer  = require("computer")
local unicode   = require("unicode")
local gpu       = component.gpu
local term      = require("term")

local W, H = gpu.getResolution()

local C = {
  bg=0x0D1117, surface=0x161B22,
  accent=0x58A6FF, accent2=0x3FB950,
  warn=0xD29922, danger=0xF85149,
  text=0xE6EDF3, muted=0x8B949E,
  prompt1=0x58A6FF, prompt2=0x3FB950, prompt3=0xE6EDF3,
}

local history = {}
local histIdx = 0
local HIST_MAX = 50

local NOVOS_ROOT = "/novos"

-- ── Built-in commands ─────────────────────────────────────────────────────────
local builtins = {}

function builtins.help()
  local cmds = {
    {"help",    "Show this help"},
    {"exit",    "Exit shell"},
    {"clear",   "Clear screen"},
    {"ls",      "List directory"},
    {"cd",      "Change directory"},
    {"pwd",     "Print working directory"},
    {"cat",     "Print file contents"},
    {"mkdir",   "Create directory"},
    {"rm",      "Remove file"},
    {"cp",      "Copy file"},
    {"mv",      "Move/rename file"},
    {"mem",     "Show memory usage"},
    {"comps",   "List components"},
    {"exec",    "Execute Lua file"},
    {"novos",   "Launch NovOS desktop"},
    {"sysmon",  "System monitor"},
    {"files",   "File manager"},
    {"edit",    "Text editor"},
    {"uptime",  "Show uptime"},
    {"reboot",  "Reboot computer"},
    {"halt",    "Halt computer"},
  }
  gpu.setForeground(C.accent)
  print("NovOS Shell — Available commands:")
  gpu.setForeground(C.muted)
  print(string.rep("─",40))
  for _, row in ipairs(cmds) do
    gpu.setForeground(C.accent2)  io.write(string.format("  %-12s", row[1]))
    gpu.setForeground(C.text)     print(row[2])
  end
  gpu.setForeground(C.muted)
  print(string.rep("─",40))
  gpu.setForeground(C.text)
end

function builtins.clear()
  term.clear()
  term.setCursor(1,1)
end

function builtins.mem()
  local total = computer.totalMemory()
  local free  = computer.freeMemory()
  local used  = total - free
  local pct   = math.floor(used/total*100)
  gpu.setForeground(C.accent)
  print(string.format("Memory: %d/%d KB used (%d%%)", used//1024, total//1024, pct))
  local barW  = 30
  local filled = math.floor(barW * pct / 100)
  local barFG  = pct > 80 and C.danger or (pct > 55 and C.warn or C.accent2)
  gpu.setForeground(C.muted)   io.write("[")
  gpu.setForeground(barFG)     io.write(string.rep("█", filled))
  gpu.setForeground(C.surface) io.write(string.rep("░", barW-filled))
  gpu.setForeground(C.muted)   print("]")
  gpu.setForeground(C.text)
end

function builtins.uptime()
  local u = math.floor(computer.uptime())
  local h = math.floor(u/3600)
  local m = math.floor((u%3600)/60)
  local s = u%60
  gpu.setForeground(C.accent2)
  print(string.format("Uptime: %02d:%02d:%02d", h,m,s))
  gpu.setForeground(C.text)
end

function builtins.comps()
  gpu.setForeground(C.accent)
  print("Installed components:")
  local i = 0
  for addr, ctype in component.list() do
    gpu.setForeground(C.accent2) io.write(string.format("  %-20s ", ctype))
    gpu.setForeground(C.muted)   print(addr:sub(1,8))
    i = i + 1
  end
  gpu.setForeground(C.muted)
  print(string.format("Total: %d", i))
  gpu.setForeground(C.text)
end

function builtins.novos()
  local ok, err = pcall(loadfile, NOVOS_ROOT.."/bin/desktop.lua")
  if ok and ok ~= true then ok() else
    os.execute(NOVOS_ROOT.."/bin/desktop.lua")
  end
end

function builtins.sysmon()
  local f = loadfile(NOVOS_ROOT.."/bin/sysmon.lua")
  if f then f() else print("sysmon not found") end
end

function builtins.files()
  local f = loadfile(NOVOS_ROOT.."/bin/files.lua")
  if f then f() else print("files not found") end
end

function builtins.edit(...)
  local args = {...}
  local f = loadfile(NOVOS_ROOT.."/bin/editor.lua")
  if f then f(table.unpack(args)) else print("editor not found") end
end

function builtins.reboot()
  gpu.setForeground(C.warn) print("Rebooting...") os.sleep(0.5)
  computer.shutdown(true)
end

function builtins.halt()
  gpu.setForeground(C.warn) print("Halting...") os.sleep(0.5)
  computer.shutdown(false)
end

function builtins.exec(path, ...)
  if not path then print("Usage: exec <path>") return end
  local f, err = loadfile(path)
  if not f then
    gpu.setForeground(C.danger) print("Error: "..(err or "load failed"))
    gpu.setForeground(C.text) return
  end
  local ok, err2 = pcall(f, ...)
  if not ok then
    gpu.setForeground(C.danger) print("Runtime error: "..(err2 or "?"))
    gpu.setForeground(C.text)
  end
end

-- ── Prompt ────────────────────────────────────────────────────────────────────
local function drawPrompt()
  local cwd = shell.getWorkingDirectory() or "/"
  gpu.setForeground(C.accent2)   io.write("novos")
  gpu.setForeground(C.muted)     io.write("@oc")
  gpu.setForeground(C.muted)     io.write(":")
  gpu.setForeground(C.accent)    io.write(cwd)
  gpu.setForeground(C.text)      io.write(" › ")
end

-- ── Run command ───────────────────────────────────────────────────────────────
local function runCommand(line)
  line = line:match("^%s*(.-)%s*$")
  if line == "" then return true end

  -- Add to history
  if history[#history] ~= line then
    table.insert(history, line)
    if #history > HIST_MAX then table.remove(history, 1) end
  end
  histIdx = #history + 1

  -- Parse
  local parts = {}
  for part in line:gmatch("%S+") do table.insert(parts, part) end
  local cmd  = parts[1]
  local args = {}
  for i=2,#parts do table.insert(args, parts[i]) end

  -- exit
  if cmd == "exit" then return false end

  -- builtins
  if builtins[cmd] then
    local ok, err = pcall(builtins[cmd], table.unpack(args))
    if not ok then
      gpu.setForeground(C.danger) print("Error: "..(err or "?"))
      gpu.setForeground(C.text)
    end
    return true
  end

  -- pass to OC shell
  local ok, err = shell.execute(line)
  if not ok and err then
    gpu.setForeground(C.danger) print("Error: "..(err or "?"))
    gpu.setForeground(C.text)
  end
  return true
end

-- ── MOTD ─────────────────────────────────────────────────────────────────────
local function motd()
  term.clear()
  gpu.setForeground(C.accent)
  print("╔══════════════════════════════════════╗")
  print("║        NovOS Shell v1.0              ║")
  print("║  Type 'help' for available commands  ║")
  print("╚══════════════════════════════════════╝")
  gpu.setForeground(C.muted)
  builtins.mem()
  builtins.uptime()
  gpu.setForeground(C.text)
  print("")
end

-- ── Input with history ────────────────────────────────────────────────────────
local function readLine()
  local buf = ""
  local pos = 1  -- cursor position within buf (1 = before first char)
  histIdx = #history + 1
  local tempBuf = ""

  local function redraw()
    local cx, cy = term.getCursor()
    -- clear to end of line
    gpu.setForeground(C.text)
    io.write(buf .. " ")
    -- redraw from start of input
    local promptLen = 3  -- " › "
    -- move cursor
    term.setCursor(cx - #buf - 1 + pos - 1, cy)
  end

  while true do
    local ev = {event.pull()}
    if ev[1] == "key_down" then
      local char = ev[3]
      local code = ev[4]

      if code == 28 then -- enter
        print("")
        return buf
      elseif code == 14 then -- backspace
        if pos > 1 then
          buf = buf:sub(1,pos-2) .. buf:sub(pos)
          pos = pos - 1
          io.write("\8 \8")
        end
      elseif code == 200 then -- up
        if histIdx > 1 then
          if histIdx == #history+1 then tempBuf = buf end
          histIdx = histIdx - 1
          -- clear line
          io.write(string.rep("\8",pos-1)..string.rep(" ",#buf+1)..string.rep("\8",#buf+1))
          buf = history[histIdx] or ""
          pos = #buf+1
          gpu.setForeground(C.text) io.write(buf)
        end
      elseif code == 208 then -- down
        if histIdx <= #history then
          histIdx = histIdx + 1
          io.write(string.rep("\8",pos-1)..string.rep(" ",#buf+1)..string.rep("\8",#buf+1))
          buf = (histIdx > #history) and tempBuf or (history[histIdx] or "")
          pos = #buf+1
          gpu.setForeground(C.text) io.write(buf)
        end
      elseif char and char >= 32 then
        local ch = unicode.char(char)
        buf = buf:sub(1,pos-1)..ch..buf:sub(pos)
        pos = pos+1
        gpu.setForeground(C.text)
        io.write(ch)
      end
    elseif ev[1] == "interrupted" then
      print("")
      return "exit"
    end
  end
end

-- ── Main ──────────────────────────────────────────────────────────────────────
local function main()
  motd()
  local running = true
  while running do
    drawPrompt()
    local line = readLine()
    running = runCommand(line)
  end
  term.clear()
  gpu.setForeground(C.muted) print("Shell exited.")
  gpu.setForeground(C.text)
end

main()
