#!/usr/bin/env elixir

# Debug OID lookup issues in SharedProfiles

# Start the application
Application.start(:logger)
Application.start(:snmp_sim)

# Wait for SharedProfiles to start
Process.sleep(2000)

# Load the walk file manually using the ProfileLoader
IO.puts("=== Loading Walk File ===")
walk_file = "priv/walks/cable_modem_oids.walk"

case SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, walk_file}) do
  {:ok, profile} ->
    IO.puts("✅ Walk file loaded successfully")
    IO.puts("Profile: #{inspect(profile)}")
    
    # Get the OID map
    oid_map = profile.oid_map
    IO.puts("Profile entries: #{map_size(oid_map)}")
    
    # Show first few entries to check format
    IO.puts("\n=== Sample Profile Data ===")
    oid_map
    |> Enum.take(5)
    |> Enum.each(fn {oid, data} ->
      IO.puts("#{oid} -> #{inspect(data)}")
    end)
    
    # Store in SharedProfiles
    IO.puts("\n=== Storing in SharedProfiles ===")
    case SnmpSim.MIB.SharedProfiles.store_profile_data(:cable_modem, oid_map, profile.behaviors) do
      :ok ->
        IO.puts("✅ Profile data stored successfully")
        
        # Test specific OIDs that should be Counter32: 0
        test_oids = [
          "1.3.6.1.2.1.2.2.1.13.1",  # Counter32: 0
          "1.3.6.1.2.1.2.2.1.15.1",  # Counter32: 0
          "1.3.6.1.2.1.2.2.1.19.1"   # Counter32: 0
        ]
        
        IO.puts("\n=== Testing OID Lookups ===")
        device_state = %{device_id: "test", uptime: 3600}
        
        for oid <- test_oids do
          case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, oid, device_state) do
            {:ok, {type, value}} ->
              IO.puts("✅ #{oid} -> {#{inspect(type)}, #{inspect(value)}}")
            {:error, reason} ->
              IO.puts("❌ #{oid} -> Error: #{inspect(reason)}")
              
              # Check if it's in the original profile data
              if Map.has_key?(oid_map, oid) do
                IO.puts("  ✓ Found in original profile data: #{inspect(Map.get(oid_map, oid))}")
              else
                IO.puts("  ✗ NOT found in original profile data")
              end
          end
        end
        
        # Test GETBULK
        IO.puts("\n=== Testing GETBULK ===")
        case SnmpSim.MIB.SharedProfiles.get_bulk_oids(:cable_modem, "1.3.6.1.2.1.2.2.1.13", 3) do
          {:ok, bulk_oids} ->
            IO.puts("✅ GETBULK returned #{length(bulk_oids)} OIDs:")
            for {oid, type, value} <- bulk_oids do
              IO.puts("  #{oid} -> {#{inspect(type)}, #{inspect(value)}}")
            end
          {:error, reason} ->
            IO.puts("❌ GETBULK failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to store profile data: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to load walk file: #{inspect(reason)}")
end
