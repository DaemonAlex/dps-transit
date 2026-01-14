--[[
    DPS-Transit Shared Functions
    Utilities available on both client and server
]]

Transit = Transit or {}

-- Generate unique train ID
function Transit.GenerateTrainId()
    return 'TRN-' .. math.random(10000, 99999) .. '-' .. os.time()
end

-- Generate ticket ID
function Transit.GenerateTicketId()
    return 'TKT-' .. math.random(100000, 999999)
end

-- Calculate fare between two stations
function Transit.CalculateFare(fromStation, toStation)
    local fromZone = GetStationZone(fromStation)
    local toZone = GetStationZone(toStation)

    if not fromZone or not toZone then
        return Config.Fares.sameZone
    end

    if fromZone == toZone then
        return Config.Fares.sameZone
    end

    local fromIndex = Config.ZoneIndex[fromZone]
    local toIndex = Config.ZoneIndex[toZone]
    local zoneDiff = math.abs(fromIndex - toIndex)

    if zoneDiff == 1 then
        return Config.Fares.oneZone
    else
        return Config.Fares.twoZones
    end
end

-- Get current schedule period (peak/offPeak/night)
function Transit.GetSchedulePeriod(hour)
    hour = hour or (IsDuplicityVersion() and os.date("*t").hour or GetClockHours())

    local peak = Config.Schedule.peak.hours
    local night = Config.Schedule.night.hours

    -- Check peak hours
    if (hour >= peak.morning.start and hour < peak.morning.stop) or
       (hour >= peak.evening.start and hour < peak.evening.stop) then
        return 'peak'
    end

    -- Check night hours
    if hour >= night.start or hour < night.stop then
        return 'night'
    end

    return 'offPeak'
end

-- Get schedule config for current period
function Transit.GetScheduleConfig(hour)
    local period = Transit.GetSchedulePeriod(hour)
    return Config.Schedule[period]
end

-- Format time (seconds to MM:SS or HH:MM:SS)
function Transit.FormatTime(seconds)
    if seconds < 0 then seconds = 0 end

    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, mins, secs)
    else
        return string.format("%d:%02d", mins, secs)
    end
end

-- Format ETA for display
function Transit.FormatETA(seconds)
    if seconds < 60 then
        return "Arriving"
    elseif seconds < 120 then
        return "1 min"
    else
        return math.floor(seconds / 60) .. " mins"
    end
end

-- Get direction name
function Transit.GetDirectionName(direction)
    if direction then
        return "Northbound to Roxwood"
    else
        return "Southbound to LSIA"
    end
end

-- Get final destination based on direction
function Transit.GetFinalDestination(direction)
    if direction then
        return 'roxwood'
    else
        return 'lsia'
    end
end

-- Check if station is valid
function Transit.IsValidStation(stationId)
    return Config.Stations[stationId] ~= nil
end

-- Get station by name (partial match)
function Transit.FindStation(searchTerm)
    searchTerm = string.lower(searchTerm)

    for stationId, station in pairs(Config.Stations) do
        if string.find(string.lower(station.name), searchTerm) or
           string.find(string.lower(station.shortName), searchTerm) or
           string.find(string.lower(stationId), searchTerm) then
            return stationId, station
        end
    end

    return nil
end

-- Get station index in route
function Transit.GetStationIndex(stationId)
    for i, id in ipairs(Config.StationOrder) do
        if id == stationId then
            return i
        end
    end
    return 0
end

-- Check if train will stop at station
function Transit.TrainWillStopAt(trainDirection, currentStation, targetStation)
    local currentIdx = Transit.GetStationIndex(currentStation)
    local targetIdx = Transit.GetStationIndex(targetStation)

    if trainDirection then  -- Northbound
        return targetIdx > currentIdx
    else  -- Southbound
        return targetIdx < currentIdx
    end
end

-- Calculate distance between two vectors
function Transit.GetDistance(pos1, pos2)
    return #(vector3(pos1.x, pos1.y, pos1.z) - vector3(pos2.x, pos2.y, pos2.z))
end

-- Get nearest station to coordinates
function Transit.GetNearestStation(coords)
    local nearestId = nil
    local nearestDist = math.huge

    for stationId, station in pairs(Config.Stations) do
        local dist = Transit.GetDistance(coords, station.platform.xyz)
        if dist < nearestDist then
            nearestDist = dist
            nearestId = stationId
        end
    end

    return nearestId, nearestDist
end

-- Debug print
function Transit.Debug(...)
    if Config.Debug then
        print('[dps-transit]', ...)
    end
end

-- Table utilities
function Transit.TableContains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

function Transit.TableLength(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Deep copy table
function Transit.DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in next, orig, nil do
            copy[Transit.DeepCopy(k)] = Transit.DeepCopy(v)
        end
        setmetatable(copy, Transit.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-----------------------------------------------------------
-- CONFIG VALIDATION (Server-side startup check)
-----------------------------------------------------------

-- Validate station configuration on startup
function Transit.ValidateStationConfig()
    local errors = {}
    local warnings = {}

    for stationId, station in pairs(Config.Stations) do
        -- Check required fields
        if not station.platform then
            table.insert(errors, '[' .. stationId .. '] Missing platform coordinates')
        elseif station.platform.x == 0 and station.platform.y == 0 then
            table.insert(warnings, '[' .. stationId .. '] Platform coords are (0,0,0) - station disabled')
        end

        if not station.kiosk then
            table.insert(warnings, '[' .. stationId .. '] Missing kiosk coordinates')
        end

        if not station.waitingArea then
            table.insert(warnings, '[' .. stationId .. '] Missing waitingArea coordinates')
        end

        if not station.zone then
            table.insert(errors, '[' .. stationId .. '] Missing zone assignment')
        end

        if station.track == nil then
            table.insert(errors, '[' .. stationId .. '] Missing track assignment')
        end

        if not station.name or not station.shortName then
            table.insert(errors, '[' .. stationId .. '] Missing name or shortName')
        end
    end

    -- Validate lines
    if Config.Lines then
        for lineId, line in pairs(Config.Lines) do
            if not line.track then
                table.insert(errors, '[Line: ' .. lineId .. '] Missing track assignment')
            end

            if not line.terminus or not line.terminus.south or not line.terminus.north then
                table.insert(errors, '[Line: ' .. lineId .. '] Missing terminus stations')
            end

            -- Check terminus stations exist
            if line.terminus then
                if line.terminus.south and not Config.Stations[line.terminus.south] then
                    table.insert(errors, '[Line: ' .. lineId .. '] South terminus "' .. line.terminus.south .. '" not found in stations')
                end
                if line.terminus.north and not Config.Stations[line.terminus.north] then
                    table.insert(warnings, '[Line: ' .. lineId .. '] North terminus "' .. line.terminus.north .. '" not found (may be expansion)')
                end
            end
        end
    end

    -- Validate shuttle routes
    if Config.ShuttleRoutes then
        for routeId, route in pairs(Config.ShuttleRoutes) do
            if route.enabled then
                for i, stop in ipairs(route.stops) do
                    if stop.coords.x == 0 and stop.coords.y == 0 then
                        table.insert(warnings, '[Shuttle ' .. routeId .. '] Stop #' .. i .. ' has no coords - route may fail')
                    end
                end
            end
        end
    end

    -- Print results
    if #errors > 0 then
        print('^1[dps-transit] CONFIG ERRORS:^0')
        for _, err in ipairs(errors) do
            print('^1  ERROR: ' .. err .. '^0')
        end
    end

    if #warnings > 0 then
        print('^3[dps-transit] CONFIG WARNINGS:^0')
        for _, warn in ipairs(warnings) do
            print('^3  WARN: ' .. warn .. '^0')
        end
    end

    if #errors == 0 and #warnings == 0 then
        print('^2[dps-transit] Config validation passed!^0')
    end

    return #errors == 0, errors, warnings
end

-----------------------------------------------------------
-- DISTANCE-BASED WAIT SCALING
-----------------------------------------------------------

-- Calculate appropriate wait time based on player distance to nearest station
function Transit.GetScaledWait(baseWait, playerCoords)
    if not playerCoords then
        return baseWait
    end

    local _, nearestDist = Transit.GetNearestStation(playerCoords)

    -- Scale wait time based on distance
    -- Close (< 100m): base wait
    -- Medium (100-500m): 2x wait
    -- Far (500-1000m): 5x wait
    -- Very far (> 1000m): 10x wait

    if nearestDist < 100.0 then
        return baseWait
    elseif nearestDist < 500.0 then
        return baseWait * 2
    elseif nearestDist < 1000.0 then
        return baseWait * 5
    else
        return baseWait * 10
    end
end

-----------------------------------------------------------
-- TICKET TIMESTAMP UTILITIES
-----------------------------------------------------------

-- Get server timestamp for tickets
function Transit.GetServerTimestamp()
    return os.time()
end

-- Check if ticket is expired
function Transit.IsTicketExpired(ticket)
    if not ticket or not ticket.expiresAt then
        return true
    end

    return os.time() > ticket.expiresAt
end

-- Validate day pass against server time
function Transit.IsDayPassValid(dayPass)
    if not dayPass then return false end

    local now = os.time()
    local purchaseTime = dayPass.purchaseTime or 0
    local validFor = 24 * 60 * 60  -- 24 hours in seconds

    return (now - purchaseTime) < validFor
end

-----------------------------------------------------------
-- STATION TYPE HELPERS
-----------------------------------------------------------

-- Check if station accepts passenger service
function Transit.StationAcceptsPassenger(stationId)
    local station = Config.Stations[stationId]
    if not station then return false end

    -- Check if explicitly marked as freight-only
    if station.features and station.features.freightOnly then
        return false
    end

    return true
end

-- Check if station accepts freight
function Transit.StationAcceptsFreight(stationId)
    local station = Config.Stations[stationId]
    if not station then return false end

    -- Check if explicitly marked as passenger-only
    if station.features and station.features.passengerOnly then
        return false
    end

    return true
end

-- Get valid next station for train type
function Transit.GetNextValidStation(currentStation, direction, trainType)
    local station = Config.Stations[currentStation]
    if not station then return nil end

    local nextId = direction and station.next or station.prev

    while nextId do
        local nextStation = Config.Stations[nextId]
        if not nextStation then break end

        -- Check if this station accepts our train type
        if trainType == 'passenger' and Transit.StationAcceptsPassenger(nextId) then
            return nextId
        elseif trainType == 'freight' and Transit.StationAcceptsFreight(nextId) then
            return nextId
        end

        -- Skip this station, try the next one
        nextId = direction and nextStation.next or nextStation.prev
    end

    return nil
end
