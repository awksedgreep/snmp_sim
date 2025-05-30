# Start SNMP application for integration tests
case Application.start(:snmp) do
  :ok -> :ok
  {:error, {:already_started, _}} -> :ok
  error -> IO.puts("Warning: Could not start SNMP application: #{inspect(error)}")
end

# Configure ExUnit to exclude shell integration tests and slow tests by default
# Run them with: mix test --include shell_integration
# Run slow tests with: mix test --include slow
ExUnit.start(exclude: [:shell_integration, :slow])
