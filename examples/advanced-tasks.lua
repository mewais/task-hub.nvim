-- examples/advanced-tasks.lua
-- Advanced example with inputs, composite tasks, and complex workflows

return {
  -- Task groups
  groups = {
    ["Build"] = { "Build", "Clean", "Rebuild" },
    ["Test"] = { "Unit Tests", "Integration Tests", "E2E Tests" },
    ["Deploy"] = { "Deploy to Staging", "Deploy to Production" },
  },

  -- Task definitions
  tasks = {
    -- Simple tasks
    {
      name = "Clean",
      command = "rm -rf build/ dist/",
    },

    {
      name = "Build",
      command = "cargo build --release --features ${input:features}",
      env = {
        RUST_LOG = "${input:logLevel}",
      },
    },

    {
      name = "Unit Tests",
      command = "cargo test --lib",
    },

    {
      name = "Integration Tests",
      command = "cargo test --test '*'",
    },

    {
      name = "E2E Tests",
      command = "npm run test:e2e -- --env ${input:environment}",
    },

    -- Composite task (serial execution)
    {
      name = "Rebuild",
      type = "composite",
      execution = "serial",
      stopOnError = true,
      tasks = { "Clean", "Build" },
    },

    -- Composite task (parallel execution)
    {
      name = "Run All Tests",
      type = "composite",
      execution = "parallel",
      tasks = { "Unit Tests", "Integration Tests" },
    },

    -- Complex composite workflow
    {
      name = "Full CI Pipeline",
      type = "composite",
      execution = "serial",
      stopOnError = true,
      tasks = { "Clean", "Build", "Run All Tests", "E2E Tests" },
    },

    -- Task with multiple inputs
    {
      name = "Deploy to Staging",
      command = "kubectl apply -f deployment.yaml --namespace ${input:namespace}",
      env = {
        KUBECONFIG = "${workspaceFolder}/kubeconfig",
        ENVIRONMENT = "staging",
        VERSION = "${input:version}",
      },
    },

    {
      name = "Deploy to Production",
      command = "kubectl apply -f deployment.yaml --namespace ${input:namespace}",
      env = {
        KUBECONFIG = "${workspaceFolder}/kubeconfig",
        ENVIRONMENT = "production",
        VERSION = "${input:version}",
      },
    },

    -- Task with custom script
    {
      name = "Custom Build",
      command = "${workspaceFolder}/scripts/build.sh --arch ${input:architecture} --opt ${input:optimization}",
    },
  },

  -- Input definitions
  inputs = {
    features = {
      type = "prompt",
      prompt = "Enter cargo features (comma-separated):",
      default = "default",
    },

    logLevel = {
      type = "select",
      prompt = "Select log level:",
      options = { "debug", "info", "warn", "error" },
      default = "info",
    },

    environment = {
      type = "select",
      prompt = "Select environment:",
      options = { "development", "staging", "production" },
      default = "development",
    },

    namespace = {
      type = "prompt",
      prompt = "Enter Kubernetes namespace:",
      default = "default",
    },

    version = {
      type = "prompt",
      prompt = "Enter deployment version:",
      default = "latest",
    },

    architecture = {
      type = "select",
      prompt = "Select target architecture:",
      options = { "x86_64", "aarch64", "riscv64" },
      default = "x86_64",
    },

    optimization = {
      type = "select",
      prompt = "Select optimization level:",
      options = { "0", "1", "2", "3", "s", "z" },
      default = "2",
    },
  },
}
