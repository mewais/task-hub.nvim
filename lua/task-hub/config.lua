-- lua/task-hub/config.lua
-- Configuration management for task-hub

local M = {}

-- Default configuration
M.defaults = {
  -- UI settings
  position = 'left',              -- 'left' or 'right'
  width = 40,                     -- width of sidebar
  height = 20,                    -- height when stacked
  auto_close = false,             -- auto close after running task
  focus_on_open = true,           -- focus task hub when opened

  -- Task file settings
  task_files = {
    '.nvim/tasks.lua',
    'tasks.lua',
    '.vscode/tasks.json',         -- fallback compatibility
  },

  -- Auto-detection settings
  auto_detect = {
    enabled = true,  -- Master switch for auto-detection

    -- Per-language/tool configuration
    languages = {
      python = {
        enabled = true,
        scripts = true,        -- Detect .py files with __main__
        pytest = true,         -- Detect pytest tests
        requirements = true,   -- pip install from requirements.txt
      },
      cmake = {
        enabled = true,
        targets = true,        -- Parse CMakeLists.txt for targets
      },
      node = {
        enabled = true,
        package_scripts = true, -- package.json scripts
      },
      bash = {
        enabled = true,
        scripts = true,        -- Detect .sh executable scripts
      },
      make = {
        enabled = true,
        targets = true,        -- Parse Makefile targets
      },
      docker = {
        enabled = true,
        compose = true,        -- docker-compose.yml services
      },
      cargo = {
        enabled = true,
        targets = true,        -- Rust Cargo.toml
      },
      go = {
        enabled = true,
        packages = true,       -- Go packages
      },
    },

    -- Scanning options
    scan = {
      depth = 3,                           -- Max directory depth
      exclude = {                          -- Patterns to exclude
        'node_modules', '.git', 'build', 'dist', '__pycache__',
        '.venv', 'venv', '.env', 'target', '.next', '.cache',
      },
      cache_ttl = 300,                     -- Cache for 5 minutes (seconds)
    },

    -- Organization options
    grouping = {
      auto_group = true,                   -- Create groups by language
      group_prefix = '',                   -- Prefix for auto-groups (e.g., "Auto: ")
      merge_with_custom = false,           -- Mix with user tasks or separate
    },

    -- Sorting options
    sort = {
      custom_tasks = 'user_order',         -- "user_order" or "alphabetical"
      auto_tasks = 'alphabetical',         -- How to sort auto-detected
    },
  },

  -- Keymaps (buffer local in task hub window)
  keymaps = {
    toggle = '<leader>th',        -- global keymap to toggle
    run_task = '<CR>',            -- run task under cursor
    refresh = 'r',                -- refresh task list
    kill_task = 'K',              -- kill task under cursor
    toggle_expand = '<Space>',    -- expand/collapse groups
    edit_task = 'e',              -- edit task config (future)
  },

  -- Display settings
  icons = {
    task_idle = '▸',
    task_running = '▶',
    task_success = '✓',
    task_failed = '✗',
    task_stopped = '■',
    task_pending = '○',
    group_expanded = '▾',
    group_collapsed = '▸',
    has_inputs = '',
    composite = '',
    auto_detected = '󰚰',      -- Auto-detected task indicator
    spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
  },

  -- Task type icons (Nerd Font icons for auto-detection)
  task_type_icons = {
    -- Build & Compilation
    build = '󰇙',       -- hammer
    make = '󰇙',
    compile = '󰇙',
    cmake = '󰘳',       -- cmake specific

    -- Testing & QA
    test = '󰙨',        -- flask
    pytest = '󰙨',
    jest = '󰙨',
    regression = '󰙨',
    lint = '󰁨',        -- checkmark in circle
    format = '󰉼',      -- format icon

    -- Deployment
    deploy = '󰐱',      -- rocket
    release = '󰐱',
    publish = '󰐱',

    -- Cleanup
    clean = '󰃢',       -- trash
    cleanup = '󰃢',
    remove = '󰃢',

    -- Debug
    debug = '󰃤',       -- bug

    -- Languages
    python = '󰌠',      -- python
    node = '󰎙',        -- nodejs
    npm = '󰎙',
    yarn = '󰎙',
    bash = '',        -- terminal
    go = '󰟓',          -- go
    rust = '󱘗',        -- rust

    -- Containers & Orchestration
    docker = '󰡨',      -- docker
    kubernetes = '󱃾',
    kubectl = '󱃾',

    -- Version Control
    git = '󰊢',         -- git

    -- Execution
    run = '󰐊',         -- play
    start = '󰐊',
    execute = '󰐊',

    -- Package Management
    install = '󰇚',     -- download
    update = '󰚰',      -- update arrows

    -- Validation
    verify = '󰄬',      -- checkmark
    validate = '󰄬',

    -- Generation
    generate = '󰈔',    -- file
  },

  -- Highlight groups (will use user's theme colors)
  highlights = {
    title = 'Title',
    group = 'Directory',           -- Groups: distinct color (blue/cyan)
    task_level_0 = 'Normal',       -- Top-level tasks (brightest)
    task_level_1 = 'Comment',      -- Level 1 tasks/subtasks (dimmed)
    task_level_2 = 'NonText',      -- Level 2+ even depths (more dimmed)
    task_level_3 = 'Comment',      -- Level 3+ odd depths (alternates with level_2 for distinction)
    task_running = 'DiagnosticInfo',
    task_success = 'DiagnosticOk',
    task_failed = 'DiagnosticError',
    task_stopped = 'DiagnosticWarn',
    separator = 'Comment',
    footer = 'Comment',
    composite = 'Special',
  },

  -- Icon colors (set to nil to use task text color)
  icon_colors = {
    -- Languages (use their brand colors)
    python = { fg = '#3776AB' },      -- Python blue
    node = { fg = '#68A063' },        -- Node green
    npm = { fg = '#CB3837' },         -- npm red
    go = { fg = '#00ADD8' },          -- Go cyan
    rust = { fg = '#CE422B' },        -- Rust orange
    bash = { fg = '#89E051' },        -- Bash/terminal green

    -- Build tools
    build = { fg = '#FFA500' },       -- Orange
    cmake = { fg = '#064F8C' },       -- CMake blue

    -- Testing (purple/magenta)
    test = { fg = '#C678DD' },        -- Purple
    regression = { fg = '#C678DD' },

    -- Git (orange/red)
    git = { fg = '#F05032' },

    -- Docker (blue)
    docker = { fg = '#2496ED' },
    kubernetes = { fg = '#326CE5' },

    -- Status-based (use semantic colors)
    debug = { fg = '#E06C75' },       -- Red for debug
    clean = { fg = '#98C379' },       -- Green for clean
    verify = { fg = '#61AFEF' },      -- Blue for verify
    deploy = { fg = '#E5C07B' },      -- Yellow for deploy
  },

  -- Terminal settings
  terminal = {
    position = 'bottom',          -- 'bottom', 'right', 'float'
    size = 15,                    -- height for bottom, width for right
    focus_on_run = true,          -- focus terminal when task runs
    auto_scroll = true,           -- auto scroll to bottom
  },

  -- Task execution settings
  execution = {
    remember_inputs = true,       -- remember last input values
    stop_on_error = true,         -- for composite tasks, stop if subtask fails
    parallel_limit = 4,           -- max parallel tasks in composite
  },

  -- UI library preferences
  ui = {
    use_nui = true,               -- use nui.nvim if available
    border = 'rounded',           -- border style for popups
  },
}

-- Current configuration (will be merged with user config)
M.options = {}

-- Check if nui.nvim is available
function M.has_nui()
  return pcall(require, 'nui.menu') and pcall(require, 'nui.input')
end

-- Setup icon highlight groups
local function setup_icon_highlights(icon_colors)
  for icon_type, color_spec in pairs(icon_colors) do
    local hl_name = 'TaskHubIcon' .. icon_type:sub(1, 1):upper() .. icon_type:sub(2)
    vim.api.nvim_set_hl(0, hl_name, color_spec)
  end
end

-- Setup function to merge user config with defaults
function M.setup(user_config)
  M.options = vim.tbl_deep_extend('force', M.defaults, user_config or {})

  -- Check nui availability
  if M.options.ui.use_nui and not M.has_nui() then
    vim.notify(
      'task-hub.nvim: nui.nvim not found, falling back to vim.ui.*\n' ..
      'Install nui.nvim for a better UI experience',
      vim.log.levels.WARN
    )
    M.options.ui.use_nui = false
  end

  -- Set up icon highlight groups
  setup_icon_highlights(M.options.icon_colors)

  -- Set up global keymap for toggle
  if M.options.keymaps.toggle then
    vim.keymap.set('n', M.options.keymaps.toggle, function()
      require('task-hub').toggle()
    end, { desc = 'Toggle Task Hub' })
  end

  return M.options
end

-- Get current config
function M.get()
  return M.options
end

return M
