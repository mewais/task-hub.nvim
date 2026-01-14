-- lua/task-hub/parser.lua
-- Parse task configuration files (Lua and JSON formats)

local M = {}

-- Find the task file in the current working directory
function M.find_task_file()
  local config = require('task-hub.config').get()
  local cwd = vim.fn.getcwd()

  for _, filename in ipairs(config.task_files) do
    local filepath = cwd .. '/' .. filename
    if vim.fn.filereadable(filepath) == 1 then
      return filepath
    end
  end

  return nil
end

-- Load a Lua task file
function M.load_lua_file(filepath)
  local ok, result = pcall(dofile, filepath)
  if not ok then
    return nil, 'Failed to load Lua file: ' .. tostring(result)
  end

  if type(result) ~= 'table' then
    return nil, 'Task file must return a table'
  end

  return result, nil
end

-- Load a JSON task file (VSCode format)
function M.load_json_file(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return nil, 'Failed to open JSON file'
  end

  local content = file:read('*all')
  file:close()

  local ok, json_data = pcall(vim.json.decode, content)
  if not ok then
    return nil, 'Failed to parse JSON: ' .. tostring(json_data)
  end

  -- Convert VSCode tasks.json format to our format
  return M.convert_vscode_format(json_data)
end

-- Convert VSCode tasks.json to our internal format
function M.convert_vscode_format(vscode_data)
  local result = {
    tasks = {},
    inputs = {},
    groups = {},
  }

  -- Convert tasks
  if vscode_data.tasks then
    for _, vscode_task in ipairs(vscode_data.tasks) do
      local task = {
        name = vscode_task.label,
        command = vscode_task.command,
        cwd = vscode_task.options and vscode_task.options.cwd,
        env = vscode_task.options and vscode_task.options.env,
      }
      table.insert(result.tasks, task)
    end
  end

  -- Convert inputs
  if vscode_data.inputs then
    for _, vscode_input in ipairs(vscode_data.inputs) do
      local input = {
        type = vscode_input.type == 'pickString' and 'select' or 'prompt',
        prompt = vscode_input.description,
        options = vscode_input.options,
        default = vscode_input.default,
      }
      result.inputs[vscode_input.id] = input
    end
  end

  return result, nil
end

-- Validate task structure
function M.validate_tasks(tasks_module)
  if not tasks_module.tasks or type(tasks_module.tasks) ~= 'table' then
    return false, 'Task file must contain a "tasks" array'
  end

  -- Validate each task
  for i, task in ipairs(tasks_module.tasks) do
    if not task.name then
      return false, string.format('Task #%d missing "name" field', i)
    end

    -- Check if it's a composite task or regular task
    if task.type == 'composite' then
      if not task.tasks or type(task.tasks) ~= 'table' then
        return false, string.format('Composite task "%s" missing "tasks" array', task.name)
      end
    else
      if not task.command then
        return false, string.format('Task "%s" missing "command" field', task.name)
      end
    end
  end

  return true, nil
end

-- Load and parse the task file
function M.load_tasks()
  local filepath = M.find_task_file()

  if not filepath then
    return nil, 'No task file found. Create .nvim/tasks.lua or tasks.lua in project root'
  end

  local tasks_module, err

  -- Determine file type and load accordingly
  if filepath:match('%.lua$') then
    tasks_module, err = M.load_lua_file(filepath)
  elseif filepath:match('%.json$') then
    tasks_module, err = M.load_json_file(filepath)
  else
    return nil, 'Unknown file format: ' .. filepath
  end

  if err then
    return nil, err
  end

  -- Validate structure
  local valid, validation_err = M.validate_tasks(tasks_module)
  if not valid then
    return nil, validation_err
  end

  -- Add default groups if not present
  if not tasks_module.groups then
    tasks_module.groups = {}
  end

  -- Add default inputs if not present
  if not tasks_module.inputs then
    tasks_module.inputs = {}
  end

  return tasks_module, nil
end

-- Substitute variables in a string
-- Supports: ${workspaceFolder}, ${input:inputName}
function M.substitute_variables(str, input_values)
  if type(str) ~= 'string' then
    return str
  end

  input_values = input_values or {}
  local cwd = vim.fn.getcwd()

  -- Replace ${workspaceFolder}
  str = str:gsub('${workspaceFolder}', cwd)

  -- Replace ${input:name}
  str = str:gsub('${input:([^}]+)}', function(input_name)
    return input_values[input_name] or ''
  end)

  return str
end

-- Process environment variables with substitution
function M.process_env(env, input_values)
  if not env or type(env) ~= 'table' then
    return {}
  end

  local processed = {}
  for key, value in pairs(env) do
    processed[key] = M.substitute_variables(value, input_values)
  end

  return processed
end

-- Get task by name
function M.get_task_by_name(tasks_module, name)
  if not tasks_module or not tasks_module.tasks then
    return nil
  end

  for _, task in ipairs(tasks_module.tasks) do
    if task.name == name then
      return task
    end
  end

  return nil
end

-- Find all input references in a task
function M.find_input_references(task)
  local references = {}

  -- Helper to extract input names from string
  local function extract_inputs(str)
    if type(str) ~= 'string' then
      return
    end
    for input_name in str:gmatch('${input:([^}]+)}') do
      references[input_name] = true
    end
  end

  -- Check command
  if task.command then
    extract_inputs(task.command)
  end

  -- Check environment variables
  if task.env then
    for _, value in pairs(task.env) do
      extract_inputs(value)
    end
  end

  -- Check cwd
  if task.cwd then
    extract_inputs(task.cwd)
  end

  return references
end

-- Organize tasks into groups
function M.organize_tasks(tasks_module)
  local organized = {
    grouped = {},    -- tasks organized by group
    ungrouped = {},  -- tasks not in any group
  }

  -- Create a set of all tasks in groups
  local grouped_tasks = {}
  for group_name, task_names in pairs(tasks_module.groups or {}) do
    for _, task_name in ipairs(task_names) do
      grouped_tasks[task_name] = group_name
    end
  end

  -- Organize tasks
  for _, task in ipairs(tasks_module.tasks) do
    local group_name = grouped_tasks[task.name]

    if group_name then
      if not organized.grouped[group_name] then
        organized.grouped[group_name] = {}
      end
      table.insert(organized.grouped[group_name], task)
    else
      table.insert(organized.ungrouped, task)
    end
  end

  return organized
end

return M
