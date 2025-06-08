# Debug OID lookup issues using WalkParser directly

# Test specific OIDs that should be Counter32: 0
test_oids = [
  "1.3.6.1.2.1.2.2.1.13.1",  # Counter32: 0
  "1.3.6.1.2.1.2.2.1.15.1",  # Counter32: 0
  "1.3.6.1.2.1.2.2.1.19.1"   # Counter32: 0
]

IO.puts("=== Direct OID Lookup Debug ===")

# Parse the walk file directly
walk_file = "priv/walks/cable_modem_oids.walk"
IO.puts("Loading walk file: #{walk_file}")

case SnmpSim.WalkParser.parse_walk_file(walk_file) do
  {:ok, oid_map} ->
    IO.puts("✅ Walk file parsed successfully")
    IO.puts("Total OIDs: #{map_size(oid_map)}")
    
    # Check if our test OIDs are in the parsed data
    IO.puts("\n=== Checking Test OIDs in Parsed Data ===")
    for oid <- test_oids do
      case Map.get(oid_map, oid) do
        nil ->
          IO.puts("❌ #{oid} -> NOT FOUND in parsed data")
        data ->
          IO.puts("✅ #{oid} -> #{inspect(data)}")
      end
    end
    
    # Load the profile into SharedProfiles
    IO.puts("\n=== Loading Profile into SharedProfiles ===")
    case SnmpSim.MIB.SharedProfiles.load_walk_profile(:cable_modem, walk_file) do
      :ok ->
        IO.puts("✅ Profile loaded into SharedProfiles")
        
        # Test OID lookups through SharedProfiles
        IO.puts("\n=== Testing SharedProfiles Lookups ===")
        device_state = %{device_id: "test", uptime: 3600}
        
        for oid <- test_oids do
          case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, oid, device_state) do
            {:ok, {type, value}} ->
              IO.puts("✅ #{oid} -> {#{inspect(type)}, #{inspect(value)}}")
            {:error, reason} ->
              IO.puts("❌ #{oid} -> Error: #{inspect(reason)}")
          end
        end
        
        # Test GETBULK operation
        IO.puts("\n=== Testing GETBULK Operation ===")
        case SnmpSim.MIB.SharedProfiles.get_bulk_oids(:cable_modem, "1.3.6.1.2.1.2.2.1.13", 5) do
          {:ok, bulk_oids} ->
            IO.puts("✅ GETBULK returned #{length(bulk_oids)} OIDs:")
            for {oid, type, value} <- bulk_oids do
              IO.puts("  #{oid} -> {#{inspect(type)}, #{inspect(value)}}")
            end
          {:error, reason} ->
            IO.puts("❌ GETBULK failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to load profile: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to parse walk file: #{inspect(reason)}")
end
