# DPS-Transit Unified Transportation System

**Project**: dps-transit
**Version**: 1.0.0
**Date**: 2025-12-30
**Author**: @daemonAlex

---

## Overview

A unified public transportation system connecting Los Santos International Airport to Roxwood County via scheduled passenger trains with real-time tracking and arrival predictions.

---

## Core Features

### 1. Unified Rail Network
- Single integrated passenger service spanning the entire map
- Airport → Downtown LS → Sandy Shores → Roxwood route
- Real trains running on actual GTA V rail tracks

### 2. Automatic Scheduling
- Trains spawn and depart on configurable schedules
- Multiple trains can operate simultaneously
- Rush hour increased frequency

### 3. Real-Time Tracking
- Live train positions on map
- ETA calculations for each station
- "Next train in X minutes" displays at stations

### 4. Ticket System
- Purchase tickets at station kiosks
- Zone-based pricing (further = more expensive)
- Integration with QBCore economy

---

## Rail Network Map

```
                                    ROXWOOD COUNTY
                                         │
                            ┌────────────┴────────────┐
                            │     ROXWOOD STATION     │ ◄─── Track 13 (Passenger)
                            │      (End of Line)      │
                            └────────────┬────────────┘
                                         │
                    ─────────────────────┼───────────────────── Track 12 (Freight Only)
                                         │
                            ┌────────────┴────────────┐
                            │   GRAPESEED JUNCTION    │
                            └────────────┬────────────┘
                                         │
                            ┌────────────┴────────────┐
                            │    SANDY SHORES STN     │
                            └────────────┬────────────┘
                                         │
                    ═════════════════════╪═════════════════════ Track 0 (Main Loop)
                                         │
                            ┌────────────┴────────────┐
                            │   PALETO BAY STATION    │
                            └────────────┬────────────┘
                                         │
                            ┌────────────┴────────────┐
                            │    DEL PERRO STATION    │
                            └────────────┬────────────┘
                                         │
                    ─────────────────────┼───────────────────── Track 3 (Metro)
                                         │
                            ┌────────────┴────────────┐
                            │  DOWNTOWN LS STATION    │
                            │    (Union Depot)        │
                            └────────────┬────────────┘
                                         │
                            ┌────────────┴────────────┐
                            │    LSIA STATION         │ ◄─── Airport
                            │   (Start of Line)       │
                            └─────────────────────────┘
```

---

## Station Definitions

### Zone A: Los Santos Metropolitan

| Station | Location | Platform | Zone |
|---------|----------|----------|------|
| LSIA (Airport) | vec3(-1102.0, -2894.0, 13.9) | Ground level | A |
| Downtown LS (Union Depot) | vec3(440.0, -620.0, 28.5) | Ground level | A |
| Del Perro | vec3(-1340.0, -430.0, 33.5) | Ground level | A |

### Zone B: Blaine County

| Station | Location | Platform | Zone |
|---------|----------|----------|------|
| Paleto Bay | vec3(-360.0, 6130.0, 31.5) | Ground level | B |
| Sandy Shores | vec3(1770.0, 3780.0, 34.0) | Ground level | B |
| Grapeseed Junction | vec3(2450.0, 4100.0, 38.0) | Ground level | B |

### Zone C: Roxwood County

| Station | Location | Platform | Zone |
|---------|----------|----------|------|
| Roxwood Central | vec3(TBD) | Ground level | C |

---

## Fare Structure

### Zone-Based Pricing
```lua
Config.Fares = {
    sameZone = 5,      -- $5 within same zone
    oneZone = 15,      -- $15 crossing one zone boundary
    twoZones = 25,     -- $25 crossing two zone boundaries
    dayPass = 50,      -- $50 unlimited daily travel
    weekPass = 200,    -- $200 weekly pass
}

Config.Zones = {
    A = { 'lsia', 'downtown', 'del_perro' },
    B = { 'paleto', 'sandy', 'grapeseed' },
    C = { 'roxwood' }
}
```

### Fare Calculation
```lua
function CalculateFare(fromStation, toStation)
    local fromZone = GetStationZone(fromStation)
    local toZone = GetStationZone(toStation)

    if fromZone == toZone then
        return Config.Fares.sameZone
    end

    local zoneDiff = math.abs(ZoneIndex[fromZone] - ZoneIndex[toZone])

    if zoneDiff == 1 then
        return Config.Fares.oneZone
    else
        return Config.Fares.twoZones
    end
end
```

---

## Schedule System

### Train Frequency
```lua
Config.Schedule = {
    -- Peak hours (7-9 AM, 5-7 PM)
    peak = {
        frequency = 10,  -- Train every 10 minutes
        trainCount = 3   -- 3 trains operating
    },
    -- Off-peak
    offPeak = {
        frequency = 20,  -- Train every 20 minutes
        trainCount = 2   -- 2 trains operating
    },
    -- Night (10 PM - 6 AM)
    night = {
        frequency = 30,  -- Train every 30 minutes
        trainCount = 1   -- 1 train operating
    }
}

Config.PeakHours = {
    morning = { start = 7, stop = 9 },
    evening = { start = 17, stop = 19 }
}
```

### Schedule Generation
```lua
-- Server generates schedule at server start and every hour
function GenerateSchedule()
    local schedule = {}
    local currentHour = GetGameHour()
    local config = GetScheduleConfig(currentHour)

    local interval = config.frequency
    local startMinute = 0

    for i = 1, 60 / interval do
        local minute = startMinute + ((i - 1) * interval)
        table.insert(schedule, {
            departure = minute,
            route = 'lsia_to_roxwood',
            trainConfig = 'passenger_config01'
        })
    end

    return schedule
end
```

---

## Real-Time Tracking System

### Train State Management
```lua
ActiveTrains = {}

-- Each active train has:
ActiveTrains[trainId] = {
    id = trainId,
    entity = trainEntity,
    route = 'lsia_to_roxwood',
    direction = 'northbound',  -- or 'southbound'
    currentPosition = vec3(x, y, z),
    currentTrackProgress = 0.45,  -- 45% along track
    speed = 25.0,
    nextStation = 'sandy',
    previousStation = 'downtown',
    departureTime = timestamp,
    passengers = 12,
    status = 'running'  -- 'stopped', 'boarding', 'departing'
}
```

### Position Tracking Thread
```lua
-- Server-side: Update train positions every second
CreateThread(function()
    while true do
        Wait(1000)

        for trainId, train in pairs(ActiveTrains) do
            if DoesEntityExist(train.entity) then
                local pos = GetEntityCoords(train.entity)
                train.currentPosition = pos
                train.currentTrackProgress = CalculateTrackProgress(pos)
                train.speed = GetEntitySpeed(train.entity)

                -- Check if approaching station
                local nearStation = GetNearestStation(pos)
                if nearStation and #(pos - nearStation.coords) < 50.0 then
                    train.nextStation = nearStation.id
                    train.status = 'approaching'
                end

                -- Broadcast update to all clients
                TriggerClientEvent('dps-transit:updateTrain', -1, trainId, {
                    position = train.currentPosition,
                    progress = train.currentTrackProgress,
                    nextStation = train.nextStation,
                    status = train.status
                })
            end
        end
    end
end)
```

### ETA Calculation
```lua
function CalculateETA(trainId, targetStation)
    local train = ActiveTrains[trainId]
    if not train then return nil end

    local trainProgress = train.currentTrackProgress
    local stationProgress = Stations[targetStation].trackProgress

    -- Calculate remaining distance (in track percentage)
    local remainingProgress = stationProgress - trainProgress
    if remainingProgress < 0 then
        remainingProgress = remainingProgress + 1.0  -- Wrapped around
    end

    -- Convert to time based on average speed
    local totalTrackLength = Config.TrackLengthMeters  -- e.g., 15000m
    local remainingDistance = remainingProgress * totalTrackLength
    local averageSpeed = Config.AverageTrainSpeed  -- m/s

    local etaSeconds = remainingDistance / averageSpeed

    -- Add station stop times
    local stationsBetween = GetStationsBetween(train.nextStation, targetStation)
    local stopTime = #stationsBetween * Config.StationStopDuration

    return etaSeconds + stopTime
end
```

---

## Train Spawning System

### Spawn Configuration
```lua
Config.TrainConfigs = {
    passenger = {
        model = 'streakcoaster',  -- BigDaddy locomotive
        carriages = {
            { model = 'streakc', count = 4 },  -- 4 passenger cars
        },
        maxPassengers = 28,  -- 7 per car
        speed = 25.0
    }
}

Config.SpawnPoints = {
    lsia_northbound = {
        coords = vec4(-1102.0, -2894.0, 13.9, 0.0),
        track = 0,
        direction = true
    },
    roxwood_southbound = {
        coords = vec4(TBD),
        track = 13,
        direction = false
    }
}
```

### Train Spawning
```lua
function SpawnScheduledTrain(spawnPoint, trainConfig)
    local spawn = Config.SpawnPoints[spawnPoint]
    local config = Config.TrainConfigs[trainConfig]

    -- Request train model
    local modelHash = GetHashKey(config.model)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    -- Create train
    local train = CreateMissionTrain(
        Config.TrainVariation,
        spawn.coords.x,
        spawn.coords.y,
        spawn.coords.z,
        spawn.direction
    )

    -- Set speed
    SetTrainSpeed(train, config.speed)
    SetTrainCruiseSpeed(train, config.speed)

    -- Register in tracking system
    local trainId = GenerateTrainId()
    ActiveTrains[trainId] = {
        id = trainId,
        entity = train,
        route = GetRouteFromSpawn(spawnPoint),
        direction = spawn.direction and 'northbound' or 'southbound',
        currentPosition = spawn.coords.xyz,
        spawnTime = os.time(),
        status = 'departing'
    }

    -- Trigger departure announcement
    TriggerClientEvent('dps-transit:trainDeparting', -1, trainId, spawnPoint)

    return trainId
end
```

---

## Station Features

### Station Kiosk
```lua
-- ox_target interaction at station kiosk
exports.ox_target:addBoxZone({
    coords = station.kioskCoords,
    size = vec3(1.5, 1.5, 2.0),
    rotation = station.kioskRotation,
    debug = Config.Debug,
    options = {
        {
            name = 'transit_kiosk',
            icon = 'fa-solid fa-ticket',
            label = 'Purchase Ticket',
            onSelect = function()
                OpenTicketKiosk(station.id)
            end
        },
        {
            name = 'transit_schedule',
            icon = 'fa-solid fa-clock',
            label = 'View Schedule',
            onSelect = function()
                OpenScheduleDisplay(station.id)
            end
        },
        {
            name = 'transit_map',
            icon = 'fa-solid fa-map',
            label = 'Route Map',
            onSelect = function()
                OpenRouteMap()
            end
        }
    }
})
```

### Arrival Display Board
```lua
-- Dynamic display showing next arrivals
function GetStationArrivals(stationId)
    local arrivals = {}

    for trainId, train in pairs(ActiveTrains) do
        if TrainWillStopAt(train, stationId) then
            local eta = CalculateETA(trainId, stationId)
            table.insert(arrivals, {
                trainId = trainId,
                direction = train.direction,
                destination = GetFinalDestination(train),
                eta = eta,
                status = train.status
            })
        end
    end

    -- Sort by ETA
    table.sort(arrivals, function(a, b) return a.eta < b.eta end)

    return arrivals
end
```

---

## Passenger System

### Boarding Logic
```lua
-- When train stops at station
RegisterNetEvent('dps-transit:trainAtStation', function(trainId, stationId)
    local train = ActiveTrains[trainId]
    if not train then return end

    train.status = 'boarding'

    -- Open doors
    SetTrainDoorOpen(train.entity, true)

    -- Allow boarding for 30 seconds
    SetTimeout(30000, function()
        SetTrainDoorOpen(train.entity, false)
        train.status = 'departing'

        -- Announce departure
        TriggerClientEvent('dps-transit:trainDeparting', -1, trainId, stationId)

        -- Resume movement
        SetTrainCruiseSpeed(train.entity, Config.TrainConfigs.passenger.speed)
    end)
end)
```

### Player Boarding
```lua
-- Client-side: Board train
function BoardTrain(trainId)
    local train = ActiveTrains[trainId]
    if not train or train.status ~= 'boarding' then
        lib.notify({ title = 'Transit', description = 'Train is not boarding', type = 'error' })
        return
    end

    -- Check ticket
    local hasTicket = lib.callback.await('dps-transit:checkTicket', false)
    if not hasTicket then
        lib.notify({ title = 'Transit', description = 'You need a ticket to board', type = 'error' })
        return
    end

    -- Find available seat
    local carriage = GetTrainCarriage(train.entity, 1)  -- First passenger car
    local seatIndex = FindAvailableSeat(carriage)

    if seatIndex then
        TaskWarpPedIntoVehicle(PlayerPedId(), carriage, seatIndex)
        CurrentTrain = trainId

        -- Show destination selector
        ShowDestinationUI(train.route)
    else
        lib.notify({ title = 'Transit', description = 'Train is full', type = 'error' })
    end
end
```

---

## User Interface

### Schedule Display (NUI)
```html
<!-- html/schedule.html -->
<div class="transit-schedule">
    <div class="station-header">
        <h2 id="station-name">Downtown LS Station</h2>
        <div class="current-time" id="current-time">14:35</div>
    </div>

    <div class="arrivals-board">
        <div class="board-header">
            <span class="col-dest">Destination</span>
            <span class="col-eta">ETA</span>
            <span class="col-status">Status</span>
        </div>

        <div class="arrivals-list" id="arrivals-list">
            <!-- Populated by JS -->
        </div>
    </div>

    <div class="announcements" id="announcements">
        <!-- "The next train to Roxwood arrives in 5 minutes" -->
    </div>
</div>
```

### Live Map Display
```lua
-- Blips for active trains
function UpdateTrainBlips()
    for trainId, train in pairs(ActiveTrains) do
        if TrainBlips[trainId] then
            SetBlipCoords(TrainBlips[trainId], train.currentPosition)
        else
            local blip = AddBlipForCoord(train.currentPosition)
            SetBlipSprite(blip, 408)  -- Train icon
            SetBlipColour(blip, train.direction == 'northbound' and 2 or 1)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Train to ' .. GetFinalDestination(train))
            EndTextCommandSetBlipName(blip)
            TrainBlips[trainId] = blip
        end
    end
end
```

---

## Configuration Summary

### config/config.lua
```lua
Config = {}

Config.Debug = false

-- Train settings
Config.TrainSpeed = 25.0  -- m/s (about 55 mph)
Config.StationStopDuration = 30  -- seconds
Config.BoardingTime = 25  -- seconds doors stay open

-- Track configuration
Config.Tracks = {
    mainLine = 0,
    metro = 3,
    roxwoodFreight = 12,
    roxwoodPassenger = 13
}

-- Schedule
Config.Schedule = {
    enabled = true,
    peakFrequency = 10,
    offPeakFrequency = 20,
    nightFrequency = 30
}

-- Fares
Config.Fares = {
    sameZone = 5,
    oneZone = 15,
    twoZones = 25,
    dayPass = 50
}
```

---

## Integration Points

### With BigDaddy Trains
- Use BigDaddy's train models and sounds
- Leverage existing vehicle configs

### With Roxwood Trains
- Connect to Track 12/13 in Roxwood County
- Use Roxwood passenger consist (`amb_statrac_config_1`)

### With NTeam Scenario
- Use for special events (jail transport via train)
- Cinematic first spawn sequence

### With QBCore
- Payment through player bank
- Job system for conductors (optional)
- Society fund for transit authority

---

## File Structure

```
dps-transit/
├── fxmanifest.lua
├── README.md
├── docs/
│   ├── SPEC.md              ← This document
│   ├── STATIONS.md          ← Station details
│   └── API.md               ← Exports/Events
├── config/
│   ├── config.lua           ← Main settings
│   ├── stations.lua         ← Station definitions
│   ├── routes.lua           ← Route configurations
│   └── fares.lua            ← Pricing
├── client/
│   ├── main.lua             ← Core client
│   ├── stations.lua         ← Station interactions
│   ├── tracking.lua         ← Real-time updates
│   ├── boarding.lua         ← Board/exit logic
│   └── ui.lua               ← NUI handlers
├── server/
│   ├── main.lua             ← Core server
│   ├── scheduler.lua        ← Train scheduling
│   ├── tracking.lua         ← Position tracking
│   ├── tickets.lua          ← Ticket management
│   └── trains.lua           ← Train spawning
├── shared/
│   └── functions.lua        ← Shared utilities
├── html/
│   ├── index.html           ← Main UI
│   ├── css/
│   │   └── style.css
│   └── js/
│       ├── schedule.js
│       └── map.js
└── locales/
    └── en.lua
```

---

## Dependencies

| Resource | Purpose |
|----------|---------|
| qb-core | Framework |
| ox_lib | UI, callbacks, zones |
| ox_target | Station interactions |
| BigDaddy Trains | Train models, sounds |
| amb-roxwood-trains | Roxwood track data |

---

## Events

### Server Events
```lua
-- Train spawned
TriggerEvent('dps-transit:trainSpawned', trainId, spawnPoint)

-- Train arrived at station
TriggerEvent('dps-transit:trainArrived', trainId, stationId)

-- Train departed station
TriggerEvent('dps-transit:trainDeparted', trainId, stationId)

-- Player boarded
TriggerEvent('dps-transit:playerBoarded', source, trainId)

-- Player exited
TriggerEvent('dps-transit:playerExited', source, stationId)
```

### Client Events
```lua
-- Receive train position update
RegisterNetEvent('dps-transit:updateTrain')

-- Station announcement
RegisterNetEvent('dps-transit:announcement')

-- Open schedule UI
RegisterNetEvent('dps-transit:openSchedule')
```

---

## Exports

### Server
```lua
exports['dps-transit']:GetActiveTrains()
exports['dps-transit']:GetTrainETA(trainId, stationId)
exports['dps-transit']:GetNextArrival(stationId)
exports['dps-transit']:SpawnTrain(spawnPoint, config)
exports['dps-transit']:GetStationArrivals(stationId)
```

### Client
```lua
exports['dps-transit']:GetNearestStation()
exports['dps-transit']:HasValidTicket()
exports['dps-transit']:GetCurrentTrain()
exports['dps-transit']:OpenScheduleUI()
```

---

## Future Enhancements

1. **Bus Integration** - Add bus routes connecting to train stations
2. **Taxi/Rideshare** - Dispatch from stations
3. **Freight Jobs** - Conductor/engineer roleplay job
4. **Dynamic Events** - Train delays, breakdowns, emergencies
5. **VIP Cars** - First class with premium fares
6. **Transit Authority Job** - Staff manage stations, check tickets

