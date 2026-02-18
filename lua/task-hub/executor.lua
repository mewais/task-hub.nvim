-- lua/task-hub/executor.lua
-- Execute tasks with support for simple, composite, and parallel execution

local M = {}

local config = require('task-hub.config')
local parser = require('task-hub.parser')

-- Task state tracking
M.running_tasks = {}
M.task_history = {}
M.terminal_buf = nil
M.terminal_win = nil
M.terminal_channel = nil

-- Get or create terminal buffer
function M.get_terminal_buffer()
  -- Check if existing terminal buffer is valid
  if M.terminal_buf and vim.api.nvim_buf_is_valid(M.terminal_buf) then
    return M.terminal_buf
  end

  -- Create new terminal buffer
  M.terminal_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.terminal_buf, 'Task Hub Terminal')
  vim.bo[M.terminal_buf].buftype = 'nofile'
  vim.bo[M.terminal_buf].bufhidden = 'hide'

  return M.terminal_buf
end

-- Open terminal window
function M.open_terminal()
  local buf = M.get_terminal_buffer()
  local term_config = config.get().terminal

  -- Check if terminal is already visible
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      if term_config.focus_on_run then
        vim.api.nvim_set_current_win(win)
      end
      return win
    end
  end

  -- Save current window
  local original_win = vim.api.nvim_get_current_win()

  -- Find the main editor window (not neo-tree, not task-hub, not floating)
  local main_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.bo[win_buf].buftype
    local filetype = vim.bo[win_buf].filetype
    local win_config = vim.api.nvim_win_get_config(win)

    -- Skip special windows (neo-tree, task-hub, floating, etc)
    if buftype == '' and filetype ~= 'neo-tree' and win_config.relative == '' then
      main_win = win
      break
    end
  end

  -- If no main window found, use current window
  if not main_win then
    main_win = original_win
  end

  -- Open terminal in configured position (split relative to main window only)
  if term_config.position == 'bottom' then
    -- Use nvim API to create a window split relative to main window
    M.terminal_win = vim.api.nvim_open_win(buf, true, {
      split = 'below',
      win = main_win,
      height = term_config.size,
    })

    -- Configure terminal window
    vim.wo[M.terminal_win].number = false
    vim.wo[M.terminal_win].relativenumber = false

    if not term_config.focus_on_run then
      vim.api.nvim_set_current_win(original_win)
    end

    return M.terminal_win
  elseif term_config.position == 'right' then
    -- Use nvim API to create a window split relative to main window
    M.terminal_win = vim.api.nvim_open_win(buf, true, {
      split = 'right',
      win = main_win,
      width = term_config.size,
    })

    -- Configure terminal window
    vim.wo[M.terminal_win].number = false
    vim.wo[M.terminal_win].relativenumber = false

    if not term_config.focus_on_run then
      vim.api.nvim_set_current_win(original_win)
    end

    return M.terminal_win
  elseif term_config.position == 'float' then
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    M.terminal_win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = row,
      col = col,
      style = 'minimal',
      border = config.get().ui.border,
    })

    if not term_config.focus_on_run then
      vim.api.nvim_set_current_win(original_win)
    end

    return M.terminal_win
  end

  M.terminal_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.terminal_win, buf)

  -- Configure window
  vim.wo[M.terminal_win].number = false
  vim.wo[M.terminal_win].relativenumber = false

  if not term_config.focus_on_run then
    vim.api.nvim_set_current_win(original_win)
  end

  return M.terminal_win
end

-- Write output to terminal
function M.write_to_terminal(text)
  local buf = M.get_terminal_buffer()

  if not M.terminal_channel then
    M.terminal_channel = vim.api.nvim_open_term(buf, {})
  end

  vim.api.nvim_chan_send(M.terminal_channel, text)

  -- Auto scroll if configured
  if config.get().terminal.auto_scroll then
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_win_set_cursor(win, { line_count, 0 })
        end
      end
    end)
  end
end

-- Build command with environment variables
function M.build_command(task, input_values)
  input_values = input_values or {}

  -- Substitute variables in command
  local command = parser.substitute_variables(task.command, input_values)

  -- Process environment variables
  local env = parser.process_env(task.env, input_values)

  -- Build shell command with environment
  local env_prefix = ''
  for key, value in pairs(env) do
    env_prefix = env_prefix .. string.format('export %s=%q; ', key, value)
  end

  -- Handle working directory
  local cwd = task.cwd
  if cwd then
    cwd = parser.substitute_variables(cwd, input_values)
    env_prefix = env_prefix .. string.format('cd %q; ', cwd)
  end

  return env_prefix .. command
end

-- Execute a simple task
function M.execute_simple_task(task, input_values, callback)
  local command = M.build_command(task, input_values)

  -- Open terminal
  M.open_terminal()

  -- Write task header
  local header = string.format('\n╭─── Running: %s ───\n│\n', task.name)
  M.write_to_terminal(header)

  -- Create task info
  local task_info = {
    name = task.name,
    command = command,
    start_time = os.time(),
    status = 'running',
    type = 'simple',
  }

  M.running_tasks[task.name] = task_info
  table.insert(M.task_history, task_info)

  -- Execute via jobstart
  local job_id = vim.fn.jobstart(command, {
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            M.write_to_terminal('│ ' .. line .. '\n')
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            M.write_to_terminal('│ ' .. line .. '\n')
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      task_info.status = exit_code == 0 and 'success' or 'failed'
      task_info.exit_code = exit_code
      task_info.end_time = os.time()
      M.running_tasks[task.name] = nil

      local status_icon = exit_code == 0 and '✓' or '✗'
      local footer = string.format('│\n╰─── %s Task completed (exit: %d) ───\n\n', status_icon, exit_code)
      M.write_to_terminal(footer)

      -- Refresh UI
      vim.schedule(function()
        require('task-hub.ui').refresh()
        if callback then
          callback(exit_code == 0, exit_code)
        end
      end)
    end,
    pty = true,
  })

  task_info.job_id = job_id

  -- Refresh UI to show running status
  require('task-hub.ui').refresh()

  return task_info
end

-- Execute composite task (serial or parallel)
function M.execute_composite_task(task, tasks_module, input_values, callback)
  local subtask_names = task.tasks or {}
  local execution_mode = task.execution or 'serial'
  local stop_on_error = task.stopOnError ~= false -- default true

  -- Create task info
  local task_info = {
    name = task.name,
    start_time = os.time(),
    status = 'running',
    type = 'composite',
    subtasks = {},
  }

  M.running_tasks[task.name] = task_info
  table.insert(M.task_history, task_info)

  -- Open terminal
  M.open_terminal()

  local header = string.format('\n╭─── Composite Task: %s (%s) ───\n│\n', task.name, execution_mode)
  M.write_to_terminal(header)

  if execution_mode == 'serial' then
    M.execute_serial(subtask_names, tasks_module, input_values, stop_on_error, task_info, callback)
  else
    M.execute_parallel(subtask_names, tasks_module, input_values, task_info, callback)
  end

  require('task-hub.ui').refresh()
end

-- Execute subtasks serially
function M.execute_serial(subtask_names, tasks_module, input_values, stop_on_error, parent_info, callback)
  local index = 1
  local all_success = true

  local function run_next()
    if index > #subtask_names then
      -- All done
      parent_info.status = all_success and 'success' or 'failed'
      parent_info.end_time = os.time()
      M.running_tasks[parent_info.name] = nil

      local status_icon = all_success and '✓' or '✗'
      local footer = string.format('│\n╰─── %s Composite task completed ───\n\n', status_icon)
      M.write_to_terminal(footer)

      vim.schedule(function()
        require('task-hub.ui').refresh()
        if callback then
          callback(all_success)
        end
      end)
      return
    end

    local subtask_name = subtask_names[index]
    local subtask = parser.get_task_by_name(tasks_module, subtask_name)

    if not subtask then
      M.write_to_terminal(string.format('│ ✗ Subtask not found: %s\n', subtask_name))
      all_success = false
      if stop_on_error then
        run_next()
        return
      end
    end

    M.write_to_terminal(string.format('│ ▶ Starting subtask %d/%d: %s\n│\n', index, #subtask_names, subtask_name))

    M.execute_simple_task(subtask, input_values, function(success)
      if success then
        M.write_to_terminal(string.format('│ ✓ Subtask completed: %s\n│\n', subtask_name))
      else
        M.write_to_terminal(string.format('│ ✗ Subtask failed: %s\n│\n', subtask_name))
        all_success = false
        if stop_on_error then
          index = #subtask_names + 1 -- Skip remaining
        end
      end

      index = index + 1
      run_next()
    end)
  end

  run_next()
end

-- Execute subtasks in parallel
function M.execute_parallel(subtask_names, tasks_module, input_values, parent_info, callback)
  local completed = 0
  local all_success = true
  local parallel_limit = config.get().execution.parallel_limit

  M.write_to_terminal(string.format('│ Running %d tasks in parallel (limit: %d)\n│\n', #subtask_names, parallel_limit))

  for _, subtask_name in ipairs(subtask_names) do
    local subtask = parser.get_task_by_name(tasks_module, subtask_name)

    if not subtask then
      M.write_to_terminal(string.format('│ ✗ Subtask not found: %s\n', subtask_name))
      completed = completed + 1
      all_success = false
    else
      M.execute_simple_task(subtask, input_values, function(success)
        completed = completed + 1
        if not success then
          all_success = false
        end

        -- Check if all completed
        if completed >= #subtask_names then
          parent_info.status = all_success and 'success' or 'failed'
          parent_info.end_time = os.time()
          M.running_tasks[parent_info.name] = nil

          local status_icon = all_success and '✓' or '✗'
          local footer = string.format('│\n╰─── %s Composite task completed ───\n\n', status_icon)
          M.write_to_terminal(footer)

          vim.schedule(function()
            require('task-hub.ui').refresh()
            if callback then
              callback(all_success)
            end
          end)
        end
      end)
    end
  end
end

-- Main execute function
function M.execute_task(task, tasks_module, input_values, callback)
  if task.type == 'composite' then
    M.execute_composite_task(task, tasks_module, input_values, callback)
  else
    M.execute_simple_task(task, input_values, callback)
  end
end

-- Get task status
function M.get_task_status(task_name)
  if M.running_tasks[task_name] then
    return 'running'
  end

  -- Check history
  for i = #M.task_history, 1, -1 do
    if M.task_history[i].name == task_name then
      return M.task_history[i].status
    end
  end

  return 'idle'
end

-- Check if task is running
function M.is_task_running(task_name)
  return M.running_tasks[task_name] ~= nil
end

-- Stop a running task
function M.stop_task(task_name)
  local task_info = M.running_tasks[task_name]

  if not task_info then
    return false
  end

  if task_info.job_id then
    vim.fn.jobstop(task_info.job_id)
  end

  task_info.status = 'stopped'
  M.running_tasks[task_name] = nil

  M.write_to_terminal(string.format('\n│ ■ Task stopped: %s\n\n', task_name))

  require('task-hub.ui').refresh()

  return true
end

-- Get list of running task names
function M.get_running_tasks()
  local names = {}
  for name in pairs(M.running_tasks) do
    table.insert(names, name)
  end
  return names
end

return M
