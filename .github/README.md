# task-hub.nvim

> 🚀 A powerful and intuitive task runner for Neovim

[![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg?style=flat-square&logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1+-blue.svg?style=flat-square&logo=lua)](https://www.lua.org)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)

![task-hub demo](https://via.placeholder.com/800x400?text=Task+Hub+Demo)

## ✨ Features

- 🎯 **Beautiful Sidebar UI** - Intuitive task explorer with collapsible groups
- 🔄 **Composite Tasks** - Serial and parallel execution with stop-on-error
- 💬 **Interactive Prompts** - Dropdown menus and text inputs via nui.nvim
- 💾 **Smart Input Memory** - Remembers your last input values per project
- ⚡ **Real-time Output** - Live task output in configurable terminal splits
- 🎨 **Visual Feedback** - Status indicators for running/success/failed tasks
- 📦 **Task Organization** - Collapsible groups for better project structure
- 🔧 **VSCode Compatible** - Reads existing tasks.json files

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'mewais/task-hub.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',  -- Optional but recommended
  },
  config = function()
    require('task-hub').setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'mewais/task-hub.nvim',
  requires = { 'MunifTanjim/nui.nvim' },
  config = function()
    require('task-hub').setup()
  end,
}
```

## 🚀 Quick Start

1. Create `.nvim/tasks.lua` in your project:

```lua
return {
  tasks = {
    { name = "Build", command = "make build" },
    { name = "Test", command = "make test" },
  },
}
```

2. Open Task Hub with `<leader>th` or `:TaskHub toggle`

3. Press `<Enter>` on a task to run it!

## 📖 Documentation

- [Full Documentation](../README.md)
- [Examples](../examples/)
- [Vim Help](../doc/task-hub.txt) - `:help task-hub`

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

## 📝 License

MIT © [mewais](https://github.com/mewais)

## 🙏 Acknowledgments

- Inspired by VSCode's Task Explorer
- UI powered by [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
