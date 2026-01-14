--[[
    DPS-Transit Shuttle Bus Configuration
    AI-driven shuttle buses connecting train lines

    Shuttle Routes:
    A: Paleto ↔ Roxwood (CRITICAL - only link to expansion)
    B-C: Roxwood internal connections
    D-H: LS Metro ↔ Regional Rail connections
]]

Config.Shuttles = {
    enabled = true,

    -- Default shuttle settings
    defaults = {
        model = 'bus',              -- Vehicle model
        speed = 25.0,               -- Cruise speed in m/s (~55 mph)
        stopDuration = 15,          -- Seconds at each stop
        frequency = 10,             -- Minutes between shuttles
        maxPassengers = 16,         -- Based on bus model
    },

    -- Blip settings for shuttles
    blips = {
        sprite = 513,               -- Bus icon
        scale = 0.7,
        shortRange = true
    }
}

--[[
    SHUTTLE ROUTES
    Each route connects two points that don't share a train line
]]

Config.ShuttleRoutes = {
    --[[
        ROUTE A: PALETO ↔ ROXWOOD
        CRITICAL: Only connection between main island and Roxwood expansion
        Connects Regional Rail (Track 0) to Roxwood Railroad (Track 13)
    ]]
    ['A'] = {
        name = 'Paleto - Roxwood Express',
        shortName = 'Route A',
        enabled = false,  -- Enable when Roxwood coords are set
        priority = 1,     -- High priority route

        -- Route endpoints
        stops = {
            {
                id = 'paleto_shuttle',
                name = 'Paleto Bay Shuttle Stop',
                coords = vec4(150.0, 6400.0, 31.0, 45.0),  -- Near Paleto Junction station
                waitingArea = vec3(152.0, 6402.0, 31.0),
                connectsTo = 'paleto_junction',  -- Train station connection
                line = 'regional'
            },
            {
                id = 'roxwood_shuttle',
                name = 'Roxwood South Shuttle Stop',
                coords = vec4(0.0, 0.0, 0.0, 0.0),  -- TBD: Roxwood expansion
                waitingArea = vec3(0.0, 0.0, 0.0),
                connectsTo = 'roxwood',
                line = 'roxwood'
            }
        },

        -- Route waypoints (for AI pathfinding)
        waypoints = {
            -- TBD: Add intermediate waypoints for bridge crossing
        },

        schedule = {
            frequency = 15,  -- Every 15 minutes (lower frequency for long route)
            peakMultiplier = 1.5,
            nightEnabled = false  -- No night service on this route
        }
    },

    --[[
        ROUTE D: MIRROR PARK CONNECTION
        Connects Regional Rail to nearest Metro station
    ]]
    ['D'] = {
        name = 'Mirror Park Shuttle',
        shortName = 'Route D',
        enabled = false,  -- Enable when metro stations are defined
        priority = 3,

        stops = {
            {
                id = 'mirror_regional',
                name = 'Mirror Park Regional',
                coords = vec4(1090.0, -370.0, 67.0, 180.0),
                waitingArea = vec3(1092.0, -368.0, 67.0),
                connectsTo = nil,  -- No direct station yet
                line = 'regional'
            },
            {
                id = 'mirror_metro',
                name = 'Mirror Park Metro',
                coords = vec4(1020.0, -450.0, 64.0, 270.0),
                waitingArea = vec3(1022.0, -448.0, 64.0),
                connectsTo = nil,
                line = 'metro'
            }
        },

        waypoints = {},

        schedule = {
            frequency = 8,
            peakMultiplier = 2.0,
            nightEnabled = true
        }
    },

    --[[
        ROUTE E: DOWNTOWN HUB
        MAIN HUB - Union Depot to Downtown Metro
        Highest traffic shuttle route
    ]]
    ['E'] = {
        name = 'Downtown Transit Link',
        shortName = 'Route E',
        enabled = true,
        priority = 1,

        stops = {
            {
                id = 'union_depot_shuttle',
                name = 'Union Depot Bus Stop',
                coords = vec4(470.0, -630.0, 28.0, 90.0),
                waitingArea = vec3(472.0, -628.0, 28.0),
                connectsTo = 'downtown',
                line = 'regional'
            },
            {
                id = 'downtown_metro_shuttle',
                name = 'Downtown Metro Bus Stop',
                coords = vec4(200.0, -850.0, 31.0, 180.0),
                waitingArea = vec3(202.0, -848.0, 31.0),
                connectsTo = nil,  -- Metro station
                line = 'metro'
            }
        },

        waypoints = {
            vec3(400.0, -700.0, 29.0),
            vec3(300.0, -780.0, 30.0),
        },

        schedule = {
            frequency = 5,  -- Every 5 minutes
            peakMultiplier = 2.0,  -- Double during peak
            nightEnabled = true
        }
    },

    --[[
        ROUTE F: DEL PERRO CONNECTION
        Connects Del Perro Regional to Del Perro Metro
    ]]
    ['F'] = {
        name = 'Del Perro Shuttle',
        shortName = 'Route F',
        enabled = true,
        priority = 2,

        stops = {
            {
                id = 'del_perro_regional',
                name = 'Del Perro Station Bus Stop',
                coords = vec4(-1340.0, -440.0, 33.0, 135.0),
                waitingArea = vec3(-1338.0, -438.0, 33.0),
                connectsTo = 'del_perro',
                line = 'regional'
            },
            {
                id = 'del_perro_metro',
                name = 'Del Perro Metro Bus Stop',
                coords = vec4(-1400.0, -520.0, 31.0, 225.0),
                waitingArea = vec3(-1398.0, -518.0, 31.0),
                connectsTo = nil,
                line = 'metro'
            }
        },

        waypoints = {},

        schedule = {
            frequency = 8,
            peakMultiplier = 1.5,
            nightEnabled = true
        }
    },

    --[[
        ROUTE G: DAVIS CONNECTION
        Connects Davis Regional to Davis Metro
    ]]
    ['G'] = {
        name = 'Davis Shuttle',
        shortName = 'Route G',
        enabled = true,
        priority = 2,

        stops = {
            {
                id = 'davis_regional',
                name = 'Davis Station Bus Stop',
                coords = vec4(-200.0, -1685.0, 33.0, 320.0),
                waitingArea = vec3(-198.0, -1683.0, 33.0),
                connectsTo = 'davis',
                line = 'regional'
            },
            {
                id = 'davis_metro',
                name = 'Davis Metro Bus Stop',
                coords = vec4(-250.0, -1750.0, 28.0, 230.0),
                waitingArea = vec3(-248.0, -1748.0, 28.0),
                connectsTo = nil,
                line = 'metro'
            }
        },

        waypoints = {},

        schedule = {
            frequency = 8,
            peakMultiplier = 1.5,
            nightEnabled = true
        }
    },

    --[[
        ROUTE H: LSIA HUB
        AIRPORT HUB - LSIA Regional to LSIA Metro Terminal
    ]]
    ['H'] = {
        name = 'LSIA Transit Link',
        shortName = 'Route H',
        enabled = true,
        priority = 1,

        stops = {
            {
                id = 'lsia_regional',
                name = 'LSIA Train Station',
                coords = vec4(-1100.0, -2900.0, 13.0, 315.0),
                waitingArea = vec3(-1098.0, -2898.0, 13.0),
                connectsTo = 'lsia',
                line = 'regional'
            },
            {
                id = 'lsia_metro',
                name = 'LSIA Metro Terminal',
                coords = vec4(-1050.0, -2720.0, 13.0, 60.0),
                waitingArea = vec3(-1048.0, -2718.0, 13.0),
                connectsTo = nil,
                line = 'metro'
            }
        },

        waypoints = {
            vec3(-1070.0, -2810.0, 13.0),
        },

        schedule = {
            frequency = 5,  -- Every 5 minutes
            peakMultiplier = 2.0,
            nightEnabled = true
        }
    }
}

--[[
    BUS MODELS
    Different bus types for different routes
]]

Config.BusModels = {
    -- Standard transit bus
    ['bus'] = {
        model = 'bus',
        maxPassengers = 16,
        livery = 0
    },

    -- Airport shuttle
    ['airbus'] = {
        model = 'airbus',
        maxPassengers = 15,
        livery = 0
    },

    -- Coach for longer routes
    ['coach'] = {
        model = 'coach',
        maxPassengers = 14,
        livery = 0
    },

    -- Rental shuttle
    ['rentalbus'] = {
        model = 'rentalbus',
        maxPassengers = 12,
        livery = 0
    }
}

-- Route to bus model mapping
Config.RouteModels = {
    ['A'] = 'coach',     -- Long route to Roxwood
    ['D'] = 'bus',
    ['E'] = 'bus',
    ['F'] = 'bus',
    ['G'] = 'bus',
    ['H'] = 'airbus',    -- Airport shuttle
}

--[[
    SCHEDULE INTEGRATION
    Shuttles coordinate with train schedules
]]

Config.ShuttleSchedule = {
    -- Shuttle arrives X seconds before train departure
    trainSyncOffset = 60,

    -- Time periods (same as trains)
    peak = {
        hours = { 7, 8, 9, 17, 18, 19 },
        multiplier = 2.0
    },

    offPeak = {
        hours = { 6, 10, 11, 12, 13, 14, 15, 16, 20, 21 },
        multiplier = 1.0
    },

    night = {
        hours = { 22, 23, 0, 1, 2, 3, 4, 5 },
        multiplier = 0.5
    }
}

--[[
    HELPER FUNCTIONS
]]

-- Get all enabled routes
function GetEnabledShuttleRoutes()
    local routes = {}
    for routeId, route in pairs(Config.ShuttleRoutes) do
        if route.enabled then
            routes[routeId] = route
        end
    end
    return routes
end

-- Get route by ID
function GetShuttleRoute(routeId)
    return Config.ShuttleRoutes[routeId]
end

-- Get bus model for route
function GetBusModelForRoute(routeId)
    local modelKey = Config.RouteModels[routeId] or 'bus'
    return Config.BusModels[modelKey]
end

-- Check if route connects to a specific train line
function RouteConnectsToLine(routeId, lineId)
    local route = Config.ShuttleRoutes[routeId]
    if not route then return false end

    for _, stop in ipairs(route.stops) do
        if stop.line == lineId then
            return true
        end
    end

    return false
end

-- Get all routes that connect two lines
function GetRoutesConnectingLines(lineA, lineB)
    local routes = {}

    for routeId, route in pairs(Config.ShuttleRoutes) do
        if route.enabled then
            local hasA, hasB = false, false
            for _, stop in ipairs(route.stops) do
                if stop.line == lineA then hasA = true end
                if stop.line == lineB then hasB = true end
            end
            if hasA and hasB then
                table.insert(routes, routeId)
            end
        end
    end

    return routes
end

-- Get next shuttle for a route
function GetNextShuttleTime(routeId)
    local route = Config.ShuttleRoutes[routeId]
    if not route or not route.enabled then return nil end

    local currentMinute = tonumber(os.date('%M'))
    local frequency = route.schedule.frequency

    -- Apply time period multiplier
    local periodName, period = GetCurrentTimePeriod()
    if period and route.schedule.peakMultiplier then
        if periodName == 'peak' then
            frequency = math.floor(frequency / route.schedule.peakMultiplier)
        elseif periodName == 'night' and not route.schedule.nightEnabled then
            return nil  -- No service
        end
    end

    local nextMinute = math.ceil(currentMinute / frequency) * frequency
    if nextMinute >= 60 then nextMinute = 0 end

    return nextMinute
end

-- Exports
exports('GetEnabledShuttleRoutes', GetEnabledShuttleRoutes)
exports('GetShuttleRoute', GetShuttleRoute)
exports('GetBusModelForRoute', GetBusModelForRoute)
exports('GetNextShuttleTime', GetNextShuttleTime)
