-- lua/task-hub/prompts.lua
-- Handle interactive prompts for task inputs with nui.nvim support

local M = {}

local config = require('task-hub.config')
local storage = require('task-hub.storage')

-- Prompt using nui.nvim (if available)
function M.prompt_with_nui(input_name, input_config, default_value, callback)
  local input_type = input_config.type or 'prompt'

  if input_type == 'select' or input_type == 'pickString' then
    -- Use nui.menu for selections
    local Menu = require('nui.menu')
    local options = input_config.options or {}

    -- Create menu items
    local items = {}
    for i, option in ipairs(options) do
      table.insert(items, Menu.item(option, { id = i }))
    end

    if #items == 0 then
      callback(default_value)
      return
    end

    local menu = Menu({
      position = {
        row = '50%',
        col = '50%',
      },
      relative = 'editor',  -- Position relative to entire editor, not current window
      size = {
        width = 60,
        height = math.min(#items + 2, 15),
      },
      border = {
        style = config.get().ui.border,
        text = {
          top = ' ' .. (input_config.prompt or input_name) .. ' ',
          top_align = 'center',
        },
      },
      win_options = {
        winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
      },
    }, {
      lines = items,
      max_width = 58,
      keymap = {
        focus_next = { 'j', '<Down>', '<Tab>' },
        focus_prev = { 'k', '<Up>', '<S-Tab>' },
        close = { '<Esc>', '<C-c>' },  -- Removed 'q' - can be part of user input
        submit = { '<CR>', '<Space>' },
      },
      on_close = function()
        callback(nil)  -- Return nil to signal cancellation
      end,
      on_submit = function(item)
        callback(item.text)
      end,
    })

    menu:mount()

  elseif input_type == 'prompt' or input_type == 'promptString' then
    -- Use nui.input for text inputs
    local Input = require('nui.input')

    local input = Input({
      position = {
        row = '50%',
        col = '50%',
      },
      relative = 'editor',  -- Position relative to entire editor, not current window
      size = {
        width = 60,
        height = 1,
      },
      border = {
        style = config.get().ui.border,
        text = {
          top = ' ' .. (input_config.prompt or input_name) .. ' ',
          top_align = 'center',
        },
      },
      win_options = {
        winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
      },
    }, {
      prompt = '> ',
      default_value = default_value or '',
      on_close = function()
        callback(nil)  -- Return nil to signal cancellation
      end,
      on_submit = function(value)
        callback(value)
      end,
    })

    -- Add escape key mapping for cancellation
    input:map('i', '<Esc>', function()
      callback(nil)
      input:unmount()
    end, { noremap = true })

    input:map('i', '<C-c>', function()
      callback(nil)
      input:unmount()
    end, { noremap = true })

    input:mount()
  else
    -- Unknown type, use default
    callback(default_value)
  end
end

-- Prompt using vim.ui (fallback)
function M.prompt_with_vim_ui(input_name, input_config, default_value, callback)
  local input_type = input_config.type or 'prompt'

  if input_type == 'select' or input_type == 'pickString' then
    -- Use vim.ui.select
    local options = input_config.options or {}

    if #options == 0 then
      callback(default_value)
      return
    end

    vim.ui.select(options, {
      prompt = input_config.prompt or input_name,
      format_item = function(item)
        return tostring(item)
      end,
    }, function(choice)
      -- choice is nil when cancelled, pass it through
      callback(choice)
    end)

  elseif input_type == 'prompt' or input_type == 'promptString' then
    -- Use vim.ui.input
    vim.ui.input({
      prompt = (input_config.prompt or input_name) .. ': ',
      default = default_value or '',
    }, function(input)
      -- input is nil when cancelled, pass it through
      callback(input)
    end)

  else
    -- Unknown type, use default
    callback(default_value)
  end
end

-- Prompt for a single input
function M.prompt_input(input_name, input_config, callback)
  if not input_config then
    callback(nil)
    return
  end

  -- Get stored value or default
  local project_path = storage.get_project_path()
  local stored = storage.get_task_inputs(project_path, 'inputs')
  local default_value = stored[input_name] or input_config.default or ''

  -- Choose prompt method based on configuration
  if config.get().ui.use_nui then
    M.prompt_with_nui(input_name, input_config, default_value, callback)
  else
    M.prompt_with_vim_ui(input_name, input_config, default_value, callback)
  end
end

-- Collect all inputs required by a task
function M.collect_inputs(task, inputs_config, callback)
  inputs_config = inputs_config or {}
  local parser = require('task-hub.parser')

  -- Find all required inputs
  local required_inputs = parser.find_input_references(task)

  -- Convert to array for sequential prompting
  local input_names = {}
  for name in pairs(required_inputs) do
    table.insert(input_names, name)
  end

  -- Sort for consistent ordering
  table.sort(input_names)

  -- If no inputs required, call callback immediately
  if #input_names == 0 then
    callback({})
    return
  end

  local input_values = {}

  -- Prompt for each input sequentially
  local function prompt_next(index)
    if index > #input_names then
      -- All inputs collected, save them if configured
      if config.get().execution.remember_inputs then
        local project_path = storage.get_project_path()
        local stored = storage.get_task_inputs(project_path, 'inputs')

        for name, value in pairs(input_values) do
          stored[name] = value
        end

        storage.set_task_inputs(project_path, 'inputs', stored)
      end

      callback(input_values)
      return
    end

    local input_name = input_names[index]
    local input_config = inputs_config[input_name]

    M.prompt_input(input_name, input_config, function(value)
      -- If value is nil, user cancelled - abort the entire input collection
      if value == nil then
        callback(nil)  -- Signal cancellation to caller
        return
      end

      input_values[input_name] = value
      prompt_next(index + 1)
    end)
  end

  prompt_next(1)
end

return M
