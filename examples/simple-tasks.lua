-- examples/simple-tasks.lua
-- Simple example task configuration for task-hub.nvim

return {
  -- Define task groups (optional)
  groups = {
    ["Build"] = { "Build Debug", "Build Release", "Clean" },
    ["Test"] = { "Run Tests", "Run Integration Tests" },
  },

  -- Define tasks
  tasks = {
    -- Simple tasks
    {
      name = "Build Debug",
      command = "make debug",
    },

    {
      name = "Build Release",
      command = "make release",
    },

    {
      name = "Clean",
      command = "make clean",
    },

    {
      name = "Run Tests",
      command = "pytest tests/ -v",
    },

    {
      name = "Run Integration Tests",
      command = "pytest tests/integration/ -v",
    },

    -- Task with environment variables
    {
      name = "Deploy",
      command = "kubectl apply -f deployment.yaml",
      env = {
        KUBECONFIG = "${workspaceFolder}/kubeconfig",
        NAMESPACE = "production",
      },
    },

    -- Task with custom working directory
    {
      name = "Build Docs",
      command = "mkdocs build",
      cwd = "${workspaceFolder}/docs",
    },
  },

  -- No inputs needed for this simple example
  inputs = {},
}
