--[[
    DPS-Transit Scheduler
    Manages automatic train spawning with 70/30 passenger/freight split
    Supports multiple lines: Regional (Track 0), Metro (Track 3), Roxwood (Track 13)
]]

-- Active trains by line
ActiveTrains = {}

-- Schedule state per line
local LineSchedules = {}

-- Last spawn time per line
local LastSpawnTime = {}

-- Emergency hold state
local EmergencyHold = {
    active = false,
    stationId = nil,
    requestedBy = nil,
    reason = nil,
    heldTrains = {}
}

-- Track occupancy (for freight conflict prevention)
local TrackOccupancy = {
    [0] = {},   -- Regional line
    [3] = {},   -- Metro line
    [13] = {}   -- Roxwood line
}

-----------------------------------------------------------
-- VIRTUAL BLOCK SIGNALING SYSTEM
-- Server-authoritative segment occupancy tracking
-----------------------------------------------------------

-- Segment occupancy state: { segmentId = { trainId, enteredAt, direction } }
local SegmentOccupancy = {}

-- Pending segment releases (for carriage clearance delay)
local PendingSegmentReleases = {}

-- Signal states for each train: { trainId = { currentSegment, signalState, nextSegment } }
local TrainSignalStates = {}

-- Segment lookup cache (built on init)
local SegmentLookup = {}

-- Last segment check time per train (for throttling)
local LastSegmentCheck = {}

-- Segment check throttle (ms) - only recalculate if this time has passed
local SEGMENT_CHECK_THROTTLE = 2000

-- Carriage clearance delays (seconds) based on train type
-- Passenger trains: ~100m at 20m/s = ~5 seconds
-- Freight trains: ~200m at 15m/s = ~13 seconds
local CARRIAGE_CLEARANCE_DELAY = {
    passenger = 6,
    freight = 14
}

-- Minimum yellow speed (prevents rubber-banding stop-start)
local MIN_YELLOW_SPEED = 5.0  -- m/s (~11 mph) - never slower than this on yellow

-- Stale segment timeout (seconds) - force-clear if no movement for this long
-- Prevents "ghost freight" deadlock from partial entity cleanup
local STALE_SEGMENT_TIMEOUT = 300  -- 5 minutes

-- Block signal deadlock timeout (seconds) - verify blocking train exists
-- Prevents permanent signal failure if blocking train was removed without cleanup
local BLOCK_SIGNAL_DEADLOCK_TIMEOUT = 120  -- 2 minutes

-- Last known positions for stale detection
local LastKnownPositions = {}

-- Signal state constants
local SIGNAL_GREEN = 'green'
local SIGNAL_YELLOW = 'yellow'
local SIGNAL_RED = 'red'

-----------------------------------------------------------
-- MANUAL SEGMENT OVERRIDES (v2.6.0)
-- Dispatcher-initiated segment locks for maintenance/investigations
-----------------------------------------------------------

-- Manual segment overrides: { segmentId = { state, reason, setBy, setAt } }
local SegmentOverrides = {}

-- Override state constants
local OVERRIDE_LOCKED = 'locked'   -- Force RED, no trains may enter
local OVERRIDE_CLEAR = nil         -- No override, normal signaling

-- Heartbeat: Check for stale segment occupancy
-- If a segment is occupied for 5+ minutes without train movement, force-clear it
CreateThread(function()
    Wait(30000)  -- Initial delay

    while true do
        Wait(60000)  -- Check every 60 seconds

        if not Config.BlockSignaling or not Config.BlockSignaling.enabled then
            goto continue
        end

        local now = os.time()

        for segmentId, occupant in pairs(SegmentOccupancy) do
            if occupant then
                local trainId = occupant.trainId
                local enteredAt = occupant.enteredAt or now
                local timeInSegment = now - enteredAt

                -- Check if segment has been occupied too long
                if timeInSegment > STALE_SEGMENT_TIMEOUT then
                    local train = ActiveTrains[trainId]

                    if not train then
                        -- Train no longer exists - ghost segment, force clear
                        Transit.Debug('HEARTBEAT: Ghost segment detected -', segmentId, '| Train', trainId, 'no longer exists')
                        SegmentOccupancy[segmentId] = nil
                        PendingSegmentReleases[segmentId] = nil

                        -- Notify clients
                        TriggerClientEvent('dps-transit:client:segmentCleared', -1, {
                            segmentId = segmentId,
                            reason = 'stale_timeout'
                        })
                    else
                        -- Train exists - check if it has moved
                        local currentPos = train.currentPosition
                        local lastPos = LastKnownPositions[trainId]

                        if currentPos and lastPos then
                            local dx = (currentPos.x or 0) - (lastPos.x or 0)
                            local dy = (currentPos.y or 0) - (lastPos.y or 0)
                            local moved = math.sqrt(dx * dx + dy * dy)

                            if moved < 5.0 then
                                -- Train hasn't moved significantly in 5 minutes
                                Transit.Debug('HEARTBEAT: Stuck train detected -', segmentId, '| Train', trainId, 'no movement for', timeInSegment, 's')

                                -- Don't auto-clear if train is in emergency hold or dispatcher hold
                                local hasDispatcherHold = DispatcherHolds and DispatcherHolds[trainId]
                                if train.status ~= 'emergency_stopped' and not hasDispatcherHold then
                                    SegmentOccupancy[segmentId] = nil
                                    PendingSegmentReleases[segmentId] = nil
                                    Transit.Debug('HEARTBEAT: Force-cleared stale segment', segmentId)
                                else
                                    Transit.Debug('HEARTBEAT: Skipping clear - train has dispatcher/emergency hold')
                                end
                            end
                        end

                        -- Update last known position
                        LastKnownPositions[trainId] = currentPos
                    end
                end
            end
        end

        -- BLOCK SIGNAL DEADLOCK CHECK: Verify blocking trains still exist
        -- If a train has been at RED signal for >120 seconds, check if blocker exists
        for trainId, signalState in pairs(TrainSignalStates) do
            if signalState.signalState == SIGNAL_RED and signalState.lastUpdate then
                -- Skip deadlock check if this is a dispatcher override
                if signalState.dispatcherOverride then
                    goto continue_signal_check
                end

                local holdDuration = now - signalState.lastUpdate

                if holdDuration > BLOCK_SIGNAL_DEADLOCK_TIMEOUT then
                    -- Train has been held at RED for too long - verify blocker
                    local nextSegmentId = signalState.nextSegment
                    if nextSegmentId then
                        local nextOccupant = SegmentOccupancy[nextSegmentId]

                        if nextOccupant then
                            local blockingTrainId = nextOccupant.trainId
                            local blockingTrain = ActiveTrains[blockingTrainId]

                            if not blockingTrain then
                                -- Blocking train no longer exists - ghost block!
                                Transit.Debug('DEADLOCK TIMEOUT: Ghost blocker detected in', nextSegmentId,
                                    '| Blocking train', blockingTrainId, 'no longer exists')

                                -- Clear the ghost segment
                                SegmentOccupancy[nextSegmentId] = nil
                                PendingSegmentReleases[nextSegmentId] = nil

                                -- Force recalculation for held train
                                TrainSignalStates[trainId].lastUpdate = now

                                -- Notify clients
                                TriggerClientEvent('dps-transit:client:segmentCleared', -1, {
                                    segmentId = nextSegmentId,
                                    reason = 'deadlock_timeout'
                                })

                                Transit.Debug('DEADLOCK TIMEOUT: Cleared ghost segment, train', trainId, 'should resume')
                            else
                                -- Blocking train exists - check if IT has moved recently
                                local blockerPos = blockingTrain.currentPosition
                                local blockerLastPos = LastKnownPositions[blockingTrainId]

                                if blockerPos and blockerLastPos then
                                    local dx = (blockerPos.x or 0) - (blockerLastPos.x or 0)
                                    local dy = (blockerPos.y or 0) - (blockerLastPos.y or 0)
                                    local blockerMoved = math.sqrt(dx * dx + dy * dy)

                                    if blockerMoved < 2.0 and holdDuration > (BLOCK_SIGNAL_DEADLOCK_TIMEOUT * 2) then
                                        -- Double timeout and blocker hasn't moved - force clear
                                        Transit.Debug('DEADLOCK TIMEOUT: Blocker', blockingTrainId, 'stuck for',
                                            holdDuration, 's - force clearing')

                                        ForceLeaveAllSegments(blockingTrainId)
                                        TrainSignalStates[trainId].lastUpdate = now
                                    end
                                end
                            end
                        else
                            -- Next segment is not occupied - why are we at RED?
                            Transit.Debug('DEADLOCK TIMEOUT: Train', trainId, 'at RED but next segment',
                                nextSegmentId, 'is clear - forcing state recalc')
                            TrainSignalStates[trainId].lastUpdate = now
                        end
                    end
                end
            end

            ::continue_signal_check::
        end

        ::continue::
    end
end)

-- Initialize block signaling system
function InitializeBlockSignaling()
    if not Config.BlockSignaling or not Config.BlockSignaling.enabled then
        Transit.Debug('Block signaling disabled')
        return
    end

    -- Build segment lookup table for fast position-to-segment queries
    for _, segment in ipairs(Config.BlockSignaling.segments) do
        SegmentLookup[segment.id] = segment

        -- Initialize as unoccupied
        SegmentOccupancy[segment.id] = nil
    end

    Transit.Debug('Block signaling initialized with', #Config.BlockSignaling.segments, 'segments')
end

-- Get segment containing a world position
function GetSegmentAtPosition(position, trackId)
    if not Config.BlockSignaling or not Config.BlockSignaling.enabled then
        return nil
    end

    local pos = vec3(position.x, position.y, position.z)

    for _, segment in ipairs(Config.BlockSignaling.segments) do
        -- Only check segments on the same track
        if segment.track == trackId then
            -- Calculate if position is within segment bounds
            -- Use distance to segment line (start to end)
            local segmentCenter = (segment.startCoords + segment.endCoords) / 2
            local segmentRadius = segment.length / 2 + 200  -- Add buffer

            local dist = #(pos - segmentCenter)
            if dist < segmentRadius then
                -- More precise check: is position between start and end?
                local toStart = #(pos - segment.startCoords)
                local toEnd = #(pos - segment.endCoords)
                local segmentLength = #(segment.endCoords - segment.startCoords)

                -- Position is in segment if sum of distances is close to segment length
                if (toStart + toEnd) < (segmentLength + 500) then  -- 500m tolerance
                    return segment
                end
            end
        end
    end

    return nil
end

-- Get the next segment in train's direction of travel
function GetNextSegment(currentSegmentId, direction, trackId)
    if not currentSegmentId then return nil end

    local segments = Config.BlockSignaling.segments
    local currentIndex = nil

    -- Find current segment index
    for i, segment in ipairs(segments) do
        if segment.id == currentSegmentId then
            currentIndex = i
            break
        end
    end

    if not currentIndex then return nil end

    -- Get adjacent segment based on direction
    local nextIndex = direction and (currentIndex + 1) or (currentIndex - 1)

    if nextIndex >= 1 and nextIndex <= #segments then
        local nextSegment = segments[nextIndex]
        -- Verify it's on the same or connected track
        if nextSegment.track == trackId then
            return nextSegment
        end
    end

    return nil
end

-- Check if a segment is occupied (by any train other than the querying one)
function IsSegmentOccupied(segmentId, excludeTrainId)
    local occupant = SegmentOccupancy[segmentId]

    if not occupant then
        return false, nil
    end

    if occupant.trainId == excludeTrainId then
        return false, nil
    end

    return true, occupant.trainId
end

-- Register train entering a segment
function EnterSegment(trainId, segmentId)
    local segment = SegmentLookup[segmentId]
    if not segment then return false end

    -- Check if segment is already occupied (excluding pending releases by same train)
    local occupied, occupantId = IsSegmentOccupied(segmentId, trainId)
    if occupied then
        Transit.Debug('BLOCK: Train', trainId, 'cannot enter', segmentId, '- occupied by', occupantId)
        return false
    end

    -- Schedule delayed release of previous segment (for carriage clearance)
    local previousState = TrainSignalStates[trainId]
    if previousState and previousState.currentSegment then
        -- Use appropriate delay based on train type
        local train = ActiveTrains[trainId]
        local trainType = (train and train.isFreight) and 'freight' or 'passenger'
        local delay = CARRIAGE_CLEARANCE_DELAY[trainType] or CARRIAGE_CLEARANCE_DELAY.passenger
        ScheduleSegmentRelease(trainId, previousState.currentSegment, delay)
    end

    -- Occupy new segment immediately (engine is in new segment)
    SegmentOccupancy[segmentId] = {
        trainId = trainId,
        enteredAt = os.time(),
        segmentName = segment.name
    }

    -- Update train state
    TrainSignalStates[trainId] = {
        currentSegment = segmentId,
        signalState = SIGNAL_GREEN,
        enteredAt = os.time()
    }

    Transit.Debug('BLOCK: Train', trainId, 'entered segment', segmentId, '(' .. segment.name .. ')')

    -- Notify clients about segment change
    TriggerClientEvent('dps-transit:client:segmentUpdate', -1, {
        trainId = trainId,
        segmentId = segmentId,
        segmentName = segment.name,
        signalState = SIGNAL_GREEN
    })

    return true
end

-- Schedule a delayed segment release (for carriage clearance)
function ScheduleSegmentRelease(trainId, segmentId, delaySeconds)
    -- Cancel any existing pending release for this segment
    if PendingSegmentReleases[segmentId] then
        Transit.Debug('BLOCK: Cancelling pending release for', segmentId)
    end

    PendingSegmentReleases[segmentId] = {
        trainId = trainId,
        releaseAt = os.time() + delaySeconds
    }

    Transit.Debug('BLOCK: Scheduled release of', segmentId, 'in', delaySeconds, 'seconds (carriage clearance)')

    -- Use SetTimeout for the delayed release
    SetTimeout(delaySeconds * 1000, function()
        local pending = PendingSegmentReleases[segmentId]
        if pending and pending.trainId == trainId then
            LeaveSegment(trainId, segmentId)
            PendingSegmentReleases[segmentId] = nil
        end
    end)
end

-- Register train leaving a segment (immediate)
function LeaveSegment(trainId, segmentId)
    local occupant = SegmentOccupancy[segmentId]

    if occupant and occupant.trainId == trainId then
        SegmentOccupancy[segmentId] = nil
        Transit.Debug('BLOCK: Train', trainId, 'left segment', segmentId)
        return true
    end

    return false
end

-- Force immediate release (used during train removal)
function ForceLeaveAllSegments(trainId)
    -- Clear any pending releases
    for segmentId, pending in pairs(PendingSegmentReleases) do
        if pending.trainId == trainId then
            PendingSegmentReleases[segmentId] = nil
        end
    end

    -- Clear all occupied segments
    for segmentId, occupant in pairs(SegmentOccupancy) do
        if occupant and occupant.trainId == trainId then
            SegmentOccupancy[segmentId] = nil
            Transit.Debug('BLOCK: Force-released segment', segmentId, 'from train', trainId)
        end
    end
end

-- Calculate signal state for a train based on next segment occupancy
function CalculateSignalState(trainId, position, trackId, direction)
    if not Config.BlockSignaling or not Config.BlockSignaling.enabled then
        return SIGNAL_GREEN, nil, nil
    end

    local currentSegment = GetSegmentAtPosition(position, trackId)
    if not currentSegment then
        return SIGNAL_GREEN, nil, nil
    end

    -- Ensure train is registered in current segment
    local currentState = TrainSignalStates[trainId]
    if not currentState or currentState.currentSegment ~= currentSegment.id then
        EnterSegment(trainId, currentSegment.id)
    end

    -- Get next segment
    local nextSegment = GetNextSegment(currentSegment.id, direction, trackId)
    if not nextSegment then
        -- No next segment (terminus) - green
        return SIGNAL_GREEN, currentSegment, nil
    end

    -- PRIORITY 1: Check for manual segment overrides (v2.6.0)
    -- If next segment is locked, force RED regardless of occupancy
    local nextOverride = SegmentOverrides[nextSegment.id]
    if nextOverride and nextOverride.state == OVERRIDE_LOCKED then
        Transit.Debug('[SIGNAL] Segment', nextSegment.id, 'is LOCKED by dispatcher - forcing RED')
        return SIGNAL_RED, currentSegment, nextSegment
    end

    -- Check if current segment is locked (train should not have entered)
    local currentOverride = SegmentOverrides[currentSegment.id]
    if currentOverride and currentOverride.state == OVERRIDE_LOCKED then
        -- Train is in a locked segment - force stop until override is cleared
        Transit.Debug('[SIGNAL] Train', trainId, 'in LOCKED segment', currentSegment.id, '- holding')
        return SIGNAL_RED, currentSegment, nextSegment
    end

    -- PRIORITY 2: Check if next segment is occupied
    local nextOccupied, occupantId = IsSegmentOccupied(nextSegment.id, trainId)
    if nextOccupied then
        -- Calculate distance to segment boundary
        local segmentBoundary = direction and currentSegment.endCoords or currentSegment.startCoords
        local pos = vec3(position.x, position.y, position.z)
        local distToBoundary = #(pos - segmentBoundary)

        -- Determine signal state based on distance
        if distToBoundary < 50.0 then
            -- At boundary - RED (full stop)
            return SIGNAL_RED, currentSegment, nextSegment
        elseif distToBoundary < Config.BlockSignaling.yellowApproachDistance then
            -- Approaching boundary - YELLOW (slow down)
            return SIGNAL_YELLOW, currentSegment, nextSegment
        else
            -- Far from boundary but next is occupied - still YELLOW (proceed with caution)
            return SIGNAL_YELLOW, currentSegment, nextSegment
        end
    end

    -- Next segment is clear - GREEN
    return SIGNAL_GREEN, currentSegment, nextSegment
end

-- Update train position and recalculate signal state (with throttling)
function UpdateTrainBlockPosition(trainId, position, trackId, direction)
    if not Config.BlockSignaling or not Config.BlockSignaling.enabled then
        return nil
    end

    local train = ActiveTrains[trainId]
    if not train then return nil end

    -- THROTTLE: Only recalculate if enough time has passed
    local now = GetGameTimer()
    local lastCheck = LastSegmentCheck[trainId] or 0
    local previousState = TrainSignalStates[trainId]

    -- Skip recalculation if throttle not met (unless state was RED - always check RED)
    if (now - lastCheck) < SEGMENT_CHECK_THROTTLE then
        if previousState and previousState.signalState ~= SIGNAL_RED then
            return previousState.signalState  -- Return cached state
        end
    end

    LastSegmentCheck[trainId] = now

    -- Calculate new signal state
    local signalState, currentSegment, nextSegment = CalculateSignalState(trainId, position, trackId, direction)

    -- Check for state change
    local stateChanged = not previousState or previousState.signalState ~= signalState

    -- Calculate speed multiplier with minimum yellow speed protection
    local speedMultiplier = Config.BlockSignaling.signalSpeeds[signalState]
    local minSpeedEnforced = false

    if signalState == SIGNAL_YELLOW then
        -- Calculate what the target speed would be
        local trackSpeed = Config.TrackSpeeds and Config.TrackSpeeds[trackId]
        local baseSpeed = trackSpeed and trackSpeed.default or Config.Train.speed
        local targetSpeed = baseSpeed * speedMultiplier

        -- Enforce minimum yellow speed to prevent rubber-banding
        if targetSpeed < MIN_YELLOW_SPEED then
            speedMultiplier = MIN_YELLOW_SPEED / baseSpeed
            minSpeedEnforced = true
        end
    end

    -- Update stored state
    TrainSignalStates[trainId] = {
        currentSegment = currentSegment and currentSegment.id,
        signalState = signalState,
        nextSegment = nextSegment and nextSegment.id,
        lastUpdate = os.time(),
        minSpeedEnforced = minSpeedEnforced
    }

    -- Notify clients if state changed
    if stateChanged then
        local segmentName = currentSegment and currentSegment.name or 'Unknown'
        local nextName = nextSegment and nextSegment.name or nil

        Transit.Debug('SIGNAL:', trainId, '=', signalState:upper(), 'in', segmentName,
            minSpeedEnforced and '(min speed enforced)' or '')

        TriggerClientEvent('dps-transit:client:signalStateChange', -1, {
            trainId = trainId,
            signalState = signalState,
            currentSegment = segmentName,
            nextSegment = nextName,
            speedMultiplier = speedMultiplier,
            minSpeedEnforced = minSpeedEnforced
        })

        -- If RED or YELLOW, update NUI with held status for ETA display
        if signalState == SIGNAL_RED or signalState == SIGNAL_YELLOW then
            TriggerClientEvent('dps-transit:client:trainHeldStatus', -1, {
                trainId = trainId,
                isHeld = (signalState == SIGNAL_RED),
                isCaution = (signalState == SIGNAL_YELLOW),
                reason = 'Train ahead in ' .. (nextName or 'next section'),
                segmentName = segmentName
            })
        elseif signalState == SIGNAL_GREEN and previousState and
               (previousState.signalState == SIGNAL_RED or previousState.signalState == SIGNAL_YELLOW) then
            -- Clear held status
            TriggerClientEvent('dps-transit:client:trainHeldStatus', -1, {
                trainId = trainId,
                isHeld = false,
                isCaution = false
            })
        end

        -- If RED, notify passengers on the train
        if signalState == SIGNAL_RED and Config.BlockSignaling.announcements.notifyPassengers then
            for playerId, playerTrainId in pairs(PlayersOnTrains or {}) do
                if playerTrainId == trainId then
                    TriggerClientEvent('dps-transit:client:signalHoldAnnouncement', playerId, {
                        segmentName = segmentName,
                        reason = 'Train ahead in ' .. (nextName or 'next section')
                    })
                end
            end
        end
    end

    return signalState
end

-- Clean up train from block signaling when removed
function CleanupTrainFromBlocks(trainId)
    -- Use force release to clear all segments and pending releases
    ForceLeaveAllSegments(trainId)

    -- Clear throttle cache
    LastSegmentCheck[trainId] = nil

    -- Clear signal state
    TrainSignalStates[trainId] = nil
end

-- Get signal state for a train
function GetTrainSignalState(trainId)
    return TrainSignalStates[trainId]
end

-- Get all segment occupancy (for debugging/NUI)
function GetAllSegmentOccupancy()
    local result = {}

    for _, segment in ipairs(Config.BlockSignaling.segments) do
        local occupant = SegmentOccupancy[segment.id]
        result[segment.id] = {
            name = segment.name,
            track = segment.track,
            occupied = occupant ~= nil,
            trainId = occupant and occupant.trainId,
            since = occupant and occupant.enteredAt
        }
    end

    return result
end

-- Exports for block signaling
exports('GetSegmentAtPosition', GetSegmentAtPosition)
exports('GetTrainSignalState', GetTrainSignalState)
exports('GetAllSegmentOccupancy', GetAllSegmentOccupancy)
exports('IsSegmentOccupied', IsSegmentOccupied)

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------

CreateThread(function()
    if not Config.Schedule.enabled then
        Transit.Debug('Scheduler disabled')
        return
    end

    Wait(2000)  -- Wait for system to initialize

    Transit.Debug('Scheduler starting with 70/30 passenger/freight split...')

    -- Initialize block signaling system
    InitializeBlockSignaling()

    -- Initialize each enabled line
    for lineId, line in pairs(Config.Lines) do
        if line.enabled then
            InitializeLine(lineId)
        end
    end

    -- Main scheduler loop
    while true do
        for lineId, line in pairs(Config.Lines) do
            if line.enabled then
                ProcessLineSchedule(lineId)
            end
        end

        Wait(10000)  -- Check every 10 seconds
    end
end)

-- Initialize a line's schedule
function InitializeLine(lineId)
    local line = Config.Lines[lineId]
    if not line then return end

    LineSchedules[lineId] = {
        currentSlot = 0,
        lastMinute = -1,
        activeTrains = {}
    }

    LastSpawnTime[lineId] = 0

    Transit.Debug('Initialized line:', lineId, '| Track:', line.track, '| P/F ratio:', line.schedule.passengerRatio .. '/' .. line.schedule.freightRatio)
end

-----------------------------------------------------------
-- SCHEDULE PROCESSING
-----------------------------------------------------------

-- Process schedule for a single line
function ProcessLineSchedule(lineId)
    local line = Config.Lines[lineId]
    local schedule = LineSchedules[lineId]
    local slots = Config.ScheduleSlots[lineId]

    if not line or not schedule or not slots then return end

    -- Get current game time or real time
    local currentMinute
    if Config.Schedule.useGameTime then
        local hour, minute = GetClockHours(), GetClockMinutes()
        currentMinute = minute
    else
        currentMinute = tonumber(os.date('%M'))
    end

    -- Skip if we already processed this minute
    if currentMinute == schedule.lastMinute then return end
    schedule.lastMinute = currentMinute

    -- Find matching slot
    for slotIndex, slot in ipairs(slots) do
        if slot.minute == currentMinute then
            -- Check if this slot should run (time period adjustment)
            if not ShouldSlotRun(slotIndex, lineId) then
                Transit.Debug('Skipping slot', slotIndex, 'on', lineId, '(off-peak reduction)')
                return
            end

            -- Check max trains
            local periodName, period = GetCurrentTimePeriod()
            local activeCount = CountActiveTrains(lineId)

            if activeCount >= period.minTrains + 2 then
                Transit.Debug('Max trains active on', lineId, '| Active:', activeCount)
                return
            end

            -- Spawn the scheduled train
            SpawnScheduledTrain(lineId, slot)

            schedule.currentSlot = slotIndex
            break
        end
    end
end

-- Count active trains on a line (excludes emergency stopped trains)
function CountActiveTrains(lineId, includeEmergency)
    local count = 0
    for _, train in pairs(ActiveTrains) do
        if train.lineId == lineId then
            -- Don't count emergency stopped trains toward the limit
            -- This allows scheduler to spawn replacement trains
            if not includeEmergency and train.status == 'emergency_stopped' then
                goto continue
            end
            count = count + 1
        end
        ::continue::
    end
    return count
end

-- Count emergency stopped trains (for monitoring)
function CountEmergencyStoppedTrains(lineId)
    local count = 0
    for _, train in pairs(ActiveTrains) do
        if train.status == 'emergency_stopped' then
            if not lineId or train.lineId == lineId then
                count = count + 1
            end
        end
    end
    return count
end

-----------------------------------------------------------
-- TRAIN SPAWNING
-----------------------------------------------------------

-- Spawn a scheduled train based on slot configuration
function SpawnScheduledTrain(lineId, slot)
    local line = Config.Lines[lineId]
    if not line then return nil end

    -- Get consist configuration
    local consist = GetConsist(slot.type, slot.consist)
    if not consist then
        Transit.Debug('Invalid consist:', slot.consist)
        return nil
    end

    -- Determine start station
    local startStation = line.terminus.south
    local direction = true  -- Northbound

    -- Alternate direction for variety
    local schedule = LineSchedules[lineId]
    if schedule and (schedule.currentSlot % 2 == 1) then
        startStation = line.terminus.north
        direction = false  -- Southbound
    end

    local station = Config.Stations[startStation]
    if not station or (station.platform.x == 0 and station.platform.y == 0) then
        Transit.Debug('Invalid start station:', startStation)
        return nil
    end

    -- Check emergency hold
    if EmergencyHold.active then
        Transit.Debug('Train spawn blocked: Emergency hold active at', EmergencyHold.stationId)
        return nil
    end

    -- Check track occupancy
    if not IsTrackClear(line.track, station.trackProgress - 0.02, station.trackProgress + 0.02) then
        Transit.Debug('Train spawn blocked: Track', line.track, 'not clear at', startStation)
        return nil
    end

    -- LOOP RESTART SAFETY: Check if spawn segment is clear (prevents ghost-blocking)
    -- This handles edge case where previous train's tail clearance timer hasn't fired yet
    if Config.BlockSignaling and Config.BlockSignaling.enabled then
        local spawnSegment = GetSegmentAtPosition(station.platform.xyz, line.track)
        if spawnSegment then
            local isOccupied, occupantId = IsSegmentOccupied(spawnSegment.id, nil)
            if isOccupied then
                Transit.Debug('Train spawn blocked: Segment', spawnSegment.id, 'still occupied by', occupantId)
                -- Clear stale occupancy if the occupant train no longer exists
                if occupantId and not ActiveTrains[occupantId] then
                    Transit.Debug('BLOCK: Clearing stale segment occupancy from removed train', occupantId)
                    ForceLeaveAllSegments(occupantId)
                else
                    return nil  -- Segment legitimately occupied, wait for next spawn window
                end
            end
            -- Also check for pending releases that might indicate tail clearance in progress
            local pending = PendingSegmentReleases[spawnSegment.id]
            if pending then
                Transit.Debug('Train spawn blocked: Segment', spawnSegment.id, 'has pending tail clearance')
                return nil
            end
        end
    end

    -- Generate train ID
    local trainId = Transit.GenerateTrainId()

    -- Create train data
    local trainData = {
        id = trainId,
        lineId = lineId,
        trainType = slot.type,
        consistKey = slot.consist,
        consist = consist,
        direction = direction,
        startStation = startStation,
        currentStation = startStation,
        nextStation = direction and station.next or station.prev,
        status = 'departing',
        trackProgress = station.trackProgress,
        currentPosition = station.platform.xyz,
        currentTrack = line.track,
        spawnTime = os.time(),
        passengers = 0,
        canBoard = (slot.type == 'passenger')  -- Only passenger trains allow boarding
    }

    -- Register in active trains
    ActiveTrains[trainId] = trainData

    -- Register on track
    RegisterTrainOnTrack(trainId, line.track, station.trackProgress)

    -- ATOMIC SPAWN CHECK: Final clearance verification right before entity creation
    -- This prevents race condition if another train's tail entered between initial check and now
    if Config.BlockSignaling and Config.BlockSignaling.enabled then
        local spawnSegment = GetSegmentAtPosition(station.platform.xyz, line.track)
        if spawnSegment then
            -- Check for segment occupation (excluding ourselves - we just registered)
            local isOccupied, occupantId = IsSegmentOccupied(spawnSegment.id, trainId)
            if isOccupied or PendingSegmentReleases[spawnSegment.id] then
                -- Race condition detected! Rollback registration
                Transit.Debug('SPAWN RACE: Segment became occupied during spawn prep, rolling back')
                ActiveTrains[trainId] = nil
                UnregisterTrainFromTrack(trainId, line.track)
                return nil
            end
        end
    end

    -- Notify clients
    TriggerClientEvent('dps-transit:client:spawnTrain', -1, trainId, trainData)

    -- Log spawn
    local typeLabel = slot.type:upper()
    Transit.Debug('[' .. typeLabel .. '] Spawned on', lineId, ':', trainId, 'at', startStation, direction and 'NB' or 'SB')

    -- Trigger events
    TriggerEvent('dps-transit:trainDeparted', trainId, startStation)
    TriggerClientEvent('dps-transit:client:trainDeparted', -1, trainId, startStation)

    return trainId
end

-----------------------------------------------------------
-- TRACK MANAGEMENT
-----------------------------------------------------------

-- Check if track segment is clear
function IsTrackClear(trackId, startProgress, endProgress)
    local occupancy = TrackOccupancy[trackId]
    if not occupancy then return true end

    for trainId, data in pairs(occupancy) do
        local trainProgress = data.progress or 0
        if trainProgress >= startProgress - 0.05 and trainProgress <= endProgress + 0.05 then
            Transit.Debug('Track', trackId, 'blocked by train', trainId, 'at progress', trainProgress)
            return false
        end
    end

    return true
end

-- Register train on track
function RegisterTrainOnTrack(trainId, trackId, progress)
    if not TrackOccupancy[trackId] then
        TrackOccupancy[trackId] = {}
    end

    TrackOccupancy[trackId][trainId] = {
        progress = progress,
        registeredAt = os.time()
    }

    Transit.Debug('Train', trainId, 'registered on track', trackId)
end

-- Update train position
function UpdateTrainTrackPosition(trainId, trackId, progress)
    if TrackOccupancy[trackId] and TrackOccupancy[trackId][trainId] then
        TrackOccupancy[trackId][trainId].progress = progress
    end
end

-- Unregister train from track
function UnregisterTrainFromTrack(trainId, trackId)
    if TrackOccupancy[trackId] then
        TrackOccupancy[trackId][trainId] = nil
        Transit.Debug('Train', trainId, 'unregistered from track', trackId)
    end
end

-----------------------------------------------------------
-- TRAIN STATE HANDLERS
-----------------------------------------------------------

-- Handle train arriving at station
RegisterNetEvent('dps-transit:server:trainAtStation', function(trainId, stationId)
    local train = ActiveTrains[trainId]
    if not train then return end

    train.currentStation = stationId
    train.status = 'boarding'

    local station = Config.Stations[stationId]
    if station then
        train.trackProgress = station.trackProgress
    end

    Transit.Debug('Train', trainId, '(' .. train.trainType .. ') arrived at', stationId)

    -- Trigger events
    TriggerEvent('dps-transit:trainArrived', trainId, stationId)
    TriggerClientEvent('dps-transit:client:trainArrived', -1, trainId, stationId)

    -- Only announce passenger trains
    if train.trainType == 'passenger' then
        AnnounceArrival(stationId, trainId)
    end
end)

-- Handle train departing station
RegisterNetEvent('dps-transit:server:trainDeparting', function(trainId, stationId)
    local train = ActiveTrains[trainId]
    if not train then return end

    local station = Config.Stations[stationId]
    if not station then return end

    -- Check emergency hold
    if EmergencyHold.active and EmergencyHold.stationId == stationId then
        train.status = 'held'
        EmergencyHold.heldTrains[trainId] = true
        Transit.Debug('Train', trainId, 'held at', stationId)
        TriggerClientEvent('dps-transit:client:trainHeld', -1, trainId, stationId)
        return
    end

    -- Update next station
    train.currentStation = stationId
    train.nextStation = train.direction and station.next or station.prev
    train.status = 'running'

    Transit.Debug('Train', trainId, 'departing', stationId, '| Next:', train.nextStation)

    -- Handle junction switching if crossing tracks
    if train.nextStation then
        HandleJunctionSwitch(trainId, stationId, train.nextStation)
    end

    -- Check terminus
    if not train.nextStation then
        Transit.Debug('Train', trainId, 'reached terminus at', stationId)
        RemoveTrain(trainId)
        return
    end

    -- Trigger events
    TriggerEvent('dps-transit:trainDeparted', trainId, stationId)
    TriggerClientEvent('dps-transit:client:trainDeparted', -1, trainId, stationId)
end)

-----------------------------------------------------------
-- JUNCTION SAFETY SYSTEM WITH BLOCK SIGNALING
-----------------------------------------------------------

-- Junction lock state (prevents collision at track switches)
local JunctionLocks = {}

-- Block signal configuration
local BlockSignals = {
    -- Distance in meters at which a block is considered occupied
    blockDistance = 500.0,

    -- Minimum clearance before another train can enter
    clearanceDistance = 200.0,

    -- Safe stop buffer: trains stop THIS far BEFORE the switch
    -- This prevents trains from blocking both tracks when signal-stopped
    safeStopBuffer = 50.0,

    -- Junction definitions
    junctions = {
        ['paleto_junction'] = {
            coords = vec3(2521.0, 6135.0, 39.0),  -- Approximate junction coords
            tracks = { 0, 13 },  -- Tracks that meet here
            blockRadius = 300.0,  -- Block signal radius
            safeStopZone = {
                -- Trains approaching from Track 0 stop here (before switch)
                [0] = vec3(2470.0, 5850.0, 38.0),
                -- Trains approaching from Track 13 stop here (before switch)
                [13] = vec3(2570.0, 6180.0, 40.0)
            }
        }
    }
}

-- Get safe stopping position for a train at a junction
function GetSafeStopPosition(junctionId, trackId)
    local junctionConfig = BlockSignals.junctions[junctionId]
    if not junctionConfig or not junctionConfig.safeStopZone then
        -- Fallback: stop at buffer distance from junction center
        if junctionConfig then
            -- Calculate position buffer meters before junction
            return junctionConfig.coords, BlockSignals.safeStopBuffer
        end
        return nil, 0
    end

    local stopPos = junctionConfig.safeStopZone[trackId]
    if stopPos then
        return stopPos, 0
    end

    -- Fallback to junction coords with buffer
    return junctionConfig.coords, BlockSignals.safeStopBuffer
end

-- Check if train is in the safe stop zone (not on the switch)
function IsTrainInSafeZone(trainId, junctionId)
    local train = ActiveTrains[trainId]
    local junctionConfig = BlockSignals.junctions[junctionId]

    if not train or not train.currentPosition or not junctionConfig then
        return false
    end

    local trainPos = vec3(train.currentPosition.x, train.currentPosition.y, train.currentPosition.z)
    local distFromJunction = #(trainPos - junctionConfig.coords)

    -- Train is safe if it's outside the switch danger zone (buffer distance)
    return distFromJunction > BlockSignals.safeStopBuffer
end

-- Check if junction is occupied (includes distance-based block signaling)
function IsJunctionOccupied(junctionId, requestingTrainId)
    local lock = JunctionLocks[junctionId]
    local junctionConfig = BlockSignals.junctions[junctionId]

    -- Check lock state
    if lock then
        local now = os.time()
        if lock.lockedAt and (now - lock.lockedAt) > 120 then
            Transit.Debug('Junction', junctionId, 'lock expired, clearing')
            JunctionLocks[junctionId] = nil
        elseif lock.trainId ~= requestingTrainId then
            return true, lock.trainId
        end
    end

    -- Check block signal (distance-based) if junction configured
    if junctionConfig then
        for trainId, train in pairs(ActiveTrains) do
            -- Skip requesting train
            if trainId == requestingTrainId then
                goto continue
            end

            -- Check if train is on a conflicting track
            local onConflictingTrack = false
            if train.currentTrack then
                for _, track in ipairs(junctionConfig.tracks) do
                    if train.currentTrack == track then
                        onConflictingTrack = true
                        break
                    end
                end
            end

            if not onConflictingTrack then
                goto continue
            end

            -- Check distance from junction
            if train.currentPosition then
                local trainPos = vec3(train.currentPosition.x, train.currentPosition.y, train.currentPosition.z)
                local dist = #(trainPos - junctionConfig.coords)

                if dist < junctionConfig.blockRadius then
                    Transit.Debug('Block signal: Train', trainId, 'within', math.floor(dist), 'm of junction', junctionId)
                    return true, trainId
                end
            end

            ::continue::
        end
    end

    return false, nil
end

-- Lock junction for a train (with block signal check)
function LockJunction(junctionId, trainId)
    local occupied, occupyingTrain = IsJunctionOccupied(junctionId, trainId)

    if occupied then
        return false, 'Block signal: junction occupied by ' .. (occupyingTrain or 'unknown')
    end

    JunctionLocks[junctionId] = {
        occupied = true,
        trainId = trainId,
        lockedAt = os.time()
    }

    Transit.Debug('Junction', junctionId, 'locked by train', trainId)
    return true
end

-- Release junction lock
function ReleaseJunction(junctionId, trainId)
    local lock = JunctionLocks[junctionId]

    if lock and lock.trainId == trainId then
        JunctionLocks[junctionId] = nil
        Transit.Debug('Junction', junctionId, 'released by train', trainId)
        return true
    end

    return false
end

-- Get train distance from junction
function GetTrainDistanceFromJunction(trainId, junctionId)
    local train = ActiveTrains[trainId]
    local junctionConfig = BlockSignals.junctions[junctionId]

    if not train or not train.currentPosition or not junctionConfig then
        return math.huge
    end

    local trainPos = vec3(train.currentPosition.x, train.currentPosition.y, train.currentPosition.z)
    return #(trainPos - junctionConfig.coords)
end

-- Check block signal status
function GetBlockSignalStatus(junctionId)
    local junctionConfig = BlockSignals.junctions[junctionId]
    if not junctionConfig then return nil end

    local status = {
        junctionId = junctionId,
        locked = JunctionLocks[junctionId] ~= nil,
        lockedBy = JunctionLocks[junctionId] and JunctionLocks[junctionId].trainId,
        trainsInBlock = {}
    }

    for trainId, train in pairs(ActiveTrains) do
        if train.currentPosition then
            local trainPos = vec3(train.currentPosition.x, train.currentPosition.y, train.currentPosition.z)
            local dist = #(trainPos - junctionConfig.coords)

            if dist < BlockSignals.blockDistance then
                table.insert(status.trainsInBlock, {
                    trainId = trainId,
                    distance = math.floor(dist),
                    track = train.currentTrack
                })
            end
        end
    end

    return status
end

exports('GetBlockSignalStatus', GetBlockSignalStatus)
exports('GetTrainDistanceFromJunction', GetTrainDistanceFromJunction)

-- Track junction wait times for deadlock detection
local JunctionWaitTimes = {}

-- Handle junction track switching with safety checks
function HandleJunctionSwitch(trainId, currentStation, nextStation)
    local current = Config.Stations[currentStation]
    local next = Config.Stations[nextStation]

    if not current or not next then return end

    local isJunction = current.features and current.features.isJunction
    local crossingTracks = current.track ~= next.track

    if isJunction or crossingTracks then
        local junctionId = currentStation

        -- Check junction safety - wait if occupied
        local occupied, blockingTrain = IsJunctionOccupied(junctionId, trainId)
        if occupied then
            local train = ActiveTrains[trainId]
            if train then
                train.status = 'waiting_junction'

                -- Initialize or update wait time tracking
                if not JunctionWaitTimes[trainId] then
                    JunctionWaitTimes[trainId] = {
                        junctionId = junctionId,
                        startedAt = os.time(),
                        retryCount = 0
                    }
                end

                local waitData = JunctionWaitTimes[trainId]
                waitData.retryCount = waitData.retryCount + 1
                local waitDuration = os.time() - waitData.startedAt

                Transit.Debug('Train', trainId, 'waiting at junction', junctionId, '(', waitDuration, 's, retry #', waitData.retryCount, ')')

                -- DEADLOCK DETECTION: If waiting more than 60 seconds
                if waitDuration > 60 then
                    Transit.Debug('DEADLOCK DETECTED: Train', trainId, 'waited', waitDuration, 's at', junctionId)

                    -- Perform safety check on blocking train
                    if blockingTrain and ActiveTrains[blockingTrain] then
                        local blocker = ActiveTrains[blockingTrain]

                        -- If blocking train is also waiting, we have a true deadlock
                        if blocker.status == 'waiting_junction' then
                            Transit.Debug('Mutual deadlock! Forcing', blockingTrain, 'to yield')

                            -- Force the older train to reverse/reroute
                            local blockerWait = JunctionWaitTimes[blockingTrain]
                            if blockerWait and (os.time() - blockerWait.startedAt) > waitDuration then
                                -- Other train waited longer, we yield
                                ResolveDeadlock(trainId, junctionId, 'yield')
                            else
                                -- We waited longer, other train yields
                                ResolveDeadlock(blockingTrain, junctionId, 'yield')
                            end
                        else
                            -- Blocking train is moving, just wait a bit more
                            Transit.Debug('Blocking train', blockingTrain, 'is', blocker.status, '- extending wait')
                        end
                    else
                        -- No blocking train found, clear the deadlock
                        Transit.Debug('No valid blocker found, clearing junction wait')
                        JunctionWaitTimes[trainId] = nil
                        train.status = 'running'
                    end
                end

                -- Queue for retry (every 5 seconds)
                SetTimeout(5000, function()
                    if ActiveTrains[trainId] and ActiveTrains[trainId].status == 'waiting_junction' then
                        HandleJunctionSwitch(trainId, currentStation, nextStation)
                    end
                end)
            end
            return
        end

        -- Junction is clear, reset wait tracking
        JunctionWaitTimes[trainId] = nil

        -- Lock junction
        local locked, err = LockJunction(junctionId, trainId)
        if not locked then
            Transit.Debug('Failed to lock junction:', err)
            return
        end

        local fromTrack = current.track
        local toTrack = next.track

        Transit.Debug('Junction switch: Train', trainId, 'from track', fromTrack, 'to', toTrack)

        TriggerClientEvent('dps-transit:client:switchTrack', -1, trainId, fromTrack, toTrack)

        UnregisterTrainFromTrack(trainId, fromTrack)
        RegisterTrainOnTrack(trainId, toTrack, current.trackProgress)

        -- Release junction after train clears (estimated time)
        SetTimeout(15000, function()
            ReleaseJunction(junctionId, trainId)
        end)
    end
end

-- Resolve a junction deadlock
function ResolveDeadlock(trainId, junctionId, resolution)
    local train = ActiveTrains[trainId]
    if not train then return end

    Transit.Debug('Resolving deadlock for train', trainId, 'with', resolution)

    if resolution == 'yield' then
        -- Remove this train from the system to clear the deadlock
        -- In a real system you might reverse it or reroute
        JunctionWaitTimes[trainId] = nil
        train.status = 'deadlock_resolved'

        -- Notify clients
        TriggerClientEvent('dps-transit:client:trainHeld', -1, trainId, junctionId)

        -- After 30 seconds, try to resume or remove
        SetTimeout(30000, function()
            if ActiveTrains[trainId] and ActiveTrains[trainId].status == 'deadlock_resolved' then
                local stillOccupied = IsJunctionOccupied(junctionId, trainId)
                if stillOccupied then
                    Transit.Debug('Junction still occupied, removing train', trainId)
                    RemoveTrain(trainId)
                else
                    Transit.Debug('Junction clear, resuming train', trainId)
                    ActiveTrains[trainId].status = 'running'
                    TriggerClientEvent('dps-transit:client:trainReleased', -1, trainId)
                end
            end
        end)
    end
end

-- Get junction status for debugging
function GetJunctionStatus()
    return JunctionLocks
end

exports('GetJunctionStatus', GetJunctionStatus)
exports('IsJunctionOccupied', IsJunctionOccupied)

-- Update train position (from client)
RegisterNetEvent('dps-transit:server:updateTrainPosition', function(trainId, position, progress)
    local train = ActiveTrains[trainId]
    if not train then return end

    train.currentPosition = position
    train.trackProgress = progress

    if train.currentTrack then
        UpdateTrainTrackPosition(trainId, train.currentTrack, progress)
    end

    -- Update block signaling state
    if Config.BlockSignaling and Config.BlockSignaling.enabled then
        local signalState = UpdateTrainBlockPosition(trainId, position, train.currentTrack, train.direction)

        -- Include signal state in position update to clients
        TriggerClientEvent('dps-transit:client:trainPositionUpdate', -1, trainId, position, progress, signalState)
    else
        TriggerClientEvent('dps-transit:client:trainPositionUpdate', -1, trainId, position, progress)
    end
end)

-- Remove train from system
function RemoveTrain(trainId)
    local train = ActiveTrains[trainId]
    if train then
        Transit.Debug('Removing train:', trainId)

        if train.currentTrack then
            UnregisterTrainFromTrack(trainId, train.currentTrack)
        end

        if EmergencyHold.heldTrains[trainId] then
            EmergencyHold.heldTrains[trainId] = nil
        end

        -- Clean up from block signaling system
        CleanupTrainFromBlocks(trainId)

        ActiveTrains[trainId] = nil

        TriggerClientEvent('dps-transit:client:removeTrain', -1, trainId)
    end
end

-----------------------------------------------------------
-- ANNOUNCEMENTS
-----------------------------------------------------------

function AnnounceArrival(stationId, trainId)
    local train = ActiveTrains[trainId]
    if not train then return end

    local station = Config.Stations[stationId]
    if not station then return end

    -- Get destination
    local line = Config.Lines[train.lineId]
    local destStation = train.direction and line.terminus.north or line.terminus.south
    local dest = Config.Stations[destStation]
    local destName = dest and dest.shortName or 'Unknown'

    -- Notify nearby players
    local players = Bridge.GetPlayers()
    for _, playerId in ipairs(players) do
        local ped = GetPlayerPed(playerId)
        if ped then
            local playerCoords = GetEntityCoords(ped)
            local stationCoords = station.platform.xyz
            local dist = #(playerCoords - stationCoords)

            if dist < 100.0 then
                TriggerClientEvent('dps-transit:client:stationAnnouncement', playerId, {
                    type = 'arrival',
                    station = stationId,
                    trainId = trainId,
                    destination = destName,
                    line = train.lineId,
                    message = line.shortName .. ' train to ' .. destName .. ' is now boarding'
                })
            end
        end
    end
end

-----------------------------------------------------------
-- SCHEDULE CALLBACKS
-----------------------------------------------------------

-- Get schedule for display
lib.callback.register('dps-transit:server:getSchedule', function(source)
    local schedules = {}

    for lineId, line in pairs(Config.Lines) do
        if line.enabled then
            local currentMinute = tonumber(os.date('%M'))
            local nextTrain = GetNextScheduledTrain(lineId, currentMinute)
            local periodName, period = GetCurrentTimePeriod()

            schedules[lineId] = {
                name = line.name,
                shortName = line.shortName,
                track = line.track,
                period = periodName,
                nextDeparture = nextTrain,
                activeTrains = CountActiveTrains(lineId),
                passengerRatio = line.schedule.passengerRatio,
                freightRatio = line.schedule.freightRatio
            }
        end
    end

    return schedules
end)

-- Get active trains
lib.callback.register('dps-transit:server:getActiveTrains', function(source)
    return ActiveTrains
end)

-- Get next departures
function GetNextDepartures()
    local departures = {}

    for lineId, line in pairs(Config.Lines) do
        if line.enabled then
            local currentMinute = tonumber(os.date('%M'))
            local nextTrain = GetNextScheduledTrain(lineId, currentMinute)

            if nextTrain then
                table.insert(departures, {
                    line = lineId,
                    lineName = line.shortName,
                    station = line.terminus.south,
                    time = nextTrain.minute,
                    type = nextTrain.type,
                    direction = true
                })
            end
        end
    end

    return departures
end

-----------------------------------------------------------
-- EMERGENCY HOLD SYSTEM
-----------------------------------------------------------

function ActivateEmergencyHold(stationId, requestedBy, reason)
    if not Config.Stations[stationId] then
        return false, 'Invalid station'
    end

    EmergencyHold.active = true
    EmergencyHold.stationId = stationId
    EmergencyHold.requestedBy = requestedBy
    EmergencyHold.reason = reason or 'Police activity'
    EmergencyHold.heldTrains = {}

    Transit.Debug('Emergency hold activated at', stationId, 'by', requestedBy)

    local station = Config.Stations[stationId]
    TriggerClientEvent('dps-transit:client:emergencyHold', -1, {
        active = true,
        stationId = stationId,
        stationName = station.shortName,
        reason = EmergencyHold.reason
    })

    -- Hold trains at station
    for trainId, train in pairs(ActiveTrains) do
        if train.currentStation == stationId then
            train.status = 'held'
            EmergencyHold.heldTrains[trainId] = true
            TriggerClientEvent('dps-transit:client:trainHeld', -1, trainId, stationId)
        end
    end

    return true
end

function ReleaseEmergencyHold(releasedBy)
    if not EmergencyHold.active then
        return false, 'No active hold'
    end

    local stationId = EmergencyHold.stationId

    Transit.Debug('Emergency hold released at', stationId, 'by', releasedBy)

    -- Resume held trains
    for trainId, _ in pairs(EmergencyHold.heldTrains) do
        local train = ActiveTrains[trainId]
        if train then
            train.status = 'boarding'
            TriggerClientEvent('dps-transit:client:trainReleased', -1, trainId)
        end
    end

    -- Clear state
    EmergencyHold.active = false
    EmergencyHold.stationId = nil
    EmergencyHold.requestedBy = nil
    EmergencyHold.reason = nil
    EmergencyHold.heldTrains = {}

    TriggerClientEvent('dps-transit:client:emergencyHold', -1, {
        active = false,
        stationId = stationId
    })

    return true
end

function GetEmergencyHoldStatus()
    return {
        active = EmergencyHold.active,
        stationId = EmergencyHold.stationId,
        reason = EmergencyHold.reason,
        heldTrains = Transit.TableLength(EmergencyHold.heldTrains)
    }
end

-- Police hold request
RegisterNetEvent('dps-transit:server:requestEmergencyHold', function(stationId, reason)
    local source = source
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local job = Bridge.GetJob(source)
    local isPolice = job == 'police' or job == 'sheriff' or job == 'lspd' or job == 'bcso'
    local isAdmin = IsPlayerAceAllowed(source, 'command')

    if not isPolice and not isAdmin then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Transit Authority',
            description = 'Only law enforcement can request emergency holds',
            type = 'error'
        })
        return
    end

    local success, err = ActivateEmergencyHold(stationId, Bridge.GetIdentifier(source), reason)

    if success then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Emergency Hold',
            description = 'Trains held at ' .. Config.Stations[stationId].shortName,
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Hold Failed',
            description = err or 'Unknown error',
            type = 'error'
        })
    end
end)

-- Release hold
RegisterNetEvent('dps-transit:server:releaseEmergencyHold', function()
    local source = source
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local job = Bridge.GetJob(source)
    local isPolice = job == 'police' or job == 'sheriff' or job == 'lspd' or job == 'bcso'
    local isAdmin = IsPlayerAceAllowed(source, 'command')

    if not isPolice and not isAdmin then return end

    local success = ReleaseEmergencyHold(Bridge.GetIdentifier(source))

    if success then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Hold Released',
            description = 'Normal service resuming',
            type = 'success'
        })
    end
end)

lib.callback.register('dps-transit:server:getHoldStatus', function(source)
    return GetEmergencyHoldStatus()
end)

-----------------------------------------------------------
-- FREIGHT TRAIN INTEGRATION
-----------------------------------------------------------

-- Register external freight (from BigDaddy-Trains or similar)
RegisterNetEvent('dps-transit:server:registerFreight', function(freightId, trackId, position)
    if not TrackOccupancy[trackId] then
        TrackOccupancy[trackId] = {}
    end

    TrackOccupancy[trackId]['freight_' .. freightId] = {
        progress = position or 0,
        isFreight = true,
        isExternal = true,
        registeredAt = os.time()
    }

    Transit.Debug('External freight registered:', freightId, 'on track', trackId)
end)

RegisterNetEvent('dps-transit:server:unregisterFreight', function(freightId, trackId)
    if TrackOccupancy[trackId] then
        TrackOccupancy[trackId]['freight_' .. freightId] = nil
        Transit.Debug('External freight unregistered:', freightId)
    end
end)

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------

exports('SpawnTrain', function(lineId, slotOverride)
    local slots = Config.ScheduleSlots[lineId]
    local slot = slotOverride or (slots and slots[1])
    if slot then
        return SpawnScheduledTrain(lineId, slot)
    end
    return nil
end)

exports('RemoveTrain', RemoveTrain)
exports('GetActiveTrains', function() return ActiveTrains end)
exports('GetLineSchedule', function(lineId) return LineSchedules[lineId] end)
exports('ActivateEmergencyHold', ActivateEmergencyHold)
exports('ReleaseEmergencyHold', ReleaseEmergencyHold)
exports('GetEmergencyHoldStatus', GetEmergencyHoldStatus)
exports('IsTrackClear', IsTrackClear)
exports('CountActiveTrains', CountActiveTrains)
exports('CountEmergencyStoppedTrains', CountEmergencyStoppedTrains)
exports('GetNextDepartures', GetNextDepartures)

-----------------------------------------------------------
-- DISPATCHER MONITORING
-----------------------------------------------------------

-- Allowed jobs for dispatcher access
local DISPATCHER_JOBS = {
    ['dispatch'] = true,
    ['police'] = true,
    ['sheriff'] = true,
    ['lspd'] = true,
    ['bcso'] = true,
    ['admin'] = true
}

-- Check if player has dispatcher access
function HasDispatcherAccess(source)
    local Player = Bridge.GetPlayer(source)
    if not Player then return false end

    local job = Bridge.GetJob(source)

    -- Check job
    if DISPATCHER_JOBS[job] then return true end

    -- Check admin ace
    if IsPlayerAceAllowed(source, 'command') then return true end

    return false
end

-- Get full dispatcher data (segments + trains)
function GetDispatcherData()
    local segmentData = {}
    local trainData = {}
    local now = os.time()

    -- Segment lengths (approximate meters) for ETA calculation
    local segmentLengths = {
        T0_SEG1 = 2500, T0_SEG2 = 2500, T0_SEG3 = 2500,
        T0_SEG4 = 2500, T0_SEG5 = 2500, T0_SEG6 = 2500,
        T13_SEG1 = 1500, T13_SEG2 = 800, T13_SEG3 = 1200,
        T12_SEG1 = 2000, T12_SEG2 = 2000
    }

    -- Average speeds by train type (m/s)
    local avgSpeeds = {
        passenger = 20.0,
        freight = 15.0
    }

    -- Build segment data with occupancy info and ETA
    if Config.BlockSignaling and Config.BlockSignaling.segments then
        for _, segment in ipairs(Config.BlockSignaling.segments) do
            local occupant = SegmentOccupancy[segment.id]
            local signalState = nil
            local trainType = nil
            local isHeld = false
            local timeInSegment = nil
            local estimatedClearTime = nil

            if occupant then
                local train = ActiveTrains[occupant.trainId]
                if train then
                    trainType = train.trainType or 'passenger'
                    local trainSignal = TrainSignalStates[occupant.trainId]
                    if trainSignal then
                        signalState = trainSignal.signalState
                        isHeld = (signalState == 'red')
                    end

                    -- Calculate time in segment
                    if occupant.enteredAt then
                        timeInSegment = now - occupant.enteredAt
                    end

                    -- Calculate estimated clear time (if not held)
                    if not isHeld then
                        local segmentLength = segmentLengths[segment.id] or 2000
                        local trainSpeed = avgSpeeds[trainType] or 18.0

                        -- Estimate remaining distance (assume halfway through on average)
                        local remainingDistance = segmentLength * 0.5
                        if timeInSegment and timeInSegment > 0 then
                            -- Adjust based on time already in segment
                            local distanceTraveled = timeInSegment * trainSpeed
                            remainingDistance = math.max(0, segmentLength - distanceTraveled)
                        end

                        estimatedClearTime = remainingDistance / trainSpeed
                        -- Add carriage clearance time
                        estimatedClearTime = estimatedClearTime + (CARRIAGE_CLEARANCE_DELAY[trainType] or 6)
                    end
                end
            end

            -- Check for segment override (v2.6.0)
            local override = SegmentOverrides[segment.id]
            local isLocked = override and override.state == OVERRIDE_LOCKED

            segmentData[segment.id] = {
                name = segment.name,
                track = segment.track,
                occupied = occupant ~= nil,
                trainId = occupant and occupant.trainId,
                trainType = trainType,
                signalState = signalState,
                isHeld = isHeld,
                since = occupant and occupant.enteredAt,
                timeInSegment = timeInSegment,
                estimatedClearTime = estimatedClearTime,
                -- Segment override info
                isLocked = isLocked,
                lockReason = override and override.reason,
                lockedBy = override and override.setBy,
                lockedAt = override and override.setAt
            }
        end
    end

    -- Build train list
    for trainId, train in pairs(ActiveTrains) do
        local trainSignal = TrainSignalStates[trainId]
        local segment = trainSignal and trainSignal.currentSegment

        table.insert(trainData, {
            id = trainId,
            type = train.trainType or 'passenger',
            line = train.lineId,
            segment = segment,
            location = train.currentStation or 'En Route',
            status = train.status or 'running',
            isHeld = trainSignal and trainSignal.signalState == 'red',
            direction = train.direction and 'NB' or 'SB'
        })
    end

    return segmentData, trainData
end

-- Callback for dispatcher data
lib.callback.register('dps-transit:server:getDispatcherData', function(source)
    if not HasDispatcherAccess(source) then
        return nil, nil
    end

    return GetDispatcherData()
end)

-- Export for external access
exports('GetDispatcherData', GetDispatcherData)
exports('HasDispatcherAccess', HasDispatcherAccess)

-----------------------------------------------------------
-- DISPATCHER EMERGENCY ACTIONS
-- Manual override controls from dispatcher panel
-----------------------------------------------------------

-- Track dispatcher-initiated holds (separate from automatic signal holds)
local DispatcherHolds = {}

-- Handle emergency stop/release from dispatcher panel
RegisterNetEvent('dps-transit:server:dispatcherEmergencyAction', function(trainId, action)
    local source = source

    -- Validate dispatcher access
    if not HasDispatcherAccess(source) then
        Transit.Debug('[DISPATCHER] Access denied for source:', source)
        return
    end

    local train = ActiveTrains[trainId]
    if not train then
        Transit.Debug('[DISPATCHER] Train not found:', trainId)
        return
    end

    local dispatcherName = Bridge.GetCharacterName(source)

    if action == 'stop' then
        -- Emergency stop - dispatcher override
        Transit.Debug('[DISPATCHER] Emergency stop initiated by', dispatcherName, 'for train:', trainId)

        -- Mark as dispatcher hold (takes priority over automatic timeouts)
        DispatcherHolds[trainId] = {
            initiatedBy = source,
            dispatcherName = dispatcherName,
            timestamp = os.time(),
            reason = 'Dispatcher emergency stop'
        }

        -- Update train state
        train.status = 'emergency_stopped'
        train.dispatcherHold = true

        -- Force signal to RED
        TrainSignalStates[trainId] = TrainSignalStates[trainId] or {}
        TrainSignalStates[trainId].signalState = 'red'
        TrainSignalStates[trainId].dispatcherOverride = true

        -- Notify all clients
        TriggerClientEvent('dps-transit:client:emergencyBrake', -1, trainId, true)

        -- Notify passengers on this train (with dispatcher-specific title)
        TriggerClientEvent('dps-transit:client:signalHoldAnnouncement', -1, {
            trainId = trainId,
            segmentName = TrainSignalStates[trainId].currentSegment or 'Current Location',
            reason = 'Dispatcher hold - please stand by',
            isDispatcherHold = true,
            dispatcherName = dispatcherName
        })

        -- Log to server console
        print('^1[DPS-Transit] DISPATCHER EMERGENCY STOP^0: Train ' .. trainId .. ' stopped by ' .. dispatcherName)

    elseif action == 'release' then
        -- Release emergency brake
        Transit.Debug('[DISPATCHER] Emergency brake released by', dispatcherName, 'for train:', trainId)

        -- Clear dispatcher hold
        DispatcherHolds[trainId] = nil
        train.dispatcherHold = nil

        -- Clear override flag
        if TrainSignalStates[trainId] then
            TrainSignalStates[trainId].dispatcherOverride = nil
        end

        -- Update train state
        train.status = 'running'

        -- Recalculate signal state (may still be RED if blocked by another train)
        local segment = TrainSignalStates[trainId] and TrainSignalStates[trainId].currentSegment
        if segment then
            local newSignal = CalculateSignalState(trainId, segment)
            TrainSignalStates[trainId].signalState = newSignal

            -- Notify client of new state
            TriggerClientEvent('dps-transit:client:signalStateChange', -1, {
                trainId = trainId,
                signalState = newSignal,
                currentSegment = segment,
                speedMultiplier = newSignal == 'yellow' and 0.3 or 1.0
            })
        else
            -- No segment tracking, just release
            TriggerClientEvent('dps-transit:client:emergencyBrake', -1, trainId, false)
        end

        -- Log to server console
        print('^2[DPS-Transit] DISPATCHER RELEASE^0: Train ' .. trainId .. ' released by ' .. dispatcherName)
    end
end)

-- Check if a train has a dispatcher hold (prevents automatic release)
function HasDispatcherHold(trainId)
    return DispatcherHolds[trainId] ~= nil
end

-- Export for block signaling system to check dispatcher holds
exports('HasDispatcherHold', HasDispatcherHold)

-----------------------------------------------------------
-- SEGMENT OVERRIDE FUNCTIONS (v2.6.0)
-- Manual segment locks for maintenance/investigations
-----------------------------------------------------------

-- Lock a segment (force RED for all approaching trains)
function LockSegment(segmentId, reason, source)
    -- Validate segment exists
    if not SegmentLookup[segmentId] then
        Transit.Debug('[OVERRIDE] Invalid segment ID:', segmentId)
        return false, 'Invalid segment ID'
    end

    -- Get dispatcher info
    local dispatcherName = source and Bridge.GetCharacterName(source) or 'System'

    -- Set override
    SegmentOverrides[segmentId] = {
        state = OVERRIDE_LOCKED,
        reason = reason or 'Maintenance',
        setBy = dispatcherName,
        setBySource = source,
        setAt = os.time()
    }

    -- Log to console
    print('^3[DPS-Transit] SEGMENT LOCKED^0: ' .. segmentId .. ' by ' .. dispatcherName .. ' | Reason: ' .. (reason or 'Maintenance'))

    -- Notify all clients about the segment lock
    TriggerClientEvent('dps-transit:client:segmentOverrideChanged', -1, {
        segmentId = segmentId,
        locked = true,
        reason = reason,
        lockedBy = dispatcherName
    })

    -- Force signal recalculation for any trains approaching this segment
    RecalculateAffectedTrains(segmentId)

    return true
end

-- Unlock a segment (restore normal signaling)
function UnlockSegment(segmentId, source)
    if not SegmentOverrides[segmentId] then
        return false, 'Segment is not locked'
    end

    local override = SegmentOverrides[segmentId]
    local wasLockedBy = override.setBy

    -- Get dispatcher info
    local dispatcherName = source and Bridge.GetCharacterName(source) or 'System'

    -- Clear override
    SegmentOverrides[segmentId] = nil

    -- Log to console
    print('^2[DPS-Transit] SEGMENT UNLOCKED^0: ' .. segmentId .. ' by ' .. dispatcherName .. ' (was locked by ' .. wasLockedBy .. ')')

    -- Notify all clients
    TriggerClientEvent('dps-transit:client:segmentOverrideChanged', -1, {
        segmentId = segmentId,
        locked = false,
        unlockedBy = dispatcherName
    })

    -- Force signal recalculation for any trains that were held
    RecalculateAffectedTrains(segmentId)

    return true
end

-- Check if a segment is locked
function IsSegmentLocked(segmentId)
    local override = SegmentOverrides[segmentId]
    return override and override.state == OVERRIDE_LOCKED
end

-- Get segment override info
function GetSegmentOverride(segmentId)
    return SegmentOverrides[segmentId]
end

-- Get all segment overrides (for dispatcher panel)
function GetAllSegmentOverrides()
    return SegmentOverrides
end

-- Recalculate signals for trains affected by segment override change
function RecalculateAffectedTrains(segmentId)
    for trainId, signalState in pairs(TrainSignalStates) do
        -- Check if this train's next segment is the affected one
        if signalState.nextSegment == segmentId or signalState.currentSegment == segmentId then
            local train = ActiveTrains[trainId]
            if train and train.currentPosition then
                -- Force recalculation
                local newSignal, currentSeg, nextSeg = CalculateSignalState(
                    trainId,
                    train.currentPosition,
                    train.trackId,
                    train.direction
                )

                signalState.signalState = newSignal
                signalState.lastUpdate = os.time()

                -- Notify client
                TriggerClientEvent('dps-transit:client:signalStateChange', -1, {
                    trainId = trainId,
                    signalState = newSignal,
                    currentSegment = currentSeg and currentSeg.id,
                    nextSegment = nextSeg and nextSeg.id,
                    speedMultiplier = newSignal == 'yellow' and 0.3 or (newSignal == 'red' and 0 or 1.0),
                    isSegmentLock = IsSegmentLocked(nextSeg and nextSeg.id)
                })
            end
        end
    end
end

-- Event handler for dispatcher segment lock/unlock
RegisterNetEvent('dps-transit:server:segmentOverride', function(segmentId, action, reason)
    local source = source

    -- Validate dispatcher access
    if not HasDispatcherAccess(source) then
        Transit.Debug('[OVERRIDE] Access denied for source:', source)
        return
    end

    if action == 'lock' then
        local success, err = LockSegment(segmentId, reason, source)
        if not success then
            -- Notify player of error
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Segment Lock Failed',
                description = err,
                type = 'error'
            })
        end
    elseif action == 'unlock' then
        local success, err = UnlockSegment(segmentId, source)
        if not success then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Segment Unlock Failed',
                description = err,
                type = 'error'
            })
        end
    end
end)

-- Exports for segment overrides
exports('LockSegment', LockSegment)
exports('UnlockSegment', UnlockSegment)
exports('IsSegmentLocked', IsSegmentLocked)
exports('GetSegmentOverride', GetSegmentOverride)
exports('GetAllSegmentOverrides', GetAllSegmentOverrides)

exports('RegisterFreightTrain', function(id, track, pos)
    TriggerEvent('dps-transit:server:registerFreight', id, track, pos)
end)
