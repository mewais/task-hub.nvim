-- lua/task-hub/ui.lua
-- User interface for task hub sidebar

local M = {}

local config = require('task-hub.config')
local parser = require('task-hub.parser')
local executor = require('task-hub.executor')
local prompts = require('task-hub.prompts')

-- UI state
M.buf = nil
M.win = nil
M.tasks_module = nil
M.expanded_groups = {}
M.expanded_composites = {}

-- Line mapping for navigation
M.line_to_item = {}

-- Create the task hub buffer
function M.create_buffer()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end

  M.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.buf, 'Task Hub')

  -- Buffer options
  vim.bo[M.buf].buftype = 'nofile'
  vim.bo[M.buf].bufhidden = 'hide'
  vim.bo[M.buf].swapfile = false
  vim.bo[M.buf].filetype = 'taskhub'
  vim.bo[M.buf].modifiable = false

  -- Set up keymaps
  M.setup_keymaps()

  return M.buf
end

-- Setup buffer-local keymaps
function M.setup_keymaps()
  if not M.buf then return end

  local cfg = config.get()
  local opts = { buffer = M.buf, silent = true, nowait = true }

  -- Run task
  vim.keymap.set('n', cfg.keymaps.run_task, function()
    M.run_item_under_cursor()
  end, vim.tbl_extend('force', opts, { desc = 'Run task' }))

  -- Toggle expand
  vim.keymap.set('n', cfg.keymaps.toggle_expand, function()
    M.toggle_item_under_cursor()
  end, vim.tbl_extend('force', opts, { desc = 'Toggle expand' }))

  -- Kill task
  vim.keymap.set('n', cfg.keymaps.kill_task, function()
    M.kill_task_under_cursor()
  end, vim.tbl_extend('force', opts, { desc = 'Kill task' }))

  -- Refresh
  vim.keymap.set('n', cfg.keymaps.refresh, function()
    M.refresh()
  end, vim.tbl_extend('force', opts, { desc = 'Refresh tasks' }))
end

-- Find existing sidebar window (generic detection)
function M.find_sidebar_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_config = vim.api.nvim_win_get_config(win)

    -- Skip floating windows
    if win_config.relative ~= '' then
      goto continue
    end

    -- Check window position and size (likely sidebar)
    local width = vim.api.nvim_win_get_width(win)
    local win_pos = vim.api.nvim_win_get_position(win)

    -- Sidebar is typically narrow and at screen edge
    if width < 60 and (win_pos[2] == 0 or win_pos[2] > vim.o.columns - 60) then
      local buf = vim.api.nvim_win_get_buf(win)
      local buftype = vim.bo[buf].buftype

      -- Likely a file explorer or similar
      if buftype == 'nofile' or buftype == '' then
        return win
      end
    end

    ::continue::
  end

  return nil
end

-- Open the task hub window
function M.open_window()
  local cfg = config.get()

  -- Create buffer
  M.create_buffer()

  -- Check if already open
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_set_current_win(M.win)
    return M.win
  end

  local original_win = vim.api.nvim_get_current_win()

  -- Try to stack with existing sidebar
  local sidebar_win = M.find_sidebar_window()

  if sidebar_win then
    vim.api.nvim_set_current_win(sidebar_win)
    vim.cmd('below ' .. cfg.height .. 'split')
  else
    -- Open on configured side
    if cfg.position == 'left' then
      vim.cmd('topleft ' .. cfg.width .. 'vsplit')
    else
      vim.cmd('botright ' .. cfg.width .. 'vsplit')
    end
  end

  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)

  -- Window options
  vim.wo[M.win].number = false
  vim.wo[M.win].relativenumber = false
  vim.wo[M.win].wrap = false
  vim.wo[M.win].cursorline = true
  vim.wo[M.win].signcolumn = 'no'
  vim.wo[M.win].foldcolumn = '0'

  -- Load and display tasks
  M.refresh()

  -- Return focus if configured
  if not cfg.focus_on_open then
    vim.api.nvim_set_current_win(original_win)
  end

  return M.win
end

-- Get status icon for a task
function M.get_task_icon(task)
  local cfg = config.get()
  local status = executor.get_task_status(task.name)

  if status == 'running' then
    return cfg.icons.task_running
  elseif status == 'success' then
    return cfg.icons.task_success
  elseif status == 'failed' then
    return cfg.icons.task_failed
  elseif status == 'stopped' then
    return cfg.icons.task_stopped
  else
    return cfg.icons.task_idle
  end
end

-- Check if task has inputs
function M.task_has_inputs(task)
  local refs = parser.find_input_references(task)
  for _ in pairs(refs) do
    return true
  end
  return false
end

-- Build display lines
function M.build_display_lines()
  local lines = {}
  M.line_to_item = {}
  local cfg = config.get()

  -- Header
  table.insert(lines, 'Task Hub')
  table.insert(lines, '')

  if not M.tasks_module or not M.tasks_module.tasks or #M.tasks_module.tasks == 0 then
    table.insert(lines, 'No tasks defined')
    table.insert(lines, '')
  else
    local organized = parser.organize_tasks(M.tasks_module)

    -- Display ungrouped tasks first
    for _, task in ipairs(organized.ungrouped) do
      local line_num = #lines + 1
      local icon = M.get_task_icon(task)
      local has_inputs = M.task_has_inputs(task) and ' ' .. cfg.icons.has_inputs or ''
      local composite = task.type == 'composite' and ' ' .. cfg.icons.composite or ''

      local line = string.format('%s %s%s%s', icon, task.name, has_inputs, composite)
      table.insert(lines, line)
      M.line_to_item[line_num] = { type = 'task', task = task }

      -- Show composite subtasks if expanded
      if task.type == 'composite' and M.expanded_composites[task.name] then
        M.add_composite_subtasks(lines, task, '  ')
      end
    end

    -- Display grouped tasks
    if next(organized.grouped) then
      if #organized.ungrouped > 0 then
        table.insert(lines, '')
      end

      for group_name, tasks in pairs(organized.grouped) do
        local line_num = #lines + 1
        local group_icon = M.expanded_groups[group_name] and cfg.icons.group_expanded or cfg.icons.group_collapsed

        local line = string.format('%s %s', group_icon, group_name)
        table.insert(lines, line)
        M.line_to_item[line_num] = { type = 'group', name = group_name }

        -- Show tasks if expanded
        if M.expanded_groups[group_name] then
          for _, task in ipairs(tasks) do
            local task_line_num = #lines + 1
            local icon = M.get_task_icon(task)
            local has_inputs = M.task_has_inputs(task) and ' ' .. cfg.icons.has_inputs or ''
            local composite = task.type == 'composite' and ' ' .. cfg.icons.composite or ''

            local task_line = string.format('  %s %s%s%s', icon, task.name, has_inputs, composite)
            table.insert(lines, task_line)
            M.line_to_item[task_line_num] = { type = 'task', task = task }

            -- Show composite subtasks if expanded
            if task.type == 'composite' and M.expanded_composites[task.name] then
              M.add_composite_subtasks(lines, task, '    ')
            end
          end
        end
      end
    end
  end

  -- Get window height to fill remaining space
  local win_height = M.win and vim.api.nvim_win_is_valid(M.win) and vim.api.nvim_win_get_height(M.win) or 20
  local footer_lines = 3  -- separator + 2 help lines
  local content_lines = #lines

  -- Add empty lines to push footer to bottom
  local padding_needed = win_height - content_lines - footer_lines
  for i = 1, math.max(0, padding_needed) do
    table.insert(lines, '')
  end

  -- Footer at the bottom
  table.insert(lines, '─────────────────────────────')
  table.insert(lines, '<CR>:run  <Space>:expand')
  table.insert(lines, 'K:kill  r:refresh')

  return lines
end

-- Add composite subtasks to display
function M.add_composite_subtasks(lines, task, indent)
  local cfg = config.get()

  if not task.tasks then
    return
  end

  for _, subtask_name in ipairs(task.tasks) do
    local subtask = parser.get_task_by_name(M.tasks_module, subtask_name)
    local line_num = #lines + 1

    if subtask then
      local icon = M.get_task_icon(subtask)
      local line = string.format('%s├─ %s %s', indent, icon, subtask_name)
      table.insert(lines, line)
      M.line_to_item[line_num] = { type = 'subtask', task = subtask, parent = task.name }
    else
      local line = string.format('%s├─ %s %s (not found)', indent, cfg.icons.task_failed, subtask_name)
      table.insert(lines, line)
    end
  end
end

-- Refresh the display
function M.refresh()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  -- Load tasks
  local tasks_module, err = parser.load_tasks()

  if err then
    -- Display error with box for emphasis
    vim.bo[M.buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, {
      '╭─── Task Hub Error ──────────╮',
      '│                             │',
      '│  Error loading tasks:       │',
      '│  ' .. err,
      '│                             │',
      '│  Create a task file:        │',
      '│    .nvim/tasks.lua          │',
      '│    or tasks.lua             │',
      '│                             │',
      '╰─────────────────────────────╯',
    })
    vim.bo[M.buf].modifiable = false
    return
  end

  M.tasks_module = tasks_module

  -- Build and set display
  local lines = M.build_display_lines()

  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.bo[M.buf].modifiable = false

  -- Apply highlighting
  M.apply_highlighting()
end

-- Apply syntax highlighting
function M.apply_highlighting()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  local ns = vim.api.nvim_create_namespace('TaskHub')
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)

  for i, line in ipairs(lines) do
    local line_num = i - 1

    -- Highlight header
    if line:match('^Task Hub') then
      vim.api.nvim_buf_add_highlight(M.buf, ns, 'Title', line_num, 0, -1)
    end

    -- Highlight separator
    if line:match('^─') then
      vim.api.nvim_buf_add_highlight(M.buf, ns, 'Comment', line_num, 0, -1)
    end

    -- Highlight running tasks
    if line:match('▶') then
      vim.api.nvim_buf_add_highlight(M.buf, ns, 'DiagnosticInfo', line_num, 0, -1)
    end

    -- Highlight success
    if line:match('✓') then
      vim.api.nvim_buf_add_highlight(M.buf, ns, 'DiagnosticOk', line_num, 0, -1)
    end

    -- Highlight errors
    if line:match('✗') then
      vim.api.nvim_buf_add_highlight(M.buf, ns, 'DiagnosticError', line_num, 0, -1)
    end
  end
end

-- Get item under cursor
function M.get_item_under_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  return M.line_to_item[line_num]
end

-- Toggle item under cursor
function M.toggle_item_under_cursor()
  local item = M.get_item_under_cursor()

  if not item then
    return
  end

  if item.type == 'group' then
    M.expanded_groups[item.name] = not M.expanded_groups[item.name]
    M.refresh()
  elseif item.type == 'task' and item.task.type == 'composite' then
    M.expanded_composites[item.task.name] = not M.expanded_composites[item.task.name]
    M.refresh()
  end
end

-- Run item under cursor
function M.run_item_under_cursor()
  local item = M.get_item_under_cursor()

  if not item or (item.type ~= 'task' and item.type ~= 'subtask') then
    return
  end

  local task = item.task

  -- Collect inputs and execute
  prompts.collect_inputs(task, M.tasks_module.inputs or {}, function(input_values)
    executor.execute_task(task, M.tasks_module, input_values)
  end)
end

-- Kill task under cursor
function M.kill_task_under_cursor()
  local item = M.get_item_under_cursor()

  if not item or (item.type ~= 'task' and item.type ~= 'subtask') then
    return
  end

  local task = item.task

  if executor.is_task_running(task.name) then
    executor.stop_task(task.name)
  else
    vim.notify('Task is not running: ' .. task.name, vim.log.levels.WARN)
  end
end

-- Close task hub
function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
end

-- Toggle task hub
function M.toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    M.close()
  else
    M.open_window()
  end
end

-- Check if open
function M.is_open()
  return M.win and vim.api.nvim_win_is_valid(M.win)
end

return M
