-- lua/task-hub/init.lua
-- Main module for task-hub.nvim

local M = {}

-- Lazy load submodules
local function get_config()
  return require('task-hub.config')
end

local function get_ui()
  return require('task-hub.ui')
end

local function get_parser()
  return require('task-hub.parser')
end

local function get_executor()
  return require('task-hub.executor')
end

local function get_prompts()
  return require('task-hub.prompts')
end

-- Setup the plugin
function M.setup(user_config)
  get_config().setup(user_config or {})
end

-- Open task hub
function M.open()
  get_ui().open_window()
end

-- Close task hub
function M.close()
  get_ui().close()
end

-- Toggle task hub
function M.toggle()
  get_ui().toggle()
end

-- Refresh task list
function M.refresh()
  get_ui().refresh()
end

-- Check if task hub is open
function M.is_open()
  return get_ui().is_open()
end

-- Run a task by name
function M.run_task_by_name(task_name)
  local parser = get_parser()
  local prompts = get_prompts()
  local executor = get_executor()

  local tasks_module, err = parser.load_tasks()

  if err then
    vim.notify('task-hub: Error loading tasks: ' .. err, vim.log.levels.ERROR)
    return
  end

  local task = parser.get_task_by_name(tasks_module, task_name)

  if not task then
    vim.notify('task-hub: Task not found: ' .. task_name, vim.log.levels.ERROR)
    return
  end

  -- Collect inputs and execute
  prompts.collect_inputs(task, tasks_module.inputs or {}, function(input_values)
    -- If input_values is nil, user cancelled
    if input_values == nil then
      vim.notify('task-hub: Task cancelled', vim.log.levels.INFO)
      return
    end

    executor.execute_task(task, tasks_module, input_values)
  end)
end

-- Get list of all task names
function M.get_task_names()
  local parser = get_parser()
  local tasks_module, err = parser.load_tasks()

  if err then
    return {}
  end

  local names = {}
  if tasks_module.tasks then
    for _, task in ipairs(tasks_module.tasks) do
      table.insert(names, task.name)
    end
  end

  return names
end

-- Get list of running task names
function M.get_running_task_names()
  return get_executor().get_running_tasks()
end

-- Stop a task
function M.stop_task(task_name)
  local executor = get_executor()

  if not executor.is_task_running(task_name) then
    vim.notify('task-hub: Task is not running: ' .. task_name, vim.log.levels.WARN)
    return false
  end

  return executor.stop_task(task_name)
end

-- Stop the currently selected task (in UI)
function M.stop_current_task()
  get_ui().kill_task_under_cursor()
end

-- Get task status
function M.get_task_status(task_name)
  return get_executor().get_task_status(task_name)
end

-- Export submodules for advanced usage
M.config = get_config
M.ui = get_ui
M.parser = get_parser
M.executor = get_executor
M.prompts = get_prompts

return M
