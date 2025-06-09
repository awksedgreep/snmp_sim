#!/usr/bin/env elixir

# Simple test to verify OID values are being returned
Mix.install([])

# Add the lib directory to the path
Code.prepend_path("lib")

# Load the modules we need
Code.require_file("lib/snmp_sim/device/oid_handler.ex")

# Test the get_device_specific_value function directly
alias SnmpSim.Device.OidHandler

# Test system OIDs
test_oids = [
  [1, 3, 6, 1, 2, 1, 1, 1, 0],  # sysDescr.0
  [1, 3, 6, 1, 2, 1, 1, 2, 0],  # sysObjectID.0
  [1, 3, 6, 1, 2, 1, 1, 3, 0],  # sysUpTime.0
  [1, 3, 6, 1, 2, 1, 2, 1, 0],  # ifNumber.0
]

IO.puts("Testing OID value retrieval...")

for oid_list <- test_oids do
  oid_string = Enum.join(oid_list, ".")
  
  # Test using the correct function signature
  result = OidHandler.get_oid_value(:cable_modem, oid_list)
  
  IO.puts("OID #{oid_string}: #{inspect(result)}")
end
