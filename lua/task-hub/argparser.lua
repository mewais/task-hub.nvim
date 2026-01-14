-- lua/task-hub/argparser.lua
-- Parse script arguments from various argument parsing libraries

local M = {}

-- Parse Python argparse arguments
local function parse_python_argparse(content)
  local args = {}

  for _, line in ipairs(content) do
    -- Match add_argument patterns
    -- Examples:
    --   parser.add_argument('--name', ...)
    --   parser.add_argument('-n', '--name', ...)
    local arg_name = line:match("add_argument%s*%(%s*['\"]%-%-([%w_-]+)['\"]")

    if arg_name then
      local arg_def = {
        name = arg_name,
        type = 'prompt',
        prompt = 'Enter ' .. arg_name:gsub('[-_]', ' ') .. ':',
        default = '',
      }

      -- Try to detect choices (makes it a select)
      local choices = line:match("choices%s*=%s*%[([^%]]+)%]")
      if choices then
        arg_def.type = 'select'
        arg_def.options = {}
        for choice in choices:gmatch("['\"]([^'\"]+)['\"]") do
          table.insert(arg_def.options, choice)
        end
      end

      -- Try to detect default value
      local default = line:match("default%s*=%s*['\"]([^'\"]+)['\"]")
      if default then
        arg_def.default = default
      end

      -- Try to detect help text for better prompt
      local help = line:match("help%s*=%s*['\"]([^'\"]+)['\"]")
      if help and #help < 60 then
        arg_def.prompt = help .. ':'
      end

      table.insert(args, arg_def)
    end
  end

  return args
end

-- Parse Python click decorators
local function parse_python_click(content)
  local args = {}

  for _, line in ipairs(content) do
    -- Match @click.option patterns
    -- Examples:
    --   @click.option('--name', ...)
    --   @click.option('-n', '--name', ...)
    local arg_name = line:match("@click%.option%s*%(%s*['\"]%-%-([%w_-]+)['\"]")

    if arg_name then
      local arg_def = {
        name = arg_name,
        type = 'prompt',
        prompt = 'Enter ' .. arg_name:gsub('[-_]', ' ') .. ':',
        default = '',
      }

      -- Try to detect type
      local click_type = line:match("type%s*=%s*click%.Choice%s*%(%s*%[([^%]]+)%]")
      if click_type then
        arg_def.type = 'select'
        arg_def.options = {}
        for choice in click_type:gmatch("['\"]([^'\"]+)['\"]") do
          table.insert(arg_def.options, choice)
        end
      end

      -- Try to detect default
      local default = line:match("default%s*=%s*['\"]([^'\"]+)['\"]")
      if default then
        arg_def.default = default
      end

      -- Try to detect help
      local help = line:match("help%s*=%s*['\"]([^'\"]+)['\"]")
      if help and #help < 60 then
        arg_def.prompt = help .. ':'
      end

      table.insert(args, arg_def)
    end
  end

  return args
end

-- Parse Python docopt
local function parse_python_docopt(content)
  local args = {}
  local in_docstring = false
  local in_arguments_section = false
  local docstring = {}

  -- Find docstring
  for _, line in ipairs(content) do
    if line:match('"""') or line:match("'''") then
      if in_docstring then
        break
      else
        in_docstring = true
      end
    elseif in_docstring then
      table.insert(docstring, line)
    end
  end

  -- Parse docstring for positional arguments only (Arguments section)
  -- Skip optional --flags as they're too complex to handle properly
  for _, line in ipairs(docstring) do
    -- Detect Arguments section
    if line:match("^Arguments:") then
      in_arguments_section = true
    elseif line:match("^%w+:") then  -- New section started
      in_arguments_section = false
    end

    -- Only parse lines in Arguments section
    if in_arguments_section then
      -- Match patterns like:
      --   file1                        Description
      --   datatype                     Data type for conversion
      local arg_name, desc = line:match("^%s+([%w_-]+)%s+(.+)")

      if arg_name and desc then
        desc = desc:gsub("^%s+", ""):gsub("%s+$", "")

        local arg_def = {
          name = arg_name,
          type = 'prompt',
          prompt = desc:gsub("%s*%.$", "") .. ':',
          default = '',
        }

        table.insert(args, arg_def)
      end
    end
  end

  return args
end

-- Parse Bash script positional parameters
local function parse_bash_params(content)
  local args = {}
  local param_count = 0

  for _, line in ipairs(content) do
    -- Look for $1, $2, etc. usage
    for param in line:gmatch("%$(%d+)") do
      local num = tonumber(param)
      if num and num > param_count then
        param_count = num
      end
    end

    -- Look for getopts
    local getopts_spec = line:match("getopts%s+['\"]([^'\"]+)['\"]")
    if getopts_spec then
      for opt in getopts_spec:gmatch("([a-zA-Z]):?") do
        table.insert(args, {
          name = opt,
          type = 'prompt',
          prompt = 'Enter -' .. opt .. ':',
          default = '',
        })
      end
    end
  end

  -- Add positional parameters
  for i = 1, param_count do
    table.insert(args, {
      name = 'arg' .. i,
      type = 'prompt',
      prompt = 'Enter argument ' .. i .. ':',
      default = '',
    })
  end

  return args
end

-- Main function: Parse script file and extract arguments
function M.parse_script_args(filepath)
  if vim.fn.filereadable(filepath) ~= 1 then
    return {}
  end

  local content = vim.fn.readfile(filepath)
  local args = {}

  -- Determine file type
  if filepath:match('%.py$') then
    -- Check for argparse
    local has_argparse = false
    local has_click = false
    local has_docopt = false

    for _, line in ipairs(content) do
      if line:match('import%s+argparse') or line:match('from%s+argparse') then
        has_argparse = true
      end
      if line:match('import%s+click') or line:match('from%s+click') then
        has_click = true
      end
      if line:match('import%s+docopt') or line:match('from%s+docopt') then
        has_docopt = true
      end
    end

    if has_argparse then
      args = parse_python_argparse(content)
    elseif has_click then
      args = parse_python_click(content)
    elseif has_docopt then
      args = parse_python_docopt(content)
    end

  elseif filepath:match('%.sh$') then
    args = parse_bash_params(content)
  end

  return args
end

-- Generate input definitions for task from parsed arguments
function M.generate_inputs(args, task_name)
  local inputs = {}

  for _, arg in ipairs(args) do
    local input_id = task_name .. '_' .. arg.name
    inputs[input_id] = {
      type = arg.type,
      prompt = arg.prompt,
      options = arg.options,
      default = arg.default,
    }
  end

  return inputs
end

-- Update task command to use input placeholders
function M.add_args_to_command(task, args)
  if #args == 0 then
    return task
  end

  local arg_placeholders = {}
  for _, arg in ipairs(args) do
    local input_ref = '${input:' .. task.name .. '_' .. arg.name .. '}'

    -- For options/flags, format as --name=value
    if arg.name:match('^[a-zA-Z]$') then
      -- Single letter (bash-style)
      table.insert(arg_placeholders, '-' .. arg.name .. ' ' .. input_ref)
    elseif arg.name:match('^arg%d+$') then
      -- Positional argument
      table.insert(arg_placeholders, input_ref)
    else
      -- Long option
      table.insert(arg_placeholders, '--' .. arg.name .. '=' .. input_ref)
    end
  end

  -- Append arguments to command
  task.command = task.command .. ' ' .. table.concat(arg_placeholders, ' ')

  return task
end

return M
