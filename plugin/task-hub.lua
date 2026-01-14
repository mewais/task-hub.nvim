-- plugin/task-hub.lua
-- Entry point for task-hub.nvim plugin

if vim.g.loaded_task_hub then
  return
end
vim.g.loaded_task_hub = true

-- Ensure we're running on Neovim 0.8+
if vim.fn.has('nvim-0.8') == 0 then
  vim.api.nvim_err_writeln('task-hub.nvim requires Neovim 0.8 or higher')
  return
end

-- Create user commands
vim.api.nvim_create_user_command('TaskHub', function(opts)
  local args = opts.args
  if args == '' or args == 'toggle' then
    require('task-hub').toggle()
  elseif args == 'open' then
    require('task-hub').open()
  elseif args == 'close' then
    require('task-hub').close()
  elseif args == 'refresh' then
    require('task-hub').refresh()
  else
    vim.notify('Unknown TaskHub command: ' .. args, vim.log.levels.ERROR)
  end
end, {
  nargs = '?',
  complete = function()
    return { 'toggle', 'open', 'close', 'refresh' }
  end,
  desc = 'Task Hub commands',
})

vim.api.nvim_create_user_command('TaskHubRun', function(opts)
  require('task-hub').run_task_by_name(opts.args)
end, {
  nargs = 1,
  complete = function()
    return require('task-hub').get_task_names()
  end,
  desc = 'Run a task by name',
})

vim.api.nvim_create_user_command('TaskHubKill', function(opts)
  if opts.args ~= '' then
    require('task-hub').stop_task(opts.args)
  else
    require('task-hub').stop_current_task()
  end
end, {
  nargs = '?',
  complete = function()
    return require('task-hub').get_running_task_names()
  end,
  desc = 'Kill a running task',
})
