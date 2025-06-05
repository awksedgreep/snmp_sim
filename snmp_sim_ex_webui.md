# SnmpSim Web Management Interface

A comprehensive web-based management interface for SnmpSim virtual SNMP device simulation, implemented as a separate Phoenix application with SnmpSim as a dependency.

## Architecture Approach

**Separate Project Structure**: Clean separation between the core simulation engine (SnmpSim) and the web management interface, allowing for:
- Independent scaling and deployment
- Technology flexibility
- Clean API boundaries
- Production isolation capabilities
- Multiple interface support

## Feature Specifications

### 📁 Walk File Management

#### Walk File Library
- **Upload and store walk files** (.walk, .snmpwalk formats)
- **Parse and validate walk file syntax** with error reporting
- **Preview walk file contents** with OID/value breakdown and formatting
- **Tag and categorize walk files** (device types, vendors, versions)
- **Walk file diff/comparison tools** for version analysis
- **Export/import walk file collections** with metadata preservation

#### Walk File Analysis
- **Auto-detect device type** from walk contents using behavior analysis
- **OID coverage analysis** showing which MIBs are represented
- **Data type distribution** analysis (counters vs gauges vs strings)
- **Generate device behavior profiles** from walk analysis patterns
- **Identify missing/unusual OIDs** compared to standard device profiles

### 🖥️ Device Management

#### Device Creation Wizard
- **Template-based device creation** (cable modem, CMTS, switch, router)
- **Walk file selection and assignment** with compatibility checking
- **Port allocation and conflict detection** with auto-suggestion
- **Custom device configuration** (MAC, community strings, device ID)
- **Bulk device creation** with port ranges and naming patterns

#### Device Lifecycle
- **Start/stop individual devices or groups** with dependency management
- **Device health monitoring and status** with real-time updates
- **Restart devices** with state preservation options
- **Device configuration hot-reloading** without interruption
- **Graceful shutdown** with proper cleanup and port release

#### Device Organization
- **Group devices** by type, location, or purpose
- **Device tagging and search** with advanced filtering
- **Topology visualization** (simple network diagrams)
- **Device dependency management** for coordinated operations

### 📊 Real-Time Monitoring

#### Live Dashboard
- **Device grid view** with color-coded status indicators
- **Real-time counter/gauge value updates** using Phoenix LiveView
- **Traffic flow visualization** with rate calculations
- **Error rate monitoring** with threshold alerts
- **System resource usage** (memory, CPU per device)

#### Device Deep Dive
- **Individual device monitoring pages** with detailed metrics
- **Counter increment rates and patterns** with trend analysis
- **Gauge value trends over time** with historical charts
- **SNMP request/response logs** with filtering capabilities
- **Device-specific error conditions** with diagnostic information

#### Performance Metrics
- **Requests per second per device** with aggregated statistics
- **Response time distributions** with percentile analysis
- **Memory usage per device** with leak detection
- **System-wide simulation performance** with bottleneck identification
- **Historical trend data** with configurable retention periods

### ⚙️ Configuration & Behavior

#### Simulation Behavior
- **Jitter pattern configuration** (uniform, gaussian, burst)
- **Time-of-day traffic variation settings** with custom schedules
- **Device-specific behavior multipliers** for realistic variance
- **Environmental factor simulation** (weather, load conditions)
- **Custom behavior pattern creation** with visual editors

#### Error Injection
- **Timeout simulation controls** with configurable delays
- **Packet loss configuration** with probability settings
- **SNMP error response injection** with specific error types
- **Device failure simulation** (reboot, power loss, network disconnect)
- **Malformed response generation** for robustness testing

#### Traffic Patterns
- **Utilization level presets** (low, normal, peak traffic)
- **Custom traffic pattern scheduling** with time-based rules
- **Burst traffic simulation** with configurable intensity
- **Correlation between related OIDs** for realistic behavior

### 🧪 Testing & Validation

#### SNMP Testing Tools
- **Built-in SNMP client** for device testing and verification
- **Walk execution and verification** with expected result comparison
- **Bulk operation testing** (GetBulk, Walk) with performance metrics
- **Community string validation** with security testing
- **MIB compliance checking** against standard specifications

#### Load Testing
- **Multi-device stress testing** with configurable load patterns
- **Concurrent request simulation** with realistic client behavior
- **Response time benchmarking** with performance baselines
- **Memory leak detection** with automated analysis
- **Performance regression testing** with historical comparison

#### Test Scenarios
- **Pre-built test scenario library** for common use cases
- **Custom test scenario creation** with scripting support
- **Automated test execution and reporting** with scheduling
- **Pass/fail criteria configuration** with custom thresholds
- **Test result history and comparison** with trend analysis

### 📈 Analytics & Reporting

#### Usage Analytics
- **Most queried OIDs analysis** with frequency statistics
- **Device utilization patterns** with peak usage identification
- **Error frequency reports** with root cause analysis
- **Performance trend analysis** with capacity planning insights
- **Capacity planning insights** with growth projections

#### Export & Integration
- **Configuration export/import** (JSON, YAML) with validation
- **Device state snapshots** for backup and restore
- **Performance data export** (CSV, JSON) with custom formatting
- **REST API for external integration** with authentication
- **Webhook notifications for events** with configurable triggers

### 🔧 System Administration

#### Resource Management
- **Memory usage optimization** with automatic cleanup
- **Port pool management** with allocation tracking
- **Device pool scaling** with dynamic resource allocation
- **Background task monitoring** with job queue management
- **Log management and rotation** with configurable retention

#### Security & Access
- **Community string management** with secure storage
- **Access control for device operations** with role-based permissions
- **Audit logging for device changes** with detailed tracking
- **Secure file upload validation** with malware scanning
- **Session management** with timeout and security controls

### 🎯 Quick Actions & Workflows

#### One-Click Operations
- **"Start 100 cable modems"** quick deploy with port auto-allocation
- **"Peak traffic simulation"** activation with predefined patterns
- **"Device reboot cascade"** testing with controlled timing
- **"Error condition injection"** scenarios with various failure modes
- **"Performance baseline"** capture with automated analysis

#### Automation Workflows
- **Scheduled device operations** with cron-like scheduling
- **Automatic error recovery** with intelligent retry logic
- **Performance threshold alerts** with escalation procedures
- **Automated scaling** based on load with resource management
- **Backup and restore operations** with point-in-time recovery

### 🔍 Search & Discovery

#### Global Search
- **Search across devices, OIDs, walk files** with unified interface
- **Advanced filtering** by device type, status, port, and custom criteria
- **OID value search and comparison** with pattern matching
- **Historical data queries** with time-based filtering
- **Saved search presets** with shareable configurations

## Implementation Priority

### MVP (Phase 1)
1. Walk file upload and basic parsing
2. Simple device creation and management
3. Real-time device status dashboard
4. Basic SNMP testing tools

### Core Features (Phase 2)
1. Advanced device monitoring and analytics
2. Configuration management and behavior settings
3. Error injection and testing scenarios
4. Performance metrics and reporting

### Advanced Features (Phase 3)
1. Automation workflows and scheduling
2. Advanced analytics and capacity planning
3. Integration APIs and external system support
4. Advanced visualization and topology mapping

## Technical Architecture

- **Frontend**: Phoenix LiveView for real-time updates
- **Backend**: Phoenix application with SnmpSim dependency
- **Database**: PostgreSQL for persistent data storage
- **Real-time**: Phoenix PubSub for live updates
- **API**: REST endpoints for external integration
- **Security**: Role-based access control and audit logging