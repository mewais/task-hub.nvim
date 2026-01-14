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
  local config = require('task-hub.config').get()
  local filepath = M.find_task_file()

  -- Load user-defined tasks
  local user_module = {tasks = {}, groups = {}, inputs = {}}
  local err = nil

  if filepath then
    -- Determine file type and load accordingly
    if filepath:match('%.lua$') then
      user_module, err = M.load_lua_file(filepath)
    elseif filepath:match('%.json$') then
      user_module, err = M.load_json_file(filepath)
    else
      return nil, 'Unknown file format: ' .. filepath
    end

    if err then
      return nil, err
    end

    -- Validate structure
    local valid, validation_err = M.validate_tasks(user_module)
    if not valid then
      return nil, validation_err
    end
  end

  -- Add default groups and inputs if not present
  if not user_module.groups then
    user_module.groups = {}
  end
  if not user_module.inputs then
    user_module.inputs = {}
  end

  -- Detect auto tasks if enabled
  local auto_module = {tasks = {}, groups = {}}
  if config.auto_detect.enabled then
    local detector = require('task-hub.detector')
    auto_module = detector.detect_all_tasks(vim.fn.getcwd(), config.auto_detect)
  end

  -- Merge user and auto tasks
  local merged = M.merge_task_modules(user_module, auto_module, config)

  return merged, nil
end

-- Merge user-defined and auto-detected tasks
function M.merge_task_modules(user_module, auto_module, config)
  local result = {tasks = {}, groups = {}, inputs = {}}

  -- Copy user inputs
  result.inputs = vim.deepcopy(user_module.inputs or {})

  -- Merge tasks and groups based on configuration
  if config.auto_detect.grouping.merge_with_custom then
    -- Mixed mode: combine into same groups
    result.tasks = vim.list_extend(vim.deepcopy(user_module.tasks or {}), auto_module.tasks or {})

    -- Merge groups
    result.groups = vim.deepcopy(user_module.groups or {})
    for name, tasks in pairs(auto_module.groups or {}) do
      result.groups[name] = tasks
    end
  else
    -- Separate mode: user tasks first, then auto tasks in separate groups
    result.tasks = vim.deepcopy(user_module.tasks or {})
    vim.list_extend(result.tasks, auto_module.tasks or {})

    -- User groups first
    result.groups = vim.deepcopy(user_module.groups or {})

    -- Add auto groups with prefix
    for name, tasks in pairs(auto_module.groups or {}) do
      local group_name = config.auto_detect.grouping.group_prefix .. name
      result.groups[group_name] = tasks
    end
  end

  -- Merge auto-detected inputs from tasks
  for _, task in ipairs(result.tasks) do
    if task.auto_inputs then
      for input_id, input_def in pairs(task.auto_inputs) do
        result.inputs[input_id] = input_def
      end
    end
  end

  -- Apply sorting to custom tasks if configured
  if config.auto_detect.sort.custom_tasks == 'alphabetical' and #(user_module.tasks or {}) > 0 then
    -- Sort only user tasks (first N tasks)
    local user_task_count = #(user_module.tasks or {})
    local user_tasks = vim.list_slice(result.tasks, 1, user_task_count)

    table.sort(user_tasks, function(a, b)
      return a.name < b.name
    end)

    -- Replace sorted portion
    for i, task in ipairs(user_tasks) do
      result.tasks[i] = task
    end
  end

  return result
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

-- Find all input references in a task (preserves order from task definition)
function M.find_input_references(task, inputs_config)
  -- If task has an explicit input_order field, use that
  if task.input_order and type(task.input_order) == 'table' then
    local references = {}
    local used_inputs = {}

    -- Helper to check if input is actually used in the task
    local function is_input_used(input_name)
      local pattern = '%${input:' .. input_name:gsub('%-', '%%-') .. '}'

      if task.command and task.command:find(pattern) then
        return true
      end

      if task.env then
        for _, value in pairs(task.env) do
          if type(value) == 'string' and value:find(pattern) then
            return true
          end
        end
      end

      if task.cwd and task.cwd:find(pattern) then
        return true
      end

      return false
    end

    -- Use the specified order, but only include inputs that are actually used
    for _, input_name in ipairs(task.input_order) do
      if is_input_used(input_name) then
        table.insert(references, input_name)
        used_inputs[input_name] = true
      end
    end

    return references
  end

  -- Fallback: extract in order of appearance
  local references = {}
  local seen = {}

  local function extract_inputs(str)
    if type(str) ~= 'string' then
      return
    end
    for input_name in str:gmatch('${input:([^}]+)}') do
      if not seen[input_name] then
        table.insert(references, input_name)
        seen[input_name] = true
      end
    end
  end

  -- Extract from command first
  if task.command then
    extract_inputs(task.command)
  end

  -- Extract from env variables (alphabetical order by key for consistency)
  if task.env then
    local env_keys = {}
    for key in pairs(task.env) do
      table.insert(env_keys, key)
    end
    table.sort(env_keys)

    for _, key in ipairs(env_keys) do
      extract_inputs(task.env[key])
    end
  end

  -- Extract from cwd last
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

  -- Create a set of tasks that are subtasks of composite tasks
  local subtask_names = {}
  for _, task in ipairs(tasks_module.tasks) do
    if task.type == 'composite' and task.tasks then
      for _, subtask_name in ipairs(task.tasks) do
        subtask_names[subtask_name] = true
      end
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
      -- Only show ungrouped if it's not a subtask of a composite
      if not subtask_names[task.name] then
        table.insert(organized.ungrouped, task)
      end
    end
  end

  return organized
end

return M
