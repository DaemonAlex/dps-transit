# DPS-Transit Station Guide

**Version**: 2.8.0
**Date**: 2026-01-01

---

## Station Network Overview

The Los Santos Metropolitan Transit Authority operates passenger rail service across two zones, connecting Los Santos International Airport to Paleto Junction (Blaine County).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PASSENGER RAIL ROUTE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   LSIA ──→ Davis ──→ Downtown ──→ Del Perro ──→ Paleto Junction            │
│   Zone A   Zone A    Zone A       Zone A        Zone B                      │
│   Track 0  Track 0   Track 0      Track 0       Track 0                     │
│                                                                             │
│   Paleto Junction is the northern terminus of the passenger line.          │
│                                                                             │
│   Sandy Shores & Grapeseed are freight sidings (Track 12) branching east   │
│   of the junction. They are freight-only and not on the passenger route.   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Zone A: Los Santos Metropolitan

### LSIA Station (Airport)
**The southern terminus of the passenger rail network.**

```lua
Stations['lsia'] = {
    id = 'lsia',
    name = 'Los Santos International Airport',
    shortName = 'LSIA',
    zone = 'A',
    track = 0,

    -- Platform location (where train stops)
    platform = vec4(-1102.44, -2894.58, 13.95, 315.0),

    -- Kiosk/ticket machine
    kiosk = vec4(-1098.5, -2890.2, 13.95, 135.0),

    -- Waiting area center
    waitingArea = vec3(-1095.0, -2888.0, 13.95),

    -- Connections
    nextStation = 'davis',
    prevStation = nil,  -- Terminus

    -- Track progress (0.0 - 1.0 along full route)
    trackProgress = 0.0,

    -- Features
    hasParking = true,
    hasRestrooms = true,
    hasCafe = false,
    isAccessible = true,
    isTerminus = true
}
```

### Davis Station
**Serves the Davis neighborhood in south Los Santos.**

```lua
Stations['davis'] = {
    id = 'davis',
    name = 'Davis Station',
    shortName = 'Davis',
    zone = 'A',
    track = 0,

    -- Near the freight yard in south LS
    -- ESTIMATED COORDINATES - Verify in-game
    platform = vec4(-195.0, -1680.0, 33.0, 320.0),
    kiosk = vec4(-191.0, -1676.0, 33.0, 140.0),
    waitingArea = vec3(-188.0, -1673.0, 33.0),

    nextStation = 'downtown',
    prevStation = 'lsia',
    trackProgress = 0.10,

    hasParking = true,
    hasRestrooms = false,
    hasCafe = false,
    isAccessible = true
}
```

### Downtown LS Station (Union Depot)
**The main hub of the transit network, located in the heart of Los Santos.**

```lua
Stations['downtown'] = {
    id = 'downtown',
    name = 'Union Depot - Downtown Los Santos',
    shortName = 'Downtown',
    zone = 'A',
    track = 0,

    platform = vec4(457.85, -619.35, 28.59, 90.0),
    kiosk = vec4(462.0, -615.0, 28.59, 270.0),
    waitingArea = vec3(465.0, -618.0, 28.59),

    nextStation = 'del_perro',
    prevStation = 'davis',
    trackProgress = 0.25,

    hasParking = true,
    hasRestrooms = true,
    hasCafe = true,
    isAccessible = true,
    isHub = true
}
```

### Del Perro Station
**Serves the Del Perro/Vespucci Beach area.**

```lua
Stations['del_perro'] = {
    id = 'del_perro',
    name = 'Del Perro Station',
    shortName = 'Del Perro',
    zone = 'A',
    track = 0,

    platform = vec4(-1336.55, -433.82, 33.58, 140.0),
    kiosk = vec4(-1332.0, -430.0, 33.58, 320.0),
    waitingArea = vec3(-1330.0, -428.0, 33.58),

    nextStation = 'paleto_junction',
    prevStation = 'downtown',
    trackProgress = 0.40,

    hasParking = false,
    hasRestrooms = true,
    hasCafe = false,
    isAccessible = true
}
```

---

## Zone B: Blaine County

### Paleto Junction
**Northern terminus of the passenger line (Track 0).**

Freight-only sidings (Sandy Shores / Grapeseed, Track 12) branch east of here.

```lua
Stations['paleto_junction'] = {
    id = 'paleto_junction',
    name = 'Paleto Junction',
    shortName = 'Junction',
    zone = 'B',
    track = 0,

    -- ESTIMATED COORDINATES - Verify in-game
    -- Located on eastern approach to Paleto, south of town
    platform = vec4(650.0, 5650.0, 35.0, 315.0),
    kiosk = vec4(654.0, 5654.0, 35.0, 135.0),
    waitingArea = vec3(658.0, 5658.0, 35.0),

    nextStation = nil,  -- Northern terminus
    prevStation = 'del_perro',
    trackProgress = 1.0,

    hasParking = true,
    hasRestrooms = true,
    hasCafe = false,
    isAccessible = true,
    isTerminus = true
}
```

---

## Station Configuration Summary

```lua
-- config/stations.lua
Config.Stations = {
    -- Zone A: Los Santos Metropolitan
    ['lsia'] = {
        name = 'Los Santos International Airport',
        shortName = 'LSIA',
        zone = 'A',
        track = 0,
        platform = vec4(-1102.44, -2894.58, 13.95, 315.0),
        trackProgress = 0.0,
        next = 'davis',
        prev = nil  -- Terminus
    },
    ['davis'] = {
        name = 'Davis Station',
        shortName = 'Davis',
        zone = 'A',
        track = 0,
        platform = vec4(-195.0, -1680.0, 33.0, 320.0),  -- ESTIMATED
        trackProgress = 0.10,
        next = 'downtown',
        prev = 'lsia'
    },
    ['downtown'] = {
        name = 'Union Depot - Downtown Los Santos',
        shortName = 'Downtown',
        zone = 'A',
        track = 0,
        platform = vec4(457.85, -619.35, 28.59, 90.0),
        trackProgress = 0.25,
        next = 'del_perro',
        prev = 'davis'
    },
    ['del_perro'] = {
        name = 'Del Perro Station',
        shortName = 'Del Perro',
        zone = 'A',
        track = 0,
        platform = vec4(-1336.55, -433.82, 33.58, 140.0),
        trackProgress = 0.40,
        next = 'paleto_junction',
        prev = 'downtown'
    },

    -- Zone B: Blaine County
    ['paleto_junction'] = {
        name = 'Paleto Junction',
        shortName = 'Junction',
        zone = 'B',
        track = 0,
        platform = vec4(650.0, 5650.0, 35.0, 315.0),  -- ESTIMATED
        trackProgress = 1.0,
        next = nil,  -- Northern terminus
        prev = 'del_perro',
        isTerminus = true
    }
}

-- Station order for route calculation
Config.StationOrder = {
    'lsia',
    'davis',
    'downtown',
    'del_perro',
    'paleto_junction'
}

-- Zone station groupings
Config.ZoneStations = {
    ['A'] = { 'lsia', 'davis', 'downtown', 'del_perro' },
    ['B'] = { 'paleto_junction' }
}
```

---

## Station Amenities Legend

| Icon | Amenity |
|------|---------|
| 🅿️ | Parking Available |
| 🚻 | Restrooms |
| ☕ | Café/Refreshments |
| ♿ | Accessible |
| 🔄 | Transfer Point |

---

## Travel Times (Approximate)

| From | To | Duration |
|------|-----|----------|
| LSIA | Davis | ~2 min |
| Davis | Downtown | ~3 min |
| Downtown | Del Perro | ~4 min |
| Del Perro | Paleto Junction | ~10 min |
| **LSIA** | **Paleto Junction (Full)** | **~19 min** |

---

## Platform Layout

```
Standard Platform Layout:
┌─────────────────────────────────────────────────┐
│                    PLATFORM                      │
│  ┌─────┐                              ┌─────┐   │
│  │Kiosk│     ═══════════════════      │Bench│   │
│  └─────┘          TRACK               └─────┘   │
│          ◄──────────────────────►               │
│              Train Stops Here                   │
│                                                 │
│  [Schedule Board]              [Route Map]      │
└─────────────────────────────────────────────────┘
```

---

## Implementation Notes

1. **Coordinate Verification**:
   - Platform coordinates need in-game verification to ensure trains stop correctly at platforms.
   - Paleto Junction coordinates are **estimated** - verify at the actual location.

2. **Track Alignment**:
   - All stations must be placed along actual GTA V train track paths.
   - Use native `GetNearestTrainTrackPosition()` to verify.

3. **Paleto Junction**:
   - Northern terminus of the passenger line on Track 0.
   - Sandy Shores / Grapeseed (Track 12, freight only) branch east of the junction.

4. **Future Expansion**:
   - Sandy Shores and Grapeseed stations could be added later as a separate freight/local service line.

---

## Virtual Block Signaling Segments

The hybrid block signaling system divides tracks into virtual segments for collision prevention. Each segment allows only one train at a time.

### Track 0: Main Line (LSIA to Paleto Junction)

| Segment ID | Name | Start Coords | End Coords | Length |
|------------|------|--------------|------------|--------|
| T0_SEG1 | LSIA Terminal | vec3(-1102, -2895, 14) | vec3(-500, -2200, 20) | ~2.5km |
| T0_SEG2 | South Los Santos | vec3(-500, -2200, 20) | vec3(100, -1200, 30) | ~2.5km |
| T0_SEG3 | Downtown Core | vec3(100, -1200, 30) | vec3(-800, -500, 35) | ~2.5km |
| T0_SEG4 | Del Perro District | vec3(-800, -500, 35) | vec3(-1800, 200, 60) | ~2.5km |
| T0_SEG5 | Great Ocean Highway | vec3(-1800, 200, 60) | vec3(-500, 4000, 50) | ~4km |
| T0_SEG6 | Paleto Approach | vec3(-500, 4000, 50) | vec3(650, 5650, 35) | ~2km |

### Track 12: Freight Line

| Segment ID | Name | Start Coords | End Coords | Notes |
|------------|------|--------------|------------|-------|
| T12_SEG1 | Sandy Shores Freight | vec3(650, 5650, 35) | vec3(1766, 3783, 34) | Freight only |
| T12_SEG2 | Grapeseed Depot | vec3(1766, 3783, 34) | vec3(2449, 4098, 38) | Freight only |

### Signal States

| State | Speed Multiplier | Behavior |
|-------|------------------|----------|
| GREEN | 100% | Full speed, next segment clear |
| YELLOW | 30% (min 5 m/s) | Caution, train ahead in next segment |
| RED | 0% | Full stop at segment boundary |

### Adding New Stations

When adding a new station (e.g., between Davis and Downtown):

1. **Identify segment**: The new station falls within T0_SEG2 (South Los Santos)
2. **Split segment**: Create T0_SEG2a and T0_SEG2b around the new station
3. **Update coordinates**: Set segment boundaries at platform locations
4. **Test spacing**: Ensure segment length > 500m to prevent rubber-banding

```lua
-- Example: Adding a new station between Davis and Downtown
{
    track = 0,
    id = 'T0_SEG2a',
    name = 'South LS North',
    startCoords = vec3(-500.0, -2200.0, 20.0),
    endCoords = vec3(-200.0, -1600.0, 28.0),  -- New station platform
    radius = 800.0
},
{
    track = 0,
    id = 'T0_SEG2b',
    name = 'New Station Approach',
    startCoords = vec3(-200.0, -1600.0, 28.0),
    endCoords = vec3(100.0, -1200.0, 30.0),
    radius = 600.0
}
```

