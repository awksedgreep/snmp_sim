# Test script to verify the walk_device fix
# Run with: mix run test_walk_fix.exs

# Load the .iex.exs helper functions
Code.require_file(".iex.exs")

port = 9999

IO.puts "🧪 Testing walk_device fix..."
IO.puts "Creating device with walk file..."

# Create device with walk file
case Sim.create_with_walk(port, "cable_modem_oids.walk") do
  {:ok, _pid} ->
    IO.puts "✅ Device created successfully"
    
    # Wait a moment for device to start
    Process.sleep(1000)
    
    # Walk the device - should now show all ~49 OIDs
    IO.puts "\n=== Walking device (should show all ~49 OIDs) ==="
    case Sim.walk_device(port) do
      results when is_list(results) ->
        IO.puts "\n✅ SUCCESS: walk_device returned #{length(results)} OIDs"
        IO.puts "Expected: ~49 OIDs from cable_modem_oids.walk"
        
        if length(results) >= 40 do
          IO.puts "🎉 Fix confirmed! Now showing all OIDs instead of just 20"
        else
          IO.puts "⚠️  Still seems limited - expected more OIDs"
        end
        
      {:error, reason} ->
        IO.puts "❌ Walk failed: #{inspect(reason)}"
    end
    
    # Test with limit parameter
    IO.puts "\n=== Testing with limit parameter (first 5 OIDs) ==="
    Sim.walk_device(port, "1.3.6.1.2.1", 5)
    
  {:error, reason} ->
    IO.puts "❌ Failed to create device: #{inspect(reason)}"
end

IO.puts "\n✅ Test complete!"
