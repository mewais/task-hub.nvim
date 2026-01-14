-- lua/task-hub/detector.lua
-- Auto-detection of tasks from project files

local M = {}

-- Cache for detected tasks
M.cache = {
  timestamp = nil,
  tasks = {},
  auto_groups = {},
}

-- Check if cache is still valid
function M.is_cache_valid(ttl)
  if not M.cache.timestamp then
    return false
  end
  local age = os.time() - M.cache.timestamp
  return age < ttl
end

-- Invalidate the cache
function M.invalidate_cache()
  M.cache = { timestamp = nil, tasks = {}, auto_groups = {} }
end

-- Helper: Check if path should be excluded
local function should_exclude(path, exclude_patterns)
  local rel_path = path:match('.*/(.*)$') or path

  for _, pattern in ipairs(exclude_patterns) do
    -- Simple pattern matching (convert glob * to lua pattern)
    local lua_pattern = pattern:gsub('%*%*', '.*'):gsub('%*', '[^/]*'):gsub('%.', '%%.')
    if rel_path:match(lua_pattern) or path:match(lua_pattern) then
      return true
    end
  end

  return false
end

-- Helper: Find files recursively
local function find_files(root_dir, pattern, max_depth, exclude_patterns, current_depth)
  current_depth = current_depth or 0
  if current_depth > max_depth then
    return {}
  end

  local files = {}
  local handle = vim.loop.fs_scandir(root_dir)

  if not handle then
    return files
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    local path = root_dir .. '/' .. name

    -- Skip excluded paths
    if should_exclude(path, exclude_patterns) then
      goto continue
    end

    if type == 'directory' then
      -- Recurse into subdirectories
      local subfiles = find_files(path, pattern, max_depth, exclude_patterns, current_depth + 1)
      vim.list_extend(files, subfiles)
    elseif type == 'file' then
      -- Check if file matches pattern
      if name:match(pattern) then
        table.insert(files, path)
      end
    end

    ::continue::
  end

  return files
end

-- Helper: Check if file is executable
local function is_executable(filepath)
  local stat = vim.loop.fs_stat(filepath)
  if not stat then
    return false
  end
  -- Check if user has execute permission (mode & 0100)
  return stat.mode and (stat.mode % 512 >= 256)
end

-- Detect Python tasks
function M.detect_python(root_dir, opts)
  local tasks = {}

  -- Find Python scripts with __main__
  if opts.scripts then
    local py_files = find_files(root_dir, '%.py$', opts.scan.depth, opts.scan.exclude)

    for _, filepath in ipairs(py_files) do
      local content = vim.fn.readfile(filepath)
      local has_main = false

      for _, line in ipairs(content) do
        if line:match('if%s+__name__%s*==%s*["\']__main__["\']') then
          has_main = true
          break
        end
      end

      if has_main then
        local script_name = filepath:match('([^/]+)%.py$')
        table.insert(tasks, {
          name = 'Run ' .. script_name,
          command = 'python3 ' .. filepath,
          cwd = root_dir,
          auto_detected = true,
          auto_source = 'python',
        })
      end
    end
  end

  -- Detect pytest
  if opts.pytest then
    local pytest_indicators = {
      'pytest.ini',
      'setup.cfg',
      'pyproject.toml',
      'tests/',
      'test_*.py',
    }

    local has_pytest = false
    for _, indicator in ipairs(pytest_indicators) do
      local path = root_dir .. '/' .. indicator
      if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
        has_pytest = true
        break
      end
    end

    if has_pytest then
      table.insert(tasks, {
        name = 'Run pytest',
        command = 'python3 -m pytest',
        cwd = root_dir,
        auto_detected = true,
        auto_source = 'python',
      })
    end
  end

  -- Detect requirements.txt
  if opts.requirements then
    local req_files = { 'requirements.txt', 'requirements-dev.txt' }

    for _, req_file in ipairs(req_files) do
      local path = root_dir .. '/' .. req_file
      if vim.fn.filereadable(path) == 1 then
        local name = req_file == 'requirements.txt' and 'Install Python Dependencies' or 'Install Python Dev Dependencies'
        table.insert(tasks, {
          name = name,
          command = 'pip install -r ' .. req_file,
          cwd = root_dir,
          auto_detected = true,
          auto_source = 'python',
        })
      end
    end
  end

  return tasks
end

-- Detect CMake tasks
function M.detect_cmake(root_dir, opts)
  local tasks = {}

  if not opts.targets then
    return tasks
  end

  local cmake_files = find_files(root_dir, 'CMakeLists%.txt$', opts.scan.depth, opts.scan.exclude)

  if #cmake_files == 0 then
    return tasks
  end

  -- Add configure task
  table.insert(tasks, {
    name = 'CMake Configure',
    command = 'cmake -B build',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'cmake',
  })

  -- Parse CMakeLists.txt for targets
  local targets = {}
  for _, cmake_file in ipairs(cmake_files) do
    local content = vim.fn.readfile(cmake_file)

    for _, line in ipairs(content) do
      -- Match add_executable(target ...)
      local target = line:match('add_executable%s*%(%s*([%w_-]+)')
      if target then
        targets[target] = true
      end

      -- Match add_library(target ...)
      target = line:match('add_library%s*%(%s*([%w_-]+)')
      if target then
        targets[target] = true
      end

      -- Match add_custom_target(target ...)
      target = line:match('add_custom_target%s*%(%s*([%w_-]+)')
      if target then
        targets[target] = true
      end
    end
  end

  -- Create build tasks for each target
  for target, _ in pairs(targets) do
    table.insert(tasks, {
      name = 'Build ' .. target,
      command = 'cmake --build build --target ' .. target,
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'cmake',
    })
  end

  -- Add build all task
  table.insert(tasks, {
    name = 'Build All',
    command = 'cmake --build build',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'cmake',
  })

  return tasks
end

-- Detect Node/NPM tasks
function M.detect_node(root_dir, opts)
  local tasks = {}

  if not opts.package_scripts then
    return tasks
  end

  local package_json = root_dir .. '/package.json'
  if vim.fn.filereadable(package_json) ~= 1 then
    return tasks
  end

  -- Detect package manager
  local pkg_manager = 'npm'
  if vim.fn.filereadable(root_dir .. '/yarn.lock') == 1 then
    pkg_manager = 'yarn'
  elseif vim.fn.filereadable(root_dir .. '/pnpm-lock.yaml') == 1 then
    pkg_manager = 'pnpm'
  elseif vim.fn.filereadable(root_dir .. '/bun.lockb') == 1 then
    pkg_manager = 'bun'
  end

  -- Parse package.json
  local content = vim.fn.readfile(package_json)
  local json_str = table.concat(content, '\n')
  local ok, data = pcall(vim.fn.json_decode, json_str)

  if ok and data.scripts then
    -- Add install task
    table.insert(tasks, {
      name = 'Install Node Dependencies',
      command = pkg_manager .. ' install',
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'node',
    })

    -- Add script tasks
    for script_name, _ in pairs(data.scripts) do
      local cmd = pkg_manager == 'npm' and 'npm run ' .. script_name or pkg_manager .. ' ' .. script_name
      table.insert(tasks, {
        name = script_name,
        command = cmd,
        cwd = root_dir,
        auto_detected = true,
        auto_source = 'node',
      })
    end
  end

  return tasks
end

-- Detect Bash scripts
function M.detect_bash(root_dir, opts)
  local tasks = {}

  if not opts.scripts then
    return tasks
  end

  local sh_files = find_files(root_dir, '%.sh$', opts.scan.depth, opts.scan.exclude)

  for _, filepath in ipairs(sh_files) do
    if is_executable(filepath) then
      local script_name = filepath:match('([^/]+)%.sh$')
      table.insert(tasks, {
        name = 'Run ' .. script_name,
        command = filepath,
        cwd = root_dir,
        auto_detected = true,
        auto_source = 'bash',
      })
    end
  end

  return tasks
end

-- Detect Makefile targets
function M.detect_make(root_dir, opts)
  local tasks = {}

  if not opts.targets then
    return tasks
  end

  local makefile_path = root_dir .. '/Makefile'
  if vim.fn.filereadable(makefile_path) ~= 1 then
    makefile_path = root_dir .. '/makefile'
  end

  if vim.fn.filereadable(makefile_path) ~= 1 then
    return tasks
  end

  local content = vim.fn.readfile(makefile_path)
  local targets = {}

  for _, line in ipairs(content) do
    -- Match target: dependencies
    local target = line:match('^([%w_-]+)%s*:')
    if target and not target:match('^%.') then
      targets[target] = true
    end
  end

  -- Create tasks for each target
  for target, _ in pairs(targets) do
    table.insert(tasks, {
      name = target,
      command = 'make ' .. target,
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'make',
    })
  end

  return tasks
end

-- Detect Docker tasks
function M.detect_docker(root_dir, opts)
  local tasks = {}

  if not opts.compose then
    return tasks
  end

  local compose_files = { 'docker-compose.yml', 'docker-compose.yaml' }
  local compose_path = nil

  for _, file in ipairs(compose_files) do
    local path = root_dir .. '/' .. file
    if vim.fn.filereadable(path) == 1 then
      compose_path = path
      break
    end
  end

  if compose_path then
    -- Add basic compose tasks
    table.insert(tasks, {
      name = 'Docker Compose Up',
      command = 'docker-compose up -d',
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'docker',
    })

    table.insert(tasks, {
      name = 'Docker Compose Down',
      command = 'docker-compose down',
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'docker',
    })

    table.insert(tasks, {
      name = 'Docker Compose Logs',
      command = 'docker-compose logs -f',
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'docker',
    })
  end

  -- Check for Dockerfile
  if vim.fn.filereadable(root_dir .. '/Dockerfile') == 1 then
    table.insert(tasks, {
      name = 'Docker Build',
      command = 'docker build -t $(basename $(pwd)):latest .',
      cwd = root_dir,
      auto_detected = true,
      auto_source = 'docker',
    })
  end

  return tasks
end

-- Detect Cargo (Rust) tasks
function M.detect_cargo(root_dir, opts)
  local tasks = {}

  if not opts.targets then
    return tasks
  end

  local cargo_toml = root_dir .. '/Cargo.toml'
  if vim.fn.filereadable(cargo_toml) ~= 1 then
    return tasks
  end

  -- Add basic Cargo tasks
  table.insert(tasks, {
    name = 'Cargo Build',
    command = 'cargo build',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'cargo',
  })

  table.insert(tasks, {
    name = 'Cargo Build (Release)',
    command = 'cargo build --release',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'cargo',
  })

  table.insert(tasks, {
    name = 'Cargo Test',
    command = 'cargo test',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'cargo',
  })

  table.insert(tasks, {
    name = 'Cargo Run',
    command = 'cargo run',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'cargo',
  })

  return tasks
end

-- Detect Go tasks
function M.detect_go(root_dir, opts)
  local tasks = {}

  if not opts.packages then
    return tasks
  end

  local go_mod = root_dir .. '/go.mod'
  if vim.fn.filereadable(go_mod) ~= 1 then
    return tasks
  end

  -- Add basic Go tasks
  table.insert(tasks, {
    name = 'Go Build',
    command = 'go build ./...',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'go',
  })

  table.insert(tasks, {
    name = 'Go Test',
    command = 'go test ./...',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'go',
  })

  table.insert(tasks, {
    name = 'Go Run',
    command = 'go run .',
    cwd = root_dir,
    auto_detected = true,
    auto_source = 'go',
  })

  return tasks
end

-- Main detection function
function M.detect_all_tasks(root_dir, config)
  -- Check cache first
  if M.is_cache_valid(config.scan.cache_ttl) then
    return { tasks = M.cache.tasks, groups = M.cache.auto_groups }
  end

  local all_tasks = {}
  local auto_groups = {}

  -- Detect tasks for each enabled language
  if config.languages.python.enabled then
    local python_tasks = M.detect_python(root_dir, {
      scripts = config.languages.python.scripts,
      pytest = config.languages.python.pytest,
      requirements = config.languages.python.requirements,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, python_tasks)
    if #python_tasks > 0 and config.grouping.auto_group then
      auto_groups['Python'] = vim.tbl_map(function(t) return t.name end, python_tasks)
    end
  end

  if config.languages.cmake.enabled then
    local cmake_tasks = M.detect_cmake(root_dir, {
      targets = config.languages.cmake.targets,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, cmake_tasks)
    if #cmake_tasks > 0 and config.grouping.auto_group then
      auto_groups['CMake'] = vim.tbl_map(function(t) return t.name end, cmake_tasks)
    end
  end

  if config.languages.node.enabled then
    local node_tasks = M.detect_node(root_dir, {
      package_scripts = config.languages.node.package_scripts,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, node_tasks)
    if #node_tasks > 0 and config.grouping.auto_group then
      auto_groups['Node'] = vim.tbl_map(function(t) return t.name end, node_tasks)
    end
  end

  if config.languages.bash.enabled then
    local bash_tasks = M.detect_bash(root_dir, {
      scripts = config.languages.bash.scripts,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, bash_tasks)
    if #bash_tasks > 0 and config.grouping.auto_group then
      auto_groups['Bash'] = vim.tbl_map(function(t) return t.name end, bash_tasks)
    end
  end

  if config.languages.make.enabled then
    local make_tasks = M.detect_make(root_dir, {
      targets = config.languages.make.targets,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, make_tasks)
    if #make_tasks > 0 and config.grouping.auto_group then
      auto_groups['Make'] = vim.tbl_map(function(t) return t.name end, make_tasks)
    end
  end

  if config.languages.docker.enabled then
    local docker_tasks = M.detect_docker(root_dir, {
      compose = config.languages.docker.compose,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, docker_tasks)
    if #docker_tasks > 0 and config.grouping.auto_group then
      auto_groups['Docker'] = vim.tbl_map(function(t) return t.name end, docker_tasks)
    end
  end

  if config.languages.cargo.enabled then
    local cargo_tasks = M.detect_cargo(root_dir, {
      targets = config.languages.cargo.targets,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, cargo_tasks)
    if #cargo_tasks > 0 and config.grouping.auto_group then
      auto_groups['Cargo'] = vim.tbl_map(function(t) return t.name end, cargo_tasks)
    end
  end

  if config.languages.go.enabled then
    local go_tasks = M.detect_go(root_dir, {
      packages = config.languages.go.packages,
      scan = config.scan,
    })
    vim.list_extend(all_tasks, go_tasks)
    if #go_tasks > 0 and config.grouping.auto_group then
      auto_groups['Go'] = vim.tbl_map(function(t) return t.name end, go_tasks)
    end
  end

  -- Sort auto-detected tasks if configured
  local sort_mode = config.sort.auto_tasks
  if sort_mode == 'alphabetical' then
    table.sort(all_tasks, function(a, b)
      return a.name < b.name
    end)
  end

  -- Update cache
  M.cache.timestamp = os.time()
  M.cache.tasks = all_tasks
  M.cache.auto_groups = auto_groups

  return { tasks = all_tasks, groups = auto_groups }
end

return M
