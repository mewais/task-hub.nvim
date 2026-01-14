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
  auto_detect_tasks = true,       -- auto-detect common tasks (build, test, etc.)

  -- Task file settings
  task_files = {
    '.nvim/tasks.lua',
    'tasks.lua',
    '.vscode/tasks.json',         -- fallback compatibility
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
    has_inputs = '[...]',
    composite = '⚡',
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
