# NovOS — OpenComputers Operating System

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenComputers](https://img.shields.io/badge/OpenComputers-1.7%2B-green.svg)](https://github.com/MightyPirates/OpenComputers)

> A beautiful, full-featured OS for OpenComputers with desktop environment, file manager, system monitor, text editor, and enhanced shell.

---

## ✨ Features

| App | Description |
|-----|-------------|
| **Desktop** | Full GUI with app dock, system stats, keyboard navigation |
| **Shell** | Enhanced shell with history, syntax coloring, built-in commands |
| **Files** | Dual-pane file manager — navigate, copy, rename, delete |
| **System Monitor** | Live CPU/memory graphs with sparkline history |
| **Text Editor** | Lua syntax highlighting, line numbers, history |
| **Settings** | Persistent config for display, system, network |

---

## 📦 Requirements

- OpenComputers mod (1.7.x or newer)
- Tier 2+ GPU + Screen
- Tier 1+ CPU
- At least 192KB RAM (256KB+ recommended)
- Internet Card *(optional — for online install)*

---

## 🚀 Installation

### Method 1 — Online Install (easiest)

In your OC computer's shell:

```
wget https://raw.githubusercontent.com/yourusername/novos/main/installer/install.lua
install.lua
```

### Method 2 — Pastebin

Upload `installer/install.lua` to Pastebin, then:

```
pastebin run <YOUR_CODE>
```

### Method 3 — Manual

Copy all files maintaining the directory structure:

```
/novos/
  init.lua
  bin/
    desktop.lua
    shell.lua
    sysmon.lua
    files.lua
    editor.lua
    settings.lua
  cfg/
    novos.cfg
  installer/
    install.lua
```

Then write the launcher:

```lua
-- /bin/novos
loadfile("/novos/init.lua")()
```

---

## ▶️ Usage

After installation, start NovOS:

```
novos
```

Or set it to auto-start by adding to `/autorun.lua`:

```lua
loadfile("/novos/init.lua")()
```

---

## 🎮 Controls

### Desktop
| Key | Action |
|-----|--------|
| `←` `→` | Navigate app dock |
| `Enter` | Launch selected app |
| `R` | Refresh desktop |
| `Q` | Exit to shell |

### File Manager
| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate files |
| `Enter` | Open file/folder |
| `D` | Delete selected |
| `N` | New directory |
| `C` | Copy file |
| `R` | Rename |
| `Q` | Quit |

### Text Editor
| Key | Action |
|-----|--------|
| Arrow keys | Move cursor |
| `Ctrl+S` | Save |
| `Ctrl+Q` | Quit |
| `Ctrl+G` | Go to line |

### Shell Commands
```
help      — show all commands
ls / cd   — navigate filesystem
cat       — print file
mem       — memory usage
comps     — list components
sysmon    — system monitor
files     — file manager
edit      — text editor
novos     — restart desktop
reboot    — reboot
halt      — shutdown
```

---

## 📁 Project Structure

```
novos/
├── init.lua              # Kernel entry point + boot splash
├── installer/
│   └── install.lua       # Installer script
├── bin/
│   ├── desktop.lua       # Desktop environment
│   ├── shell.lua         # Enhanced shell
│   ├── sysmon.lua        # System monitor
│   ├── files.lua         # File manager
│   ├── editor.lua        # Text editor
│   └── settings.lua      # Settings app
├── cfg/
│   └── novos.cfg         # Configuration file
├── lib/                  # Shared libraries (future)
└── docs/                 # Documentation (future)
```

---

## ⚙️ Configuration

Config is stored at `/novos/cfg/novos.cfg`:

```
resolution = max
colorscheme = dark
animations = true
autosave = true
shell = novos
loglevel = info
```

Edit via the Settings app or directly with the text editor.

---

## 🗺️ Roadmap

- [ ] Network app (ping, HTTP client)
- [ ] Process manager
- [ ] Package manager (install OC programs)
- [ ] Dual-pane file manager
- [ ] Markdown viewer
- [ ] Lua REPL
- [ ] Theming system

---

## 🤝 Contributing

Pull requests welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test in-game with OpenComputers
4. Submit a PR with description

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Credits

Built with ❤️ for the OpenComputers community.  
Inspired by classic Unix systems and modern terminal UIs.
