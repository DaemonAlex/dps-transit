--[[
    DPS-Transit Configuration
    Unified Transportation System
]]

Config = {}

-- Framework: 'auto', 'qb', or 'esx'
-- Auto-detection checks for qb-core first, then es_extended
Config.Framework = 'auto'

-- Debug mode
Config.Debug = false

-- Train Settings
Config.Train = {
    speed = 25.0,                    -- Train speed in m/s (~55 mph)
    cruiseSpeed = 25.0,              -- Cruise speed
    stationStopDuration = 30,        -- Seconds train waits at station
    boardingTime = 25,               -- Seconds doors stay open
    variation = 25,                  -- Train variation for CreateMissionTrain
    model = 'metrotrain',            -- Default train model

    -- Speed smoothing for station approach
    slowZone = {
        enabled = true,
        approachDistance = 150.0,    -- Start slowing at this distance
        platformDistance = 30.0,     -- Full slow at this distance
        approachSpeed = 15.0,        -- Speed while approaching
        platformSpeed = 5.0,         -- Speed at platform
        accelerateDistance = 50.0    -- Distance to accelerate after leaving
    },

    -- Entity cleanup settings
    cleanup = {
        enabled = true,
        maxAge = 1800,               -- Remove trains older than 30 minutes
        maxTrains = 10,              -- Max trains per line before cleanup
        cleanupInterval = 60         -- Check every 60 seconds
    },

    -- Dynamic pathing for curved tracks (Roxwood bridge)
    curvatureHandling = {
        enabled = true,
        curveSpeedMultiplier = 0.7,  -- Slow to 70% on curves
        curveDetectionAngle = 15.0,  -- Degrees of heading change per second
        recoveryDistance = 100.0     -- Distance to resume normal speed
    },

    -- Audio settings
    audio = {
        enabled = true,
        brakeSqueal = {
            enabled = true,
            speedThreshold = 10.0,   -- Play below this speed
            soundName = 'VEHICLE_SLOWDOWN_SLIPPY',
            soundSet = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
        },
        horn = {
            enabled = true,
            approachDistance = 200.0  -- Sound horn when approaching junction
        }
    }
}

-- Platform Capacity Settings
Config.PlatformCapacity = {
    enabled = true,
    maxEntities = 20,           -- Max players/NPCs before "overcrowded"
    checkRadius = 15.0,         -- Radius to check around waitingArea
    announceOvercrowding = true,
    overcrowdingMessage = 'Platform is crowded. Please stand back from the edge.',
    checkInterval = 5000        -- Check every 5 seconds
}

-- Emergency Services Integration
Config.EmergencyServices = {
    enabled = true,
    allowedJobs = { 'police', 'sheriff', 'lspd', 'bcso', 'sasp', 'fib' },
    emergencyBraking = {
        enabled = true,
        stopDistance = 500.0,   -- Max distance to nearest station for emergency stop
        holdDuration = 300      -- Hold train for 5 minutes during emergency
    }
}

-- Track Configuration
Config.Tracks = {
    mainLine = 0,           -- Main loop track
    metro = 3,              -- LS Metro track
    roxwoodFreight = 12,    -- Roxwood freight line
    roxwoodPassenger = 13,  -- Roxwood passenger line
}

--[[
    VIRTUAL BLOCK SIGNALING SYSTEM
    Prevents train collisions by dividing tracks into exclusive segments.
    Only one train can occupy a segment at a time.

    Signal States:
    - GREEN:  Next segment clear, proceed at full speed
    - YELLOW: Next segment occupied, reduce to 30% speed
    - RED:    Current segment boundary reached, full stop
]]
Config.BlockSignaling = {
    enabled = true,

    -- Safe following distance (fallback for edge cases)
    safeFollowingDistance = 200.0,

    -- Speed multipliers for signal states
    signalSpeeds = {
        green = 1.0,      -- 100% of track speed
        yellow = 0.30,    -- 30% (caution approach)
        red = 0.0         -- Full stop
    },

    -- How far before segment boundary to start yellow approach
    yellowApproachDistance = 150.0,

    -- Carriage stability during holds (prevent physics snapping)
    carriageStability = {
        enabled = true,
        freezeOnHold = true,       -- Freeze entity during signal stops
        unfreezeDelay = 500        -- ms delay before unfreezing on green
    },

    -- Announcement settings
    announcements = {
        enabled = true,
        showOnNUI = true,          -- Show signal holds on schedule board
        notifyPassengers = true    -- Notify players on affected trains
    },

    --[[
        VIRTUAL BLOCK SEGMENTS
        Each track is divided into segments ~1000m apart.
        Segment boundaries are defined by world coordinates.

        Format:
        {
            id = 'unique_segment_id',
            track = trackId,
            startCoords = vec3(...),  -- Segment entry point
            endCoords = vec3(...),    -- Segment exit point
            length = meters,          -- Approximate length
            name = 'Human readable'   -- For announcements
        }
    ]]
    segments = {
        --[[
            TRACK 0: LSIA → Paleto Junction (Main Line)
            Total distance: ~15km
            Segments: 6 blocks (~2.5km each)
        ]]

        -- Segment 1: LSIA Terminal Zone
        {
            id = 'T0_SEG1',
            track = 0,
            startCoords = vec3(-1102.0, -2895.0, 14.0),   -- LSIA platform
            endCoords = vec3(-500.0, -2200.0, 20.0),      -- South LS approach
            length = 1200,
            name = 'LSIA Terminal',
            stations = { 'lsia' }
        },

        -- Segment 2: South Los Santos (Davis)
        {
            id = 'T0_SEG2',
            track = 0,
            startCoords = vec3(-500.0, -2200.0, 20.0),
            endCoords = vec3(100.0, -1200.0, 30.0),       -- Approaching downtown
            length = 1500,
            name = 'South Los Santos',
            stations = { 'davis' }
        },

        -- Segment 3: Downtown Core
        {
            id = 'T0_SEG3',
            track = 0,
            startCoords = vec3(100.0, -1200.0, 30.0),
            endCoords = vec3(-800.0, -500.0, 35.0),       -- West of downtown
            length = 1800,
            name = 'Downtown Core',
            stations = { 'downtown' }
        },

        -- Segment 4: West Los Santos (Del Perro)
        {
            id = 'T0_SEG4',
            track = 0,
            startCoords = vec3(-800.0, -500.0, 35.0),
            endCoords = vec3(-1800.0, 200.0, 60.0),       -- North of Del Perro
            length = 1500,
            name = 'Del Perro District',
            stations = { 'del_perro' }
        },

        -- Segment 5: Great Ocean Highway
        {
            id = 'T0_SEG5',
            track = 0,
            startCoords = vec3(-1800.0, 200.0, 60.0),
            endCoords = vec3(-500.0, 4000.0, 50.0),       -- Mid-highway
            length = 4000,
            name = 'Great Ocean Highway',
            stations = {}
        },

        -- Segment 6: Paleto Approach
        {
            id = 'T0_SEG6',
            track = 0,
            startCoords = vec3(-500.0, 4000.0, 50.0),
            endCoords = vec3(650.0, 5650.0, 35.0),        -- Paleto Junction
            length = 2000,
            name = 'Paleto Approach',
            stations = { 'paleto_junction' }
        },

        --[[
            TRACK 13: Paleto Junction → Roxwood (Passenger Line)
            Total distance: ~5km
            Segments: 3 blocks
        ]]

        -- Segment 1: Junction Departure
        {
            id = 'T13_SEG1',
            track = 13,
            startCoords = vec3(650.0, 5650.0, 35.0),      -- Junction platform
            endCoords = vec3(2400.0, 5900.0, 30.0),       -- Bridge approach
            length = 1800,
            name = 'Junction Departure',
            stations = {}
        },

        -- Segment 2: Roxwood Bridge (CRITICAL - curved section)
        {
            id = 'T13_SEG2',
            track = 13,
            startCoords = vec3(2400.0, 5900.0, 30.0),     -- Bridge start
            endCoords = vec3(2800.0, 6400.0, 45.0),       -- Bridge end
            length = 800,
            name = 'Roxwood Bridge',
            stations = {},
            isCritical = true  -- Extra caution on curves
        },

        -- Segment 3: Roxwood Terminal
        {
            id = 'T13_SEG3',
            track = 13,
            startCoords = vec3(2800.0, 6400.0, 45.0),
            endCoords = vec3(3200.0, 6800.0, 50.0),       -- Roxwood station (TBD)
            length = 600,
            name = 'Roxwood Terminal',
            stations = { 'roxwood' }
        },

        --[[
            TRACK 12: Freight Line (Sandy/Grapeseed)
            Lower priority - freight trains only
        ]]

        -- Segment 1: Sandy Shores Yard
        {
            id = 'T12_SEG1',
            track = 12,
            startCoords = vec3(650.0, 5650.0, 35.0),      -- Junction
            endCoords = vec3(1766.0, 3783.0, 34.0),       -- Sandy yard
            length = 2500,
            name = 'Sandy Shores Freight',
            stations = { 'sandy' },
            freightOnly = true
        },

        -- Segment 2: Grapeseed Depot
        {
            id = 'T12_SEG2',
            track = 12,
            startCoords = vec3(1766.0, 3783.0, 34.0),
            endCoords = vec3(2449.0, 4098.0, 38.0),       -- Grapeseed
            length = 800,
            name = 'Grapeseed Depot',
            stations = { 'grapeseed' },
            freightOnly = true
        }
    },

    -- Junction definitions (where tracks cross)
    junctions = {
        ['paleto_junction'] = {
            coords = vec3(650.0, 5650.0, 35.0),
            connectingTracks = { 0, 13, 12 },
            blockRadius = 300.0,
            -- Safe stopping positions per track (before switch)
            safeStopZone = {
                [0] = vec3(600.0, 5400.0, 35.0),
                [13] = vec3(700.0, 5700.0, 36.0),
                [12] = vec3(700.0, 5600.0, 35.0)
            }
        }
    }
}

-- Track-specific speed overrides (for curves, bridges, etc.)
Config.TrackSpeeds = {
    [0] = {                 -- Main line (Track 0)
        default = 25.0,
        zones = {}          -- No special zones
    },
    [3] = {                 -- Metro (Track 3)
        default = 20.0,     -- Urban areas, slower
        zones = {}
    },
    [13] = {                -- Roxwood Passenger (Track 13)
        default = 18.0,     -- Slower default for bridge curvature
        zones = {
            -- Bridge approach zone (NNE curve into Roxwood)
            {
                name = 'roxwood_bridge',
                start = vec3(2400.0, 5900.0, 30.0),  -- Approx start of bridge
                finish = vec3(2800.0, 6400.0, 45.0), -- Approx end of bridge
                radius = 300.0,                       -- Detection radius
                maxSpeed = 12.0,                      -- Max 12 m/s on bridge (~27 mph)
                reason = 'Bridge curvature - reduced speed for safety'
            }
        }
    },
    [12] = {                -- Roxwood Freight (Track 12)
        default = 15.0,     -- Freight moves slower
        zones = {}
    }
}

-- Schedule Configuration
Config.Schedule = {
    enabled = true,
    useGameTime = true,     -- Use in-game time for schedules

    -- Peak hours (more frequent trains)
    peak = {
        frequency = 10,     -- Minutes between trains
        trainCount = 3,     -- Active trains
        hours = {
            morning = { start = 7, stop = 9 },
            evening = { start = 17, stop = 19 }
        }
    },

    -- Off-peak
    offPeak = {
        frequency = 20,
        trainCount = 2
    },

    -- Night service (10 PM - 6 AM)
    night = {
        frequency = 30,
        trainCount = 1,
        hours = { start = 22, stop = 6 }
    }
}

-- Fare Configuration
Config.Fares = {
    sameZone = 5,           -- $5 within same zone
    oneZone = 15,           -- $15 crossing one zone
    twoZones = 25,          -- $25 crossing two zones
    dayPass = 50,           -- $50 unlimited daily
    weekPass = 200,         -- $200 weekly pass

    -- Payment methods
    acceptCash = true,
    acceptBank = true,
}

-- Zone Definitions
Config.Zones = {
    ['A'] = { name = 'Los Santos Metropolitan', color = 0 },    -- White
    ['B'] = { name = 'Blaine County', color = 2 },              -- Green
    ['C'] = { name = 'Roxwood County', color = 1 },             -- Red
}

Config.ZoneIndex = {
    ['A'] = 1,
    ['B'] = 2,
    ['C'] = 3
}

-- Blip Settings
Config.Blips = {
    stations = {
        sprite = 124,       -- Train station icon
        scale = 0.8,
        shortRange = true
    },
    trains = {
        sprite = 408,       -- Train icon
        scale = 0.7,
        shortRange = false
    }
}

-- Notification Settings
Config.Notifications = {
    arrivalWarning = 60,    -- Notify X seconds before arrival
    departureWarning = 10,  -- Notify X seconds before departure
}

-- Ticket Settings
Config.Tickets = {
    expireTime = 3600,      -- Tickets expire after 1 hour (seconds)
    maxPerPlayer = 5,       -- Max tickets a player can hold
}

-- Train Models (compatible with BigDaddy Trains)
Config.TrainModels = {
    passenger = {
        locomotive = 'metrotrain',
        carriages = { 'metrotrain' },
        maxPassengers = 20
    },
    -- Add more configs if using BigDaddy custom models
    bigdaddy = {
        locomotive = 'streak',
        carriages = { 'streakc', 'streakc', 'streakc' },
        maxPassengers = 28
    }
}

-- Enable/disable features
Config.Features = {
    realTimeTracking = true,
    announcements = true,
    ticketSystem = true,
    mapBlips = true,
    scheduleBoard = true,
    xsoundAnnouncements = true,  -- Use xsound for audio announcements
    persistentTickets = true      -- Store tickets in qb-inventory
}

-- Audio Announcements (xsound)
Config.Audio = {
    enabled = true,
    volume = 0.4,
    range = 50.0,  -- Meters from platform

    sounds = {
        arrival = 'train_arrival',        -- Sound name in xsound
        departure = 'train_departure',
        warning = 'train_warning',
        announcement = 'station_chime'
    },

    -- URLs for xsound (if using external audio)
    urls = {
        arrival = 'https://example.com/sounds/train_arrival.ogg',
        departure = 'https://example.com/sounds/train_departure.ogg',
        announcement = 'https://example.com/sounds/station_chime.ogg'
    }
}

-- Zone Clipping Safety (for custom MLO stations)
Config.MLOSafety = {
    enabled = true,

    -- Ground check distance (prevent falling through map)
    groundCheckDistance = 5.0,

    -- Teleport offset from waitingArea if ground check fails
    fallbackOffset = vec3(0.0, 0.0, 1.0),

    -- Custom portal handling for specific stations
    -- Add entries here if a station uses a custom MLO interior
    portals = {
        -- ['roxwood'] = {
        --     interiorId = 12345,  -- MLO interior ID
        --     portalCoords = vec3(0.0, 0.0, 0.0),
        --     exitCoords = vec3(0.0, 0.0, 0.0)
        -- }
    }
}

-- Persistent Ticket Item (for qb-inventory)
Config.TicketItem = {
    name = 'transit_ticket',
    label = 'Transit Ticket',
    weight = 10,
    unique = true,
    useable = true,
    description = 'A valid transit ticket for the LSIA-Roxwood line'
}
