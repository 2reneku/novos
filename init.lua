-- NovOS v1.0 | by NovOS Project
-- Main init script for OpenComputers
-- https://github.com/yourusername/novos

local component = require("component")
local computer  = require("computer")
local event     = require("event")
local fs        = require("filesystem")
local shell     = require("shell")
local term      = require("term")
local gpu       = component.gpu
local unicode   = require("unicode")

-- ── Constants ────────────────────────────────────────────────────────────────
local NOVOS_VERSION = "1.0.0"
local NOVOS_ROOT    = "/novos"
local CONFIG_PATH   = NOVOS_ROOT .. "/cfg/novos.cfg"

-- ── Color Palette ─────────────────────────────────────────────────────────────
local C = {
  bg        = 0x0D1117,
  surface   = 0x161B22,
  border    = 0x30363D,
  accent    = 0x58A6FF,
  accent2   = 0x3FB950,
  warn      = 0xD29922,
  danger    = 0xF85149,
  text      = 0xE6EDF3,
  muted     = 0x8B949E,
  highlight = 0x1F6FEB,
  white     = 0xFFFFFF,
  black     = 0x000000,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function setColor(fg, bg)
  gpu.setForeground(fg or C.text)
  if bg then gpu.setBackground(bg) end
end

local function cls()
  gpu.setBackground(C.bg)
  gpu.fill(1, 1, gpu.getResolution())
end

local function center(y, text, fg, bg)
  local w = select(1, gpu.getResolution())
  local x = math.floor((w - unicode.len(text)) / 2) + 1
  setColor(fg or C.text, bg)
  gpu.set(x, y, text)
end

local function hline(y, char, fg, bg)
  local w = select(1, gpu.getResolution())
  setColor(fg or C.border, bg or C.bg)
  gpu.set(1, y, string.rep(char or "─", w))
end

local function box(x, y, w, h, title, fg_border, bg_fill)
  bg_fill  = bg_fill  or C.surface
  fg_border = fg_border or C.border
  setColor(fg_border, bg_fill)
  -- corners
  gpu.set(x,       y,       "┌")
  gpu.set(x+w-1,   y,       "┐")
  gpu.set(x,       y+h-1,   "└")
  gpu.set(x+w-1,   y+h-1,   "┘")
  -- top/bottom edges
  for i = x+1, x+w-2 do
    gpu.set(i, y,     "─")
    gpu.set(i, y+h-1, "─")
  end
  -- sides + fill
  for j = y+1, y+h-2 do
    gpu.set(x,     j, "│")
    gpu.set(x+w-1, j, "│")
    setColor(fg_border, bg_fill)
    gpu.fill(x+1, j, w-2, 1, " ")
  end
  if title then
    setColor(C.accent, bg_fill)
    gpu.set(x+2, y, " " .. title .. " ")
  end
end

-- ── Config ────────────────────────────────────────────────────────────────────
local Config = {}

function Config.load()
  local cfg = {}
  if fs.exists(CONFIG_PATH) then
    local f = io.open(CONFIG_PATH, "r")
    if f then
      for line in f:lines() do
        local k, v = line:match("^(%w+)%s*=%s*(.+)$")
        if k then cfg[k] = v end
      end
      f:close()
    end
  end
  return cfg
end

function Config.save(t)
  local f = io.open(CONFIG_PATH, "w")
  if f then
    for k, v in pairs(t) do
      f:write(k .. " = " .. tostring(v) .. "\n")
    end
    f:close()
  end
end

-- ── Boot Splash ────────────────────────────────────────────────────────────────
local function bootSplash()
  cls()
  local w, h = gpu.getResolution()
  local mid  = math.floor(h / 2)

  local logo = {
    "███╗   ██╗ ██████╗ ██╗   ██╗ ██████╗ ███████╗",
    "████╗  ██║██╔═══██╗██║   ██║██╔═══██╗██╔════╝",
    "██╔██╗ ██║██║   ██║██║   ██║██║   ██║███████╗",
    "██║╚██╗██║██║   ██║╚██╗ ██╔╝██║   ██║╚════██║",
    "██║ ╚████║╚██████╔╝ ╚████╔╝ ╚██████╔╝███████║",
    "╚═╝  ╚═══╝ ╚═════╝   ╚═══╝   ╚═════╝ ╚══════╝",
  }

  local startY = mid - math.floor(#logo / 2) - 2
  for i, line in ipairs(logo) do
    local col = (i % 2 == 0) and C.accent or C.accent2
    center(startY + i - 1, line, col)
  end

  center(startY + #logo + 1, "v" .. NOVOS_VERSION .. "  ·  OpenComputers Operating System", C.muted)
  hline(startY + #logo + 3, "─", C.border)

  -- Progress bar
  local barW  = 40
  local barX  = math.floor((w - barW) / 2) + 1
  local barY  = startY + #logo + 5
  local steps = { "Initializing kernel...", "Loading drivers...", "Mounting filesystem...",
                  "Starting services...", "Ready." }

  setColor(C.border)
  gpu.set(barX - 1, barY, "[" .. string.rep(" ", barW) .. "]")

  for i, msg in ipairs(steps) do
    os.sleep(0.3)
    local filled = math.floor(barW * i / #steps)
    setColor(C.accent)
    gpu.set(barX, barY, string.rep("█", filled))
    setColor(C.muted)
    center(barY + 2, msg, C.muted)
    gpu.fill(1, barY + 2, w, 1, " ")  -- clear old msg line
    setColor(C.muted)
    gpu.set(math.floor((w - unicode.len(msg)) / 2) + 1, barY + 2, msg)
  end
  os.sleep(0.4)
end

-- ── Desktop / Shell Launcher ───────────────────────────────────────────────────
local function launchDesktop()
  -- Load the desktop module
  local ok, err = pcall(function()
    local desktop = loadfile(NOVOS_ROOT .. "/bin/desktop.lua")
    if desktop then desktop() else
      shell.execute(NOVOS_ROOT .. "/bin/shell.lua")
    end
  end)
  if not ok then
    setColor(C.danger)
    print("Desktop error: " .. tostring(err))
    setColor(C.text)
  end
end

-- ── Main ──────────────────────────────────────────────────────────────────────
local function main()
  gpu.setResolution(gpu.maxResolution())
  bootSplash()
  cls()
  launchDesktop()
end

main()
