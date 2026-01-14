-- lua/task-hub/visual.lua
-- Visual enhancements: task type detection, icons, animations, and styling

local M = {}

-- Spinner state for animations
M.spinner_index = 1
M.spinner_timer = nil

-- Extract the executable/script from command (ignoring arguments)
local function extract_command_base(command)
  if not command or command == '' then
    return ''
  end

  -- Remove leading/trailing whitespace
  command = command:match("^%s*(.-)%s*$")

  -- Get the first word (the actual command/script)
  local base_cmd = command:match("^([^%s]+)")
  if not base_cmd then
    return ''
  end

  -- Extract just the command name without path
  -- e.g., "/usr/bin/python3" -> "python3", "./script.sh" -> "script.sh"
  local cmd_name = base_cmd:match("([^/\\]+)$") or base_cmd

  return cmd_name:lower()
end

-- Detect task type from task name or command
function M.detect_task_type(task)
  if not task or not task.name then
    return nil
  end

  local config = require('task-hub.config').get()
  if not config or not config.task_type_icons then
    return nil
  end

  local name_lower = task.name:lower()

  -- Extract command base (executable only, no arguments)
  local cmd_base = extract_command_base(task.command)

  -- Priority 1: Check task name for keywords
  local name_patterns = {
    { pattern = 'clean', icon = 'clean' },
    { pattern = 'debug', icon = 'debug' },
    { pattern = 'test', icon = 'test' },
    { pattern = 'regression', icon = 'regression' },
    { pattern = 'verify', icon = 'verify' },
    { pattern = 'validat', icon = 'verify' },
    { pattern = 'generat', icon = 'generate' },
    { pattern = 'build', icon = 'build' },
    { pattern = 'compile', icon = 'build' },
    { pattern = 'deploy', icon = 'deploy' },
    { pattern = 'install', icon = 'install' },
    { pattern = 'lint', icon = 'lint' },
    { pattern = 'format', icon = 'format' },
  }

  for _, item in ipairs(name_patterns) do
    if name_lower:find(item.pattern, 1, true) then
      return config.task_type_icons[item.icon]
    end
  end

  -- Priority 2: Check command base for known tools/interpreters
  local cmd_patterns = {
    -- Scripting languages
    { pattern = 'python', icon = 'python' },
    { pattern = 'python3', icon = 'python' },
    { pattern = 'node', icon = 'node' },
    { pattern = 'npm', icon = 'npm' },
    { pattern = 'yarn', icon = 'npm' },
    { pattern = 'bash', icon = 'bash' },
    { pattern = 'sh', icon = 'bash' },
    { pattern = 'zsh', icon = 'bash' },

    -- Build tools
    { pattern = 'make', icon = 'build' },
    { pattern = 'cmake', icon = 'cmake' },
    { pattern = 'cargo', icon = 'rust' },
    { pattern = 'go', icon = 'go' },
    { pattern = 'gcc', icon = 'build' },
    { pattern = 'g++', icon = 'build' },
    { pattern = 'clang', icon = 'build' },

    -- Testing
    { pattern = 'pytest', icon = 'test' },
    { pattern = 'jest', icon = 'test' },
    { pattern = 'mocha', icon = 'test' },

    -- Docker/Containers
    { pattern = 'docker', icon = 'docker' },
    { pattern = 'kubectl', icon = 'kubernetes' },

    -- Git
    { pattern = 'git', icon = 'git' },

    -- Cleanup
    { pattern = 'rm', icon = 'clean' },
  }

  for _, item in ipairs(cmd_patterns) do
    if cmd_base:find(item.pattern, 1, true) then
      return config.task_type_icons[item.icon]
    end
  end

  -- Default: no special icon
  return nil
end

-- Get icon for task based on status and type
function M.get_task_icon(task, status)
  local config = require('task-hub.config').get()

  -- Status icons take priority
  if status == 'running' then
    -- Use spinner for running tasks
    return config.icons.spinner[M.spinner_index] or config.icons.task_running
  elseif status == 'success' then
    return config.icons.task_success
  elseif status == 'failed' then
    return config.icons.task_failed
  elseif status == 'stopped' then
    return config.icons.task_stopped
  end

  -- For idle tasks, use type-specific icon if available
  local type_icon = M.detect_task_type(task)
  if type_icon then
    return type_icon
  end

  -- Default idle icon
  return config.icons.task_idle
end

-- Get highlight group for a line based on content (supports infinite nesting)
function M.get_line_highlight(line, item)
  local config = require('task-hub.config').get()

  -- Header
  if line:match('^Task Hub') then
    return config.highlights.title
  end

  -- Separator or footer
  if line:match('^─') or line:match('^<CR>') or line:match('^K:') then
    return config.highlights.footer
  end

  -- Group names
  if item and item.type == 'group' then
    return config.highlights.group
  end

  -- Tasks and subtasks - check status first for color override
  if item and (item.type == 'task' or item.type == 'subtask') then
    local executor = require('task-hub.executor')
    local status = executor.get_task_status(item.task.name)

    -- Status colors override level colors
    if status == 'running' then
      return config.highlights.task_running
    elseif status == 'success' then
      return config.highlights.task_success
    elseif status == 'failed' then
      return config.highlights.task_failed
    elseif status == 'stopped' then
      return config.highlights.task_stopped
    end

    -- Use level-based coloring for idle tasks (infinite levels)
    local level = item.level or 0

    -- Cycle through available level highlights
    -- Level 0: Normal (brightest)
    -- Level 1: Comment (dimmed)
    -- Level 2+: NonText (most dimmed), alternates slightly for visual distinction
    if level == 0 then
      return config.highlights.task_level_0
    elseif level == 1 then
      return config.highlights.task_level_1
    else
      -- For deeper levels, alternate between level_2 and level_3 for distinction
      -- Even levels (2, 4, 6...) use task_level_2
      -- Odd levels (3, 5, 7...) use task_level_3
      return (level % 2 == 0) and config.highlights.task_level_2 or config.highlights.task_level_3
    end
  end

  return config.highlights.task_level_0
end

-- Start spinner animation for running tasks
function M.start_spinner()
  if M.spinner_timer then
    return -- Already running
  end

  local config = require('task-hub.config').get()

  M.spinner_timer = vim.loop.new_timer()
  M.spinner_timer:start(100, 100, vim.schedule_wrap(function()
    M.spinner_index = M.spinner_index % #config.icons.spinner + 1

    -- Refresh UI if we have running tasks
    local executor = require('task-hub.executor')
    if next(executor.running_tasks) then
      local ui = require('task-hub.ui')
      if ui.is_open() then
        ui.refresh()
      end
    else
      -- No running tasks, stop spinner
      M.stop_spinner()
    end
  end))
end

-- Stop spinner animation
function M.stop_spinner()
  if M.spinner_timer then
    M.spinner_timer:stop()
    M.spinner_timer:close()
    M.spinner_timer = nil
  end
  M.spinner_index = 1
end

-- Get icon type for a task (used for coloring)
function M.get_icon_type(task)
  if not task or not task.name then
    return nil
  end

  local config = require('task-hub.config').get()
  if not config or not config.task_type_icons then
    return nil
  end

  local name_lower = task.name:lower()
  local cmd_base = extract_command_base(task.command)

  -- Check name patterns first
  local name_patterns = {
    'clean', 'debug', 'test', 'regression', 'verify', 'validat',
    'generat', 'build', 'compile', 'deploy', 'install', 'lint', 'format'
  }

  for _, pattern in ipairs(name_patterns) do
    if name_lower:find(pattern, 1, true) then
      return pattern == 'validat' and 'verify' or pattern
    end
  end

  -- Check command patterns
  local cmd_map = {
    python = 'python', python3 = 'python', node = 'node', npm = 'npm',
    yarn = 'npm', bash = 'bash', sh = 'bash', zsh = 'bash',
    make = 'build', cmake = 'cmake', cargo = 'rust', go = 'go',
    pytest = 'test', jest = 'test', docker = 'docker',
    kubectl = 'kubernetes', git = 'git', rm = 'clean'
  }

  for cmd_pattern, icon_type in pairs(cmd_map) do
    if cmd_base:find(cmd_pattern, 1, true) then
      return icon_type
    end
  end

  return nil
end

-- Format task line with icon, name, and indicators
function M.format_task_line(task, indent, status)
  local config = require('task-hub.config').get()

  local icon = M.get_task_icon(task, status)
  local has_inputs = M.task_has_inputs(task) and ' ' .. config.icons.has_inputs or ''
  local composite = task.type == 'composite' and ' ' .. config.icons.composite or ''
  local auto_detected = task.auto_detected and ' ' .. (config.icons.auto_detected or '󰚰') or ''

  return string.format('%s%s %s%s%s%s', indent, icon, task.name, has_inputs, composite, auto_detected)
end

-- Check if task has inputs
function M.task_has_inputs(task)
  local parser = require('task-hub.parser')
  local refs = parser.find_input_references(task)
  return #refs > 0
end

-- Format group separator line
function M.format_group_separator(group_name)
  local separator = string.rep('─', 3)
  return string.format('%s %s %s', separator, group_name, string.rep('─', 20 - #group_name))
end

-- Get status summary (for header or statusline)
function M.get_status_summary()
  local executor = require('task-hub.executor')
  local running = 0
  local success = 0
  local failed = 0

  for _ in pairs(executor.running_tasks) do
    running = running + 1
  end

  for i = #executor.task_history, math.max(1, #executor.task_history - 10), -1 do
    local info = executor.task_history[i]
    if info.status == 'success' then
      success = success + 1
    elseif info.status == 'failed' then
      failed = failed + 1
    end
  end

  if running > 0 then
    return string.format('[%d running]', running)
  elseif success > 0 or failed > 0 then
    return string.format('[✓ %d  ✗ %d]', success, failed)
  end

  return ''
end

return M
