#!/usr/bin/env elixir

IO.puts("=== Device Only Debug ===")

Application.ensure_all_started(:snmp_sim_ex)
Process.sleep(200)

# Test device behavior directly
device_config = %{
  port: 19997,
  device_type: :cable_modem,
  device_id: "debug_device",
  community: "public"
}

{:ok, device_pid} = SNMPSimEx.Device.start_link(device_config)
Process.sleep(100)

test_oid = "1.3.6.1.2.1.1.1.0"
IO.puts("Testing OID: #{test_oid}")

# Test the get_oid_value function directly via GenServer call
result = GenServer.call(device_pid, {:get_oid, test_oid})
IO.puts("Direct get_oid result: #{inspect(result)}")

# Also test through the Device.get wrapper
wrapper_result = SNMPSimEx.Device.get(device_pid, test_oid)
IO.puts("Device.get result: #{inspect(wrapper_result)}")

SNMPSimEx.Device.stop(device_pid)

IO.puts("=== Complete ===")