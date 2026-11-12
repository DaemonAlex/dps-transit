# DPS-Transit v2.8.0

A comprehensive multi-modal public transportation system for FiveM featuring automated train scheduling, virtual block signaling for collision prevention, dispatcher control panels, and real-time passenger tracking.

## Status

Not running on DelPerroSands. Replaced by [dps-trains](https://github.com/DaemonAlex/dps-trains),
with [dps-transitapp](https://github.com/DaemonAlex/dps-transitapp) for arrival times on the phone.
The code here is complete and last matched the live server on 18 August 2026.

## What it is for

GTA trains pass at random and never stop for a player. This script runs them to a timetable
between named stations, sells tickets, and gives staff a panel to watch and stop trains. It also
runs AI shuttle buses between stations that share no rail line.

## On its own, and with other scripts

**On its own.** Needs Qbox, `ox_lib` and `ox_target`. A player walks up to a station, targets the
kiosk and buys a ticket or a day pass. The schedule board shows the next arrivals. The train
pulls in, stops, and the player boards with `E`. Fares depend on the zone. Freight trains share
the track. Block signals slow or stop a train when the section ahead is taken. Staff in a listed
job open the dispatcher panel with `/dispatch` and can stop a train or lock a section of track.
Tickets are held in server memory, so they are lost on a restart.

**With ox_inventory.** A ticket is also a real `transit_ticket` item with the trip written on it.
The server reads it back when the player joins, so it survives a restart. Add the `transit_ticket` item to the
inventory first.

**With qs-inventory.** The same ticket item, through qs-inventory. DelPerroSands does not run
qs-inventory, so this path is not tested there.

**With xsound.** Station announcements play as audio: next station, now arriving, doors closing.
Without xsound the player gets text only.

**With police or dispatch scripts.** The server export `EmergencyBrakeNearestTrain` lets another
script stop the nearest train for an officer. No police script is wired in by default.

**What it does not do.** It does not put arrival times on a phone. It does not use the
dps-trains-stock engine, the dps-traintools seating, or the Roxwood line. Do not run it next to
dps-trains: both spawn trains on the same tracks.

---

## Features

### Core Transit System
- **Multi-Line Rail Network** - Regional Rail and LS Metro lines
- **70/30 Mixed Traffic** - Configurable passenger/freight train scheduling
- **Zone-Based Fares** - Distance-based pricing with ticket validation
- **Real-Time Tracking** - Live train positions with ETA calculations
- **Day Passes** - Unlimited 24-hour travel option
- **NUI Schedule Board** - Visual arrival display at stations

### Block Signaling System (v2.4.0+)
- **Virtual Block Segments** - 8 track segments preventing train collisions
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
- **Multi-Framework Support** - Works with Qbox (qbx_core), QBCore, and ESX
- **Auto-Detection** - Automatically detects your framework on startup (qbx_core preferred)
- **Clean Abstraction** - All framework-specific code isolated in bridge files
- **Easy Configuration** - Set `Config.Framework = 'qbx'`, `'qb'`, `'esx'`, or `'auto'`

---

## Rail Network

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TRANSIT NETWORK MAP                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                        BLAINE COUNTY                                        │
│  ═══════════════════════════╪═════════════════════════════════════════════  │
│                             │                                               │
│            ┌────────────────┴────────────────┐                              │
│            │       PALETO JUNCTION           │  Zone B                      │
│            │     (Northern Terminus)         │                              │
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

Open with the `/dispatch` command. The panel has no default key (the F7 bind was removed on 18 August 2026).
A player can set one in the GTA key bindings under "Toggle Transit Dispatch Panel". Requires one of the following jobs:
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
│     ZONE A                    ZONE B                                        │
│  ┌───────────┐             ┌───────────┐                                    │
│  │   LSIA    │             │  Paleto   │                                    │
│  │ Downtown  │             │   Sandy*  │                                    │
│  │ Del Perro │             │ Grapeseed*│                                    │
│  │   Davis   │             │           │                                    │
│  └───────────┘             └───────────┘                                    │
│                            * Freight only                                   │
│                                                                             │
│     FARE STRUCTURE:                                                         │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │  Same Zone (A→A, B→B)               │    $5                     │    │
│     │  One Zone  (A→B)                    │   $15                     │    │
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
   ensure qbx_core
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
| [qbx_core](https://github.com/Qbox-project/qbx_core) | Framework. `fxmanifest.lua` lists it as a hard dependency. |
| [ox_lib](https://github.com/overextended/ox_lib) | UI, callbacks, keybinds |
| [ox_target](https://github.com/overextended/ox_target) | Station interactions |
| [ox_inventory](https://github.com/overextended/ox_inventory) | Ticket items (optional) |
| xsound | Audio announcements (optional) |

The bridge files for QBCore and ESX are still in `bridge/`. To use them, remove `qbx_core` from the
`dependencies` list in `fxmanifest.lua`. They are not tested on DelPerroSands, which runs Qbox.

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
    [12] = 15.0,  -- Sandy/Grapeseed Freight
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
| none by default | Toggle dispatcher panel (authorized users). Set a key in the GTA key bindings. |
| `ESC` | Close dispatcher panel |

---

## Commands

| Command | Description |
|---------|-------------|
| `/dispatch` | Open dispatcher control panel |

---

## Compatibility

- **Qbox (qbx_core)** - Native framework integration (preferred; uses discrete `qbx_core` exports, no `GetCoreObject`)
- **QBCore / ESX** - Supported via the framework bridge
- **ox_inventory / qs-inventory** - Auto-detected for ticket items

---

## Version History

| Version | Features |
|---------|----------|
| v2.8.0 | Qbox (qbx_core) bridge + fix pass: single-owner train model, net-event validation, Roxwood removed |
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

---

## Recent changes

- **12 November 2026.** README: status, what it is for, how it works alone and with paid scripts, other DPS scripts. Fixed the dependency list and the dispatcher key.
- **18 August 2026.** Version 2.8.0 imported from the live server: native Qbox bridge, one owner per train, checks on network events, Roxwood line removed.
- **18 August 2026.** Dispatcher panel unbound from F7. The key command was renamed so old client binds stop firing.
- **18 August 2026.** Line endings pinned in `.gitattributes`.

## Author

Made by [DaemonAlex](https://github.com/DaemonAlex) for DelPerroSands.

## Other DPS scripts

All of these are made for DelPerroSands and run together on one Qbox server. Each one works on
its own. The ones marked "pairs with" do more when both are running.

| Script | What it does |
|---|---|
| [dps-inventory](https://github.com/DaemonAlex/dps-inventory) | The inventory: ox_inventory with equipment slots, backpacks, armour plates and a self status panel, in the DelPerroSands colours. |
| [dps-medical](https://github.com/DaemonAlex/dps-medical) | Patient records, illness and diagnostic tests. A companion to wasabi_ambulance. Pairs with dps-inventory: symptoms and diagnoses show on the status panel. |
| [dps-insurance](https://github.com/DaemonAlex/dps-insurance) | Ties m-Insurance into the MDT, impound, hospital and medical chart. Pairs with dps-medical. |
| [dps-studio](https://github.com/DaemonAlex/dps-studio) | Build rooms, doors and portals in game from one panel (`/studio`), with owners and managers so staff do not have to support them. |
| [dps-shops](https://github.com/DaemonAlex/dps-shops) | Shop clerks who greet and react to a robbery, then player-owned shops. |
| [dps-fleet](https://github.com/DaemonAlex/dps-fleet) | Vehicle browser and workshop on one panel: extras, liveries and mods for emergency vehicles. |
| [dps-parking](https://github.com/DaemonAlex/dps-parking) | Parking with valet, impound, violations and reserved spots. |
| [dps-vehiclepersistence](https://github.com/DaemonAlex/dps-vehiclepersistence) | Vehicles stay where they were parked. Pairs with dps-parking. |
| [dps-towjob](https://github.com/DaemonAlex/dps-towjob) | Queue-based tow job with jg-mechanic integration. |
| [dps-services](https://github.com/DaemonAlex/dps-services) | Request a tow and follow it live on the lb-phone and lb-tablet. Pairs with dps-towjob. |
| [dps-autoshops](https://github.com/DaemonAlex/dps-autoshops) | Self-service repair shops when no mechanic is on duty. |
| [dps-cityworker](https://github.com/DaemonAlex/dps-cityworker) | City infrastructure job and career. |
| [dps-ainpcs](https://github.com/DaemonAlex/dps-ainpcs) | NPCs you can talk to, with trust, quests and intel. |
| [dps-badpeds](https://github.com/DaemonAlex/dps-badpeds) | Police interaction with NPCs: stops, arrests, intel and jail records. |
| [dps-gangwars](https://github.com/DaemonAlex/dps-gangwars) | Ambient gang NPCs, territory population and war reinforcements. |
| [dps-rotations](https://github.com/DaemonAlex/dps-rotations) | Moves dealers, harvests and other spots on a fixed schedule. |
| [dps-trains](https://github.com/DaemonAlex/dps-trains) | The train system. Pairs with dps-trains-stock, dps-traintools and dps-transitapp. |
| [dps-transitapp](https://github.com/DaemonAlex/dps-transitapp) | Live train arrival boards on the lb-phone. |
| [dps-faceplant](https://github.com/DaemonAlex/dps-faceplant) | City help, reports and staff tools on the lb-phone and lb-tablet. |
| [dps-chat](https://github.com/DaemonAlex/dps-chat) | A command box for voice-only servers. No chat feed. |
| [dps-filmmode](https://github.com/DaemonAlex/dps-filmmode) | One key hides every HUD layer and gives a smooth free camera for recording. |
