--[[
    DPS-Transit Client Main
    Core client-side functionality
]]

-- Local train entities
LocalTrains = {}

-- Station blips
StationBlips = {}

-- Train blips
TrainBlips = {}

-- Current player state
PlayerState = {
    currentTrain = nil,
    currentStation = nil,
    currentZone = nil,
    lastZoneCheck = 0,
    tickets = {}
}

-- Initialize client
CreateThread(function()
    Wait(1000)

    -- Enable tracks
    EnableTracks()

    -- Create station blips
    if Config.Features.mapBlips then
        CreateStationBlips()
    end

    -- Get existing trains from server
    local trains = lib.callback.await('dps-transit:server:getActiveTrains', false)
    if trains then
        for trainId, trainData in pairs(trains) do
            Transit.Debug('Syncing train:', trainId)
        end
    end

    Transit.Debug('Client initialized')
end)

-- Enable train tracks
function EnableTracks()
    -- Enable main tracks
    SwitchTrainTrack(Config.Tracks.mainLine, true)
    SwitchTrainTrack(Config.Tracks.metro, true)

    -- Enable Roxwood tracks
    SwitchTrainTrack(Config.Tracks.roxwoodFreight, true)
    SwitchTrainTrack(Config.Tracks.roxwoodPassenger, true)

    -- Disable random trains
    SetTrainTrackSpawnFrequency(Config.Tracks.mainLine, 0)
    SetTrainTrackSpawnFrequency(Config.Tracks.metro, 0)
    SetRandomTrains(false)

    Transit.Debug('Tracks enabled')
end

-- Create station blips
function CreateStationBlips()
    for stationId, station in pairs(Config.Stations) do
        -- Skip if coordinates not set (like Roxwood TBD)
        if station.platform.x == 0 and station.platform.y == 0 then
            goto continue
        end

        local blip = AddBlipForCoord(station.platform.xyz)

        SetBlipSprite(blip, Config.Blips.stations.sprite)

        -- Color by zone
        local zone = Config.Zones[station.zone]
        if zone then
            SetBlipColour(blip, zone.color)
        end

        local scale = (station.blip and station.blip.scale) or Config.Blips.stations.scale
        SetBlipScale(blip, scale)
        SetBlipAsShortRange(blip, Config.Blips.stations.shortRange)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(station.name)
        EndTextCommandSetBlipName(blip)

        StationBlips[stationId] = blip

        ::continue::
    end

    Transit.Debug('Created', Transit.TableLength(StationBlips), 'station blips')
end

-- Spawn train locally (called from server)
RegisterNetEvent('dps-transit:client:spawnTrain', function(trainId, trainData)
    local station = Config.Stations[trainData.startStation]
    if not station then return end

    local coords = station.platform
    local consist = trainData.consist
    local line = Config.Lines[trainData.lineId]

    -- Determine model and variation
    local model = Config.Train.model
    local variation = Config.Train.variation

    if consist then
        model = consist.locomotive or model
        variation = consist.variation or variation
    end

    -- Request model
    local modelHash = GetHashKey(model)
    RequestModel(modelHash)

    local timeout = 0
    while not HasModelLoaded(modelHash) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            Transit.Debug('Failed to load train model:', model)
            return
        end
    end

    -- Create the train
    local train = CreateMissionTrain(
        variation,
        coords.x,
        coords.y,
        coords.z,
        trainData.direction
    )

    if not DoesEntityExist(train) then
        Transit.Debug('Failed to create train')
        return
    end

    -- Set properties
    SetTrainSpeed(train, Config.Train.speed)
    SetTrainCruiseSpeed(train, Config.Train.cruiseSpeed)

    -- Store locally with type info
    LocalTrains[trainId] = {
        entity = train,
        data = trainData,
        trainType = trainData.trainType,
        lineId = trainData.lineId,
        canBoard = trainData.canBoard
    }

    -- Create blip with line color
    if Config.Features.mapBlips then
        local blipColor = line and line.color or (trainData.direction and 2 or 1)
        CreateTrainBlipWithType(trainId, train, trainData)
    end

    -- Log spawn type
    local typeLabel = trainData.trainType:upper()
    Transit.Debug('[' .. typeLabel .. '] Spawned:', trainId, 'on', trainData.lineId, 'entity:', train)
end)

-- Create blip for train with type info
function CreateTrainBlipWithType(trainId, entity, trainData)
    if TrainBlips[trainId] then
        RemoveBlip(TrainBlips[trainId])
    end

    local blip = AddBlipForEntity(entity)
    SetBlipSprite(blip, Config.Blips.trains.sprite)

    -- Color based on train type and line
    local line = Config.Lines[trainData.lineId]
    local color = line and line.color or 2

    -- Freight trains use different color
    if trainData.trainType == 'freight' then
        color = 1  -- Red for freight
    end

    SetBlipColour(blip, color)
    SetBlipScale(blip, Config.Blips.trains.scale)
    SetBlipAsShortRange(blip, Config.Blips.trains.shortRange)

    -- Build blip name
    local lineName = line and line.shortName or 'Train'
    local typeLabel = trainData.trainType == 'freight' and 'Freight' or 'Passenger'
    local destStation = trainData.direction and line.terminus.north or line.terminus.south
    local dest = Config.Stations[destStation]
    local destName = dest and dest.shortName or 'Unknown'

    BeginTextCommandSetBlipName('STRING')
    if trainData.trainType == 'freight' then
        AddTextComponentSubstringPlayerName(lineName .. ' Freight')
    else
        AddTextComponentSubstringPlayerName(lineName .. ' to ' .. destName)
    end
    EndTextCommandSetBlipName(blip)

    TrainBlips[trainId] = blip
end

-- Create blip for train
function CreateTrainBlip(trainId, entity, direction)
    if TrainBlips[trainId] then
        RemoveBlip(TrainBlips[trainId])
    end

    local blip = AddBlipForEntity(entity)
    SetBlipSprite(blip, Config.Blips.trains.sprite)
    SetBlipColour(blip, direction and 2 or 1)  -- Green north, Red south
    SetBlipScale(blip, Config.Blips.trains.scale)
    SetBlipAsShortRange(blip, Config.Blips.trains.shortRange)

    local destination = Transit.GetFinalDestination(direction)
    local destStation = Config.Stations[destination]
    local destName = destStation and destStation.shortName or 'Unknown'

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Train to ' .. destName)
    EndTextCommandSetBlipName(blip)

    TrainBlips[trainId] = blip
end

-- NOTE: Train removal handler moved to BLOCK SIGNALING section for proper cleanup

-- Train arrived at station
RegisterNetEvent('dps-transit:client:trainArrived', function(trainId, stationId)
    local train = LocalTrains[trainId]
    if not train then return end

    train.data.currentStation = stationId
    train.data.status = 'boarding'

    -- Play arrival sound/animation
    -- TODO: Add platform announcements

    Transit.Debug('Train', trainId, 'arrived at', stationId)
end)

-- Train departed station
RegisterNetEvent('dps-transit:client:trainDeparted', function(trainId, stationId)
    local train = LocalTrains[trainId]
    if not train then return end

    train.data.status = 'running'

    Transit.Debug('Train', trainId, 'departed', stationId)
end)

-- NOTE: trainPositionUpdate handler moved to BLOCK SIGNALING section for signal state integration

-- Station announcement
RegisterNetEvent('dps-transit:client:stationAnnouncement', function(data)
    if data.type == 'arrival' then
        lib.notify({
            title = 'Transit',
            description = data.message,
            type = 'inform',
            duration = 5000,
            icon = 'train'
        })

        -- Play xsound announcement if enabled
        if Config.Features.xsoundAnnouncements and Config.Audio.enabled then
            PlayStationAnnouncement('arrival', data.station)
        else
            -- Fallback to native sound
            PlaySoundFrontend(-1, "FLIGHT_INFO", "MP_MISSION_COUNTDOWN_SOUNDSET", false)
        end
    elseif data.type == 'departure' then
        lib.notify({
            title = 'Departing',
            description = 'Train departing for ' .. data.destination,
            type = 'warning',
            duration = 3000,
            icon = 'train'
        })

        if Config.Features.xsoundAnnouncements and Config.Audio.enabled then
            PlayStationAnnouncement('departure', data.station)
        end
    end
end)

-----------------------------------------------------------
-- XSOUND AUDIO ANNOUNCEMENTS
-----------------------------------------------------------

-- Play station announcement via xsound
function PlayStationAnnouncement(soundType, stationId)
    local station = Config.Stations[stationId]
    if not station then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local stationCoords = station.platform.xyz
    local distance = #(playerCoords - stationCoords)

    -- Only play if within range
    if distance > Config.Audio.range then return end

    local soundName = Config.Audio.sounds[soundType]
    local soundUrl = Config.Audio.urls[soundType]

    if not soundName or not soundUrl then return end

    -- Check if xsound is available
    if GetResourceState('xsound') == 'started' then
        local soundId = 'transit_' .. stationId .. '_' .. soundType

        -- Play positional audio at station
        exports.xsound:PlayUrlPos(soundId, soundUrl, Config.Audio.volume, stationCoords, false)

        -- Clean up after playback
        SetTimeout(5000, function()
            if exports.xsound:soundExists(soundId) then
                exports.xsound:Destroy(soundId)
            end
        end)
    end
end

-----------------------------------------------------------
-- JUNCTION TRACK SWITCHING
-----------------------------------------------------------

-- Handle track switch at junction
RegisterNetEvent('dps-transit:client:switchTrack', function(trainId, fromTrack, toTrack)
    local train = LocalTrains[trainId]
    if not train or not DoesEntityExist(train.entity) then return end

    Transit.Debug('Switching train', trainId, 'from track', fromTrack, 'to track', toTrack)

    -- Use native track switching
    SwitchTrainTrack(toTrack, true)

    -- Update local train data
    train.data.currentTrack = toTrack
end)

-----------------------------------------------------------
-- EMERGENCY HOLD SYSTEM (Client)
-----------------------------------------------------------

local EmergencyHoldActive = false

-- Handle emergency hold notification
RegisterNetEvent('dps-transit:client:emergencyHold', function(data)
    EmergencyHoldActive = data.active

    if data.active then
        lib.notify({
            title = 'TRANSIT ALERT',
            description = 'Service suspended at ' .. data.stationName .. ': ' .. data.reason,
            type = 'error',
            duration = 10000,
            icon = 'triangle-exclamation'
        })

        -- Show NUI emergency alert
        SendNUIMessage({
            action = 'showEmergencyAlert',
            message = data.reason,
            stationName = data.stationName
        })
    else
        lib.notify({
            title = 'Service Resumed',
            description = 'Normal train service resuming',
            type = 'success',
            duration = 5000
        })

        SendNUIMessage({ action = 'hideEmergencyAlert' })
    end
end)

-- Train held at station
RegisterNetEvent('dps-transit:client:trainHeld', function(trainId, stationId)
    local train = LocalTrains[trainId]
    if not train then return end

    train.data.status = 'held'

    -- Stop the train
    if DoesEntityExist(train.entity) then
        SetTrainSpeed(train.entity, 0.0)
        SetTrainCruiseSpeed(train.entity, 0.0)
    end

    Transit.Debug('Train', trainId, 'held at', stationId)
end)

-- Train released from hold
RegisterNetEvent('dps-transit:client:trainReleased', function(trainId)
    local train = LocalTrains[trainId]
    if not train then return end

    train.data.status = 'boarding'

    -- Resume train speed
    if DoesEntityExist(train.entity) then
        SetTrainSpeed(train.entity, Config.Train.speed)
        SetTrainCruiseSpeed(train.entity, Config.Train.cruiseSpeed)
    end

    Transit.Debug('Train', trainId, 'released from hold')
end)

-----------------------------------------------------------
-- ZONE CLIPPING SAFETY (MLO Portal Handling)
-----------------------------------------------------------

-- Safe teleport with ground check
function SafeTeleportToStation(stationId)
    if not Config.MLOSafety.enabled then return false end

    local station = Config.Stations[stationId]
    if not station then return false end

    local targetCoords = station.waitingArea
    if not targetCoords then return false end

    local ped = PlayerPedId()

    -- Check for MLO portal
    local portal = Config.MLOSafety.portals[stationId]
    if portal and portal.interiorId then
        -- Load interior first
        if not IsInteriorReady(portal.interiorId) then
            RequestScriptAudioBank(portal.interiorId, false)
            local timeout = 0
            while not IsInteriorReady(portal.interiorId) and timeout < 5000 do
                Wait(100)
                timeout = timeout + 100
            end
        end

        targetCoords = portal.exitCoords or targetCoords
    end

    -- Ground check to prevent falling through map
    local groundZ = 0.0
    local foundGround, z = GetGroundZFor_3dCoord(targetCoords.x, targetCoords.y, targetCoords.z + 10.0, false)

    if foundGround then
        groundZ = z
    else
        -- Use fallback offset
        groundZ = targetCoords.z + Config.MLOSafety.fallbackOffset.z
        Transit.Debug('Ground check failed at', stationId, '- using fallback')
    end

    -- Teleport with safe Z
    SetEntityCoords(ped, targetCoords.x, targetCoords.y, groundZ + 1.0, false, false, false, false)

    return true
end

-----------------------------------------------------------
-- TRAIN POSITION TRACKING WITH DISTANCE SCALING
-----------------------------------------------------------

-- Track announced stations to prevent repeat announcements
local AnnouncedStations = {}

CreateThread(function()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())

        -- Use distance-scaled wait time
        local waitTime = Transit.GetScaledWait(1000, playerCoords)

        for trainId, train in pairs(LocalTrains) do
            if DoesEntityExist(train.entity) then
                local pos = GetEntityCoords(train.entity)
                local progress = train.data.trackProgress or 0

                -- Update via state bag (more efficient than triggers)
                local bagName = 'transit:train:' .. trainId
                LocalPlayer.state:set(bagName, {
                    pos = pos,
                    progress = progress,
                    status = train.data.status
                }, true)

                -- Fallback trigger for server sync
                TriggerServerEvent('dps-transit:server:updateTrainPosition', trainId, pos, progress)

                -- Check if near station
                local nearStation, dist = Transit.GetNearestStation(pos)
                if dist < 30.0 and train.data.status == 'running' then
                    if nearStation ~= train.data.currentStation then
                        TriggerServerEvent('dps-transit:server:trainAtStation', trainId, nearStation)
                    end
                end

                -- Station approach announcement (only if player is on this train)
                if PlayerState.currentTrain == trainId and train.canBoard then
                    CheckStationApproach(trainId, train, nearStation, dist)
                end

                -- Speed smoothing for station approach
                if Config.Train.slowZone.enabled then
                    ApplySpeedSmoothing(train, nearStation, dist)
                end
            end
        end

        Wait(waitTime)
    end
end)

-----------------------------------------------------------
-- STATION AUDIO ANNOUNCEMENTS
-----------------------------------------------------------

-- Check for station approach and play announcements
function CheckStationApproach(trainId, train, nearStation, distance)
    if not nearStation or not train.canBoard then return end

    local station = Config.Stations[nearStation]
    if not station then return end

    local announceKey = trainId .. '_' .. nearStation

    -- Get destination for subtitle
    local line = Config.Lines[train.lineId]
    local destStation = train.data.direction and line.terminus.north or line.terminus.south
    local dest = Config.Stations[destStation]
    local destName = dest and dest.shortName or 'Unknown'

    -- Approaching announcement (150m - 80m)
    if distance < 150.0 and distance > 80.0 then
        if not AnnouncedStations[announceKey .. '_approach'] then
            AnnouncedStations[announceKey .. '_approach'] = true

            -- Play approach chime
            PlayStationChime('approach')

            -- Show NUI announcement banner
            SendNUIMessage({
                action = 'showAnnouncement',
                type = 'approach',
                title = 'Next Station',
                station = station.shortName or station.name,
                subtitle = 'Service to ' .. destName,
                duration = 5000
            })

            Transit.Debug('Announcement: Approaching', station.shortName)
        end
    end

    -- Arrival announcement (< 40m)
    if distance < 40.0 then
        if not AnnouncedStations[announceKey .. '_arrival'] then
            AnnouncedStations[announceKey .. '_arrival'] = true

            -- Play arrival bell
            PlayStationChime('arrival')

            -- Show NUI arrival announcement
            SendNUIMessage({
                action = 'showAnnouncement',
                type = 'arrival',
                title = 'Now Arriving',
                station = station.shortName or station.name,
                subtitle = 'Press E to exit',
                duration = 8000
            })

            Transit.Debug('Announcement: Arriving at', station.shortName)
        end
    end

    -- Clear announcements when train leaves station
    if distance > 200.0 then
        AnnouncedStations[announceKey .. '_approach'] = nil
        AnnouncedStations[announceKey .. '_arrival'] = nil

        -- Hide any lingering announcement
        SendNUIMessage({ action = 'hideAnnouncement' })
    end
end

-- Play station audio chimes
function PlayStationChime(chimeType)
    if chimeType == 'approach' then
        -- Approaching station - soft notification sound
        PlaySoundFrontend(-1, 'PIN_BUTTON', 'ATM_SOUNDS', true)
    elseif chimeType == 'arrival' then
        -- Arriving at station - door/bell sound
        PlaySoundFrontend(-1, 'FLIGHT_SCHOOL_LESSON_PASSED', 'HUD_AWARDS', true)
    elseif chimeType == 'departure' then
        -- Doors closing - warning tone
        PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    end
end

-- Train departure announcement (called from station boarding logic)
function AnnounceTrainDeparture(trainId, stationId)
    local train = LocalTrains[trainId]
    if not train or not train.canBoard then return end

    local station = Config.Stations[stationId]
    if not station then return end

    -- Get destination
    local line = Config.Lines[train.lineId]
    local destStation = train.data.direction and line.terminus.north or line.terminus.south
    local dest = Config.Stations[destStation]
    local destName = dest and dest.shortName or 'Unknown'

    -- Play departure chime
    PlayStationChime('departure')

    -- Show NUI departure announcement
    SendNUIMessage({
        action = 'showAnnouncement',
        type = 'departure',
        title = 'Doors Closing',
        station = 'Stand Clear',
        subtitle = 'Train to ' .. destName .. ' departing',
        duration = 3000
    })
end

-- Signal hold announcement (called when train is held at block signal)
function AnnounceSignalHold(trainId, segmentName, reason)
    -- Only announce to passengers on this train
    if PlayerState.currentTrain ~= trainId then return end

    local train = LocalTrains[trainId]
    if not train or not train.canBoard then return end

    -- Play hold notification sound
    PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    -- Show NUI held announcement (stays until cleared)
    SendNUIMessage({
        action = 'showAnnouncement',
        type = 'held',
        title = 'Signal Hold',
        station = segmentName or 'Current Section',
        subtitle = reason or 'Please stand by',
        duration = 0  -- Stays until manually cleared
    })
end

-- Clear signal hold announcement
function ClearSignalHoldAnnouncement()
    SendNUIMessage({ action = 'hideAnnouncement' })
end

-- Handle train arrival event
RegisterNetEvent('dps-transit:client:trainArrived', function(trainId, stationId)
    local train = LocalTrains[trainId]
    if train then
        train.data.currentStation = stationId
        train.data.status = 'boarding'
    end

    -- If player is on this train, announce arrival
    if PlayerState.currentTrain == trainId then
        local station = Config.Stations[stationId]
        if station then
            PlayStationChime('arrival')
        end
    end
end)

-- Handle train departure event
RegisterNetEvent('dps-transit:client:trainDeparted', function(trainId, stationId)
    local train = LocalTrains[trainId]
    if train then
        train.data.status = 'running'
    end

    -- If player is on this train, announce departure
    if PlayerState.currentTrain == trainId then
        AnnounceTrainDeparture(trainId, stationId)
    end

    -- Clear announcement flags
    local announceKey = trainId .. '_' .. stationId
    AnnouncedStations[announceKey .. '_approach'] = nil
    AnnouncedStations[announceKey .. '_arrival'] = nil
end)

-----------------------------------------------------------
-- SPEED SMOOTHING FOR STATION APPROACH
-----------------------------------------------------------

-- Smooth speed interpolation factors (0.0 - 1.0, higher = faster transition)
local SPEED_LERP_FACTOR = 0.15        -- Normal transitions
local CURVE_LERP_FACTOR = 0.35        -- Faster for curve/safety zones (prevents derailment)
local EMERGENCY_LERP_FACTOR = 0.5     -- Very fast for emergency speed changes

-- Linear interpolation helper
function Lerp(a, b, t)
    return a + (b - a) * math.min(1.0, math.max(0.0, t))
end

-- Track previous target speeds for smooth lerping
local TrainTargetSpeeds = {}
local TrainInSpeedZone = {}  -- Track if train is in a speed zone

function ApplySpeedSmoothing(train, nearStation, distance)
    if not DoesEntityExist(train.entity) then return end

    local trainId = nil
    for id, t in pairs(LocalTrains) do
        if t == train then
            trainId = id
            break
        end
    end

    -- SERVER AUTHORITY: If server says RED, don't override with client-side speed
    -- The server's block signaling system has ultimate authority over train stops
    if trainId then
        local signalState = TrainSignalStates[trainId]
        if signalState and signalState.signalState == 'red' then
            -- Server has authority - train should be stopped, don't apply distance-based speed
            Transit.Debug('ApplySpeedSmoothing skipped: Server RED signal for train', trainId)
            return
        end
    end

    local slowZone = Config.Train.slowZone
    local currentSpeed = GetEntitySpeed(train.entity)

    -- Get base speed for this track (if configured)
    local trackId = train.data.currentTrack or 0
    local baseSpeed = GetTrackBaseSpeed(trackId)

    local targetSpeed = baseSpeed
    local inSpeedZone = false

    -- Check for track-specific speed zones (bridges, curves, etc.)
    local zoneSpeed, zoneName = GetTrackZoneSpeed(trackId, GetEntityCoords(train.entity))
    if zoneSpeed then
        targetSpeed = math.min(targetSpeed, zoneSpeed)
        inSpeedZone = true
    end

    -- Determine target speed based on distance to station
    if distance < slowZone.platformDistance then
        -- At platform - very slow or stopped
        targetSpeed = slowZone.platformSpeed
    elseif distance < slowZone.approachDistance then
        -- Approaching - gradual slowdown
        local t = (distance - slowZone.platformDistance) / (slowZone.approachDistance - slowZone.platformDistance)
        targetSpeed = math.min(targetSpeed, slowZone.platformSpeed + (slowZone.approachSpeed - slowZone.platformSpeed) * t)
    elseif train.data.status == 'departing' and distance < slowZone.accelerateDistance then
        -- Just departed - accelerating
        local t = distance / slowZone.accelerateDistance
        targetSpeed = slowZone.platformSpeed + (baseSpeed - slowZone.platformSpeed) * t
    end

    -- Determine lerp factor based on context
    local lerpFactor = SPEED_LERP_FACTOR
    local wasInSpeedZone = TrainInSpeedZone[trainId]

    -- Use faster lerp when ENTERING a speed zone (critical for safety)
    if inSpeedZone and not wasInSpeedZone then
        lerpFactor = CURVE_LERP_FACTOR
        Transit.Debug('Train', trainId, 'entering speed zone - fast lerp active')
    elseif inSpeedZone then
        -- Already in zone, use moderate speed
        lerpFactor = CURVE_LERP_FACTOR
    end

    -- Track zone state
    if trainId then
        TrainInSpeedZone[trainId] = inSpeedZone
    end

    -- Apply smooth speed transition using Lerp
    -- This prevents jarring speed changes when transitioning between zones
    local previousTarget = TrainTargetSpeeds[trainId] or currentSpeed
    local smoothedSpeed = Lerp(previousTarget, targetSpeed, lerpFactor)

    -- Store for next frame
    if trainId then
        TrainTargetSpeeds[trainId] = smoothedSpeed
    end

    -- Apply speed if difference is significant
    if math.abs(currentSpeed - smoothedSpeed) > 0.5 then
        SetTrainSpeed(train.entity, smoothedSpeed)
        SetTrainCruiseSpeed(train.entity, smoothedSpeed)
    end
end

-- Clean up target speeds when train is removed
function ClearTrainTargetSpeed(trainId)
    TrainTargetSpeeds[trainId] = nil
end

-- Get base speed for a track
function GetTrackBaseSpeed(trackId)
    if Config.TrackSpeeds and Config.TrackSpeeds[trackId] then
        return Config.TrackSpeeds[trackId].default or Config.Train.speed
    end
    return Config.Train.speed
end

-- Pre-emptive approach distance for curve slowdown (meters)
-- Start slowing down BEFORE entering the zone to prevent derailment
local CURVE_APPROACH_DISTANCE = 50.0

-- Check if train is in or approaching a special speed zone on this track
-- Returns: speed, zoneName, isApproaching (or nil if not in zone)
function GetTrackZoneSpeed(trackId, position)
    if not Config.TrackSpeeds or not Config.TrackSpeeds[trackId] then
        return nil, nil, false
    end

    local zones = Config.TrackSpeeds[trackId].zones
    if not zones or #zones == 0 then
        return nil, nil, false
    end

    for _, zone in ipairs(zones) do
        -- Check if position is within zone radius of the zone area
        local zoneCenter = (zone.start + zone.finish) / 2
        local dist = #(position - zoneCenter)

        -- Check distance to zone START point for approach detection
        local distToStart = #(position - zone.start)

        if dist < zone.radius then
            -- Already in the zone
            Transit.Debug('Train in speed zone:', zone.name, '- max speed:', zone.maxSpeed)
            return zone.maxSpeed, zone.name, false
        elseif distToStart < (zone.radius + CURVE_APPROACH_DISTANCE) then
            -- Approaching the zone - start pre-emptive slowdown
            -- Interpolate speed based on approach distance
            local approachProgress = 1.0 - (distToStart - zone.radius) / CURVE_APPROACH_DISTANCE
            approachProgress = math.max(0.0, math.min(1.0, approachProgress))

            -- Blend between current track speed and zone max speed
            local trackSpeed = Config.TrackSpeeds[trackId].default or Config.Train.speed
            local approachSpeed = Lerp(trackSpeed, zone.maxSpeed, approachProgress)

            Transit.Debug('Approaching speed zone:', zone.name, '- distance:', math.floor(distToStart), 'm - speed:', math.floor(approachSpeed))
            return approachSpeed, zone.name, true
        end
    end

    return nil, nil, false
end

-----------------------------------------------------------
-- ENTITY CLEANUP (Ghost Train & Orphan Carriage Prevention)
-----------------------------------------------------------

CreateThread(function()
    if not Config.Train.cleanup or not Config.Train.cleanup.enabled then
        return
    end

    while true do
        Wait(Config.Train.cleanup.cleanupInterval * 1000)

        local now = os.time()
        local cleaned = 0

        for trainId, train in pairs(LocalTrains) do
            local shouldClean = false
            local reason = ''

            -- Check if entity no longer exists
            if not DoesEntityExist(train.entity) then
                shouldClean = true
                reason = 'entity deleted'
            end

            -- Check age
            if train.data.spawnTime then
                local age = now - train.data.spawnTime
                if age > Config.Train.cleanup.maxAge then
                    shouldClean = true
                    reason = 'max age exceeded (' .. age .. 's)'
                end
            end

            -- Cleanup
            if shouldClean then
                Transit.Debug('Cleaning up train:', trainId, '-', reason)

                if DoesEntityExist(train.entity) then
                    -- Delete the entire train consist including carriages
                    DeleteTrainWithCarriages(train.entity)
                end

                if TrainBlips[trainId] then
                    RemoveBlip(TrainBlips[trainId])
                    TrainBlips[trainId] = nil
                end

                LocalTrains[trainId] = nil
                cleaned = cleaned + 1

                -- Notify server
                TriggerServerEvent('dps-transit:server:trainCleaned', trainId, reason)
            end
        end

        if cleaned > 0 then
            Transit.Debug('Cleaned up', cleaned, 'trains')
        end

        -- Also check for orphan carriages (carriages without a locomotive)
        CleanupOrphanCarriages()
    end
end)

-- Delete train and all attached carriages
function DeleteTrainWithCarriages(trainEntity)
    if not DoesEntityExist(trainEntity) then return end

    -- Get all carriages attached to this train
    local carriages = {}
    local currentCarriage = trainEntity

    -- Walk through the train consist
    while currentCarriage and DoesEntityExist(currentCarriage) do
        table.insert(carriages, currentCarriage)

        -- Get next carriage in consist
        local nextCarriage = GetTrainCarriage(currentCarriage, 1)
        if nextCarriage == currentCarriage or nextCarriage == 0 then
            break
        end
        currentCarriage = nextCarriage
    end

    Transit.Debug('Deleting train with', #carriages, 'carriages')

    -- Delete all carriages (reverse order to avoid issues)
    for i = #carriages, 1, -1 do
        local carriage = carriages[i]
        if DoesEntityExist(carriage) then
            -- Remove any passengers first
            local maxSeats = GetVehicleMaxNumberOfPassengers(carriage)
            for seat = -1, maxSeats do
                local ped = GetPedInVehicleSeat(carriage, seat)
                if ped and DoesEntityExist(ped) and IsPedAPlayer(ped) then
                    TaskLeaveVehicle(ped, carriage, 16)
                end
            end

            SetEntityAsMissionEntity(carriage, false, true)
            DeleteMissionTrain(carriage)
        end
    end
end

-- Clean up orphan carriages (carriages without a locomotive)
function CleanupOrphanCarriages()
    local playerCoords = GetEntityCoords(PlayerPedId())

    -- Search for nearby vehicles that are train models
    local trainModels = {
        'metrotrain', 'freight', 'freightcar', 'freightcont1', 'freightcont2',
        'freightgrain', 'freighttrailer', 'tankercar', 'streakc', 'streak'
    }

    for _, modelName in ipairs(trainModels) do
        local modelHash = GetHashKey(modelName)

        -- Find vehicles of this model nearby
        local vehicle = GetClosestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 500.0, modelHash, 70)

        if vehicle and DoesEntityExist(vehicle) then
            -- Check if this is a known train
            local isKnown = false
            for trainId, train in pairs(LocalTrains) do
                if train.entity == vehicle then
                    isKnown = true
                    break
                end

                -- Check if it's a carriage of a known train
                local carriage = train.entity
                while carriage and DoesEntityExist(carriage) do
                    if carriage == vehicle then
                        isKnown = true
                        break
                    end
                    local nextCarriage = GetTrainCarriage(carriage, 1)
                    if nextCarriage == carriage or nextCarriage == 0 then
                        break
                    end
                    carriage = nextCarriage
                end

                if isKnown then break end
            end

            -- If not known and stationary for too long, it's orphaned
            if not isKnown then
                local speed = GetEntitySpeed(vehicle)
                if speed < 0.5 then
                    Transit.Debug('Found orphan carriage:', modelName, '- cleaning up')
                    SetEntityAsMissionEntity(vehicle, false, true)
                    DeleteVehicle(vehicle)
                end
            end
        end
    end
end

-- Proper cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    Transit.Debug('Resource stopping - cleaning up all trains')

    for trainId, train in pairs(LocalTrains) do
        if DoesEntityExist(train.entity) then
            DeleteMissionTrain(train.entity)
        end
    end

    for _, blip in pairs(TrainBlips) do
        RemoveBlip(blip)
    end

    for _, blip in pairs(StationBlips) do
        RemoveBlip(blip)
    end
end)

-----------------------------------------------------------
-- TICKET SWEEP SYSTEM (Zone Crossing Validation)
-----------------------------------------------------------

-- Track last confirmed zone crossing to prevent duplicate triggers
local LastZoneCrossing = {
    fromZone = nil,
    toZone = nil,
    timestamp = 0,
    stationId = nil
}

-- Minimum distance into new zone before triggering fare check (meters)
local ZONE_CROSSING_MIN_DISTANCE = 100.0

-- Minimum time at platform before confirming zone crossing (seconds)
local ZONE_CROSSING_PLATFORM_TIME = 5.0

-- Monitor zone crossings while player is on a train
CreateThread(function()
    while true do
        Wait(5000)  -- Check every 5 seconds

        -- Only check if player is on a train
        if not PlayerState.currentTrain then
            goto continue
        end

        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            PlayerState.currentTrain = nil
            PlayerState.currentZone = nil
            goto continue
        end

        -- SIGNAL HOLD PROTECTION: Skip zone check if train is held at signal
        -- This prevents false-positive fare validation when train is stopped at zone boundary
        local trainSignal = TrainSignalStates[PlayerState.currentTrain]
        if trainSignal and trainSignal.signalState == 'red' then
            Transit.Debug('Zone check skipped - train held at signal')
            goto continue
        end

        -- Get current position and determine zone
        local pos = GetEntityCoords(ped)
        local nearStation, dist = Transit.GetNearestStation(pos)

        if nearStation and dist < 500.0 then
            local station = Config.Stations[nearStation]
            local newZone = station and station.zone

            -- Check for zone transition
            if newZone and PlayerState.currentZone and newZone ~= PlayerState.currentZone then
                local train = LocalTrains[PlayerState.currentTrain]
                local trainSpeed = train and train.entity and GetEntitySpeed(train.entity) or 0

                -- CONDITION 1: Train must be moving (not stuck at boundary)
                if trainSpeed < 2.0 then
                    Transit.Debug('Zone check deferred - train nearly stopped:', trainSpeed, 'm/s')
                    goto continue
                end

                -- CONDITION 2: Check if train has actually arrived at platform in new zone
                -- OR is sufficiently far into the new zone
                local arrivedAtPlatform = false
                local deepInNewZone = false

                -- Check if at platform (near station waiting area)
                if station.waitingArea then
                    local distToPlatform = #(pos - station.waitingArea)
                    arrivedAtPlatform = distToPlatform < 50.0
                end

                -- Check if deep enough into new zone (not just at boundary)
                local zoneStations = Config.ZoneStations and Config.ZoneStations[newZone]
                if zoneStations then
                    for _, stationId in ipairs(zoneStations) do
                        local zoneStation = Config.Stations[stationId]
                        if zoneStation and zoneStation.platform then
                            local distToZoneStation = #(pos - vec3(zoneStation.platform.x, zoneStation.platform.y, zoneStation.platform.z))
                            if distToZoneStation < ZONE_CROSSING_MIN_DISTANCE then
                                deepInNewZone = true
                                break
                            end
                        end
                    end
                end

                -- CONDITION 3: Prevent duplicate triggers for same zone crossing
                local now = os.time()
                local isDuplicate = (LastZoneCrossing.fromZone == PlayerState.currentZone and
                                   LastZoneCrossing.toZone == newZone and
                                   (now - LastZoneCrossing.timestamp) < 60)

                if isDuplicate then
                    Transit.Debug('Zone check skipped - duplicate crossing within 60s')
                    goto continue
                end

                -- Only trigger if at platform OR deep in new zone
                if arrivedAtPlatform or deepInNewZone then
                    Transit.Debug('Zone crossing confirmed:', PlayerState.currentZone, '->', newZone,
                        arrivedAtPlatform and '(at platform)' or '(deep in zone)')

                    -- Record this crossing
                    LastZoneCrossing = {
                        fromZone = PlayerState.currentZone,
                        toZone = newZone,
                        timestamp = now,
                        stationId = nearStation
                    }

                    -- Trigger ticket sweep
                    PerformTicketSweep(PlayerState.currentZone, newZone, nearStation)
                else
                    Transit.Debug('Zone check deferred - not yet at platform or deep in zone')
                    goto continue
                end
            end

            PlayerState.currentZone = newZone
        end

        ::continue::
    end
end)

-- Perform ticket sweep when crossing zones
function PerformTicketSweep(fromZone, toZone, atStation)
    -- Request server to validate ticket
    local valid, result = lib.callback.await('dps-transit:server:validateZoneCrossing', false, fromZone, toZone)

    if not valid then
        -- Player doesn't have valid ticket for this zone
        lib.notify({
            title = 'Fare Inspection',
            description = result or 'Your ticket is not valid for this zone',
            type = 'error',
            duration = 8000,
            icon = 'ticket'
        })

        -- Offer to pay additional fare or exit
        local choice = lib.alertDialog({
            header = 'Fare Inspector',
            content = 'Your ticket does not cover Zone ' .. toZone .. '.\n\nYou must pay the additional fare or exit at the next station.',
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Pay Additional Fare',
                cancel = 'Exit at Next Station'
            }
        })

        if choice == 'confirm' then
            -- Pay additional fare
            local success, msg = lib.callback.await('dps-transit:server:payAdditionalFare', false, fromZone, toZone)

            if success then
                lib.notify({
                    title = 'Fare Paid',
                    description = 'Zone extension purchased',
                    type = 'success',
                    duration = 3000
                })
            else
                lib.notify({
                    title = 'Payment Failed',
                    description = msg or 'Insufficient funds',
                    type = 'error',
                    duration = 3000
                })

                -- Force exit at next station
                ForceExitAtNextStation()
            end
        else
            -- Player chose to exit
            ForceExitAtNextStation()
        end
    else
        -- Valid ticket - just a friendly notification
        lib.notify({
            title = 'Zone ' .. toZone,
            description = 'Entering ' .. (Config.Zones[toZone] and Config.Zones[toZone].name or toZone),
            type = 'inform',
            duration = 3000
        })
    end
end

-- Force player to exit at next station
function ForceExitAtNextStation()
    PlayerState.mustExitNextStation = true

    lib.notify({
        title = 'Exit Required',
        description = 'You must exit at the next station',
        type = 'warning',
        duration = 5000
    })
end

-- Monitor for forced exit
CreateThread(function()
    while true do
        Wait(1000)

        if PlayerState.mustExitNextStation and PlayerState.currentTrain then
            local train = LocalTrains[PlayerState.currentTrain]

            if train and train.data.status == 'boarding' then
                -- Train is at a station - force exit
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)

                if vehicle and DoesEntityExist(vehicle) then
                    TaskLeaveVehicle(ped, vehicle, 0)

                    lib.notify({
                        title = 'Fare Enforcement',
                        description = 'You have been removed from the train',
                        type = 'error',
                        duration = 5000
                    })

                    PlayerState.mustExitNextStation = false
                    PlayerState.currentTrain = nil
                    PlayerState.currentZone = nil
                end
            end
        end
    end
end)

-- Get nearest station to player
function GetNearestStationToPlayer()
    local playerCoords = GetEntityCoords(PlayerPedId())
    return Transit.GetNearestStation(playerCoords)
end

-- Check if player is at a station
function IsPlayerAtStation()
    local stationId, dist = GetNearestStationToPlayer()
    return dist < 50.0, stationId, dist
end

-----------------------------------------------------------
-- DYNAMIC CURVATURE HANDLING (Roxwood Bridge)
-----------------------------------------------------------

-- Track train headings for curve detection
local TrainHeadings = {}
local CurvatureSlowdown = {}

-- Monitor train heading changes for curve detection
CreateThread(function()
    if not Config.Train.curvatureHandling or not Config.Train.curvatureHandling.enabled then
        return
    end

    local cfg = Config.Train.curvatureHandling

    while true do
        Wait(500)  -- Check every 500ms

        for trainId, train in pairs(LocalTrains) do
            if not DoesEntityExist(train.entity) then goto continue end

            local currentHeading = GetEntityHeading(train.entity)
            local lastHeading = TrainHeadings[trainId]

            if lastHeading then
                -- Calculate heading change (degrees per 500ms = 2x per second)
                local headingChange = math.abs(currentHeading - lastHeading)

                -- Handle wraparound (359 -> 1 = 2 degrees, not 358)
                if headingChange > 180 then
                    headingChange = 360 - headingChange
                end

                -- Double it to get degrees/second
                local degreesPerSecond = headingChange * 2

                -- Check if on a curve
                if degreesPerSecond > cfg.curveDetectionAngle then
                    if not CurvatureSlowdown[trainId] then
                        CurvatureSlowdown[trainId] = {
                            startTime = GetGameTimer(),
                            startPos = GetEntityCoords(train.entity)
                        }

                        -- Apply curve speed reduction
                        local curveSpeed = Config.Train.speed * cfg.curveSpeedMultiplier
                        SetTrainSpeed(train.entity, curveSpeed)
                        SetTrainCruiseSpeed(train.entity, curveSpeed)

                        Transit.Debug('Curve detected for train', trainId, '- slowing to', curveSpeed)
                    end
                else
                    -- Check if we've recovered from the curve
                    if CurvatureSlowdown[trainId] then
                        local startPos = CurvatureSlowdown[trainId].startPos
                        local currentPos = GetEntityCoords(train.entity)
                        local distance = #(currentPos - startPos)

                        if distance > cfg.recoveryDistance then
                            -- Resume normal speed
                            SetTrainSpeed(train.entity, Config.Train.speed)
                            SetTrainCruiseSpeed(train.entity, Config.Train.cruiseSpeed)
                            CurvatureSlowdown[trainId] = nil

                            Transit.Debug('Curve cleared for train', trainId, '- resuming normal speed')
                        end
                    end
                end
            end

            TrainHeadings[trainId] = currentHeading

            ::continue::
        end
    end
end)

-----------------------------------------------------------
-- PLATFORM CAPACITY MONITORING
-----------------------------------------------------------

local PlatformStatus = {}

CreateThread(function()
    if not Config.PlatformCapacity or not Config.PlatformCapacity.enabled then
        return
    end

    local cfg = Config.PlatformCapacity

    while true do
        Wait(cfg.checkInterval)

        local playerCoords = GetEntityCoords(PlayerPedId())

        for stationId, station in pairs(Config.Stations) do
            -- Skip freight-only stations
            if station.features and station.features.freightOnly then
                goto continue
            end

            -- Skip if no waiting area defined
            if not station.waitingArea then
                goto continue
            end

            local waitingArea = station.waitingArea
            local distance = #(playerCoords - waitingArea)

            -- Only check stations player is near
            if distance > 100.0 then
                goto continue
            end

            -- Count entities near waiting area
            local entities = 0

            -- Count players
            local players = GetActivePlayers()
            for _, playerId in ipairs(players) do
                local ped = GetPlayerPed(playerId)
                if DoesEntityExist(ped) then
                    local pedPos = GetEntityCoords(ped)
                    if #(pedPos - waitingArea) < cfg.checkRadius then
                        entities = entities + 1
                    end
                end
            end

            -- Count NPCs (peds in area)
            local handle, ped = FindFirstPed()
            local success = true

            while success do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    local pedPos = GetEntityCoords(ped)
                    if #(pedPos - waitingArea) < cfg.checkRadius then
                        entities = entities + 1
                    end
                end
                success, ped = FindNextPed(handle)
            end
            EndFindPed(handle)

            -- Check overcrowding
            local wasOvercrowded = PlatformStatus[stationId] and PlatformStatus[stationId].overcrowded
            local isOvercrowded = entities >= cfg.maxEntities

            if isOvercrowded and not wasOvercrowded then
                -- Just became overcrowded
                if cfg.announceOvercrowding and distance < 50.0 then
                    lib.notify({
                        title = station.shortName or station.name,
                        description = cfg.overcrowdingMessage,
                        type = 'warning',
                        duration = 8000,
                        icon = 'users'
                    })

                    PlaySoundFrontend(-1, 'PIN_BUTTON', 'ATM_SOUNDS', true)
                end

                Transit.Debug('Platform overcrowded:', stationId, 'entities:', entities)
            end

            PlatformStatus[stationId] = {
                entities = entities,
                overcrowded = isOvercrowded,
                lastCheck = GetGameTimer()
            }

            ::continue::
        end
    end
end)

-- Export platform status
function GetPlatformStatus(stationId)
    return PlatformStatus[stationId]
end

-----------------------------------------------------------
-- BRAKE SQUEAL SFX
-----------------------------------------------------------

local BrakeSquealActive = {}

-- Monitor trains for brake squeal sound
CreateThread(function()
    if not Config.Train.audio or not Config.Train.audio.enabled then
        return
    end

    if not Config.Train.audio.brakeSqueal or not Config.Train.audio.brakeSqueal.enabled then
        return
    end

    local cfg = Config.Train.audio.brakeSqueal

    while true do
        Wait(500)

        for trainId, train in pairs(LocalTrains) do
            if not DoesEntityExist(train.entity) then
                BrakeSquealActive[trainId] = nil
                goto continue
            end

            local speed = GetEntitySpeed(train.entity)
            local isBraking = train.data.status == 'boarding' or speed < cfg.speedThreshold

            -- Check if train is decelerating (slowing down for station)
            if isBraking and speed > 1.0 and speed < cfg.speedThreshold then
                if not BrakeSquealActive[trainId] then
                    BrakeSquealActive[trainId] = true

                    -- Play brake squeal sound on train entity
                    local playerCoords = GetEntityCoords(PlayerPedId())
                    local trainCoords = GetEntityCoords(train.entity)
                    local distance = #(playerCoords - trainCoords)

                    -- Only play if player is close enough to hear
                    if distance < 80.0 then
                        PlaySoundFromEntity(-1, cfg.soundName, train.entity, cfg.soundSet, false, 0)
                        Transit.Debug('Brake squeal for train', trainId, 'at speed', speed)
                    end
                end
            else
                -- Reset when train stops or speeds up
                if BrakeSquealActive[trainId] and (speed < 1.0 or speed > cfg.speedThreshold + 5) then
                    BrakeSquealActive[trainId] = nil
                end
            end

            ::continue::
        end
    end
end)

-----------------------------------------------------------
-- TRAIN HORN AT JUNCTIONS
-----------------------------------------------------------

local HornSounded = {}

CreateThread(function()
    if not Config.Train.audio or not Config.Train.audio.enabled then
        return
    end

    if not Config.Train.audio.horn or not Config.Train.audio.horn.enabled then
        return
    end

    local cfg = Config.Train.audio.horn

    -- Junction locations (from config)
    local junctions = {
        paleto_junction = vec3(2521.0, 6135.0, 39.0)
    }

    while true do
        Wait(2000)

        for trainId, train in pairs(LocalTrains) do
            if not DoesEntityExist(train.entity) then
                HornSounded[trainId] = nil
                goto continue
            end

            local trainPos = GetEntityCoords(train.entity)

            for junctionId, junctionPos in pairs(junctions) do
                local distance = #(trainPos - junctionPos)
                local hornKey = trainId .. '_' .. junctionId

                if distance < cfg.approachDistance and distance > 50.0 then
                    if not HornSounded[hornKey] then
                        HornSounded[hornKey] = true

                        -- Sound train horn
                        StartVehicleHorn(train.entity, 2000, GetHashKey('NORMAL'), false)

                        Transit.Debug('Train horn at junction', junctionId, 'distance:', distance)
                    end
                elseif distance > cfg.approachDistance + 50 then
                    -- Reset horn flag when train moves away
                    HornSounded[hornKey] = nil
                end
            end

            ::continue::
        end
    end
end)

-----------------------------------------------------------
-- EMERGENCY BRAKING (Client Handling)
-----------------------------------------------------------

-----------------------------------------------------------
-- SERVICE ALERTS (Client Handling)
-----------------------------------------------------------

-- Handle service alert from server
RegisterNetEvent('dps-transit:client:serviceAlert', function(data)
    if not data or not data.action then return end

    SendNUIMessage(data)

    -- Also show notification for important alerts
    if data.action == 'showServiceAlert' then
        local notifyType = 'inform'
        if data.alertType == 'delay' then
            notifyType = 'warning'
        elseif data.alertType == 'disruption' or data.alertType == 'emergency' then
            notifyType = 'error'
        end

        lib.notify({
            title = 'Transit Alert',
            description = data.message,
            type = notifyType,
            duration = 8000,
            icon = 'train'
        })
    end
end)

-- Request service alerts on resource start
CreateThread(function()
    Wait(3000)
    TriggerServerEvent('dps-transit:client:requestAlerts')
end)

-- Handle emergency brake command from server
RegisterNetEvent('dps-transit:client:emergencyBrake', function(trainId, active)
    local train = LocalTrains[trainId]
    if not train or not DoesEntityExist(train.entity) then return end

    if active then
        -- Emergency stop
        SetTrainSpeed(train.entity, 0.0)
        SetTrainCruiseSpeed(train.entity, 0.0)
        train.data.status = 'emergency_stopped'

        -- Visual/audio feedback
        PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)

        Transit.Debug('Emergency brake activated for train', trainId)
    else
        -- Resume with GRADUAL speed ramp-up
        -- This prevents physics engine from launching trains on steep grades
        train.data.status = 'resuming'

        -- Get target speed for this track
        local trackId = train.data.currentTrack or 0
        local targetSpeed = GetTrackBaseSpeed(trackId)

        -- Gradual ramp-up over 5 seconds
        GradualSpeedResume(trainId, train.entity, targetSpeed, 5.0)

        Transit.Debug('Emergency brake released for train', trainId, '- ramping to', targetSpeed)
    end
end)

-- Gradual speed resume to prevent physics launching
function GradualSpeedResume(trainId, entity, targetSpeed, duration)
    local startTime = GetGameTimer()
    local durationMs = duration * 1000

    CreateThread(function()
        while true do
            Wait(100)

            -- Check if train still exists
            if not DoesEntityExist(entity) then
                return
            end

            -- Check if train state changed (e.g., another emergency stop)
            local train = LocalTrains[trainId]
            if not train or train.data.status == 'emergency_stopped' then
                return
            end

            local elapsed = GetGameTimer() - startTime
            local t = math.min(1.0, elapsed / durationMs)

            -- Use smooth ease-out curve for natural acceleration
            local easeT = 1 - (1 - t) * (1 - t)
            local currentTarget = Lerp(0, targetSpeed, easeT)

            SetTrainSpeed(entity, currentTarget)
            SetTrainCruiseSpeed(entity, currentTarget)

            if t >= 1.0 then
                -- Ramp complete, set to running
                if train then
                    train.data.status = 'running'
                end
                Transit.Debug('Train', trainId, 'resume complete at', targetSpeed, 'm/s')
                return
            end
        end
    end)
end

-----------------------------------------------------------
-- BLOCK SIGNALING (Client-Side Speed Control)
-----------------------------------------------------------

-- Current signal states for each train
local TrainSignalStates = {}

-- Frozen carriages during RED signal
local FrozenCarriages = {}

-- Handle signal state changes from server
RegisterNetEvent('dps-transit:client:signalStateChange', function(data)
    if not data or not data.trainId then return end

    local train = LocalTrains[data.trainId]
    if not train then return end

    local previousState = TrainSignalStates[data.trainId]
    TrainSignalStates[data.trainId] = {
        signalState = data.signalState,
        currentSegment = data.currentSegment,
        nextSegment = data.nextSegment,
        speedMultiplier = data.speedMultiplier or 1.0,
        timestamp = GetGameTimer()
    }

    -- Apply speed based on signal state
    ApplySignalSpeed(data.trainId, train, data.signalState, data.speedMultiplier, previousState)

    -- Handle carriage stability
    if Config.BlockSignaling and Config.BlockSignaling.carriageStability.enabled then
        HandleCarriageStability(data.trainId, train, data.signalState, previousState)
    end

    Transit.Debug('Signal state:', data.trainId, '=', data.signalState:upper())
end)

-- Handle segment update
RegisterNetEvent('dps-transit:client:segmentUpdate', function(data)
    if not data or not data.trainId then return end

    -- Update NUI with segment info if enabled
    if Config.BlockSignaling and Config.BlockSignaling.announcements.showOnNUI then
        SendNUIMessage({
            action = 'updateTrainSegment',
            trainId = data.trainId,
            segmentName = data.segmentName,
            signalState = data.signalState
        })
    end
end)

-- Handle signal hold announcement (player on train)
RegisterNetEvent('dps-transit:client:signalHoldAnnouncement', function(data)
    if not data then return end

    -- Play warning sound - subtle alert chime
    PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    -- Determine title based on hold type
    local holdTitle = 'Signal Hold'
    local holdType = 'held'
    if data.isDispatcherHold then
        holdTitle = 'Dispatcher Hold'
        holdType = 'dispatcher'
    end

    -- Show NUI passenger announcement overlay
    SendNUIMessage({
        action = 'showAnnouncement',
        type = holdType,
        title = holdTitle,
        station = data.segmentName or 'Current Section',
        subtitle = data.reason or 'Please stand by',
        duration = 0  -- Stays until signal clears
    })

    -- Also update schedule board signal hold indicator
    SendNUIMessage({
        action = 'showSignalHold',
        segmentName = data.segmentName,
        reason = data.reason,
        isDispatcherHold = data.isDispatcherHold
    })
end)

-- Handle train held status update (for NUI ETA display)
RegisterNetEvent('dps-transit:client:trainHeldStatus', function(data)
    if not data or not data.trainId then return end

    -- Update NUI with held status
    SendNUIMessage({
        action = 'trainHeldStatus',
        trainId = data.trainId,
        isHeld = data.isHeld,
        isCaution = data.isCaution,
        reason = data.reason,
        segmentName = data.segmentName
    })

    -- If this is the player's train and it's no longer held, hide announcements
    if PlayerState.currentTrain == data.trainId and not data.isHeld and not data.isCaution then
        -- Hide signal hold banner
        SendNUIMessage({ action = 'hideSignalHold' })

        -- Hide passenger announcement overlay
        SendNUIMessage({ action = 'hideAnnouncement' })

        -- Play "all clear" chime
        PlaySoundFrontend(-1, 'PICK_UP_COLLECTIBLE', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end)

-- Apply speed based on signal state
function ApplySignalSpeed(trainId, train, signalState, multiplier, previousState)
    if not DoesEntityExist(train.entity) then return end

    local trackId = train.data.currentTrack or 0
    local baseSpeed = GetTrackBaseSpeed(trackId)

    -- Check for speed zone reduction (curves/bridges)
    local zoneSpeed = GetTrackZoneSpeed(trackId, GetEntityCoords(train.entity))
    if zoneSpeed then
        baseSpeed = math.min(baseSpeed, zoneSpeed)
    end

    -- Calculate target speed based on signal
    local targetSpeed = baseSpeed * multiplier

    if signalState == 'red' then
        -- Full stop - use fast lerp
        local currentSpeed = GetEntitySpeed(train.entity)

        -- Immediate stop for RED signal
        SetTrainSpeed(train.entity, 0.0)
        SetTrainCruiseSpeed(train.entity, 0.0)

        -- Update train status
        train.data.status = 'signal_hold'

        Transit.Debug('SIGNAL RED: Train', trainId, 'stopped')

    elseif signalState == 'yellow' then
        -- Slow approach - use CURVE_LERP_FACTOR for smooth slowdown
        local currentSpeed = GetEntitySpeed(train.entity)
        local lerpedSpeed = Lerp(currentSpeed, targetSpeed, CURVE_LERP_FACTOR)

        SetTrainSpeed(train.entity, lerpedSpeed)
        SetTrainCruiseSpeed(train.entity, lerpedSpeed)

        -- Update train status
        train.data.status = 'signal_caution'

        Transit.Debug('SIGNAL YELLOW: Train', trainId, 'slowing to', math.floor(targetSpeed), 'm/s')

    elseif signalState == 'green' then
        -- Check if coming from RED (need gradual resume)
        if previousState and previousState.signalState == 'red' then
            -- Gradual speed resume to prevent physics issues
            GradualSpeedResume(trainId, train.entity, targetSpeed, 3.0)
            train.data.status = 'resuming'
        else
            -- Normal speed - apply with standard lerp
            local currentSpeed = GetEntitySpeed(train.entity)
            local lerpedSpeed = Lerp(currentSpeed, targetSpeed, SPEED_LERP_FACTOR)

            SetTrainSpeed(train.entity, lerpedSpeed)
            SetTrainCruiseSpeed(train.entity, lerpedSpeed)

            train.data.status = 'running'
        end

        Transit.Debug('SIGNAL GREEN: Train', trainId, 'proceeding at', math.floor(targetSpeed), 'm/s')
    end
end

-- Handle carriage stability during signal holds
function HandleCarriageStability(trainId, train, signalState, previousState)
    if not DoesEntityExist(train.entity) then return end

    local cfg = Config.BlockSignaling.carriageStability

    if signalState == 'red' and cfg.freezeOnHold then
        -- Freeze all carriages to prevent physics snapping
        FreezeTrainConsist(trainId, train.entity, true)
    elseif signalState == 'green' and previousState and previousState.signalState == 'red' then
        -- Unfreeze after delay
        SetTimeout(cfg.unfreezeDelay, function()
            if LocalTrains[trainId] then
                FreezeTrainConsist(trainId, train.entity, false)
            end
        end)
    end
end

-- Freeze/unfreeze entire train consist
function FreezeTrainConsist(trainId, locomotiveEntity, freeze)
    if not DoesEntityExist(locomotiveEntity) then return end

    local carriages = { locomotiveEntity }
    local currentCarriage = locomotiveEntity

    -- Collect all carriages
    while currentCarriage and DoesEntityExist(currentCarriage) do
        local nextCarriage = GetTrainCarriage(currentCarriage, 1)
        if nextCarriage == currentCarriage or nextCarriage == 0 then
            break
        end
        table.insert(carriages, nextCarriage)
        currentCarriage = nextCarriage
    end

    -- Apply freeze to all
    for _, carriage in ipairs(carriages) do
        if DoesEntityExist(carriage) then
            FreezeEntityPosition(carriage, freeze)
        end
    end

    if freeze then
        FrozenCarriages[trainId] = carriages
        Transit.Debug('Froze', #carriages, 'carriages for train', trainId)
    else
        FrozenCarriages[trainId] = nil
        Transit.Debug('Unfroze', #carriages, 'carriages for train', trainId)
    end
end

-- Get current signal state for a train
function GetTrainSignalState(trainId)
    return TrainSignalStates[trainId]
end

-- Update trainPositionUpdate handler to include signal state
RegisterNetEvent('dps-transit:client:trainPositionUpdate', function(trainId, position, progress, signalState)
    local train = LocalTrains[trainId]
    if train then
        train.data.currentPosition = position
        train.data.trackProgress = progress

        -- Store signal state if provided
        if signalState then
            TrainSignalStates[trainId] = TrainSignalStates[trainId] or {}
            TrainSignalStates[trainId].signalState = signalState
        end
    end
end)

-- Clean up signal state when train is removed
RegisterNetEvent('dps-transit:client:removeTrain', function(trainId)
    -- Existing cleanup...
    local train = LocalTrains[trainId]
    if train then
        if DoesEntityExist(train.entity) then
            -- Unfreeze before deletion
            if FrozenCarriages[trainId] then
                FreezeTrainConsist(trainId, train.entity, false)
            end
            DeleteMissionTrain(train.entity)
        end
        LocalTrains[trainId] = nil
    end

    if TrainBlips[trainId] then
        RemoveBlip(TrainBlips[trainId])
        TrainBlips[trainId] = nil
    end

    -- Clean up signal state
    TrainSignalStates[trainId] = nil
    FrozenCarriages[trainId] = nil

    Transit.Debug('Removed train:', trainId)
end)

-----------------------------------------------------------
-- DISPATCHER MONITORING PANEL
-----------------------------------------------------------

local DispatcherState = {
    isOpen = false,
    hasAccess = false,
    lastUpdate = 0
}

-- Update interval for dispatcher panel (ms)
local DISPATCHER_UPDATE_INTERVAL = 2000

-- Check if player has dispatcher access (job-based)
function CheckDispatcherAccess()
    local job = Bridge.GetJob()
    if not job then return false end

    local dispatcherJobs = {
        dispatch = true,
        police = true,
        sheriff = true,
        lspd = true,
        bcso = true,
        sasp = true,
        admin = true,
        transit = true
    }

    return dispatcherJobs[job] == true
end

-- Toggle dispatcher panel
function ToggleDispatcherPanel()
    if DispatcherState.isOpen then
        CloseDispatcherPanel()
    else
        OpenDispatcherPanel()
    end
end

-- Open dispatcher panel
function OpenDispatcherPanel()
    -- Check access first
    if not CheckDispatcherAccess() then
        lib.notify({
            title = 'Access Denied',
            description = 'You do not have access to the dispatch panel',
            type = 'error',
            duration = 3000
        })
        return
    end

    DispatcherState.isOpen = true
    DispatcherState.hasAccess = true

    -- Show NUI panel
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showDispatcher'
    })

    -- Request initial data
    RequestDispatcherData()

    Transit.Debug('Dispatcher panel opened')
end

-- Close dispatcher panel
function CloseDispatcherPanel()
    DispatcherState.isOpen = false

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'hideDispatcher'
    })

    Transit.Debug('Dispatcher panel closed')
end

-- Request dispatcher data from server
function RequestDispatcherData()
    if not DispatcherState.isOpen then return end

    local segments, trains = lib.callback.await('dps-transit:server:getDispatcherData', false)

    if segments and trains then
        -- Send to NUI
        SendNUIMessage({
            action = 'updateDispatcher',
            segments = segments,
            trains = trains,
            timestamp = GetGameTimer()
        })

        DispatcherState.lastUpdate = GetGameTimer()
    end
end

-- Periodic dispatcher update loop
CreateThread(function()
    while true do
        Wait(DISPATCHER_UPDATE_INTERVAL)

        if DispatcherState.isOpen and DispatcherState.hasAccess then
            RequestDispatcherData()
        end
    end
end)

-- NUI callback for close button / ESC
RegisterNUICallback('closeDispatcher', function(data, cb)
    CloseDispatcherPanel()
    cb('ok')
end)

-- NUI callback for data refresh request
RegisterNUICallback('requestDispatcherData', function(data, cb)
    if DispatcherState.isOpen and DispatcherState.hasAccess then
        RequestDispatcherData()
    end
    cb('ok')
end)

-- NUI callback for segment lock/unlock from dispatcher panel (v2.6.0)
RegisterNUICallback('segmentOverride', function(data, cb)
    if not DispatcherState.hasAccess then
        cb({ success = false, error = 'Access denied' })
        return
    end

    local segmentId = data.segmentId
    local action = data.action
    local reason = data.reason

    if not segmentId then
        cb({ success = false, error = 'No segment ID provided' })
        return
    end

    -- Forward to server
    TriggerServerEvent('dps-transit:server:segmentOverride', segmentId, action, reason)
    cb({ success = true })
end)

-- Handle segment override change notification
RegisterNetEvent('dps-transit:client:segmentOverrideChanged', function(data)
    if not data then return end

    -- Update NUI dispatcher panel if open
    if DispatcherState.isOpen then
        SendNUIMessage({
            action = 'segmentOverrideChanged',
            segmentId = data.segmentId,
            locked = data.locked,
            reason = data.reason,
            lockedBy = data.lockedBy,
            unlockedBy = data.unlockedBy
        })
    end

    -- Show notification
    if data.locked then
        lib.notify({
            title = 'Segment Locked',
            description = data.segmentId .. ' locked by ' .. (data.lockedBy or 'Dispatcher'),
            type = 'warning',
            duration = 5000
        })
    else
        lib.notify({
            title = 'Segment Unlocked',
            description = data.segmentId .. ' unlocked by ' .. (data.unlockedBy or 'Dispatcher'),
            type = 'success',
            duration = 3000
        })
    end
end)

-- NUI callback for emergency stop/release from dispatcher panel
RegisterNUICallback('emergencyStop', function(data, cb)
    if not DispatcherState.hasAccess then
        cb({ success = false, error = 'Access denied' })
        return
    end

    local trainId = data.trainId
    local action = data.action

    if not trainId then
        cb({ success = false, error = 'No train ID provided' })
        return
    end

    -- Forward to server for processing
    TriggerServerEvent('dps-transit:server:dispatcherEmergencyAction', trainId, action)

    cb({ success = true })
end)

-- Keybind to toggle dispatcher panel (F7)
RegisterKeyMapping('dispatch_panel', 'Toggle Transit Dispatch Panel', 'keyboard', 'F7')
RegisterCommand('dispatch_panel', function()
    ToggleDispatcherPanel()
end, false)

-- Also register as chat command
RegisterCommand('dispatch', function()
    ToggleDispatcherPanel()
end, false)

-- Export dispatcher functions
exports('ToggleDispatcherPanel', ToggleDispatcherPanel)
exports('IsDispatcherOpen', function() return DispatcherState.isOpen end)

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------

-- Export client functions
exports('GetNearestStation', GetNearestStationToPlayer)
exports('IsPlayerAtStation', IsPlayerAtStation)
exports('GetLocalTrains', function() return LocalTrains end)
exports('GetPlatformStatus', GetPlatformStatus)
exports('GetTrainSignalState', GetTrainSignalState)
