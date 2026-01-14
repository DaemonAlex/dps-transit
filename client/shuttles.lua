--[[
    DPS-Transit Shuttle Bus Client
    Handles AI-driven shuttle bus spawning and management
]]

-- Active shuttles
local ActiveShuttles = {}

-- Shuttle blips
local ShuttleBlips = {}

-- Stop blips
local ShuttleStopBlips = {}

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------

CreateThread(function()
    if not Config.Shuttles.enabled then
        Transit.Debug('Shuttle system disabled')
        return
    end

    Wait(3000)  -- Wait for train system to init

    -- Create stop blips
    CreateShuttleStopBlips()

    Transit.Debug('Shuttle client initialized')
end)

-- Create blips for shuttle stops
function CreateShuttleStopBlips()
    for routeId, route in pairs(Config.ShuttleRoutes) do
        if route.enabled then
            for _, stop in ipairs(route.stops) do
                -- Skip if coords not set
                if stop.coords.x == 0 and stop.coords.y == 0 then
                    goto continue
                end

                local blip = AddBlipForCoord(stop.coords.xyz)
                SetBlipSprite(blip, Config.Shuttles.blips.sprite)
                SetBlipColour(blip, 5)  -- Yellow for bus stops
                SetBlipScale(blip, Config.Shuttles.blips.scale)
                SetBlipAsShortRange(blip, Config.Shuttles.blips.shortRange)

                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(stop.name)
                EndTextCommandSetBlipName(blip)

                ShuttleStopBlips[stop.id] = blip

                ::continue::
            end
        end
    end

    Transit.Debug('Created shuttle stop blips')
end

-----------------------------------------------------------
-- SHUTTLE SPAWNING
-----------------------------------------------------------

-- Spawn shuttle (called from server)
RegisterNetEvent('dps-transit:client:spawnShuttle', function(shuttleId, shuttleData)
    local route = Config.ShuttleRoutes[shuttleData.routeId]
    if not route then return end

    local startStop = route.stops[1]
    if not startStop or (startStop.coords.x == 0 and startStop.coords.y == 0) then
        Transit.Debug('Invalid start stop for shuttle:', shuttleId)
        return
    end

    local busConfig = GetBusModelForRoute(shuttleData.routeId)
    local model = busConfig and busConfig.model or 'bus'

    -- Request model
    local modelHash = GetHashKey(model)
    RequestModel(modelHash)

    local timeout = 0
    while not HasModelLoaded(modelHash) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            Transit.Debug('Failed to load bus model:', model)
            return
        end
    end

    -- Create bus
    local bus = CreateVehicle(
        modelHash,
        startStop.coords.x,
        startStop.coords.y,
        startStop.coords.z,
        startStop.coords.w,
        true,
        false
    )

    if not DoesEntityExist(bus) then
        Transit.Debug('Failed to create shuttle bus')
        return
    end

    -- Set vehicle properties
    SetVehicleEngineOn(bus, true, true, false)
    SetVehicleDoorsLocked(bus, 0)
    SetEntityAsMissionEntity(bus, true, true)

    -- Create driver
    local driverHash = GetHashKey('s_m_m_gentransport')
    RequestModel(driverHash)
    while not HasModelLoaded(driverHash) do Wait(10) end

    local driver = CreatePedInsideVehicle(
        bus,
        4,  -- PED_TYPE_CIVMALE
        driverHash,
        -1,
        true,
        false
    )

    if DoesEntityExist(driver) then
        SetDriverAbility(driver, 1.0)
        SetDriverAggressiveness(driver, 0.0)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetPedCanBeDraggedOut(driver, false)
        SetEntityInvincible(driver, true)
    end

    -- Store shuttle
    ActiveShuttles[shuttleId] = {
        vehicle = bus,
        driver = driver,
        data = shuttleData,
        currentStopIndex = 1,
        status = 'departing'
    }

    -- Create blip
    CreateShuttleBlip(shuttleId, bus, shuttleData.routeId)

    -- Start AI driving
    DriveShuttleRoute(shuttleId)

    Transit.Debug('Spawned shuttle:', shuttleId, 'on route', shuttleData.routeId)
end)

-- Create blip for shuttle
function CreateShuttleBlip(shuttleId, entity, routeId)
    if ShuttleBlips[shuttleId] then
        RemoveBlip(ShuttleBlips[shuttleId])
    end

    local blip = AddBlipForEntity(entity)
    SetBlipSprite(blip, Config.Shuttles.blips.sprite)
    SetBlipColour(blip, 5)  -- Yellow
    SetBlipScale(blip, Config.Shuttles.blips.scale)
    SetBlipAsShortRange(blip, Config.Shuttles.blips.shortRange)

    local route = Config.ShuttleRoutes[routeId]
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(route and route.shortName or 'Shuttle')
    EndTextCommandSetBlipName(blip)

    ShuttleBlips[shuttleId] = blip
end

-----------------------------------------------------------
-- AI DRIVING
-----------------------------------------------------------

-- Drive shuttle along route
function DriveShuttleRoute(shuttleId)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle then return end

    local route = Config.ShuttleRoutes[shuttle.data.routeId]
    if not route then return end

    CreateThread(function()
        while ActiveShuttles[shuttleId] do
            local shuttle = ActiveShuttles[shuttleId]
            if not shuttle or not DoesEntityExist(shuttle.vehicle) then
                break
            end

            local driver = shuttle.driver
            if not DoesEntityExist(driver) then break end

            -- Get next stop
            local nextIndex = shuttle.currentStopIndex + 1
            if nextIndex > #route.stops then
                nextIndex = 1  -- Loop back to start
            end

            local nextStop = route.stops[nextIndex]
            if not nextStop or (nextStop.coords.x == 0 and nextStop.coords.y == 0) then
                Wait(5000)
                goto continue
            end

            shuttle.status = 'driving'

            -- Drive to next stop using waypoints
            local waypoints = route.waypoints or {}
            local currentPos = GetEntityCoords(shuttle.vehicle)

            -- Drive through waypoints first
            for _, waypoint in ipairs(waypoints) do
                if not ActiveShuttles[shuttleId] then break end

                TaskVehicleDriveToCoordLongrange(
                    driver,
                    shuttle.vehicle,
                    waypoint.x,
                    waypoint.y,
                    waypoint.z,
                    Config.Shuttles.defaults.speed,
                    786603,  -- Normal driving
                    10.0
                )

                -- Wait until near waypoint
                while ActiveShuttles[shuttleId] do
                    local pos = GetEntityCoords(shuttle.vehicle)
                    if #(pos - waypoint) < 20.0 then
                        break
                    end
                    Wait(500)
                end
            end

            if not ActiveShuttles[shuttleId] then break end

            -- Drive to stop
            TaskVehicleDriveToCoordLongrange(
                driver,
                shuttle.vehicle,
                nextStop.coords.x,
                nextStop.coords.y,
                nextStop.coords.z,
                Config.Shuttles.defaults.speed,
                786603,
                5.0
            )

            -- Wait until at stop
            local stuckTimer = 0
            local lastPos = GetEntityCoords(shuttle.vehicle)

            while ActiveShuttles[shuttleId] do
                local pos = GetEntityCoords(shuttle.vehicle)

                if #(pos - nextStop.coords.xyz) < 15.0 then
                    break
                end

                -- Check if stuck
                if #(pos - lastPos) < 0.5 then
                    stuckTimer = stuckTimer + 1
                    if stuckTimer > 20 then
                        Transit.Debug('Shuttle stuck, teleporting to next stop')
                        SetEntityCoords(shuttle.vehicle, nextStop.coords.x, nextStop.coords.y, nextStop.coords.z, false, false, false, false)
                        SetEntityHeading(shuttle.vehicle, nextStop.coords.w)
                        break
                    end
                else
                    stuckTimer = 0
                end

                lastPos = pos
                Wait(500)
            end

            if not ActiveShuttles[shuttleId] then break end

            -- Arrived at stop
            shuttle.currentStopIndex = nextIndex
            shuttle.status = 'boarding'

            -- Stop and wait
            TaskVehicleTempAction(driver, shuttle.vehicle, 1, 1000)  -- Brake

            -- Announce arrival
            AnnounceShuttleArrival(shuttleId, nextStop)

            -- Wait at stop
            Wait(Config.Shuttles.defaults.stopDuration * 1000)

            ::continue::
        end

        Transit.Debug('Shuttle route loop ended:', shuttleId)
    end)
end

-- Announce shuttle arrival
function AnnounceShuttleArrival(shuttleId, stop)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle then return end

    local route = Config.ShuttleRoutes[shuttle.data.routeId]
    local playerCoords = GetEntityCoords(PlayerPedId())
    local stopCoords = stop.coords.xyz

    if #(playerCoords - stopCoords) < 50.0 then
        lib.notify({
            title = 'Shuttle',
            description = route.shortName .. ' arrived at ' .. stop.name,
            type = 'inform',
            duration = 3000,
            icon = 'bus'
        })
    end
end

-----------------------------------------------------------
-- SHUTTLE REMOVAL
-----------------------------------------------------------

-- Remove shuttle (called from server)
RegisterNetEvent('dps-transit:client:removeShuttle', function(shuttleId)
    local shuttle = ActiveShuttles[shuttleId]
    if shuttle then
        if DoesEntityExist(shuttle.driver) then
            DeleteEntity(shuttle.driver)
        end
        if DoesEntityExist(shuttle.vehicle) then
            DeleteEntity(shuttle.vehicle)
        end
        ActiveShuttles[shuttleId] = nil
    end

    if ShuttleBlips[shuttleId] then
        RemoveBlip(ShuttleBlips[shuttleId])
        ShuttleBlips[shuttleId] = nil
    end

    Transit.Debug('Removed shuttle:', shuttleId)
end)

-----------------------------------------------------------
-- SHUTTLE INTERACTION
-----------------------------------------------------------

-- Check if player can board shuttle
function CanBoardShuttle(shuttleId)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle then return false end

    -- Check if shuttle is at a stop
    if shuttle.status ~= 'boarding' then return false end

    -- Check distance
    local playerCoords = GetEntityCoords(PlayerPedId())
    local busCoords = GetEntityCoords(shuttle.vehicle)

    return #(playerCoords - busCoords) < 5.0
end

-- Board shuttle
function BoardShuttle(shuttleId)
    local shuttle = ActiveShuttles[shuttleId]
    if not shuttle or not CanBoardShuttle(shuttleId) then return false end

    local ped = PlayerPedId()
    local bus = shuttle.vehicle

    -- Find empty seat
    for seat = 0, 15 do
        if IsVehicleSeatFree(bus, seat) then
            TaskWarpPedIntoVehicle(ped, bus, seat)
            PlayerState.currentShuttle = shuttleId
            return true
        end
    end

    lib.notify({
        title = 'Shuttle Full',
        description = 'This shuttle is at capacity',
        type = 'error',
        duration = 3000
    })

    return false
end

-- Exit shuttle
function ExitShuttle()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 0)
        PlayerState.currentShuttle = nil
    end
end

-----------------------------------------------------------
-- SHUTTLE TARGET ZONES
-----------------------------------------------------------

CreateThread(function()
    Wait(5000)

    if not Config.Shuttles.enabled then return end

    -- Create target zones at each stop
    for routeId, route in pairs(Config.ShuttleRoutes) do
        if route.enabled then
            for _, stop in ipairs(route.stops) do
                if stop.coords.x ~= 0 and stop.coords.y ~= 0 then
                    exports.ox_target:addSphereZone({
                        coords = stop.waitingArea,
                        radius = 3.0,
                        debug = Config.Debug,
                        options = {
                            {
                                name = 'shuttle_wait_' .. stop.id,
                                icon = 'fas fa-bus',
                                label = 'Wait for ' .. route.shortName,
                                onSelect = function()
                                    WaitForShuttle(routeId, stop.id)
                                end
                            },
                            {
                                name = 'shuttle_info_' .. stop.id,
                                icon = 'fas fa-info-circle',
                                label = 'View Schedule',
                                onSelect = function()
                                    ShowShuttleSchedule(routeId)
                                end
                            }
                        }
                    })
                end
            end
        end
    end

    Transit.Debug('Created shuttle stop target zones')
end)

-- Wait for shuttle at stop
function WaitForShuttle(routeId, stopId)
    local nextTime = GetNextShuttleTime(routeId)

    if not nextTime then
        lib.notify({
            title = 'No Service',
            description = 'No shuttle service at this time',
            type = 'error',
            duration = 3000
        })
        return
    end

    local currentMinute = tonumber(os.date('%M'))
    local waitMinutes = nextTime - currentMinute
    if waitMinutes < 0 then waitMinutes = waitMinutes + 60 end

    lib.notify({
        title = 'Shuttle Coming',
        description = 'Next shuttle in ' .. waitMinutes .. ' minutes',
        type = 'inform',
        duration = 5000,
        icon = 'bus'
    })
end

-- Show shuttle schedule
function ShowShuttleSchedule(routeId)
    local route = Config.ShuttleRoutes[routeId]
    if not route then return end

    local nextTime = GetNextShuttleTime(routeId)
    local frequency = route.schedule.frequency

    lib.alertDialog({
        header = route.name .. ' Schedule',
        content = [[
**Route:** ]] .. route.shortName .. [[

**Frequency:** Every ]] .. frequency .. [[ minutes

**Next Shuttle:** :]] .. (nextTime and string.format('%02d', nextTime) or 'N/A') .. [[

**Stops:**
]] .. table.concat(vim.tbl_map(function(s) return '- ' .. s.name end, route.stops) or {'Loading...'}, '\n'),
        centered = true
    })
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------

exports('GetActiveShuttles', function() return ActiveShuttles end)
exports('CanBoardShuttle', CanBoardShuttle)
exports('BoardShuttle', BoardShuttle)
exports('ExitShuttle', ExitShuttle)
