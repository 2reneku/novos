-- NovOS Installer
-- Run this script on your OpenComputers machine to install NovOS
-- Usage: pastebin run <code>  OR  wget <url> installer.lua && installer.lua

local component = require("component")
local fs        = require("filesystem")
local computer  = require("computer")
local gpu       = component.gpu
local internet  -- optional

local C = {
  bg=0x0D1117, surface=0x161B22,
  accent=0x58A6FF, accent2=0x3FB950,
  warn=0xD29922, danger=0xF85149,
  text=0xE6EDF3, muted=0x8B949E,
}

local function set(fg,bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function W() return select(1, gpu.getResolution()) end
local function cls() gpu.setBackground(C.bg) gpu.fill(1,1,gpu.getResolution()) end
local function hr()
  set(C.border or C.muted) print(string.rep("─", W()))
end
local function info(msg)   set(C.text)    print("  "..msg) end
local function ok(msg)     set(C.accent2) print("  ✓ "..msg) end
local function warn(msg)   set(C.warn)    print("  ⚠ "..msg) end
local function err(msg)    set(C.danger)  print("  ✗ "..msg) end
local function head(msg)   set(C.accent)  print("\n  "..msg) end

-- ── GitHub raw base URL ────────────────────────────────────────────────────────
-- EDIT THIS to your actual repository:
local GITHUB_BASE = "https://raw.githubusercontent.com/yourusername/novos/main"

local FILES = {
  { src = "/init.lua",          dst = "/novos/init.lua"          },
  { src = "/bin/desktop.lua",   dst = "/novos/bin/desktop.lua"   },
  { src = "/bin/shell.lua",     dst = "/novos/bin/shell.lua"     },
  { src = "/bin/sysmon.lua",    dst = "/novos/bin/sysmon.lua"    },
  { src = "/bin/files.lua",     dst = "/novos/bin/files.lua"     },
  { src = "/bin/editor.lua",    dst = "/novos/bin/editor.lua"    },
  { src = "/bin/settings.lua",  dst = "/novos/bin/settings.lua"  },
}

local DIRS = {
  "/novos", "/novos/bin", "/novos/lib", "/novos/cfg", "/novos/docs"
}

-- ── Banner ────────────────────────────────────────────────────────────────────
local function banner()
  cls()
  set(C.accent)
  print("")
  print("  ███╗   ██╗ ██████╗ ██╗   ██╗ ██████╗ ███████╗")
  print("  ████╗  ██║██╔═══██╗██║   ██║██╔═══██╗██╔════╝")
  print("  ██╔██╗ ██║██║   ██║██║   ██║██║   ██║███████╗")
  print("  ██║╚██╗██║██║   ██║╚██╗ ██╔╝██║   ██║╚════██║")
  print("  ██║ ╚████║╚██████╔╝ ╚████╔╝ ╚██████╔╝███████║")
  print("  ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝   ╚═════╝ ╚══════╝")
  set(C.muted)
  print("  OpenComputers Operating System  v1.0.0")
  print("  Installer")
  print("")
  hr()
end

-- ── Check requirements ────────────────────────────────────────────────────────
local function checkReqs()
  head("Checking requirements...")
  local ok_all = true

  -- GPU
  if component.isAvailable("gpu") then
    ok("GPU found")
  else
    err("No GPU detected!") ok_all = false
  end

  -- Screen
  if component.isAvailable("screen") then
    ok("Screen found")
  else
    err("No Screen detected!") ok_all = false
  end

  -- Internet (optional)
  if component.isAvailable("internet") then
    internet = component.internet
    ok("Internet card found (online install available)")
  else
    warn("No internet card — will use bundled files only")
  end

  -- Memory
  local mem = computer.totalMemory()
  if mem >= 196608 then
    ok(string.format("Memory OK (%d KB)", mem//1024))
  else
    warn(string.format("Low memory (%d KB) — recommend 192KB+", mem//1024))
  end

  return ok_all
end

-- ── Create directories ────────────────────────────────────────────────────────
local function createDirs()
  head("Creating directory structure...")
  for _, dir in ipairs(DIRS) do
    if not fs.exists(dir) then
      local success, e = fs.makeDirectory(dir)
      if success then ok("Created " .. dir)
      else err("Failed: " .. dir .. " (" .. (e or "?") .. ")") end
    else
      info("Exists: " .. dir)
    end
  end
end

-- ── Download file via internet ─────────────────────────────────────────────────
local function downloadFile(url, dst)
  if not internet then return false, "no internet" end
  local req = internet.request(url)
  if not req then return false, "request failed" end

  local data = ""
  local timeout = computer.uptime() + 10
  repeat
    local chunk, reason = req.read(8192)
    if chunk then data = data .. chunk
    elseif reason then return false, reason end
    os.sleep(0)
  until chunk == nil or computer.uptime() > timeout

  if #data == 0 then return false, "empty response" end

  -- Write to disk
  fs.makeDirectory(fs.path(dst))
  local f, fe = io.open(dst, "w")
  if not f then return false, fe end
  f:write(data)
  f:close()
  return true
end

-- ── Install files ─────────────────────────────────────────────────────────────
local function installFiles()
  head("Installing NovOS files...")

  if internet then
    info("Downloading from GitHub...")
    for _, file in ipairs(FILES) do
      local url = GITHUB_BASE .. file.src
      io.write("  Fetching " .. file.dst .. " ... ")
      gpu.setForeground(C.text)
      local success, e = downloadFile(url, file.dst)
      if success then
        set(C.accent2) print("OK")
      else
        set(C.warn)    print("SKIP (" .. (e or "?") .. ")")
      end
    end
  else
    warn("No internet — skipping download.")
    warn("Copy files manually to /novos/")
  end
end

-- ── Write launcher ────────────────────────────────────────────────────────────
local function writeLauncher()
  head("Writing launcher script...")
  local launcher = [[
-- NovOS Launcher — /bin/novos
-- Run 'novos' from OC shell to start NovOS
local f = loadfile("/novos/init.lua")
if f then f()
else print("NovOS not installed! Run installer.lua")
end
]]
  local f = io.open("/bin/novos", "w")
  if f then
    f:write(launcher)
    f:close()
    ok("Launcher written to /bin/novos")
  else
    warn("Could not write /bin/novos launcher")
  end
end

-- ── Write default config ──────────────────────────────────────────────────────
local function writeConfig()
  head("Writing default config...")
  if not fs.exists("/novos/cfg/novos.cfg") then
    local f = io.open("/novos/cfg/novos.cfg","w")
    if f then
      f:write("resolution = max\n")
      f:write("colorscheme = dark\n")
      f:write("animations = true\n")
      f:write("autosave = true\n")
      f:write("shell = novos\n")
      f:write("loglevel = info\n")
      f:close()
      ok("Default config written")
    end
  else
    info("Config already exists, skipping")
  end
end

-- ── Finish ────────────────────────────────────────────────────────────────────
local function finish()
  print("")
  hr()
  set(C.accent2)
  print("")
  print("  Installation complete!")
  print("")
  set(C.text)
  print("  To start NovOS, type:")
  set(C.accent)
  print("    novos")
  print("")
  set(C.muted)
  print("  Or add to your /autorun.lua:")
  set(C.accent)
  print("    loadfile('/novos/init.lua')()")
  print("")
  set(C.muted)
  print("  GitHub: https://github.com/yourusername/novos")
  print("")
  hr()
  set(C.text)
  print("")
end

-- ── Main ──────────────────────────────────────────────────────────────────────
banner()

local reqs = checkReqs()
if not reqs then
  err("Requirements not met. Aborting.")
  return
end

set(C.text)
io.write("\n  Proceed with installation? [Y/n]: ")
local ans = io.read()
if ans:lower() == "n" then
  warn("Installation cancelled.")
  return
end

createDirs()
installFiles()
writeLauncher()
writeConfig()
finish()
