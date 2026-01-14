-- lua/task-hub/storage.lua
-- Persistent storage for task input values

local M = {}

-- Get the storage file path
function M.get_storage_path()
  local data_path = vim.fn.stdpath('data')
  return data_path .. '/task-hub-inputs.json'
end

-- Load stored input values from disk
function M.load()
  local filepath = M.get_storage_path()

  if vim.fn.filereadable(filepath) == 0 then
    return {}
  end

  local file = io.open(filepath, 'r')
  if not file then
    return {}
  end

  local content = file:read('*all')
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    vim.notify('task-hub: Failed to parse storage file', vim.log.levels.WARN)
    return {}
  end

  return data or {}
end

-- Save input values to disk
function M.save(data)
  local filepath = M.get_storage_path()

  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('task-hub: Failed to encode storage data', vim.log.levels.ERROR)
    return false
  end

  local file = io.open(filepath, 'w')
  if not file then
    vim.notify('task-hub: Failed to open storage file for writing', vim.log.levels.ERROR)
    return false
  end

  file:write(json)
  file:close()

  return true
end

-- Get stored inputs for a specific task in a project
function M.get_task_inputs(project_path, task_name)
  local data = M.load()

  if not data[project_path] then
    return {}
  end

  return data[project_path][task_name] or {}
end

-- Store inputs for a specific task in a project
function M.set_task_inputs(project_path, task_name, inputs)
  local data = M.load()

  if not data[project_path] then
    data[project_path] = {}
  end

  data[project_path][task_name] = inputs

  M.save(data)
end

-- Get the current project path (cwd)
function M.get_project_path()
  return vim.fn.getcwd()
end

return M
