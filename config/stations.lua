--[[
    DPS-Transit Station Configuration
    All station definitions and properties

    ROUTE LAYOUT:
    +-------------------------------------------------------------------+
    |                                                                   |
    |   LSIA --> Davis --> Downtown --> Del Perro --> Paleto Junction   |
    |   Zone A   Zone A    Zone A       Zone A        Zone B            |
    |   Track 0  Track 0   Track 0      Track 0       Track 0           |
    |                                                                   |
    |   Paleto Junction is the northern terminus of the Regional line.  |
    |   Sandy Shores / Grapeseed (Track 12) are freight-only sidings    |
    |   branching east of the junction (no passenger service).          |
    |                                                                   |
    +-------------------------------------------------------------------+
]]

Config.Stations = {
    --[[
        Zone A: Los Santos Metropolitan
    ]]
    ['lsia'] = {
        name = 'Los Santos International Airport',
        shortName = 'LSIA',
        zone = 'A',
        track = 0,

        -- Platform location (where train stops)
        platform = vec4(-1102.44, -2894.58, 13.95, 315.0),

        -- Kiosk/ticket machine location
        kiosk = vec4(-1098.5, -2890.2, 13.95, 135.0),

        -- Waiting area center
        waitingArea = vec3(-1095.0, -2888.0, 13.95),

        -- Track progress (0.0 - 1.0 along full route)
        trackProgress = 0.0,

        -- Connections
        next = 'davis',
        prev = nil,  -- Terminus

        -- Features
        features = {
            hasParking = true,
            hasRestrooms = true,
            hasCafe = false,
            isAccessible = true,
            isTerminus = true
        },

        -- Blip override (optional)
        blip = {
            scale = 0.9
        }
    },

    ['davis'] = {
        name = 'Davis Station',
        shortName = 'Davis',
        zone = 'A',
        track = 0,

        -- Near the freight yard in south LS
        -- ESTIMATED COORDINATES - Verify in-game
        platform = vec4(-195.0, -1680.0, 33.0, 320.0),
        kiosk = vec4(-191.0, -1676.0, 33.0, 140.0),
        waitingArea = vec3(-188.0, -1673.0, 33.0),

        trackProgress = 0.10,

        next = 'downtown',
        prev = 'lsia',

        features = {
            hasParking = true,
            hasRestrooms = false,
            hasCafe = false,
            isAccessible = true
        },

        blip = {
            scale = 0.8
        }
    },

    ['downtown'] = {
        name = 'Union Depot - Downtown Los Santos',
        shortName = 'Downtown',
        zone = 'A',
        track = 0,

        platform = vec4(457.85, -619.35, 28.59, 90.0),
        kiosk = vec4(462.0, -615.0, 28.59, 270.0),
        waitingArea = vec3(465.0, -618.0, 28.59),

        trackProgress = 0.25,

        next = 'del_perro',
        prev = 'davis',

        features = {
            hasParking = true,
            hasRestrooms = true,
            hasCafe = true,
            isAccessible = true,
            isHub = true  -- Main hub station
        },

        blip = {
            scale = 1.0  -- Larger for main hub
        }
    },

    ['del_perro'] = {
        name = 'Del Perro Station',
        shortName = 'Del Perro',
        zone = 'A',
        track = 0,

        platform = vec4(-1336.55, -433.82, 33.58, 140.0),
        kiosk = vec4(-1332.0, -430.0, 33.58, 320.0),
        waitingArea = vec3(-1330.0, -428.0, 33.58),

        trackProgress = 0.40,

        next = 'paleto_junction',
        prev = 'downtown',

        features = {
            hasParking = false,
            hasRestrooms = true,
            hasCafe = false,
            isAccessible = true
        }
    },

    --[[
        Zone B: Blaine County - Paleto Junction (Northern Terminus)
        Northern end of the Regional passenger line (Track 0). Freight-only
        sidings (Sandy Shores / Grapeseed, Track 12) branch east of here.
    ]]
    ['paleto_junction'] = {
        name = 'Paleto Junction',
        shortName = 'Junction',
        zone = 'B',
        track = 0,

        -- ESTIMATED COORDINATES - Verify in-game
        -- Located on eastern approach to Paleto, south of town
        platform = vec4(650.0, 5650.0, 35.0, 315.0),
        kiosk = vec4(654.0, 5654.0, 35.0, 135.0),
        waitingArea = vec3(658.0, 5658.0, 35.0),

        trackProgress = 1.0,

        next = nil,  -- Northern terminus of the passenger line
        prev = 'del_perro',

        features = {
            hasParking = true,
            hasRestrooms = true,
            hasCafe = false,
            isAccessible = true,
            isTerminus = true,
            -- Track 0 continues to Paleto Bay; Sandy Shores / Grapeseed (Track 12,
            -- freight only) branch east of the junction.
        },

        blip = {
            scale = 1.0  -- Larger for junction
        }
    },

    --[[
        FREIGHT-ONLY SIDINGS
        Sandy Shores and Grapeseed are freight sidings (Track 12) branching east
        of Paleto Junction. They are NOT on the passenger route.
        Passenger trains should SKIP these stations.
    ]]

    ['sandy'] = {
        name = 'Sandy Shores Freight Yard',
        shortName = 'Sandy (Freight)',
        zone = 'B',
        track = 0,

        -- Freight siding - no passenger service
        platform = vec4(1766.82, 3782.55, 34.18, 30.0),
        kiosk = nil,  -- No ticket kiosk
        waitingArea = nil,  -- No passenger waiting

        trackProgress = 0.75,

        -- Not connected to passenger route
        next = 'grapeseed',
        prev = nil,  -- Dead end for passengers

        features = {
            freightOnly = true,  -- IMPORTANT: No passenger service
            hasParking = true,
            hasRestrooms = false,
            hasCafe = false,
            isAccessible = false
        }
    },

    ['grapeseed'] = {
        name = 'Grapeseed Depot',
        shortName = 'Grapeseed (Freight)',
        zone = 'B',
        track = 0,

        -- Freight depot - no passenger service
        platform = vec4(2448.65, 4098.32, 38.12, 60.0),
        kiosk = nil,
        waitingArea = nil,

        trackProgress = 0.80,

        next = nil,  -- End of freight line
        prev = 'sandy',

        features = {
            freightOnly = true,  -- IMPORTANT: No passenger service
            hasParking = true,
            hasRestrooms = false,
            hasCafe = false,
            isAccessible = false
        }
    }
}

-- Station order for route calculation (LSIA to Paleto Junction - Passenger Only)
Config.StationOrder = {
    'lsia',
    'davis',
    'downtown',
    'del_perro',
    'paleto_junction'
}

-- Freight station order (includes freight-only sidings)
Config.FreightStationOrder = {
    'lsia',
    'davis',
    'downtown',
    'del_perro',
    'paleto_junction',
    'sandy',     -- Freight only
    'grapeseed'  -- Freight only
}

-- Zone station groupings
Config.ZoneStations = {
    ['A'] = { 'lsia', 'davis', 'downtown', 'del_perro' },
    ['B'] = { 'paleto_junction', 'sandy', 'grapeseed' },  -- Include freight yards
}

-- Get station zone
function GetStationZone(stationId)
    local station = Config.Stations[stationId]
    return station and station.zone or nil
end

-- Get zone by station
function GetZoneByStation(stationId)
    for zone, stations in pairs(Config.ZoneStations) do
        for _, id in ipairs(stations) do
            if id == stationId then
                return zone
            end
        end
    end
    return nil
end

-- Get stations between two points
function GetStationsBetween(fromStation, toStation)
    local stations = {}
    local recording = false

    for _, stationId in ipairs(Config.StationOrder) do
        if stationId == fromStation then
            recording = true
        elseif stationId == toStation then
            break
        elseif recording then
            table.insert(stations, stationId)
        end
    end

    return stations
end
