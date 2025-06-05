# DeviceSimulator Module Missing - SNMP Device Starting Issue

## Problem Summary
The SnmpSim Web UI can successfully create devices but fails when trying to start them due to a missing `DeviceSimulator` module. Device creation works perfectly, but the SNMP simulation backend is not available.

## Error Details
```
** (UndefinedFunctionError) function DeviceSimulator.start_link/1 is undefined (module DeviceSimulator is not available)
```

## Current Working Features
✅ **Phoenix Web UI**: Fully functional with dark mode
✅ **File Upload**: SNMP walk file upload and parsing works
✅ **Walk File Parsing**: Successfully parses ARRIS DOCSIS cable modem walk files
✅ **Device Creation**: Bulk device creation works (creates devices in database)
✅ **Database**: All CRUD operations for devices and walk files work
✅ **Device Detection**: Auto-detects device type (cable_modem) and vendor (ARRIS)

## Failing Feature
❌ **Device Starting**: `DeviceManager.start_device/1` fails because it calls `DeviceSimulator.start_link/1`

## Technical Details

### Error Location
File: `lib/snmp_sim_ex_ui/device_manager.ex:226`
```elixir
DeviceSimulator.start_link(%{
  name: "test3_1", 
  port: 10000, 
  config: %{}, 
  device_type: "cable_modem", 
  ip_address: "127.0.0.1", 
  community_string: "public", 
  walk_data: %{...} # Full parsed walk file data available
})
```

### What's Available
- **Device Data**: Complete device records with walk file associations
- **Walk File Data**: Parsed SNMP walk files with 1414 OIDs from ARRIS cable modem
- **Database Schema**: All device and walk file data properly stored
- **Device Manager**: Handles device lifecycle but needs the simulator backend

### Expected DeviceSimulator Interface
Based on the call pattern, the `DeviceSimulator` module should:

```elixir
defmodule DeviceSimulator do
  def start_link(config) do
    # config contains:
    # - name: device name
    # - port: SNMP port to bind to  
    # - device_type: "cable_modem", "cmts", "switch", etc.
    # - ip_address: IP to bind to (usually "127.0.0.1")
    # - community_string: SNMP community (usually "public")
    # - walk_data: parsed OID data from walk file
    
    # Should start an SNMP agent that responds to queries
    # using the walk_data OIDs and values
  end
end
```

### Sample Walk Data Structure
The parsed walk data contains:
```elixir
%{
  "oids" => [
    %{"oid" => "1.3.6.1.2.1.1.1.0", "type" => "STRING", "value" => "ARRIS DOCSIS 3.1 Touchstone..."},
    %{"oid" => "1.3.6.1.2.1.1.2.0", "type" => "OID", "value" => ".1.3.6.1.4.1.4115.3450.7.0.0.0.0.0"},
    # ... 1414 total OIDs
  ],
  "error_count" => 36,
  "parsed_oids" => 1414,
  "total_lines" => 1450
}
```

## What Needs Implementation

1. **DeviceSimulator Module**: Core SNMP agent simulation
2. **SNMP Agent**: Bind to specified port and respond to SNMP requests
3. **OID Resolution**: Use walk_data to respond to GET/WALK/GETBULK requests
4. **Process Management**: Proper supervision and lifecycle management

## Test Scenario
1. User uploads ARRIS cable modem walk file ✅
2. Walk file gets parsed (1414 OIDs detected) ✅  
3. User creates cable modem device with walk file ✅
4. User clicks "Start" on device ❌ (fails here)
5. Device should bind to port 10000 and respond to SNMP queries ❌

## Current Workaround
Auto-start has been disabled in the web UI to prevent crashes. Devices can be created but manual starting will fail until DeviceSimulator is implemented.

## Dependencies
The project appears to use:
- Elixir/Phoenix for web UI
- Ecto for database
- SQLite for storage
- The SnmpSim core library (which may contain the missing pieces)

## Files to Examine
- `lib/snmp_sim_ex_ui/device_manager.ex` - calls DeviceSimulator
- `deps/snmp_sim_ex/` - may contain the actual SNMP simulation code
- `lib/snmp_sim_ex_ui/` - web UI components (working)

The SnmpSim core library (`deps/snmp_sim_ex/`) likely contains the SNMP simulation functionality, but it may not be properly integrated or the DeviceSimulator module may be missing or misnamed.

## Goal
Get device starting to work so users can:
1. Upload walk files ✅
2. Create simulated devices ✅
3. Start devices to respond to SNMP queries ❌ (fix needed)
4. Test SNMP responses using the built-in test tools ❌ (depends on #3)