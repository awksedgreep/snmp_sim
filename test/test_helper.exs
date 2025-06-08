# Start SNMP application for integration tests
case Application.start(:snmp) do
  :ok -> :ok
  {:error, {:already_started, _}} -> :ok
  error -> IO.puts("Warning: Could not start SNMP application: #{inspect(error)}")
end

# Start the snmp_sim application to ensure SharedProfiles GenServer is available
case Application.ensure_all_started(:snmp_sim) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  error -> IO.puts("Warning: Could not start snmp_sim application: #{inspect(error)}")
end

# Configure SNMP logging to be silent during tests
# This eliminates the verbose .snmpm:snmpm:mk_target_name logs and other SNMP verbosity

# Configure SNMP manager before starting it
Application.put_env(:snmp, :manager, [
  {:config, [{:dir, '/tmp'}, {:log_type, :none}]},
  {:server, [{:timeout, 30000}, {:verbosity, :silence}]},
  {:net_if, [{:verbosity, :silence}]},
  {:note_store, [{:verbosity, :silence}]},
  {:config, [{:verbosity, :silence}]},
  {:versions, [:v1, :v2, :v3]}
])

# Also set application environment for agent
Application.put_env(:snmp, :agent, [
  {:config, [{:dir, '/tmp'}, {:log_type, :none}]},
  {:verbosity, :silence}
])

# Set SNMP manager logging to none
try do
  :snmpm.set_log_type(:none)
  # Also try setting verbosity levels
  :snmpm.set_verbosity(:silence)
  :snmpm.set_verbosity(:net_if, :silence)
  :snmpm.set_verbosity(:note_store, :silence)
  :snmpm.set_verbosity(:server, :silence)
catch
  # Ignore if manager is not running
  _, _ -> :ok
end

# Set SNMP agent logging to none  
try do
  :snmpa.set_log_type(:none)
  :snmpa.set_verbosity(:silence)
catch
  # Ignore if agent is not running
  _, _ -> :ok
end

# Configure erlang logger to suppress snmp logs completely
:logger.set_module_level(:snmpm, :none)
:logger.set_module_level(:snmpa, :none)
:logger.set_module_level(:snmp, :none)

# Suppress specific SNMP processes
:logger.set_module_level(:snmpm_server, :none)
:logger.set_module_level(:snmpm_config, :none)
:logger.set_module_level(:snmpm_net_if, :none)

# Try to suppress the specific debugging output by redirecting it
# These mk_target_name logs appear to be debug prints, not logger messages
# Configure a logger filter to drop SNMP-related messages
:logger.add_primary_filter(
  :snmp_filter,
  {fn log_event, _filter_config ->
     case log_event do
       %{msg: {:string, msg}} when is_list(msg) ->
         msg_str = List.to_string(msg)

         if String.contains?(msg_str, "snmpm:") or String.contains?(msg_str, "mk_target_name") do
           :stop
         else
           :ignore
         end

       %{msg: {:report, report}} when is_map(report) ->
         if Map.has_key?(report, :snmpm) or
              (Map.has_key?(report, :label) and report.label == :snmpm) do
           :stop
         else
           :ignore
         end

       _ ->
         :ignore
     end
   end, %{}}
)

# Configure ExUnit to exclude noisy/optional tests by default
# Run shell integration tests with: mix test --include shell_integration
# Run slow tests with: mix test --include slow  
# Run Erlang SNMP integration tests with: mix test --include erlang
# Run optional tests with: mix test --include optional
# Run snmp_ex integration tests with: mix test --include snmp_ex_integration

# Note: SNMP manager debug output (snmpm:mk_target_name messages) appears to be
# deeply embedded in the Erlang SNMP library and cannot be easily suppressed.
# These messages are informational only and do not affect test functionality.
# To filter them visually, you can pipe test output through grep:
# mix test 2>&1 | grep -v "snmpm:"

ExUnit.start(exclude: [:shell_integration, :slow, :erlang, :optional, :snmp_ex_integration])
