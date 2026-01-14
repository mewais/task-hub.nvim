# task-hub.nvim

A powerful and intuitive task runner for Neovim with a beautiful sidebar UI, interactive prompts, and support for composite workflows.

## Features

- 🎯 **Sidebar UI** - Beautiful task explorer that stacks nicely with file explorers
- 🔄 **Composite Tasks** - Run tasks in serial or parallel with stop-on-error support
- 💬 **Interactive Prompts** - Collect user inputs with dropdown menus (via nui.nvim)
- 💾 **Input Memory** - Remembers your last input values per project
- ⚡ **Real-time Output** - See task output in terminal splits
- 🎨 **Status Indicators** - Visual feedback for running/success/failed tasks
- 📦 **Task Groups** - Organize tasks into collapsible groups
- 🔧 **Flexible Config** - Lua-native with VSCode tasks.json compatibility

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'mewais/task-hub.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',  -- Optional but recommended for better UI
  },
  config = function()
    require('task-hub').setup({
      -- Optional: customize configuration
      position = 'left',        -- 'left' or 'right'
      width = 40,
      keymaps = {
        toggle = '<leader>th',  -- Toggle task hub
      },
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'mewais/task-hub.nvim',
  requires = {
    'MunifTanjim/nui.nvim',  -- Optional
  },
  config = function()
    require('task-hub').setup()
  end,
}
```

## Quick Start

1. **Create a task file** in your project root:

```lua
-- .nvim/tasks.lua or tasks.lua
return {
  tasks = {
    {
      name = "Build",
      command = "make build",
    },
    {
      name = "Test",
      command = "make test",
    },
  },
}
```

2. **Open Task Hub**:
   - Press `<leader>th` (or your configured keymap)
   - Or run `:TaskHub toggle`

3. **Run a task**:
   - Navigate to a task and press `<Enter>`
   - Or run `:TaskHubRun Build`

## Configuration

### Default Configuration

```lua
require('task-hub').setup({
  -- UI settings
  position = 'left',              -- 'left' or 'right'
  width = 40,
  height = 20,
  auto_close = false,
  focus_on_open = true,

  -- Task files (searched in order)
  task_files = {
    '.nvim/tasks.lua',
    'tasks.lua',
    '.vscode/tasks.json',         -- VSCode compatibility
  },

  -- Keymaps (in Task Hub window)
  keymaps = {
    toggle = '<leader>th',        -- Global toggle
    run_task = '<CR>',            -- Run task under cursor
    close = 'q',
    refresh = 'r',
    kill_task = 'K',
    toggle_expand = '<Space>',
  },

  -- Icons
  icons = {
    task_idle = '▸',
    task_running = '▶',
    task_success = '✓',
    task_failed = '✗',
    task_stopped = '■',
    group_expanded = '▾',
    group_collapsed = '▸',
    has_inputs = '[...]',
    composite = '⚡',
  },

  -- Terminal settings
  terminal = {
    position = 'bottom',          -- 'bottom', 'right', 'float'
    size = 15,
    focus_on_run = true,
    auto_scroll = true,
  },

  -- Execution settings
  execution = {
    remember_inputs = true,       -- Remember last input values
    stop_on_error = true,         -- For composite tasks
    parallel_limit = 4,
  },

  -- UI library
  ui = {
    use_nui = true,               -- Use nui.nvim if available
    border = 'rounded',
  },
})
```

## Task Configuration

### Simple Tasks

```lua
return {
  tasks = {
    {
      name = "Build",
      command = "make build",
    },
    {
      name = "Test",
      command = "pytest tests/",
      cwd = "${workspaceFolder}/backend",  -- Custom working directory
    },
  },
}
```

### Tasks with Environment Variables

```lua
{
  name = "Deploy",
  command = "kubectl apply -f deployment.yaml",
  env = {
    KUBECONFIG = "${workspaceFolder}/kubeconfig",
    NAMESPACE = "production",
  },
}
```

### Tasks with Inputs

```lua
return {
  tasks = {
    {
      name = "Deploy",
      command = "deploy.sh ${input:environment} ${input:version}",
      env = {
        LOG_LEVEL = "${input:logLevel}",
      },
    },
  },

  inputs = {
    environment = {
      type = "select",
      prompt = "Select environment:",
      options = { "development", "staging", "production" },
      default = "development",
    },
    version = {
      type = "prompt",
      prompt = "Enter version:",
      default = "latest",
    },
    logLevel = {
      type = "select",
      prompt = "Select log level:",
      options = { "DEBUG", "INFO", "WARNING", "ERROR" },
      default = "INFO",
    },
  },
}
```

### Composite Tasks (Serial)

```lua
{
  name = "Full Build",
  type = "composite",
  execution = "serial",         -- Run one after another
  stopOnError = true,           -- Stop if any task fails
  tasks = { "Clean", "Build", "Test" },
}
```

### Composite Tasks (Parallel)

```lua
{
  name = "Run All Tests",
  type = "composite",
  execution = "parallel",       -- Run simultaneously
  tasks = { "Unit Tests", "Integration Tests", "E2E Tests" },
}
```

### Task Groups

```lua
return {
  groups = {
    ["Build"] = { "Build Debug", "Build Release", "Clean" },
    ["Test"] = { "Unit Tests", "Integration Tests" },
    ["Deploy"] = { "Deploy Staging", "Deploy Production" },
  },

  tasks = {
    -- ... task definitions
  },
}
```

## Commands

- `:TaskHub toggle` - Toggle task hub sidebar
- `:TaskHub open` - Open task hub sidebar
- `:TaskHub close` - Close task hub sidebar
- `:TaskHub refresh` - Refresh task list
- `:TaskHubRun <task-name>` - Run a specific task
- `:TaskHubKill [task-name]` - Kill a running task

## Keybindings (in Task Hub window)

- `<CR>` - Run task under cursor
- `<Space>` - Expand/collapse group or composite task
- `K` - Kill task under cursor (if running)
- `r` - Refresh task list
- `q` - Close Task Hub

## Usage Examples

### Basic Workflow

```lua
-- tasks.lua
return {
  tasks = {
    { name = "Install", command = "npm install" },
    { name = "Dev Server", command = "npm run dev" },
    { name = "Build", command = "npm run build" },
    { name = "Lint", command = "npm run lint" },
    { name = "Format", command = "npm run format" },
  },
}
```

### CI/CD Pipeline

```lua
return {
  tasks = {
    { name = "Lint", command = "npm run lint" },
    { name = "Test", command = "npm test" },
    { name = "Build", command = "npm run build" },
    { name = "Deploy", command = "npm run deploy" },

    -- Full pipeline
    {
      name = "CI Pipeline",
      type = "composite",
      execution = "serial",
      stopOnError = true,
      tasks = { "Lint", "Test", "Build", "Deploy" },
    },
  },
}
```

### Multi-Environment Deployment

```lua
return {
  tasks = {
    {
      name = "Deploy",
      command = "kubectl apply -f k8s/ --namespace ${input:namespace}",
      env = {
        ENVIRONMENT = "${input:environment}",
        VERSION = "${input:version}",
      },
    },
  },

  inputs = {
    environment = {
      type = "select",
      prompt = "Select environment:",
      options = { "dev", "staging", "production" },
      default = "dev",
    },
    namespace = {
      type = "prompt",
      prompt = "Enter namespace:",
      default = "default",
    },
    version = {
      type = "prompt",
      prompt = "Enter version tag:",
      default = "latest",
    },
  },
}
```

## VSCode Compatibility

Task Hub can read VSCode's `tasks.json` files for easier migration:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build",
      "type": "shell",
      "command": "make build"
    }
  ],
  "inputs": [
    {
      "id": "environment",
      "type": "pickString",
      "description": "Select environment",
      "options": ["dev", "prod"],
      "default": "dev"
    }
  ]
}
```

## Tips & Tricks

1. **Stacking with File Explorers**: Task Hub automatically detects NERDTree, nvim-tree, or neo-tree and stacks below them.

2. **Input Memory**: Your input values are remembered per project in `~/.local/share/nvim/task-hub-inputs.json`

3. **Custom Terminal Position**: Set `terminal.position = 'float'` for a floating terminal window.

4. **Expandable Composites**: Press `<Space>` on a composite task to see its subtasks.

5. **Direct Task Execution**: Run tasks without opening the UI:
   ```vim
   :TaskHubRun "Build"
   ```

## Requirements

- Neovim 0.8+
- (Optional) [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for enhanced UI

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

- Inspired by VSCode's Task Explorer
- UI powered by [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
