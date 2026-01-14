# DPS-Transit v2.7.0

A comprehensive multi-modal public transportation system for FiveM featuring automated train scheduling, virtual block signaling for collision prevention, dispatcher control panels, and real-time passenger tracking.

---

## Features

### Core Transit System
- **Multi-Line Rail Network** - Regional Rail, LS Metro, and Roxwood Lines
- **70/30 Mixed Traffic** - Configurable passenger/freight train scheduling
- **Zone-Based Fares** - Distance-based pricing with ticket validation
- **Real-Time Tracking** - Live train positions with ETA calculations
- **Day Passes** - Unlimited 24-hour travel option
- **NUI Schedule Board** - Visual arrival display at stations

### Block Signaling System (v2.4.0+)
- **Virtual Block Segments** - 11 track segments preventing train collisions
- **Three-State Signals** - GREEN/YELLOW/RED with automatic speed control
- **Deadlock Detection** - 60-second timeout with automatic resolution
- **Carriage Clearance** - 6-second delay for long consists to clear segments

### Dispatcher Control Panel (v2.5.0+)
- **Real-Time Overview** - Visual track schematic with train positions
- **Interactive Selection** - Click trains/segments for details and ETA
- **Emergency Controls** - Stop/release trains with logging
- **Manual Segment Locks** - Right-click to lock/unlock track sections
- **Job-Restricted Access** - Only authorized personnel can access

### Audio & Atmosphere (v2.5.0+)
- **Station Announcements** - Next station, now arriving, doors closing
- **Brake Squeal SFX** - Positional audio when decelerating
- **Train Horn** - Sounds at junctions (200m approach)
- **Dynamic Speed Control** - Automatic curve/bridge speed reduction

### Framework Bridge (v2.7.0+)
- **Multi-Framework Support** - Works with both QBCore and ESX
- **Auto-Detection** - Automatically detects your framework on startup
- **Clean Abstraction** - All framework-specific code isolated in bridge files
- **Easy Configuration** - Set `Config.Framework = 'qb'`, `'esx'`, or `'auto'`

---

## Rail Network

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TRANSIT NETWORK MAP                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                                 ROXWOOD COUNTY                              │
│                                      │                                      │
│                         ┌────────────┴────────────┐                         │
│                         │    ROXWOOD CENTRAL      │  Zone C                 │
│                         │     (End of Line)       │  Track 13               │
│                         └────────────┬────────────┘                         │
│                                      │                                      │
│                                    ╱╱  Bridge curves NNE                    │
│                                  ╱╱    into Roxwood County                  │
│                                ╱╱                                           │
│  ════════════════════════════╱╱═══════════════════════════════════════════  │
│                        BLAINE COUNTY                                        │
│  ═══════════════════════════╪═════════════════════════════════════════════  │
│                             │                                               │
│            ┌────────────────┴────────────────┐                              │
│            │       PALETO JUNCTION           │  Zone B                      │
│            │   (Track 0 / Track 13 Split)    │  Transfer Point              │
│            └────────────────┬────────────────┘                              │
│                             │                                               │
│                             │  Track 0 (Main Line)                          │
│                             │                                               │
│  ════════════════════════════╪════════════════════════════════════════════  │
│                        LOS SANTOS METRO                                     │
│  ════════════════════════════╪════════════════════════════════════════════  │
│                              │                                              │
│              ┌───────────────┴───────────────┐                              │
│              │         DEL PERRO             │  Zone A                      │
│              └───────────────┬───────────────┘                              │
│                              │                                              │
│              ┌───────────────┴───────────────┐                              │
│              │     DOWNTOWN LS (HUB)         │  Zone A                      │
│              │       Union Depot             │                              │
│              └───────────────┬───────────────┘                              │
│                              │                                              │
│              ┌───────────────┴───────────────┐                              │
│              │          DAVIS                │  Zone A                      │
│              └───────────────┬───────────────┘                              │
│                              │                                              │
│              ┌───────────────┴───────────────┐                              │
│              │           LSIA                │  Zone A                      │
│              │      (Start of Line)          │  Airport                     │
│              └───────────────────────────────┘                              │
│                                                                             │
│  ═══════════════════════════════════════════════════════════════════════   │
│  FREIGHT ONLY: Sandy Shores & Grapeseed (Track 12) - No passenger service  │
│  ═══════════════════════════════════════════════════════════════════════   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Block Signaling System

The virtual block signaling system divides tracks into protected segments, preventing collisions by controlling train speeds based on segment occupancy.

### Track Segments

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BLOCK SIGNAL SEGMENTS                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  TRACK 0 (Regional Rail) - 6 Segments (~2.5km each)                         │
│  ┌──────┬──────┬──────┬──────┬──────┬──────┐                                │
│  │ SEG1 │ SEG2 │ SEG3 │ SEG4 │ SEG5 │ SEG6 │                                │
│  │ LSIA │ S.LS │  DT  │ D.P. │ HWY  │ JCT  │                                │
│  └──────┴──────┴──────┴──────┴──────┴──────┘                                │
│                                                                             │
│  TRACK 13 (Roxwood Line) - 3 Segments                                       │
│  ┌──────┬────────┬──────┐                                                   │
│  │ SEG1 │  SEG2  │ SEG3 │                                                   │
│  │ JCT  │ BRIDGE │ RXW  │  ← Bridge has 12 m/s speed limit                  │
│  └──────┴────────┴──────┘                                                   │
│                                                                             │
│  TRACK 12 (Freight) - 2 Segments                                            │
│  ┌───────┬───────┐                                                          │
│  │ SEG1  │ SEG2  │                                                          │
│  │ SANDY │ GRAPE │                                                          │
│  └───────┴───────┘                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Signal States

| Signal | Speed | Description |
|--------|-------|-------------|
| GREEN | 100% | Next segment clear, proceed normally |
| YELLOW | 30% | Next segment occupied, reduce speed |
| RED | STOP | At boundary with occupied segment ahead |

---

## Dispatcher Panel

Authorized personnel can access the dispatcher control panel to monitor and control train operations.

### Access Requirements

Open with `F7` or `/dispatch` command. Requires one of the following jobs:
- `police`, `sheriff`, `bcso`
- `dps_dispatch`, `trainstaff`, `traindriver`
- `management`, `admin`

### Features

| Feature | Description |
|---------|-------------|
| **Track Schematic** | Visual representation of all track segments |
| **Train Positions** | Real-time train locations shown on segments |
| **Interactive Selection** | Click trains/segments for ETA and details |
| **Emergency Stop** | Stop individual trains with reason logging |
| **Emergency Release** | Resume stopped trains |
| **Segment Lock** | Right-click segments to lock/unlock |

### Segment Locking (v2.6.0)

Right-click any segment on the dispatcher panel to:
- **Lock Segment** - Prevents trains from entering (requires reason)
- **Unlock Segment** - Releases the lock

Lock Priority Order:
1. Manual Segment Lock (dispatcher)
2. Dispatcher Hold (emergency stop)
3. Block Occupancy (train in segment)

---

## Fare System

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ZONE-BASED FARES                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│     ZONE A                    ZONE B                    ZONE C              │
│  ┌───────────┐             ┌───────────┐             ┌───────────┐         │
│  │   LSIA    │             │  Paleto   │             │  Roxwood  │         │
│  │ Downtown  │             │   Sandy*  │             │           │         │
│  │ Del Perro │             │ Grapeseed*│             │           │         │
│  │   Davis   │             │           │             │           │         │
│  └───────────┘             └───────────┘             └───────────┘         │
│                            * Freight only                                   │
│                                                                             │
│     FARE STRUCTURE:                                                         │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │  Same Zone (A→A, B→B, C→C)          │    $5                     │    │
│     │  One Zone  (A→B, B→C)               │   $15                     │    │
│     │  Two Zones (A→C)                    │   $25                     │    │
│     │  Day Pass  (Unlimited 24hr)         │   $50                     │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Schedule

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         70/30 PASSENGER/FREIGHT                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│     TIME PERIOD              PASSENGER        FREIGHT        TOTAL          │
│     ───────────              ─────────        ───────        ─────          │
│                                                                             │
│     PEAK HOURS                  7               3              10           │
│     (7-9 AM, 5-7 PM)         per hour        per hour       per hour        │
│                                                                             │
│     OFF-PEAK                    5               2               7           │
│     (9 AM - 5 PM)            per hour        per hour       per hour        │
│                                                                             │
│     NIGHT SERVICE               3               1               4           │
│     (10 PM - 6 AM)           per hour        per hour       per hour        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Installation

1. **Download** the resource to your server's resources folder
2. **Add** to your `server.cfg`:
   ```
   ensure ox_lib
   ensure ox_target
   ensure qb-core  # OR ensure es_extended
   ensure dps-transit
   ```
3. **Configure** framework in `config/config.lua` (optional - auto-detects by default):
   ```lua
   Config.Framework = 'auto'  -- 'qb', 'esx', or 'auto'
   ```
4. **Configure** station coordinates in `config/stations.lua`
5. **Restart** your server

---

## Dependencies

| Resource | Purpose |
|----------|---------|
| [qb-core](https://github.com/qbcore-framework/qb-core) OR [es_extended](https://github.com/esx-framework/esx_core) | Framework (one required) |
| [ox_lib](https://github.com/overextended/ox_lib) | UI, callbacks, keybinds |
| [ox_target](https://github.com/overextended/ox_target) | Station interactions |
| [ox_inventory](https://github.com/overextended/ox_inventory) | Ticket items (optional) |

---

## Configuration

### Main Config (`config/config.lua`)

```lua
Config.Train = {
    speed = 25.0,              -- Default train speed (m/s)
    stationStopDuration = 30,  -- Time at station (seconds)
}

Config.Fares = {
    sameZone = 5,              -- Within same zone
    oneZone = 15,              -- Cross one zone
    twoZones = 25,             -- Cross two zones
    dayPass = 50,              -- 24-hour unlimited
}

Config.Schedule = {
    peak = { frequency = 10, trainCount = 3 },
    offPeak = { frequency = 20, trainCount = 2 },
    night = { frequency = 30, trainCount = 1 },
}

-- Track-specific speeds (v2.2.2+)
Config.TrackSpeeds = {
    [0] = 25.0,   -- Regional Rail
    [3] = 20.0,   -- LS Metro (urban)
    [12] = 15.0,  -- Freight
    [13] = 18.0,  -- Roxwood Line
}
```

### Dispatcher Access (`config/config.lua`)

```lua
Config.DispatcherJobs = {
    'police', 'sheriff', 'bcso',
    'dps_dispatch', 'trainstaff', 'traindriver',
    'management', 'admin'
}
```

---

## Exports

### Server Exports

```lua
-- Train Management
exports['dps-transit']:GetActiveTrains()           -- Get all active trains
exports['dps-transit']:GetTrainETA(trainId, stationId)  -- Get ETA to station
exports['dps-transit']:GetStationArrivals(stationId)    -- Get arrivals list
exports['dps-transit']:SpawnTrain(startStation, direction)  -- Manual spawn

-- Block Signaling (v2.4.0+)
exports['dps-transit']:GetBlockSignalStatus()      -- Get segment occupancy
exports['dps-transit']:CalculateSignalState(trainId)  -- Get signal for train
exports['dps-transit']:CountActiveTrains()         -- Count non-stopped trains
exports['dps-transit']:CountEmergencyStoppedTrains()  -- Count stopped trains

-- Segment Control (v2.6.0+)
exports['dps-transit']:LockSegment(segmentId, reason, source)    -- Lock segment
exports['dps-transit']:UnlockSegment(segmentId, source)          -- Unlock segment
exports['dps-transit']:IsSegmentLocked(segmentId)                -- Check if locked

-- Emergency Control (v2.5.2+)
exports['dps-transit']:EmergencyBrakeNearestTrain(source, coords, radius)
exports['dps-transit']:ReleaseEmergencyBrake(source, trainId)

-- Player Tracking (v2.2.1+)
exports['dps-transit']:IsPlayerOnTrain(citizenid)  -- Check if player on train
exports['dps-transit']:GetPlayerTrain(citizenid)   -- Get player's current train

-- Service Alerts (v2.2.0+)
exports['dps-transit']:BroadcastServiceAlert(type, message, lines)
exports['dps-transit']:SetTrainDelay(trainId, minutes, reason)
```

### Client Exports

```lua
-- Station Info
exports['dps-transit']:GetNearestStation()         -- Nearest station to player
exports['dps-transit']:IsPlayerAtStation()         -- Is player at any station

-- Train Info
exports['dps-transit']:GetLocalTrains()            -- Get nearby train entities

-- Dispatcher (v2.5.1+)
exports['dps-transit']:ToggleDispatcherPanel()     -- Open/close dispatcher
exports['dps-transit']:CheckDispatcherAccess()     -- Check job permission
```

---

## File Structure

```
dps-transit/
├── fxmanifest.lua
├── README.md
├── docs/
│   ├── ARCHITECTURE.md         # System diagrams
│   ├── SPEC.md                 # Full specification
│   └── STATIONS.md             # Station details
├── config/
│   ├── config.lua              # Main settings
│   └── stations.lua            # Station definitions
├── shared/
│   └── functions.lua           # Shared utilities
├── client/
│   ├── main.lua                # Core client + dispatcher
│   └── stations.lua            # Station interactions
├── server/
│   ├── main.lua                # Core server
│   └── scheduler.lua           # Scheduling + block signaling
├── html/
│   ├── index.html              # NUI template + dispatcher panel
│   ├── css/style.css           # Styling
│   └── js/app.js               # NUI logic + dispatcher
└── locales/
    └── en.json                 # English strings
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `E` | Board/exit train when at station |
| `F7` | Toggle dispatcher panel (authorized users) |
| `ESC` | Close dispatcher panel |

---

## Commands

| Command | Description |
|---------|-------------|
| `/dispatch` | Open dispatcher control panel |

---

## Compatibility

- **Roxwood County** - Supports Track 12/13 from amb-roxwood-trains
- **QBCore** - Native framework integration
- **ox_inventory / qs-inventory** - Auto-detected for ticket items

---

## Version History

| Version | Features |
|---------|----------|
| v2.7.0 | Framework bridge (QBCore + ESX support) |
| v2.6.0 | Manual segment overrides (lock/unlock) |
| v2.5.3 | Dispatcher hold visual differentiation |
| v2.5.2 | Interactive selection, ETA tooltips, emergency controls |
| v2.5.1 | Dispatcher panel client integration |
| v2.5.0 | Dynamic audio, station announcements |
| v2.4.1 | Carriage clearance, rubber-band prevention |
| v2.4.0 | Virtual block signaling system |
| v2.3.0 | Junction deadlock detection, speed lerp |
| v2.2.2 | Track-specific speeds, emergency brake isolation |
| v2.2.1 | Player tracking, orphan cleanup |
| v2.2.0 | Platform capacity, service alerts, police integration |
| v2.1.0 | Revenue integrity, ticket sweeps |
| v2.0.0 | Multi-modal transit, 70/30 scheduling |

---

## Credits

- **Author**: DaemonAlex
- **Frameworks**: QBCore Team, ESX Team
- **UI Library**: Overextended (ox_lib, ox_target)

---

## License

This resource is provided for use on the DPS Roleplay server.
