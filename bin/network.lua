-- NovOS Network App
-- /novos/bin/network.lua

local component = require("component")
local event     = require("event")
local computer  = require("computer")
local gpu       = component.gpu

local W, H = gpu.getResolution()

local C = {
  bg=0x0D1117, surface=0x161B22, surface2=0x21262D,
  border=0x30363D, accent=0x58A6FF, accent2=0x3FB950,
  warn=0xD29922, danger=0xF85149, text=0xE6EDF3,
  muted=0x8B949E,
}

local function set(fg,bg) gpu.setForeground(fg) if bg then gpu.setBackground(bg) end end
local function put(x,y,s) gpu.set(x,y,s) end
local function fill(x,y,w,h,c) gpu.fill(x,y,w,h,c or " ") end

local function box(x,y,w,h,title)
  set(C.border,C.surface)
  put(x,y,"┌"..string.rep("─",w-2).."┐")
  for j=y+1,y+h-2 do put(x,j,"│") fill(x+1,j,w-2,1) put(x+w-1,j,"│") end
  put(x,y+h-1,"└"..string.rep("─",w-2).."┘")
  if title then set(C.accent,C.surface) put(x+2,y," "..title.." ") end
end

local log = {}
local function addLog(msg, color)
  table.insert(log, {msg=msg, color=color or C.text})
  if #log > 20 then table.remove(log,1) end
end

local modem = nil
local internet = nil

local function initComponents()
  if component.isAvailable("modem") then
    modem = component.modem
  end
  if component.isAvailable("internet") then
    internet = component.internet
  end
end

local function drawStatus()
  local sx, sy = 2, 2
  local sw, sh = 30, 8
  box(sx,sy,sw,sh,"Status")

  set(C.text,C.surface)
  local function statusLine(y,label,val,ok_val)
    set(C.muted,C.surface) put(sx+2,sy+y,label..":")
    local fg = (val == ok_val) and C.accent2 or C.danger
    set(fg,C.surface)
    put(sx+2+#label+2,sy+y,val or "N/A")
  end

  statusLine(2,"Modem",   modem    and "online"  or "offline", "online")
  statusLine(3,"Internet",internet and "online"  or "offline", "online")
  statusLine(4,"Wireless",modem and modem.isWireless and modem.isWireless() and "yes" or "no","yes")
  if modem then
    set(C.muted,C.surface) put(sx+2,sy+5,"Address:")
    set(C.accent,C.surface)
    local addr = modem.address or "?"
    put(sx+11,sy+5,addr:sub(1,sw-14))
  end
end

local function drawActions()
  local ax, ay = 34, 2
  local aw, ah = W-35, 10
  box(ax,ay,aw,ah,"Actions")
  local actions = {
    "[1] Broadcast message",
    "[2] HTTP GET request",
    "[3] Open port",
    "[4] Close all ports",
    "[5] Network scan",
    "[R] Refresh status",
    "[Q] Quit",
  }
  for i,a in ipairs(actions) do
    set(C.muted,C.surface) put(ax+2,ay+i,a)
  end
end

local function drawLog()
  local lx, ly = 2, 11
  local lw, lh = W-3, H-12
  box(lx,ly,lw,lh,"Network Log")
  local startIdx = math.max(1, #log - (lh-3))
  for i=startIdx, #log do
    local entry = log[i]
    local row   = ly+1+(i-startIdx)
    if row >= ly+lh-1 then break end
    set(entry.color,C.surface)
    put(lx+2,row,entry.msg:sub(1,lw-4))
  end
end

local function draw()
  gpu.setBackground(C.bg) fill(1,1,W,H)
  set(C.text,C.surface2) fill(1,1,W,1)
  set(C.accent,C.surface2) put(1,1," NovOS Network ")
  set(C.muted,C.surface2) put(17,1,"Q:Quit  1-5:Actions  R:Refresh")

  drawStatus()
  drawActions()
  drawLog()
end

local function doHTTPGet()
  if not internet then addLog("No internet card!", C.danger) return end
  set(C.accent,C.bg) put(1,H," URL: ")
  set(C.text,C.bg) fill(8,H,W-8,1)
  local url = io.read()
  if not url or url=="" then addLog("Cancelled",C.muted) return end
  addLog("GET "..url, C.accent)
  local ok2, req = pcall(internet.request, url)
  if not ok2 or not req then addLog("Request failed!",C.danger) return end
  local data = ""
  local t = computer.uptime()+8
  repeat
    local chunk = req.read(256)
    if chunk then data=data..chunk end
    os.sleep(0)
  until chunk==nil or computer.uptime()>t
  addLog("Response: "..#data.." bytes", C.accent2)
  -- show first 200 chars
  addLog(data:sub(1,80):gsub("\n"," "), C.muted)
end

local function doBroadcast()
  if not modem then addLog("No modem!",C.danger) return end
  set(C.accent,C.bg) put(1,H," Message: ")
  set(C.text,C.bg) fill(12,H,W-12,1)
  local msg = io.read()
  if not msg or msg=="" then addLog("Cancelled",C.muted) return end
  local ok2,err = pcall(modem.broadcast, 1234, msg)
  if ok2 then addLog("Broadcast: "..msg, C.accent2)
  else addLog("Error: "..(err or "?"), C.danger) end
end

local function doOpenPort()
  if not modem then addLog("No modem!",C.danger) return end
  set(C.accent,C.bg) put(1,H," Port: ")
  set(C.text,C.bg) fill(9,H,W-9,1)
  local p = tonumber(io.read())
  if not p then addLog("Invalid port",C.danger) return end
  modem.open(p)
  addLog("Opened port "..p, C.accent2)
end

local function doScan()
  addLog("Scanning network...",C.accent)
  local found = 0
  for addr,ctype in component.list() do
    if ctype=="modem" then
      addLog("  Modem: "..addr:sub(1,12),C.accent2)
      found=found+1
    end
  end
  addLog("Scan complete. Found "..found.." network device(s).",C.muted)
end

local function main()
  W,H = gpu.getResolution()
  initComponents()
  addLog("NovOS Network initialized", C.accent)
  if modem    then addLog("Modem detected",    C.accent2) end
  if internet then addLog("Internet detected", C.accent2) end

  local running = true
  while running do
    draw()
    local ev = {event.pull(5)}
    if ev[1]=="key_down" then
      local char = ev[3]
      local code = ev[4]
      if code==16 then running=false
      elseif char==string.byte("1") then doBroadcast()
      elseif char==string.byte("2") then doHTTPGet()
      elseif char==string.byte("3") then doOpenPort()
      elseif char==string.byte("4") then
        if modem then modem.closeAll() addLog("Closed all ports",C.warn) end
      elseif char==string.byte("5") then doScan()
      elseif char==string.byte("r") or char==string.byte("R") then
        initComponents()
        addLog("Refreshed",C.muted)
      end
    elseif ev[1]=="modem_message" then
      addLog(string.format("MSG from %s port %s: %s",
        tostring(ev[3]):sub(1,8), tostring(ev[4]), tostring(ev[5])), C.accent2)
    elseif ev[1]=="interrupted" then
      running=false
    end
  end
end

main()
