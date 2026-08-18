--[[
    DPS-Transit Shuttle Bus Server
    Manages shuttle bus scheduling and spawning
]]

-- Active shuttles
local ActiveShuttles = {}

-- Route schedules
local RouteSchedules = {}

-- Last spawn time per route
local LastSpawnTime = {}

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------

CreateThread(function()
    if not Config.Shuttles or not Config.Shuttles.enabled then
        Transit.Debug('Shuttle system disabled')
        return
    end

    Wait(5000)  -- Wait for train system to init

    Transit.Debug('Shuttle scheduler starting...')

    -- Initialize each enabled route
    for routeId, route in pairs(Config.ShuttleRoutes) do
        if route.enabled then
            InitializeRoute(routeId)
        end
    end

    -- Main scheduler loop
    while true do
        for routeId, route in pairs(Config.ShuttleRoutes) do
            if route.enabled then
                ProcessRouteSchedule(routeId)
            end
        end

        Wait(30000)  -- Check every 30 seconds
    end
end)

-- Initialize a route's schedule
function InitializeRoute(routeId)
    local route = Config.ShuttleRoutes[routeId]
    if not route then return end

    RouteSchedules[routeId] = {
        lastMinute = -1,
        activeShuttles = {}
    }

    LastSpawnTime[routeId] = 0

    Transit.Debug('Initialized shuttle route:', routeId, '| Frequency:', route.schedule.frequency, 'min')
end

-----------------------------------------------------------
-- SCHEDULE PROCESSING
-----------------------------------------------------------

-- Process schedule for a single route
function ProcessRouteSchedule(routeId)
    local route = Config.ShuttleRoutes[routeId]
    local schedule = RouteSchedules[routeId]

    if not route or not schedule then return end

    -- Get current time
    local currentMinute = tonumber(os.date('%M'))

    -- Skip if already processed this minute
    if currentMinute == schedule.lastMinute then return end
    schedule.lastMinute = currentMinute

    -- Check if this is a scheduled spawn time
    local frequency = route.schedule.frequency

    -- Apply time period adjustments
    local periodName, period = GetCurrentTimePeriod()
    if periodName == 'peak' and route.schedule.peakMultiplier then
        frequency = math.floor(frequency / route.schedule.peakMultiplier)
    elseif periodName == 'night' and not route.schedule.nightEnabled then
        return  -- No night service
    end

    -- Check if we should spawn
    if currentMinute % frequency == 0 then
        -- Check max shuttles per route
        local activeCount = CountActiveShuttles(routeId)
        if activeCount >= 2 then
            Transit.Debug('Max shuttles active on route', routeId)
            return
        end

        SpawnShuttle(routeId)
    end
end

-- Count active shuttles on a route
function CountActiveShuttles(routeId)
    local count = 0
    for _, shuttle in pairs(ActiveShuttles) do
        if shuttle.routeId == routeId then
            count = count + 1
        end
    end
    return count
end

-----------------------------------------------------------
-- SHUTTLE SPAWNING
-----------------------------------------------------------

-- Generate shuttle ID
function GenerateShuttleId()
    return 'SHUTTLE_' .. os.time() .. '_' .. math.random(1000, 9999)
end

-- Spawn a shuttle on a route
function SpawnShuttle(routeId)
    local route = Config.ShuttleRoutes[routeId]
    if not route then return nil end

    -- Check first stop has valid coords
    local startStop = route.stops[1]
    if not startStop or (startStop.coords.x == 0 and startStop.coords.y == 0) then
        Transit.Debug('Invalid start stop for route:', routeId)
        return nil
    end

    -- Generate ID
    local shuttleId = GenerateShuttleId()

    -- Create shuttle data
    local shuttleData = {
        id = shuttleId,
        routeId = routeId,
        startStop = startStop.id,
        currentStop = startStop.id,
        status = 'spawning',
        spawnTime = os.time(),
        passengers = 0
    }

    -- Elect ONE client to create the shuttle. This was broadcast to -1 and every
    -- client created its own NETWORKED bus, so N players meant N duplicate buses
    -- stacked at the first stop, each independently driving the route.
    local spawnCoords = vector3(startStop.coords.x, startStop.coords.y, startStop.coords.z or 0.0)
    local owner, ownerDist = nil, math.huge
    for _, pid in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(pid)
        if ped and ped ~= 0 then
            local d = #(GetEntityCoords(ped) - spawnCoords)
            if d < ownerDist then owner, ownerDist = tonumber(pid), d end
        end
    end

    -- Nobody near enough to stream it in; don't register a shuttle that can't exist
    if not owner or ownerDist > (Config.ShuttleSpawnRadius or 400.0) then
        return nil
    end

    shuttleData.owner = owner

    -- Register shuttle
    ActiveShuttles[shuttleId] = shuttleData

    -- Notify the elected client to spawn
    TriggerClientEvent('dps-transit:client:spawnShuttle', owner, shuttleId, shuttleData)

    Transit.Debug('Spawned shuttle:', shuttleId, 'on route', routeId)

    return shuttleId
end

-- Reap stale shuttles. Clients never report route completion, so without this
-- ActiveShuttles filled to the per-route cap and shuttle service stopped for good.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local maxAge = Config.ShuttleMaxAge or 3600
        for id, s in pairs(ActiveShuttles) do
            local stale = (s.spawnTime and (now - s.spawnTime) > maxAge)
            local ownerGone = (s.owner and GetPlayerName(s.owner) == nil)
            if stale or ownerGone then
                ActiveShuttles[id] = nil
                TriggerClientEvent('dps-transit:client:removeShuttle', -1, id)
            end
        end
    end
end)

-- Remove shuttle
function RemoveShuttle(shuttleId)
    local shuttle = ActiveShuttles[shuttleId]
    if shuttle then
        Transit.Debug('Removing shuttle:', shuttleId)

        ActiveShuttles[shuttleId] = nil

        TriggerClientEvent('dps-transit:client:removeShuttle', -1, shuttleId)
    end
end

-----------------------------------------------------------
-- SHUTTLE STATE HANDLERS
-----------------------------------------------------------

-- Shuttle arrived at stop
RegisterNetEvent('dps-transit:server:shuttleAtStop', function(shuttleId, stopId)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle then return end

    shuttle.currentStop = stopId
    shuttle.status = 'boarding'

    Transit.Debug('Shuttle', shuttleId, 'at stop:', stopId)

    TriggerEvent('dps-transit:shuttleArrived', shuttleId, stopId)
end)

-- Shuttle departing stop
RegisterNetEvent('dps-transit:server:shuttleDeparting', function(shuttleId, stopId)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle then return end

    shuttle.status = 'driving'

    Transit.Debug('Shuttle', shuttleId, 'departing:', stopId)

    TriggerEvent('dps-transit:shuttleDeparted', shuttleId, stopId)
end)

-- Update shuttle position
RegisterNetEvent('dps-transit:server:updateShuttlePosition', function(shuttleId, position)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle then return end

    shuttle.currentPosition = position
end)

-----------------------------------------------------------
-- CALLBACKS
-----------------------------------------------------------

-- Get active shuttles
lib.callback.register('dps-transit:server:getActiveShuttles', function(source)
    return ActiveShuttles
end)

-- Get shuttle schedule
lib.callback.register('dps-transit:server:getShuttleSchedule', function(source, routeId)
    local route = Config.ShuttleRoutes[routeId]
    if not route or not route.enabled then return nil end

    local nextTime = GetNextShuttleTime(routeId)

    return {
        routeId = routeId,
        name = route.name,
        shortName = route.shortName,
        frequency = route.schedule.frequency,
        nextDeparture = nextTime,
        activeShuttles = CountActiveShuttles(routeId),
        stops = route.stops
    }
end)

-- Get all shuttle routes
lib.callback.register('dps-transit:server:getShuttleRoutes', function(source)
    local routes = {}

    for routeId, route in pairs(Config.ShuttleRoutes) do
        if route.enabled then
            routes[routeId] = {
                name = route.name,
                shortName = route.shortName,
                priority = route.priority,
                frequency = route.schedule.frequency,
                stops = #route.stops,
                active = CountActiveShuttles(routeId)
            }
        end
    end

    return routes
end)

-----------------------------------------------------------
-- PASSENGER EVENTS
-----------------------------------------------------------

-- Player boarding shuttle
RegisterNetEvent('dps-transit:server:boardShuttle', function(shuttleId)
    local source = source
    local shuttle = ActiveShuttles[shuttleId]

    if not shuttle then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Error',
            description = 'Shuttle not found',
            type = 'error'
        })
        return
    end

    -- No fare for shuttle (free transfer)
    shuttle.passengers = (shuttle.passengers or 0) + 1

    Transit.Debug('Player', source, 'boarded shuttle', shuttleId)

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Shuttle',
        description = 'Free transfer service',
        type = 'success',
        duration = 3000
    })
end)

-- Player exiting shuttle
RegisterNetEvent('dps-transit:server:exitShuttle', function(shuttleId)
    local source = source
    local shuttle = ActiveShuttles[shuttleId]

    if shuttle then
        shuttle.passengers = math.max(0, (shuttle.passengers or 1) - 1)
        Transit.Debug('Player', source, 'exited shuttle', shuttleId)
    end
end)

-----------------------------------------------------------
-- ADMIN COMMANDS
-----------------------------------------------------------

-- Force spawn shuttle
RegisterNetEvent('dps-transit:server:adminSpawnShuttle', function(routeId)
    local source = source

    if not IsPlayerAceAllowed(source, 'command') then
        return
    end

    local shuttleId = SpawnShuttle(routeId)

    if shuttleId then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Shuttle Spawned',
            description = 'ID: ' .. shuttleId,
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Spawn Failed',
            description = 'Check route configuration',
            type = 'error'
        })
    end
end)

-- Remove all shuttles on route
RegisterNetEvent('dps-transit:server:adminClearShuttles', function(routeId)
    local source = source

    if not IsPlayerAceAllowed(source, 'command') then
        return
    end

    local count = 0
    for shuttleId, shuttle in pairs(ActiveShuttles) do
        if not routeId or shuttle.routeId == routeId then
            RemoveShuttle(shuttleId)
            count = count + 1
        end
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Shuttles Cleared',
        description = 'Removed ' .. count .. ' shuttles',
        type = 'success'
    })
end)

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------

exports('SpawnShuttle', SpawnShuttle)
exports('RemoveShuttle', RemoveShuttle)
exports('GetActiveShuttles', function() return ActiveShuttles end)
exports('CountActiveShuttles', CountActiveShuttles)
