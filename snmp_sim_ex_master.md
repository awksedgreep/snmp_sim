# SNMPSimEx Master Plan - Comprehensive SNMP Simulator for Elixir

A complete implementation plan for building a production-ready, large-scale SNMP simulator with MIB-based realistic behaviors, supporting 10,000+ concurrent devices for comprehensive testing of SNMP polling systems.

## Executive Summary

**Vision**: Create the most realistic and scalable SNMP simulator available, combining Elixir's massive concurrency capabilities with authentic vendor MIB-driven behaviors.

**Key Innovations**:
- **Flexible Profile Sources**: Support walk files, OID dumps, JSON profiles, AND compiled MIBs
- **Progressive Enhancement**: Start simple with walk files, upgrade to MIB-based when ready
- **Lazy Device Creation**: On-demand device instantiation with 10K+ device support
- **Shared OID Trees**: 90% memory reduction through ETS-based shared profiles
- **Realistic Behaviors**: Authentic counter increments, gauge variations, and signal correlations

**Scale Targets**:
- 🎯 **10,000 concurrent devices** (ports 30,000-40,000)
- 🎯 **100K+ requests/second** sustained throughput
- 🎯 **< 1GB total memory** usage with optimizations
- 🎯 **Multiple profile sources** from simple walks to vendor MIBs

## Architecture Overview

```
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│   Profile Sources   │───▶│   Profile Loader     │───▶│   Shared Profiles   │
│   • Walk Files      │    │   • Walk Parser      │    │   (ETS Tables)      │
│   • OID Dumps       │    │   • JSON Parser      │    │                     │
│   • JSON Profiles   │    │   • MIB Compiler     │    │                     │
│   • Vendor MIBs     │    │   (Flexible Input)   │    │                     │
└─────────────────────┘    └──────────────────────┘    └─────────────────────┘
                                     │                            │
                                     ▼                            ▼
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│   Behavior Engine   │    │   Lazy Device Pool   │    │   Value Simulators  │
│   (Pattern Analysis)│    │   (On-Demand Create) │    │   (Dynamic Values)  │
└─────────────────────┘    └──────────────────────┘    └─────────────────────┘
                                     │                            │
                                     ▼                            ▼
                           ┌──────────────────────┐    ┌─────────────────────┐
                           │   Device Instances   │    │   SNMP Responders   │
                           │   (GenServers)        │    │   (UDP Handlers)    │
                           └──────────────────────┘    └─────────────────────┘
```

## Flexible Profile Sources (Progressive Enhancement)

**Design Philosophy**: Start simple and upgrade incrementally. Begin with basic walk files from your actual devices, then add sophisticated behaviors as time permits.

### Profile Source Hierarchy

```elixir
defmodule SNMPSimEx.ProfileLoader do
  @moduledoc """
  Flexible profile loading supporting multiple sources and progressive enhancement.
  Start with simple walk files, upgrade to MIB-based simulation when ready.
  """
  
  def load_profile(device_type, source, opts \\ []) do
    case source do
      # 1. Simple SNMP walk files - START HERE
      {:walk_file, path} ->
        load_from_snmp_walk(path, opts)
        
      # 2. Raw OID dumps (numeric OIDs only)
      {:oid_walk, path} ->
        load_from_oid_walk(path, opts)
        
      # 3. Structured JSON profiles
      {:json_profile, path} ->
        load_from_json_profile(path, opts)
        
      # 4. Manual OID definitions (for testing)
      {:manual, oid_map} ->
        load_from_manual_definitions(oid_map, opts)
        
      # 5. Advanced MIB compilation (future upgrade)
      {:compiled_mib, mib_files} ->
        load_from_compiled_mibs(mib_files, opts)
    end
  end
end
```

### Walk File Support (Both Formats)

#### Named MIB Format (Standard snmpwalk output)
```bash
# Generate with standard snmpwalk command
snmpwalk -v2c -c public cable-modem.example.com 1.3.6.1.2.1 > cable_modem_named.walk

# File format:
SNMPv2-MIB::sysDescr.0 = STRING: "Motorola SB6141 DOCSIS 3.0 Cable Modem"
SNMPv2-MIB::sysObjectID.0 = OID: SNMPv2-SMI::enterprises.4491.2.4.1
SNMPv2-MIB::sysUpTime.0 = Timeticks: (12345600) 1 day, 10:17:36.00
IF-MIB::ifIndex.1 = INTEGER: 1
IF-MIB::ifIndex.2 = INTEGER: 2
IF-MIB::ifInOctets.2 = Counter32: 1234567890
IF-MIB::ifOutOctets.2 = Counter32: 987654321
```

#### Numeric OID Format (Pure OID numbers)
```bash
# Generate with numeric OID option
snmpwalk -v2c -c public -On cable-modem.example.com 1.3.6.1.2.1 > cable_modem_oid.walk

# File format:
.1.3.6.1.2.1.1.1.0 = STRING: "Motorola SB6141 DOCSIS 3.0 Cable Modem"
.1.3.6.1.2.1.1.2.0 = OID: .1.3.6.1.4.1.4491.2.4.1
.1.3.6.1.2.1.1.3.0 = Timeticks: (12345600) 1 day, 10:17:36.00
.1.3.6.1.2.1.2.2.1.1.1 = INTEGER: 1
.1.3.6.1.2.1.2.2.1.1.2 = INTEGER: 2  
.1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890
.1.3.6.1.2.1.2.2.1.16.2 = Counter32: 987654321
```

### Profile Parsing Implementation

```elixir
defmodule SNMPSimEx.WalkParser do
  @moduledoc """
  Parse both named MIB and numeric OID walk file formats.
  Handle different snmpwalk output variations automatically.
  """
  
  def parse_walk_file(file_path) do
    file_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&parse_walk_line/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end
  
  defp parse_walk_line(line) do
    line = String.trim(line)
    
    cond do
      # Named MIB format: "IF-MIB::ifInOctets.2 = Counter32: 1234567890"
      String.contains?(line, "::") ->
        parse_named_mib_line(line)
        
      # Numeric OID format: ".1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890"
      String.starts_with?(line, ".") ->
        parse_numeric_oid_line(line)
        
      # Skip comments and empty lines
      String.starts_with?(line, "#") or line == "" ->
        nil
        
      # Try generic parsing for other formats
      true ->
        parse_generic_line(line)
    end
  end
  
  defp parse_named_mib_line(line) do
    # Handle: "IF-MIB::ifInOctets.2 = Counter32: 1234567890"
    case Regex.run(~r/^(.+?)::(.+?)\s*=\s*(\w+):\s*(.+)$/, line) do
      [_, mib_name, oid_suffix, data_type, value] ->
        # Convert MIB name to numeric OID (requires MIB knowledge or lookup table)
        numeric_oid = resolve_mib_name(mib_name, oid_suffix)
        {numeric_oid, %{type: data_type, value: clean_value(value), mib_name: "#{mib_name}::#{oid_suffix}"}}
      _ ->
        nil
    end
  end
  
  defp parse_numeric_oid_line(line) do
    # Handle: ".1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890"
    case Regex.run(~r/^(\.[\d\.]+)\s*=\s*(\w+):\s*(.+)$/, line) do
      [_, oid, data_type, value] ->
        clean_oid = String.trim_leading(oid, ".")
        {clean_oid, %{type: data_type, value: clean_value(value)}}
      _ ->
        nil
    end
  end
  
  defp parse_generic_line(line) do
    # Handle other potential formats
    case Regex.run(~r/^(.+?)\s*=\s*(\w+):\s*(.+)$/, line) do
      [_, oid_part, data_type, value] ->
        oid = normalize_oid(oid_part)
        {oid, %{type: data_type, value: clean_value(value)}}
      _ ->
        nil
    end
  end
  
  defp clean_value(value) do
    value
    |> String.trim()
    |> String.trim("\"")  # Remove quotes from strings
    |> parse_typed_value()
  end
  
  defp parse_typed_value(value) do
    cond do
      # Handle integers
      Regex.match?(~r/^\d+$/, value) ->
        String.to_integer(value)
        
      # Handle hex strings: "00 1A 2B 3C 4D 5E"
      Regex.match?(~r/^[0-9A-F\s]+$/i, value) and String.contains?(value, " ") ->
        value
        
      # Handle quoted strings
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2)
        
      # Default to string
      true ->
        value
    end
  end
  
  # Basic MIB name resolution (can be extended)
  defp resolve_mib_name(mib_name, oid_suffix) do
    base_oids = %{
      "SNMPv2-MIB" => "1.3.6.1.2.1.1",
      "IF-MIB" => "1.3.6.1.2.1.2",
      "IP-MIB" => "1.3.6.1.2.1.4",
      "TCP-MIB" => "1.3.6.1.2.1.6",
      "UDP-MIB" => "1.3.6.1.2.1.7"
    }
    
    case Map.get(base_oids, mib_name) do
      nil -> 
        # Unknown MIB, use suffix as-is (may need manual mapping)
        oid_suffix
      base_oid ->
        "#{base_oid}.#{oid_suffix}"
    end
  end
end
```

### Progressive Enhancement Path

#### Level 1: Static Walk Files (Start Here)
```elixir
# Basic usage - just get devices responding
cable_modem_profile = SNMPSimEx.ProfileLoader.load_profile(
  :cable_modem,
  {:walk_file, "priv/walks/cable_modem.walk"}
)

{:ok, device} = SNMPSimEx.start_device(cable_modem_profile, port: 9001)

# Test basic functionality
response = :snmp.sync_get("127.0.0.1", 9001, "public", ["1.3.6.1.2.1.1.1.0"])
# Returns: "Motorola SB6141 DOCSIS 3.0 Cable Modem"
```

#### Level 2: Add Basic Behaviors
```elixir
# Add simple counter increments and gauge variations
cable_modem_profile = SNMPSimEx.ProfileLoader.load_profile(
  :cable_modem,
  {:walk_file, "priv/walks/cable_modem.walk"},
  behaviors: [
    {:increment_counters, rate: 1000},  # Increment by ~1000/sec
    {:vary_gauges, variance: 0.1},      # ±10% variation
    {:increment_uptime}                 # sysUpTime increases
  ]
)
```

#### Level 3: Realistic Time Patterns
```elixir
# Add daily traffic patterns and correlations
cable_modem_profile = SNMPSimEx.ProfileLoader.load_profile(
  :cable_modem,
  {:walk_file, "priv/walks/cable_modem.walk"},
  behaviors: [
    {:traffic_patterns, daily_cycle: true},
    {:signal_correlation, snr_vs_utilization: true},
    {:realistic_errors, error_rate: 0.01}
  ]
)
```

#### Level 4: MIB-Based Simulation (Future)
```elixir
# Upgrade to full MIB compilation when ready
cable_modem_profile = SNMPSimEx.ProfileLoader.load_profile(
  :cable_modem,
  {:compiled_mib, ["DOCS-CABLE-DEVICE-MIB", "IF-MIB"]}
)
```

### Mixed Profile Support

```elixir
# Support multiple devices with different profile sources
device_configs = [
  # Cable modems from walk files
  {:cable_modem, {:walk_file, "priv/walks/cm_walk.txt"}, count: 1000},
  
  # Switches from OID dumps  
  {:switch, {:oid_walk, "priv/walks/switch_oids.txt"}, count: 50},
  
  # CMTS from JSON profiles
  {:cmts, {:json_profile, "priv/profiles/cmts.json"}, count: 5},
  
  # Test routers from manual definitions
  {:router, {:manual, %{"1.3.6.1.2.1.1.1.0" => "Test Router"}}, count: 10}
]

{:ok, devices} = SNMPSimEx.start_device_population(device_configs, 
  port_range: 30_000..39_999
)
```

### File Format Examples

#### cable_modem.walk (Named MIB format)
```
SNMPv2-MIB::sysDescr.0 = STRING: "Motorola SB6141 DOCSIS 3.0 Cable Modem"
SNMPv2-MIB::sysObjectID.0 = OID: SNMPv2-SMI::enterprises.4491.2.4.1
SNMPv2-MIB::sysUpTime.0 = Timeticks: (12345600) 1 day, 10:17:36.00
SNMPv2-MIB::sysName.0 = STRING: "CM-001A2B3C4D5E"
IF-MIB::ifNumber.0 = INTEGER: 2
IF-MIB::ifIndex.1 = INTEGER: 1
IF-MIB::ifIndex.2 = INTEGER: 2
IF-MIB::ifDescr.1 = STRING: "cable-modem0"
IF-MIB::ifDescr.2 = STRING: "docsis-mac"
IF-MIB::ifType.1 = INTEGER: ethernetCsmacd(6)
IF-MIB::ifType.2 = INTEGER: docsCableMaclayer(127)
IF-MIB::ifMtu.1 = INTEGER: 1500
IF-MIB::ifMtu.2 = INTEGER: 1518
IF-MIB::ifSpeed.1 = Gauge32: 1000000000
IF-MIB::ifSpeed.2 = Gauge32: 38000000
IF-MIB::ifInOctets.1 = Counter32: 1234567890
IF-MIB::ifOutOctets.1 = Counter32: 987654321
IF-MIB::ifInOctets.2 = Counter32: 456789012
IF-MIB::ifOutOctets.2 = Counter32: 234567890
```

#### cable_modem_oids.walk (Numeric OID format)
```
.1.3.6.1.2.1.1.1.0 = STRING: "Motorola SB6141 DOCSIS 3.0 Cable Modem"
.1.3.6.1.2.1.1.2.0 = OID: .1.3.6.1.4.1.4491.2.4.1
.1.3.6.1.2.1.1.3.0 = Timeticks: (12345600) 1 day, 10:17:36.00
.1.3.6.1.2.1.1.5.0 = STRING: "CM-001A2B3C4D5E"
.1.3.6.1.2.1.2.1.0 = INTEGER: 2
.1.3.6.1.2.1.2.2.1.1.1 = INTEGER: 1
.1.3.6.1.2.1.2.2.1.1.2 = INTEGER: 2
.1.3.6.1.2.1.2.2.1.2.1 = STRING: "cable-modem0"
.1.3.6.1.2.1.2.2.1.2.2 = STRING: "docsis-mac"
.1.3.6.1.2.1.2.2.1.3.1 = INTEGER: 6
.1.3.6.1.2.1.2.2.1.3.2 = INTEGER: 127
.1.3.6.1.2.1.2.2.1.4.1 = INTEGER: 1500
.1.3.6.1.2.1.2.2.1.4.2 = INTEGER: 1518
.1.3.6.1.2.1.2.2.1.5.1 = Gauge32: 1000000000
.1.3.6.1.2.1.2.2.1.5.2 = Gauge32: 38000000
.1.3.6.1.2.1.2.2.1.10.1 = Counter32: 1234567890
.1.3.6.1.2.1.2.2.1.16.1 = Counter32: 987654321
.1.3.6.1.2.1.2.2.1.10.2 = Counter32: 456789012
.1.3.6.1.2.1.2.2.1.16.2 = Counter32: 234567890
```

## Multi-Phase Implementation Plan

### Phase 1: Core SNMP Protocol Engine + Walk File Support (Week 1)
**Goal**: Foundation SNMP PDU handling with walk file profile loading

#### Core Components
```elixir
# SNMP PDU Processing
defmodule SNMPSimEx.PDU do
  @moduledoc """
  Complete SNMP PDU encoding/decoding for v1 and v2c protocols.
  Handles GET, GETNEXT, GETBULK, and SET operations.
  """
  
  def decode(binary_packet) do
    # Parse BER/DER encoded SNMP packets
    # Extract version, community, PDU type, variable bindings
  end
  
  def encode(response_pdu) do
    # Create properly formatted SNMP response packets
    # Handle different data types (INTEGER, OCTET STRING, Counter32, etc.)
  end
  
  def validate_community(packet, expected_community) do
    # Community string validation for v1/v2c
  end
end

# UDP Server Management
defmodule SNMPSimEx.Server do
  @moduledoc """
  High-performance UDP server for SNMP request handling.
  Supports concurrent packet processing with minimal latency.
  """
  use GenServer
  
  def start_link(port, opts \\ []) do
    # Start UDP server on specified port
    # Configure socket options for high throughput
  end
  
  def handle_info({:udp, socket, ip, port, packet}, state) do
    # Process incoming SNMP packets
    # Route to appropriate device handler
  end
end
```

#### Success Criteria
- [ ] Parse SNMPv1 and v2c GET/GETNEXT requests
- [ ] Encode proper SNMP responses with all data types  
- [ ] **Parse both named MIB and numeric OID walk files**
- [ ] **Load walk files into device profiles automatically**
- [ ] **Start devices responding with static values from walks**
- [ ] Community string validation and error handling
- [ ] Basic error responses (noSuchName, genErr, tooBig)
- [ ] UDP packet handling with proper socket management

#### Test Coverage (30 tests)
```elixir
describe "Walk File Parsing" do
  test "parses named MIB format walk files (IF-MIB::ifInOctets.2)"
  test "parses numeric OID format walk files (.1.3.6.1.2.1.2.2.1.10.2)"
  test "handles mixed walk file formats in same file"
  test "extracts data types correctly (Counter32, STRING, INTEGER)"
  test "cleans quoted strings and hex values"
  test "resolves basic MIB names to numeric OIDs"
  test "skips comments and empty lines"
end

describe "SNMP PDU Processing" do
  test "decodes SNMPv1 GET request with multiple OIDs"
  test "decodes SNMPv2c GETNEXT request" 
  test "handles malformed PDU gracefully"
  test "validates community strings correctly"
  test "encodes responses with proper data types"
  test "handles oversized requests with tooBig error"
end

describe "Profile Loading" do
  test "loads walk file into device profile"
  test "starts device with walk-based profile"
  test "responds to SNMP GET with walk file values"
  test "handles missing OIDs with noSuchName"
end

describe "UDP Server" do
  test "handles concurrent requests without blocking"
  test "processes 1000+ requests per second"
  test "manages socket resources efficiently"
end
```

### Phase 2: Enhanced Behaviors & Optional MIB Compilation (Week 2)
**Goal**: Add realistic behaviors to walk files + optional MIB compiler integration

#### MIB Integration Components
```elixir
# Erlang MIB Compiler Integration
defmodule SNMPSimEx.MIBCompiler do
  @moduledoc """
  Leverage Erlang's battle-tested :snmpc module for MIB compilation.
  Extract OID definitions, data types, and constraints from vendor MIBs.
  """
  
  def compile_mib_directory(mib_dir) do
    # Use :snmpc.compile for robust MIB processing
    # Extract object definitions, tables, and types
    # Generate Elixir-friendly data structures
  end
  
  def load_compiled_mib(bin_file) do
    # Load .bin files from Erlang MIB compiler
    # Extract OID tree structure and metadata
  end
end

# Behavior Analysis Engine
defmodule SNMPSimEx.BehaviorAnalyzer do
  @moduledoc """
  Automatically determine realistic behaviors from MIB object definitions.
  Analyze object names, descriptions, and types to infer simulation patterns.
  """
  
  def analyze_object_behavior(oid_info) do
    # Pattern matching on object names/descriptions
    # Determine counter rates, gauge variations, enum values
    # Create behavior specifications for value simulation
  end
  
  defp analyze_counter_behavior(oid_info) do
    # Traffic counters: ifInOctets, ifOutOctets
    # Error counters: ifInErrors, ifOutErrors  
    # Protocol counters: tcpActiveOpens, udpInDatagrams
  end
  
  defp analyze_gauge_behavior(oid_info) do
    # Utilization gauges: CPU, memory, interface utilization
    # Signal quality: DOCSIS power levels, SNR
    # Environmental: temperature, voltage
  end
end

# Shared Profile Management
defmodule SNMPSimEx.SharedProfiles do
  @moduledoc """
  Memory-efficient shared OID profiles using ETS tables.
  Reduces memory from 1GB to ~10MB for 10K devices.
  """
  
  def init_profiles do
    # Create ETS tables for each device type
    :ets.new(:cable_modem_profile, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(:cmts_profile, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(:switch_profile, [:set, :public, :named_table, {:read_concurrency, true}])
  end
  
  def load_mib_profile(device_type, mib_files) do
    # Compile MIBs and populate ETS tables
    # Store behavior patterns and value generators
  end
  
  def get_oid_value(device_type, oid, device_state) do
    # Fast ETS lookup with behavior application
    # Apply device-specific state to shared patterns
  end
end
```

#### Success Criteria
- [x] Successfully compile standard MIBs (IF-MIB, IP-MIB, DOCS-*)
- [x] Extract 500+ OID definitions per device type
- [x] Automatically categorize 90%+ of objects by behavior type
- [x] Generate shared profiles with < 10MB memory footprint
- [x] Achieve < 1ms OID lookup times from ETS tables

#### Test Coverage (20 tests)
```elixir
describe "MIB Compilation" do
  test "compiles DOCS-CABLE-DEVICE-MIB successfully"
  test "extracts interface table structure from IF-MIB"
  test "handles MIB dependencies correctly"
  test "generates complete OID tree"
end

describe "Behavior Analysis" do
  test "identifies traffic counters from object names"
  test "determines gauge ranges from MIB constraints"
  test "creates realistic increment patterns"
  test "handles vendor-specific extensions"
end
```

### Phase 3: OID Tree Management & GETBULK (Week 3)
**Goal**: Efficient OID storage with GETNEXT traversal and GETBULK support

#### OID Tree Components
```elixir
# High-Performance OID Tree
defmodule SNMPSimEx.OIDTree do
  @moduledoc """
  Optimized OID tree for fast lookups and lexicographic traversal.
  Supports GETNEXT operations and GETBULK bulk retrieval.
  """
  
  def new() do
    # Create efficient tree structure (possibly radix tree)
    # Optimize for sequential access patterns
  end
  
  def insert(tree, oid_string, value, behavior_info) do
    # Insert OID with associated behavior metadata
    # Maintain lexicographic ordering for GETNEXT
  end
  
  def get_next(tree, oid_string) do
    # Efficient GETNEXT traversal
    # Handle end-of-table conditions
  end
  
  def bulk_walk(tree, start_oid, max_repetitions, non_repeaters) do
    # Implement GETBULK algorithm
    # Respect UDP packet size limits
    # Optimize for bulk operations
  end
end

# GETBULK Operation Handler
defmodule SNMPSimEx.BulkOperations do
  @moduledoc """
  Efficient GETBULK implementation for SNMPv2c.
  Handles non-repeaters, max-repetitions, and response size management.
  """
  
  def handle_bulk_request(oid_tree, non_repeaters, max_repetitions, varbinds) do
    # Process non-repeating OIDs once
    # Process repeating OIDs up to max_repetitions
    # Build response within UDP size limits
  end
  
  def optimize_bulk_response(results, max_size \\ 1400) do
    # Estimate response size
    # Truncate if needed to fit in UDP packet
    # Return tooBig error if necessary
  end
end
```

#### Success Criteria
- [x] Support 10,000+ OIDs per device type in tree
- [x] GETNEXT traversal in correct lexicographic order
- [x] GETBULK operations with proper non-repeater handling
- [x] Response size management for UDP packet limits
- [x] Bulk operations 5x faster than individual GETs

#### Test Coverage (25 tests)
```elixir
describe "OID Tree Operations" do
  test "maintains lexicographic order for GETNEXT"
  test "handles large OID trees (10K+ entries)"
  test "performs fast lookups (< 1ms for 10K OIDs)"
  test "manages memory efficiently"
end

describe "GETBULK Operations" do
  test "respects non-repeaters parameter"
  test "limits repetitions correctly"
  test "handles response size limits"
  test "returns tooBig when appropriate"
  test "processes interface tables efficiently"
end
```

### Phase 4: Lazy Device Pool & Multi-Device Support (Week 4)
**Goal**: On-demand device creation supporting 10,000+ concurrent devices

#### Lazy Device Management
```elixir
# Lazy Device Pool Manager
defmodule SNMPSimEx.LazyDevicePool do
  @moduledoc """
  On-demand device creation and lifecycle management.
  Supports 10K+ devices with minimal memory footprint.
  """
  use GenServer
  
  defstruct [
    :active_devices,      # Map: port -> device_pid
    :device_configs,      # Map: port -> device_config
    :last_access,         # Map: port -> timestamp
    :cleanup_timer,       # Periodic cleanup timer
    :port_assignments     # Device type port ranges
  ]
  
  def get_or_create_device(port) do
    # Create device on first access
    # Update access tracking
    # Return existing device if available
  end
  
  def handle_info(:cleanup_idle_devices, state) do
    # Cleanup devices idle for 30+ minutes
    # Preserve memory and file descriptors
    # Schedule next cleanup cycle
  end
end

# Device Type Distribution
defmodule SNMPSimEx.DeviceDistribution do
  @moduledoc """
  Realistic device type distribution across port ranges.
  Supports mixed device populations for authentic testing.
  """
  
  def device_type_ranges do
    %{
      cable_modem: 30_000..37_999,  # 8,000 cable modems
      mta: 38_000..39_499,          # 1,500 MTAs
      switch: 39_500..39_899,       # 400 switches
      router: 39_900..39_949,       # 50 routers
      cmts: 39_950..39_974,         # 25 CMTS devices
      server: 39_975..39_999        # 25 servers
    }
  end
  
  def determine_device_type(port) do
    # Map port to device type based on ranges
    # Support mixed device populations
  end
end

# Lightweight Device Implementation
defmodule SNMPSimEx.Device do
  @moduledoc """
  Minimal memory footprint device simulation.
  Uses shared profiles and device-specific state only.
  """
  use GenServer
  
  defstruct [
    :device_id, :port, :device_type,
    :mac_address, :uptime_start,
    :counters, :gauges, :status_vars
  ]
  
  def start_link(opts) do
    # Initialize device with minimal state
    # Open UDP socket for SNMP communication
    # Link to shared profile data
  end
  
  def handle_info({:udp, socket, ip, port, packet}, state) do
    # Process SNMP requests
    # Use shared profiles for OID resolution
    # Apply device-specific behaviors
  end
end
```

#### Success Criteria
- [x] Support 10,000 concurrent devices on unique ports
- [x] Lazy creation with < 10ms device startup time
- [x] Memory usage < 1GB total for 10K devices
- [x] Automatic cleanup of idle devices
- [x] Mixed device type populations
- [x] No port conflicts or resource leaks

#### Test Coverage (30 tests)
```elixir
describe "Lazy Device Pool" do
  test "creates devices on first access"
  test "reuses existing devices efficiently"
  test "cleans up idle devices after timeout"
  test "handles 10K concurrent devices"
  test "manages memory usage effectively"
end

describe "Device Distribution" do
  test "assigns device types by port ranges"
  test "supports mixed device populations"
  test "handles device type determination"
end

describe "Device Lifecycle" do
  test "starts devices with minimal memory"
  test "processes SNMP requests correctly"
  test "applies device-specific behaviors"
  test "handles device shutdown gracefully"
end
```

### Phase 5: Realistic Value Simulation (Week 5)
**Goal**: Authentic counter increments, gauge variations, and time-based behaviors

#### Value Simulation Engine
```elixir
# Dynamic Value Generation
defmodule SNMPSimEx.ValueSimulator do
  @moduledoc """
  Generate realistic values based on MIB-derived behavior patterns.
  Supports counters, gauges, enums, and correlated metrics.
  """
  
  def simulate_value(oid_info, device_state, simulation_time) do
    case oid_info.behavior do
      {:traffic_counter, config} ->
        simulate_traffic_counter(oid_info.oid, device_state, config)
        
      {:signal_gauge, config} ->
        simulate_signal_gauge(oid_info.oid, device_state, config)
        
      {:utilization_gauge, config} ->
        simulate_utilization_gauge(oid_info.oid, device_state, config)
        
      {:enum, possible_values} ->
        simulate_enum_value(oid_info.oid, device_state, possible_values)
        
      {:correlated_gauge, config} ->
        apply_metric_correlations(oid_info.oid, device_state, config)
    end
  end
  
  defp simulate_traffic_counter(oid, device_state, config) do
    # Calculate realistic traffic increments
    # Apply time-of-day patterns
    # Add burst behavior and jitter
    # Handle 32-bit vs 64-bit counter wrapping
  end
  
  defp simulate_signal_gauge(oid, device_state, config) do
    # DOCSIS signal quality simulation
    # Environmental factors (weather, interference)
    # Correlation with utilization levels
    # Realistic variance within constraints
  end
  
  defp simulate_utilization_gauge(oid, device_state, config) do
    # Daily utilization patterns
    # Business hours vs evening peaks
    # Weekend vs weekday variations
    # Random fluctuations within bounds
  end
end

# Time-Based Pattern Engine
defmodule SNMPSimEx.TimePatterns do
  @moduledoc """
  Realistic time-based variations for network metrics.
  Implements daily, weekly, and seasonal patterns.
  """
  
  def get_daily_utilization_pattern(time) do
    # 0-5 AM: Low usage (30%)
    # 6-8 AM: Morning ramp (70%)
    # 9-17 PM: Business hours (90-100%)
    # 18-20 PM: Evening peak (120%)
    # 21-23 PM: Late evening (80%)
  end
  
  def apply_seasonal_variation(base_value, time) do
    # Weather-related signal variations
    # Holiday traffic patterns
    # Maintenance windows
  end
  
  def get_interface_traffic_rate(interface_type, time) do
    # Ethernet gigabit: 1KB/s to 125MB/s
    # DOCSIS downstream: 10KB/s to 193MB/s
    # DOCSIS upstream: 1KB/s to 50MB/s
  end
end

# Metric Correlation Engine
defmodule SNMPSimEx.CorrelationEngine do
  @moduledoc """
  Implement realistic correlations between different metrics.
  Signal quality degrades with higher utilization, etc.
  """
  
  def apply_correlations(primary_oid, value, device_state, correlations) do
    # Inverse correlation: SNR decreases with utilization
    # Positive correlation: Errors increase with utilization
    # Environmental correlation: Power levels vary together
  end
end
```

#### Success Criteria
- [x] Realistic counter increment patterns by interface type
- [x] Signal quality variations with environmental factors
- [x] Daily/weekly utilization patterns
- [x] Metric correlations (SNR vs utilization)
- [x] Proper counter wrapping for 32-bit/64-bit
- [x] Configurable jitter and variance levels

#### Test Coverage (25 tests)
```elixir
describe "Value Simulation" do
  test "generates realistic traffic counter increments"
  test "applies daily utilization patterns"
  test "handles counter wrapping correctly"
  test "correlates signal quality with utilization"
  test "maintains gauge values within constraints"
end

describe "Time Patterns" do
  test "implements daily traffic patterns"
  test "applies seasonal variations"
  test "handles weekend vs weekday differences"
end
```

### Phase 6: Error Injection & Testing Features (Week 6)
**Goal**: Comprehensive error simulation and testing capabilities

#### Error Injection System
```elixir
# Error Injection Engine
defmodule SNMPSimEx.ErrorInjector do
  @moduledoc """
  Inject realistic error conditions for comprehensive testing.
  Supports timeouts, packet loss, malformed responses, and device failures.
  """
  
  def inject_timeout(device, probability, duration_ms) do
    # Simulate network timeouts
    # Configure timeout probability and duration
    # Track timeout statistics
  end
  
  def inject_packet_loss(device, loss_rate) do
    # Simulate network packet loss
    # Progressive degradation scenarios
    # Burst loss patterns
  end
  
  def inject_snmp_error(device, error_type, oid_patterns) do
    # Generate SNMP protocol errors
    # noSuchName, genErr, tooBig responses
    # Target specific OID patterns
  end
  
  def inject_malformed_response(device, corruption_type) do
    # Corrupt SNMP response packets
    # Test poller error handling
    # Simulate buggy device firmware
  end
  
  def simulate_device_reboot(device, reboot_duration) do
    # Simulate device restart
    # Reset counters and uptime
    # Temporary unavailability
  end
end

# Test Scenario Builder
defmodule SNMPSimEx.TestScenarios do
  @moduledoc """
  Pre-built test scenarios for common network conditions.
  Simplify complex error injection patterns.
  """
  
  def network_outage_scenario(devices, duration_seconds) do
    # Simulate complete network outage
    # All devices become unreachable
    # Test poller recovery mechanisms
  end
  
  def signal_degradation_scenario(device, degradation_config) do
    # Simulate weather-related signal issues
    # Gradual SNR degradation
    # Power level fluctuations
  end
  
  def high_load_scenario(devices, utilization_percent) do
    # Simulate network congestion
    # Increased error rates
    # Higher response times
  end
  
  def device_flapping_scenario(device, flap_interval) do
    # Simulate intermittent connectivity
    # Periodic device availability
    # Test error recovery logic
  end
end
```

#### Success Criteria
- [x] Configurable error injection (timeouts, packet loss, errors)
- [x] Realistic network condition simulation
- [x] Test scenario templates for common failures
- [x] ExUnit integration for seamless testing
- [x] Error injection without affecting other devices
- [x] Statistical tracking of injected errors

#### Test Coverage (20 tests)
```elixir
describe "Error Injection" do
  test "injects timeouts with specified probability"
  test "simulates packet loss accurately"
  test "generates proper SNMP error responses"
  test "handles malformed packet injection"
end

describe "Test Scenarios" do
  test "simulates complete network outage"
  test "creates realistic signal degradation"
  test "handles device reboot scenarios"
  test "supports progressive failure patterns"
end
```

### Phase 7: Performance Optimization & Production Features (Week 7)
**Goal**: Optimize for 10K+ devices with monitoring and resource management

#### Performance Optimization
```elixir
# Resource Management
defmodule SNMPSimEx.ResourceManager do
  @moduledoc """
  Manage system resources for large-scale simulation.
  Monitor memory usage, file descriptors, and network buffers.
  """
  
  def set_device_limits(max_devices, max_memory_mb) do
    # Enforce device count and memory limits
    # Prevent system resource exhaustion
  end
  
  def monitor_resource_usage() do
    # Track memory usage per device type
    # Monitor file descriptor consumption
    # Network buffer utilization
  end
  
  def optimize_port_allocation(port_range) do
    # Efficient port assignment
    # Minimize fragmentation
    # Support hot-swapping
  end
  
  def cleanup_idle_devices(idle_threshold_minutes) do
    # Automatic cleanup of unused devices
    # Preserve system resources
    # Maintain performance under load
  end
end

# Performance Monitoring
defmodule SNMPSimEx.Performance do
  @moduledoc """
  Real-time performance monitoring and optimization.
  Track throughput, latency, and resource utilization.
  """
  
  def get_performance_stats() do
    # Request throughput (req/sec)
    # Average response latency
    # Memory usage breakdown
    # Device distribution statistics
  end
  
  def enable_response_caching(device, ttl_seconds) do
    # Cache frequently accessed OIDs
    # Reduce computation overhead
    # Improve response times
  end
  
  def optimize_oid_tree(tree) do
    # Tree balancing and optimization
    # Memory layout improvements
    # Access pattern optimization
  end
end

# Load Testing Framework
defmodule SNMPSimEx.LoadTesting do
  @moduledoc """
  Comprehensive load testing and benchmarking.
  Validate performance under realistic conditions.
  """
  
  def run_scaling_test(device_scales) do
    # Test 100, 1K, 5K, 10K devices
    # Measure startup time, memory usage
    # Track performance degradation
  end
  
  def benchmark_throughput(num_devices, duration) do
    # Sustained throughput testing
    # Concurrent request processing
    # Latency distribution analysis
  end
  
  def memory_stress_test(target_devices) do
    # Memory usage validation
    # Leak detection
    # Resource cleanup verification
  end
end
```

#### Success Criteria
- [x] Support 10,000+ concurrent devices reliably
- [x] Sustain 100K+ requests/second throughput
- [x] Memory usage < 1GB for 10K devices
- [x] Response times < 5ms for cached lookups
- [x] 24+ hour stability under load
- [x] Automatic resource management and cleanup

#### Test Coverage (15 tests)
```elixir
describe "Performance" do
  test "handles 10K devices concurrently"
  test "sustains 100K+ req/sec throughput"
  test "maintains memory usage under 1GB"
  test "achieves sub-5ms response times"
end

describe "Resource Management" do
  test "enforces device and memory limits"
  test "cleans up idle devices automatically"
  test "optimizes port allocation"
  test "monitors resource usage accurately"
end
```

### Phase 8: Integration & Production Readiness (Week 8)
**Goal**: Complete ExUnit integration and production deployment

#### Test Integration
```elixir
# ExUnit Test Helpers
defmodule SNMPSimEx.TestHelpers do
  @moduledoc """
  Seamless ExUnit integration for SNMP Poller testing.
  Simplify test setup and cleanup for complex scenarios.
  """
  
  def setup_test_devices(device_configs) do
    # Start test devices with specified configurations
    # Wait for devices to be ready
    # Return device references for testing
  end
  
  def cleanup_test_devices() do
    # Clean shutdown of all test devices
    # Verify resource cleanup
    # Reset shared state
  end
  
  def assert_snmp_response(device, oid, expected_value, timeout \\ 5000) do
    # Perform SNMP GET and assert response
    # Handle different value types
    # Provide detailed failure messages
  end
  
  def wait_for_device_ready(device, timeout \\ 5000) do
    # Wait for device to respond to SNMP
    # Verify basic connectivity
    # Timeout with clear error message
  end
  
  def simulate_network_conditions(devices, conditions) do
    # Apply network conditions to device group
    # Support complex multi-device scenarios
    # Easy integration with test cases
  end
end

# Configuration Management
defmodule SNMPSimEx.Config do
  @moduledoc """
  Environment-specific configuration management.
  Support development, testing, and production scenarios.
  """
  
  def load_test_config() do
    # Minimal device count for fast tests
    # Reduced timeouts and intervals
    # Enhanced logging for debugging
  end
  
  def load_development_config() do
    # Moderate device count (1K devices)
    # Interactive debugging features
    # Performance monitoring enabled
  end
  
  def load_production_simulation_config() do
    # Full-scale device counts (10K+)
    # Production-realistic timing
    # Comprehensive monitoring
  end
end
```

#### Documentation & Deployment
```elixir
# Deployment Manager
defmodule SNMPSimEx.Deployment do
  @moduledoc """
  Production deployment and management tools.
  Handle large-scale simulator deployment.
  """
  
  def deploy_device_population(device_mix, port_range) do
    # Deploy mixed device population
    # Validate port assignments
    # Monitor deployment progress
  end
  
  def health_check() do
    # Comprehensive system health validation
    # Device responsiveness checking
    # Resource utilization monitoring
  end
  
  def rolling_restart(device_groups) do
    # Restart devices in groups
    # Minimize service disruption
    # Validate successful restart
  end
end
```

#### Success Criteria
- [x] Complete ExUnit test helper integration
- [x] Configuration management for all environments
- [x] Comprehensive API documentation with examples
- [x] Production deployment automation
- [x] Health monitoring and alerting
- [x] Performance benchmarks and regression testing

#### Test Coverage (20 tests)
```elixir
describe "Test Integration" do
  test "sets up test devices quickly"
  test "cleans up resources completely"
  test "provides useful assertion helpers"
  test "handles test failures gracefully"
end

describe "Configuration" do
  test "loads environment-specific configs"
  test "validates configuration parameters"
  test "handles missing configuration gracefully"
end

describe "Production Features" do
  test "deploys large device populations"
  test "performs comprehensive health checks"
  test "supports rolling restarts"
end
```

## File Structure

```
apps/snmp_poller/lib/snmp_sim_ex/
├── application.ex                # OTP application entry point
├── supervisor.ex                 # Main supervision tree
│
├── core/
│   ├── pdu.ex                   # SNMP PDU encoding/decoding
│   ├── server.ex                # UDP server management
│   ├── oid_tree.ex              # OID tree data structure
│   ├── bulk_operations.ex       # GETBULK implementation
│   └── data_types.ex            # SNMP data type handling
│
├── mib/
│   ├── compiler.ex              # Erlang MIB compiler integration
│   ├── behavior_analyzer.ex     # Behavior pattern analysis
│   ├── profile_generator.ex     # Device profile generation
│   └── shared_profiles.ex       # ETS-based shared profiles
│
├── devices/
│   ├── lazy_pool.ex             # Lazy device creation pool
│   ├── device.ex                # Individual device GenServer
│   ├── distribution.ex          # Device type distribution
│   └── state.ex                 # Device state management
│
├── simulation/
│   ├── value_simulator.ex       # Dynamic value generation
│   ├── time_patterns.ex         # Time-based behavior patterns
│   ├── correlation_engine.ex    # Metric correlation logic
│   └── counter_manager.ex       # Counter state management
│
├── testing/
│   ├── error_injector.ex        # Error condition injection
│   ├── test_scenarios.ex        # Pre-built test scenarios
│   ├── test_helpers.ex          # ExUnit integration helpers
│   └── load_testing.ex          # Performance testing framework
│
├── performance/
│   ├── resource_manager.ex      # System resource management
│   ├── performance_monitor.ex   # Real-time monitoring
│   ├── telemetry.ex             # Telemetry integration
│   └── benchmarks.ex            # Performance benchmarking
│
└── profiles/
    ├── cable_modem.ex           # Cable modem MIB profile
    ├── cmts.ex                  # CMTS MIB profile
    ├── switch.ex                # Switch MIB profile
    ├── router.ex                # Router MIB profile
    ├── mta.ex                   # MTA MIB profile
    └── server.ex                # Server MIB profile

test/snmp_sim_ex/
├── core/
├── mib/
├── devices/
├── simulation/
├── testing/
├── performance/
└── integration/
```

## Usage Examples

### Basic Device Simulation
```elixir
# Start a cable modem with MIB-based profile
{:ok, device} = SNMPSimEx.start_device(:cable_modem,
  port: 9001,
  mib_sources: ["DOCS-CABLE-DEVICE-MIB", "IF-MIB"],
  mac_address: "00:1A:2B:3C:4D:5E"
)

# Device automatically responds with realistic behaviors
response = :snmp.sync_get("127.0.0.1", 9001, "public", ["1.3.6.1.2.1.1.1.0"])
```

### Large-Scale Load Testing
```elixir
# Start 10K mixed device population
device_population = [
  {:cable_modem, 8000},  # 8K cable modems
  {:mta, 1500},          # 1.5K voice devices
  {:switch, 400},        # 400 switches
  {:cmts, 50},           # 50 CMTS devices
  {:router, 50}          # 50 routers
]

{:ok, devices} = SNMPSimEx.start_device_population(device_population,
  port_range: 30_000..39_999,
  mib_sources: load_vendor_mibs()
)

# Run sustained load test
results = SNMPSimEx.run_load_test(devices,
  duration: 3_600_000,        # 1 hour
  concurrent_polls: 100,      # 100 concurrent pollers
  polling_interval: 600_000   # 10 minute intervals
)
```

### Error Injection Testing
```elixir
# Test cable modem signal degradation
device = SNMPSimEx.start_device(:cable_modem, port: 9001)

# Simulate weather-related signal issues
SNMPSimEx.inject_signal_degradation(device,
  duration: 300_000,     # 5 minutes
  snr_degradation: 10,   # 10 dB SNR loss
  power_variation: 5     # ±5 dBmV power swing
)

# Test poller's response to realistic conditions
metrics = SnmpPoller.collect_metrics_over_time(device, 300_000)
assert signal_quality_trends_detected(metrics)
```

### ExUnit Integration
```elixir
defmodule SnmpPollerIntegrationTest do
  use ExUnit.Case
  import SNMPSimEx.TestHelpers
  
  setup do
    # Start test devices automatically
    devices = setup_test_devices([
      {:cable_modem, port: 9001},
      {:cmts, port: 9002}
    ])
    
    on_exit(fn -> cleanup_test_devices() end)
    {:ok, devices: devices}
  end
  
  test "handles device timeout gracefully", %{devices: devices} do
    device = devices[:cable_modem]
    
    # Inject timeout condition
    SNMPSimEx.inject_timeout(device, probability: 1.0, duration: 10_000)
    
    # Test poller behavior
    result = SnmpPoller.poll_device_with_retries(device)
    assert result.status == :timeout
    assert result.retry_count > 0
  end
end
```

## Performance Targets

### Memory Usage (Optimized)
- **1,000 devices**: ~523MB total (12MB + 511MB overhead)
- **10,000 devices**: ~633MB total (122MB + 511MB overhead)
- **50,000 devices**: ~1.1GB total (610MB + 511MB overhead)

### Throughput Targets
- **Per-device**: 1,000 simple GETs/sec, 500 GETBULK/sec
- **System-wide sustained**: 100K simple GETs/sec, 50K GETBULK/sec
- **Burst capability**: 1M+ requests/sec (short duration)

### Response Times
- **Cached OID lookup**: < 1ms
- **Dynamic value generation**: < 5ms
- **GETBULK operations**: < 10ms for 100-OID response

### Reliability Targets
- **Uptime**: 99.9% availability for individual devices
- **System stability**: 24+ hour continuous operation
- **Memory stability**: No memory leaks under sustained load
- **Error handling**: Graceful degradation under resource pressure

## System Requirements

### Development Environment
```bash
# Minimum requirements
Elixir 1.15+
Erlang/OTP 26+
Memory: 4GB RAM
Disk: 1GB for MIB files and compiled profiles

# File descriptor limits
ulimit -n 65536

# Network buffer optimization
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216
```

### Production Environment
```bash
# Recommended for 10K devices
Memory: 8GB RAM (with safety margin)
CPU: 8+ cores for parallel processing
Network: Gigabit interface for high throughput
Storage: SSD for fast MIB compilation and profile loading

# Kernel parameter tuning
net.core.netdev_max_backlog=5000
net.core.somaxconn=1024
vm.swappiness=10
```

## Getting Started

### Quick Setup (Start with Walk Files)
```bash
# Clone and setup project
git clone <repository>
cd snmp_poller

# Install dependencies
mix deps.get

# Create walk files directory
mkdir -p priv/walks

# Generate walk file from your actual device
snmpwalk -v2c -c public your-cable-modem.local 1.3.6.1.2.1 > priv/walks/cable_modem.walk
# OR with numeric OIDs:
snmpwalk -v2c -c public -On your-cable-modem.local 1.3.6.1.2.1 > priv/walks/cable_modem_oids.walk

# Start simulator with walk file
iex -S mix
iex> profile = SNMPSimEx.ProfileLoader.load_profile(:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"})
iex> {:ok, device} = SNMPSimEx.start_device(profile, port: 9001)
iex> :snmp.sync_get("127.0.0.1", 9001, "public", ["1.3.6.1.2.1.1.1.0"])
```

### Alternative: MIB-Based Setup (Advanced)
```bash
# Setup MIB files (optional, for advanced simulation)
mkdir -p priv/mibs
# Copy DOCS-CABLE-DEVICE-MIB.txt, IF-MIB.txt, etc.

# Compile MIBs and start simulator
iex -S mix
iex> SNMPSimEx.setup_mib_profiles()
iex> SNMPSimEx.start_device(:cable_modem, port: 9001)
```

### Development Workflow
```elixir
# Start development environment
iex -S mix

# Load test configuration
SNMPSimEx.Config.load_development_config()

# Start small device population for testing
devices = SNMPSimEx.start_device_population([
  {:cable_modem, 10},
  {:switch, 5},
  {:cmts, 1}
], port_range: 9001..9020)

# Run basic functionality tests
SNMPSimEx.run_basic_tests(devices)

# Monitor performance
SNMPSimEx.Performance.start_monitoring()
:observer.start()
```

## Success Metrics Summary

### Phase Completion Targets
- **Phase 1**: Core SNMP + walk file support (30 tests passing)
- **Phase 2**: Enhanced behaviors + optional MIB compilation (50 tests passing) 
- **Phase 3**: OID trees and GETBULK (75 tests passing)
- **Phase 4**: Multi-device support (105 tests passing)
- **Phase 5**: Realistic behaviors (130 tests passing)
- **Phase 6**: Error injection (150 tests passing)
- **Phase 7**: Performance optimization (165 tests passing)
- **Phase 8**: Production readiness (185+ tests passing)

### Final System Capabilities
- 🎯 **10,000+ concurrent devices** with unique behaviors
- 🎯 **100K+ requests/second** sustained throughput
- 🎯 **Vendor-authentic responses** from compiled MIBs
- 🎯 **< 1GB total memory** usage with optimizations
- 🎯 **Comprehensive error injection** for realistic testing
- 🎯 **Seamless ExUnit integration** for test automation
- 🎯 **Production-ready reliability** with 24+ hour stability

This master plan combines the scalability innovations from device simulation, the authenticity benefits of MIB-based behaviors, and the comprehensive protocol support from the core SNMP implementation to create the most advanced SNMP simulator available for testing large-scale polling systems.