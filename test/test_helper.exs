# Configure ExUnit to exclude shell integration tests by default
# Run them with: mix test --include shell_integration
ExUnit.start(exclude: [:shell_integration])
