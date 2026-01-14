--[[
    DPS-Transit Server Main
    Core server-side functionality

    DATABASE SCALING NOTE:
    ----------------------
    Ticket persistence uses ox_inventory/qs-inventory metadata, NOT direct database queries.
    Day Pass expiry checks use os.time() comparisons in-memory (PlayerTickets table).

    If you add database persistence (oxmysql) in the future:
    1. Index the 'expiresAt' column for ticket queries
    2. Use server timestamps (os.time()) not client time for validation
    3. Consider periodic cleanup job for expired tickets (avoid table bloat)
    4. Use prepared statements to prevent SQL injection

    Current architecture: In-memory + inventory metadata = no database bottleneck.
]]

-- Active trains tracking
ActiveTrains = {}

-- Player tickets
PlayerTickets = {}

-- Initialize transit system
CreateThread(function()
    Wait(1000)

    print('^5[dps-transit] Initializing DPS Transit System v2.3.1...^0')

    -- Run config validation
    local valid, errors, warnings = Transit.ValidateStationConfig()

    if not valid then
        print('^1[dps-transit] Config validation failed! Some features may not work correctly.^0')
    end

    -- Start the scheduler if enabled
    if Config.Schedule.enabled then
        Transit.Debug('Schedule system enabled')
    end

    -- Start shuttles if enabled
    if Config.Shuttles and Config.Shuttles.enabled then
        Transit.Debug('Shuttle system enabled')
    end

    print('^2[dps-transit] Transit system initialized^0')
end)

-----------------------------------------------------------
-- TRAIN CLEANUP HANDLING
-----------------------------------------------------------

-- Handle client-side train cleanup notifications
RegisterNetEvent('dps-transit:server:trainCleaned', function(trainId, reason)
    if ActiveTrains[trainId] then
        Transit.Debug('Train', trainId, 'cleaned by client:', reason)
        ActiveTrains[trainId] = nil
    end
end)

-----------------------------------------------------------
-- PLAYER DROP-OFF HANDLING (Disconnect Cleanup)
-----------------------------------------------------------

-- Track players currently on trains
local PlayersOnTrains = {}

-- Register player boarding a train
RegisterNetEvent('dps-transit:server:playerBoarded', function(trainId)
    local source = source
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local citizenid = Bridge.GetIdentifier(source)

    PlayersOnTrains[citizenid] = {
        trainId = trainId,
        boardedAt = os.time(),
        lastZone = nil,
        source = source
    }

    Transit.Debug('Player', citizenid, 'boarded train', trainId)
end)

-- Register player exiting a train
RegisterNetEvent('dps-transit:server:playerExited', function(trainId)
    local source = source
    local Player = Bridge.GetPlayer(source)
    if not Player then return end

    local citizenid = Bridge.GetIdentifier(source)

    if PlayersOnTrains[citizenid] then
        PlayersOnTrains[citizenid] = nil
        Transit.Debug('Player', citizenid, 'exited train', trainId)
    end
end)

-- Handle player disconnect - clear their train state
AddEventHandler('playerDropped', function(reason)
    local source = source
    local citizenid = Bridge.GetIdentifier(source)

    if citizenid and PlayersOnTrains[citizenid] then
        Transit.Debug('Player', citizenid, 'disconnected while on train - clearing state')
        PlayersOnTrains[citizenid] = nil
    else
        -- Fallback: Search by source if identifier unavailable
        for cid, data in pairs(PlayersOnTrains) do
            if data.source == source then
                Transit.Debug('Player source', source, 'disconnected while on train - clearing state')
                PlayersOnTrains[cid] = nil
                break
            end
        end
    end
end)

-- Handle player unload (framework-agnostic via Bridge)
Bridge.OnPlayerUnload(function(source)
    local citizenid = Bridge.GetIdentifier(source)

    if citizenid and PlayersOnTrains[citizenid] then
        Transit.Debug('Player', citizenid, 'unloaded while on train - clearing state')
        PlayersOnTrains[citizenid] = nil
    end
end)

-- Check if player is on a train (for ticket sweep validation)
function IsPlayerOnTrain(citizenid)
    return PlayersOnTrains[citizenid] ~= nil
end

-- Get player's current train
function GetPlayerTrain(citizenid)
    local data = PlayersOnTrains[citizenid]
    return data and data.trainId or nil
end

exports('IsPlayerOnTrain', IsPlayerOnTrain)
exports('GetPlayerTrain', GetPlayerTrain)

-- Get all active trains
lib.callback.register('dps-transit:server:getActiveTrains', function(source)
    local trainData = {}

    for trainId, train in pairs(ActiveTrains) do
        trainData[trainId] = {
            id = train.id,
            direction = train.direction,
            currentStation = train.currentStation,
            nextStation = train.nextStation,
            status = train.status,
            position = train.currentPosition,
            progress = train.trackProgress
        }
    end

    return trainData
end)

-- Get train ETA for specific station
lib.callback.register('dps-transit:server:getTrainETA', function(source, trainId, stationId)
    local train = ActiveTrains[trainId]
    if not train then return nil end

    return CalculateETA(trainId, stationId)
end)

-- Get next arrivals at station
lib.callback.register('dps-transit:server:getStationArrivals', function(source, stationId)
    return GetStationArrivals(stationId)
end)

-- Purchase ticket
lib.callback.register('dps-transit:server:purchaseTicket', function(source, fromStation, toStation, paymentMethod)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false, 'Player not found' end

    -- Validate stations
    if not Transit.IsValidStation(fromStation) or not Transit.IsValidStation(toStation) then
        return false, 'Invalid station'
    end

    -- Calculate fare
    local fare = Transit.CalculateFare(fromStation, toStation)

    -- Check payment
    local hasMoney = false
    if paymentMethod == 'cash' and Config.Fares.acceptCash then
        hasMoney = Bridge.GetMoney(source, 'cash') >= fare
    elseif paymentMethod == 'bank' and Config.Fares.acceptBank then
        hasMoney = Bridge.GetMoney(source, 'bank') >= fare
    end

    if not hasMoney then
        return false, 'Insufficient funds'
    end

    -- Check ticket limit
    if not PlayerTickets[citizenid] then
        PlayerTickets[citizenid] = {}
    end

    if #PlayerTickets[citizenid] >= Config.Tickets.maxPerPlayer then
        return false, 'Maximum tickets reached'
    end

    -- Process payment
    Bridge.RemoveMoney(source, paymentMethod, fare)

    -- Create ticket
    local ticket = {
        id = Transit.GenerateTicketId(),
        from = fromStation,
        to = toStation,
        fare = fare,
        purchasedAt = os.time(),
        expiresAt = os.time() + Config.Tickets.expireTime,
        used = false
    }

    -- Store in memory
    table.insert(PlayerTickets[citizenid], ticket)

    -- If persistent tickets enabled, also add to qs-inventory
    if Config.Features.persistentTickets then
        GivePhysicalTicket(source, ticket)
    end

    Transit.Debug('Ticket purchased:', ticket.id, 'by', citizenid)

    return true, ticket
end)

-----------------------------------------------------------
-- PERSISTENT TICKETS (qs-inventory integration)
-----------------------------------------------------------

-- Give physical ticket item to player
function GivePhysicalTicket(source, ticketData)
    local fromStation = Config.Stations[ticketData.from]
    local toStation = Config.Stations[ticketData.to]

    local metadata = {
        ticketId = ticketData.id,
        from = ticketData.from,
        to = ticketData.to,
        fromName = fromStation and fromStation.shortName or ticketData.from,
        toName = toStation and toStation.shortName or ticketData.to,
        fare = ticketData.fare,
        expiresAt = ticketData.expiresAt,
        type = ticketData.type or 'single',
        description = string.format('%s → %s | Expires: %s',
            fromStation and fromStation.shortName or ticketData.from,
            toStation and toStation.shortName or ticketData.to,
            os.date('%H:%M', ticketData.expiresAt)
        )
    }

    -- Use qs-inventory export
    if GetResourceState('qs-inventory') == 'started' then
        exports['qs-inventory']:AddItem(source, 'transit_ticket', 1, nil, metadata)
        Transit.Debug('Physical ticket given to', source)
    end
end

-- Check if player has physical ticket for journey
function HasPhysicalTicket(source, fromStation, toStation)
    if GetResourceState('qs-inventory') ~= 'started' then
        return false, nil
    end

    local items = exports['qs-inventory']:GetItemsByName(source, 'transit_ticket')
    if not items or #items == 0 then
        return false, nil
    end

    local now = os.time()

    for _, item in ipairs(items) do
        local meta = item.info or item.metadata or {}

        -- Check if ticket is valid
        if meta.expiresAt and meta.expiresAt > now then
            -- Check if ticket covers this journey (or is a day pass)
            if meta.type == 'daypass' then
                return true, item
            elseif meta.from == fromStation or meta.to == toStation then
                return true, item
            end
        end
    end

    return false, nil
end

-- Use physical ticket
function UsePhysicalTicket(source, ticketSlot)
    if GetResourceState('qs-inventory') ~= 'started' then
        return false
    end

    exports['qs-inventory']:RemoveItem(source, 'transit_ticket', 1, ticketSlot)
    Transit.Debug('Physical ticket used by', source)
    return true
end

-- Restore tickets on player load (reconnect handling)
Bridge.OnPlayerLoaded(function(source)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return end

    -- Clear memory tickets (will be restored from inventory)
    PlayerTickets[citizenid] = {}

    -- If using persistent tickets, sync from inventory
    if Config.Features.persistentTickets and GetResourceState('qs-inventory') == 'started' then
        Wait(2000)  -- Wait for inventory to load

        local items = exports['qs-inventory']:GetItemsByName(source, 'transit_ticket')
        if items then
            for _, item in ipairs(items) do
                local meta = item.info or item.metadata or {}
                if meta.ticketId then
                    table.insert(PlayerTickets[citizenid], {
                        id = meta.ticketId,
                        from = meta.from,
                        to = meta.to,
                        fare = meta.fare,
                        expiresAt = meta.expiresAt,
                        type = meta.type,
                        used = false,
                        slot = item.slot
                    })
                end
            end

            Transit.Debug('Restored', #PlayerTickets[citizenid], 'tickets for', citizenid)
        end
    end
end)

-- Validate ticket for boarding
lib.callback.register('dps-transit:server:validateTicket', function(source, ticketId)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false end

    local tickets = PlayerTickets[citizenid]

    if not tickets then return false end

    for i, ticket in ipairs(tickets) do
        if ticket.id == ticketId then
            -- Check expiration
            if os.time() > ticket.expiresAt then
                table.remove(tickets, i)
                return false, 'Ticket expired'
            end

            -- Check if already used
            if ticket.used then
                return false, 'Ticket already used'
            end

            -- Mark as used
            ticket.used = true
            ticket.usedAt = os.time()

            return true, ticket
        end
    end

    return false, 'Ticket not found'
end)

-- Check if player has valid ticket
lib.callback.register('dps-transit:server:hasValidTicket', function(source, fromStation, toStation)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false end

    local tickets = PlayerTickets[citizenid]

    if not tickets then return false end

    for _, ticket in ipairs(tickets) do
        if not ticket.used and os.time() <= ticket.expiresAt then
            -- Check if ticket covers this journey
            if ticket.from == fromStation or ticket.to == toStation then
                return true, ticket
            end
            -- Day pass covers all journeys
            if ticket.type == 'daypass' then
                return true, ticket
            end
        end
    end

    return false
end)

-- Get player tickets
lib.callback.register('dps-transit:server:getPlayerTickets', function(source)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return {} end

    local tickets = PlayerTickets[citizenid] or {}

    -- Filter out expired tickets
    local validTickets = {}
    for _, ticket in ipairs(tickets) do
        if os.time() <= ticket.expiresAt then
            table.insert(validTickets, ticket)
        end
    end

    PlayerTickets[citizenid] = validTickets
    return validTickets
end)

-- Purchase day pass (with proper server timestamp validation)
lib.callback.register('dps-transit:server:purchaseDayPass', function(source, paymentMethod)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false, 'Player not found' end

    local fare = Config.Fares.dayPass

    -- Check payment
    local hasMoney = false
    if paymentMethod == 'cash' and Config.Fares.acceptCash then
        hasMoney = Bridge.GetMoney(source, 'cash') >= fare
    elseif paymentMethod == 'bank' and Config.Fares.acceptBank then
        hasMoney = Bridge.GetMoney(source, 'bank') >= fare
    end

    if not hasMoney then
        return false, 'Insufficient funds'
    end

    -- Process payment
    Bridge.RemoveMoney(source, paymentMethod, fare)

    -- Create day pass with SERVER timestamp (for logout/login validation)
    if not PlayerTickets[citizenid] then
        PlayerTickets[citizenid] = {}
    end

    local serverTime = Transit.GetServerTimestamp()

    local dayPass = {
        id = Transit.GenerateTicketId(),
        type = 'daypass',
        fare = fare,
        purchaseTime = serverTime,        -- Server timestamp for validation
        purchasedAt = serverTime,
        expiresAt = serverTime + 86400,   -- 24 hours from SERVER time
        used = false,
        validUntil = os.date('%Y-%m-%d %H:%M:%S', serverTime + 86400)  -- Human readable
    }

    table.insert(PlayerTickets[citizenid], dayPass)

    -- If persistent tickets, save with timestamp metadata
    if Config.Features.persistentTickets then
        GivePhysicalDayPass(source, dayPass)
    end

    Transit.Debug('Day pass purchased:', dayPass.id, 'valid until', dayPass.validUntil)

    return true, dayPass
end)

-- Give physical day pass item
function GivePhysicalDayPass(source, dayPass)
    local metadata = {
        ticketId = dayPass.id,
        type = 'daypass',
        purchaseTime = dayPass.purchaseTime,
        expiresAt = dayPass.expiresAt,
        validUntil = dayPass.validUntil,
        description = 'Day Pass | Valid until: ' .. dayPass.validUntil
    }

    if GetResourceState('qs-inventory') == 'started' then
        exports['qs-inventory']:AddItem(source, 'transit_ticket', 1, nil, metadata)
        Transit.Debug('Physical day pass given to', source)
    end
end

-- Enhanced day pass validation (works across logout/login)
function ValidateDayPass(ticket)
    if not ticket or ticket.type ~= 'daypass' then
        return false, 'Not a day pass'
    end

    -- Use server timestamp for validation
    local now = Transit.GetServerTimestamp()
    local purchaseTime = ticket.purchaseTime or ticket.purchasedAt or 0
    local validFor = 24 * 60 * 60  -- 24 hours

    if (now - purchaseTime) >= validFor then
        return false, 'Day pass expired'
    end

    return true
end

-- Calculate ETA for train to reach station
function CalculateETA(trainId, targetStation)
    local train = ActiveTrains[trainId]
    if not train then return nil end

    local trainProgress = train.trackProgress or 0
    local station = Config.Stations[targetStation]
    if not station then return nil end

    local stationProgress = station.trackProgress

    -- Calculate remaining distance
    local remainingProgress = stationProgress - trainProgress
    if remainingProgress < 0 then
        remainingProgress = remainingProgress + 1.0
    end

    -- Get track-specific speed (for short segments like Davis)
    local trackId = train.currentTrack or 0
    local trackConfig = Config.TrackSpeeds and Config.TrackSpeeds[trackId]
    local averageSpeed = trackConfig and trackConfig.default or Config.Train.speed

    -- Convert to time (assuming ~15km total track)
    local totalTrackLength = 15000  -- meters (approximate)
    local remainingDistance = remainingProgress * totalTrackLength

    local etaSeconds = remainingDistance / averageSpeed

    -- Add station stop times
    local stationsBetween = GetStationsBetween(train.nextStation, targetStation)
    local stopTime = #stationsBetween * Config.Train.stationStopDuration

    -- SIGNAL HOLD ADJUSTMENT: If train is held, add delay estimate
    local signalState = GetTrainSignalState and GetTrainSignalState(trainId)
    if signalState then
        if signalState.signalState == 'red' then
            -- Train is stopped - add estimated wait time (assume 30s average)
            etaSeconds = etaSeconds + 30
        elseif signalState.signalState == 'yellow' then
            -- Train is slowed to ~30% - add proportional delay
            etaSeconds = etaSeconds * 1.5  -- 50% longer at reduced speed
        end
    end

    -- Minimum ETA for very short segments (prevents 0 or negative)
    if etaSeconds < 15 and remainingProgress > 0.01 then
        etaSeconds = 15  -- Minimum 15 seconds
    end

    return math.floor(etaSeconds + stopTime)
end

-- Get arrivals at a station
function GetStationArrivals(stationId)
    local arrivals = {}

    for trainId, train in pairs(ActiveTrains) do
        if Transit.TrainWillStopAt(train.direction, train.currentStation or train.nextStation, stationId) then
            local eta = CalculateETA(trainId, stationId)
            if eta then
                table.insert(arrivals, {
                    trainId = trainId,
                    direction = train.direction,
                    destination = Transit.GetFinalDestination(train.direction),
                    eta = eta,
                    status = train.status
                })
            end
        end
    end

    -- Sort by ETA
    table.sort(arrivals, function(a, b) return a.eta < b.eta end)

    return arrivals
end

-- Clean up expired tickets periodically
CreateThread(function()
    while true do
        Wait(60000)  -- Every minute

        local now = os.time()
        for citizenid, tickets in pairs(PlayerTickets) do
            local validTickets = {}
            for _, ticket in ipairs(tickets) do
                if now <= ticket.expiresAt then
                    table.insert(validTickets, ticket)
                end
            end
            PlayerTickets[citizenid] = validTickets
        end
    end
end)

-----------------------------------------------------------
-- TICKET SWEEP SYSTEM (Zone Crossing Validation)
-----------------------------------------------------------

-- Validate zone crossing
lib.callback.register('dps-transit:server:validateZoneCrossing', function(source, fromZone, toZone)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false, 'Player not found' end

    local tickets = PlayerTickets[citizenid]

    if not tickets then return false, 'No tickets' end

    -- Check for valid ticket covering destination zone
    local now = os.time()

    for _, ticket in ipairs(tickets) do
        -- Skip expired tickets
        if ticket.expiresAt and now > ticket.expiresAt then
            goto continue
        end

        -- Day pass covers all zones
        if ticket.type == 'daypass' then
            return true, ticket
        end

        -- Check if ticket covers destination zone
        if ticket.to then
            local destStation = Config.Stations[ticket.to]
            if destStation and destStation.zone == toZone then
                return true, ticket
            end
        end

        -- Check if ticket is a zone pass
        if ticket.zones then
            for _, zone in ipairs(ticket.zones) do
                if zone == toZone then
                    return true, ticket
                end
            end
        end

        ::continue::
    end

    return false, 'Ticket does not cover Zone ' .. toZone
end)

-- Pay additional fare for zone extension
lib.callback.register('dps-transit:server:payAdditionalFare', function(source, fromZone, toZone)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return false, 'Player not found' end

    -- Calculate additional fare
    local fromIndex = Config.ZoneIndex[fromZone] or 1
    local toIndex = Config.ZoneIndex[toZone] or 1
    local zoneDiff = math.abs(toIndex - fromIndex)

    local additionalFare = Config.Fares.oneZone
    if zoneDiff > 1 then
        additionalFare = Config.Fares.twoZones
    end

    -- Check if player can pay
    local bankMoney = Bridge.GetMoney(source, 'bank')
    local cashMoney = Bridge.GetMoney(source, 'cash')
    local hasMoney = bankMoney >= additionalFare or cashMoney >= additionalFare

    if not hasMoney then
        return false, 'Insufficient funds ($' .. additionalFare .. ' required)'
    end

    -- Process payment (prefer bank)
    if bankMoney >= additionalFare then
        Bridge.RemoveMoney(source, 'bank', additionalFare)
    else
        Bridge.RemoveMoney(source, 'cash', additionalFare)
    end

    -- Create zone extension ticket
    if not PlayerTickets[citizenid] then
        PlayerTickets[citizenid] = {}
    end

    local extension = {
        id = Transit.GenerateTicketId(),
        type = 'extension',
        zones = { fromZone, toZone },
        fare = additionalFare,
        purchasedAt = os.time(),
        expiresAt = os.time() + 3600,  -- 1 hour validity
        used = false
    }

    table.insert(PlayerTickets[citizenid], extension)

    Transit.Debug('Zone extension purchased:', citizenid, fromZone, '->', toZone, '$' .. additionalFare)

    return true, extension
end)

-----------------------------------------------------------
-- EMERGENCY BRAKING SYSTEM (Police Integration)
-----------------------------------------------------------

local EmergencyStoppedTrains = {}

-- Server export for emergency braking (for police scripts)
function EmergencyBrakeNearestTrain(source, coords, radius)
    if not Config.EmergencyServices or not Config.EmergencyServices.enabled then
        return false, 'Emergency services integration disabled'
    end

    -- Check if player has allowed job
    local job, _ = Bridge.GetJob(source)
    if not job then return false, 'Player not found' end

    local isAuthorized = false

    for _, allowedJob in ipairs(Config.EmergencyServices.allowedJobs) do
        if job == allowedJob then
            isAuthorized = true
            break
        end
    end

    if not isAuthorized then
        return false, 'Not authorized (requires emergency services job)'
    end

    -- Find nearest train within radius
    local nearestTrain = nil
    local nearestDist = Config.EmergencyServices.emergencyBraking.stopDistance

    for trainId, train in pairs(ActiveTrains) do
        if train.currentPosition then
            local trainPos = vec3(train.currentPosition.x, train.currentPosition.y, train.currentPosition.z)
            local dist = #(coords - trainPos)

            if dist < nearestDist then
                nearestDist = dist
                nearestTrain = trainId
            end
        end
    end

    if not nearestTrain then
        return false, 'No train found within range'
    end

    -- Activate emergency brake
    EmergencyStoppedTrains[nearestTrain] = {
        stoppedBy = source,
        stoppedAt = os.time(),
        holdUntil = os.time() + Config.EmergencyServices.emergencyBraking.holdDuration
    }

    ActiveTrains[nearestTrain].status = 'emergency_stopped'

    -- Notify all clients
    TriggerClientEvent('dps-transit:client:emergencyBrake', -1, nearestTrain, true)

    -- Broadcast alert
    local playerName = Bridge.GetCharacterName(source)
    TriggerClientEvent('dps-transit:client:emergencyHold', -1, {
        active = true,
        stationName = ActiveTrains[nearestTrain].currentStation or 'Unknown Location',
        reason = 'Police emergency stop'
    })

    Transit.Debug('Emergency brake activated by', playerName, 'on train', nearestTrain)

    return true, { trainId = nearestTrain, distance = nearestDist }
end

-- Release emergency brake
function ReleaseEmergencyBrake(source, trainId)
    if not EmergencyStoppedTrains[trainId] then
        return false, 'Train is not emergency stopped'
    end

    -- Check authorization
    if source then
        local job, _ = Bridge.GetJob(source)
        local isAuthorized = false

        for _, allowedJob in ipairs(Config.EmergencyServices.allowedJobs) do
            if job == allowedJob then
                isAuthorized = true
                break
            end
        end

        if not isAuthorized then
            return false, 'Not authorized'
        end
    end

    -- Release the brake
    EmergencyStoppedTrains[trainId] = nil
    ActiveTrains[trainId].status = 'running'

    TriggerClientEvent('dps-transit:client:emergencyBrake', -1, trainId, false)
    TriggerClientEvent('dps-transit:client:emergencyHold', -1, { active = false })

    Transit.Debug('Emergency brake released for train', trainId)

    return true
end

-- Auto-release emergency brakes after hold duration
CreateThread(function()
    while true do
        Wait(30000)  -- Check every 30 seconds

        local now = os.time()

        for trainId, data in pairs(EmergencyStoppedTrains) do
            if now >= data.holdUntil then
                Transit.Debug('Auto-releasing emergency brake for train', trainId)
                ReleaseEmergencyBrake(nil, trainId)
            end
        end
    end
end)

-----------------------------------------------------------
-- OX_INVENTORY SUPPORT (Alternative to qs-inventory)
-----------------------------------------------------------

-- Detect which inventory system is available
local function GetInventorySystem()
    if GetResourceState('ox_inventory') == 'started' then
        return 'ox_inventory'
    elseif GetResourceState('qs-inventory') == 'started' then
        return 'qs-inventory'
    end
    return nil
end

-- Give ticket using detected inventory
function GiveTicketItem(source, ticketData)
    local inventory = GetInventorySystem()
    if not inventory then
        Transit.Debug('No inventory system detected for physical tickets')
        return false
    end

    local fromStation = Config.Stations[ticketData.from]
    local toStation = Config.Stations[ticketData.to]

    local ticketType = ticketData.type or 'single'
    local now = os.time()
    local expiresAt = ticketData.expiresAt
    local remainingSeconds = expiresAt - now
    local remainingMinutes = math.floor(remainingSeconds / 60)
    local remainingHours = math.floor(remainingMinutes / 60)

    -- Build tooltip-friendly description
    local description
    local label

    if ticketType == 'daypass' then
        label = 'Day Pass'
        if remainingHours > 0 then
            description = string.format('Valid for %dh %dm | All Zones | Expires: %s',
                remainingHours,
                remainingMinutes % 60,
                os.date('%H:%M', expiresAt)
            )
        else
            description = string.format('Valid for %d minutes | All Zones | Expires: %s',
                remainingMinutes,
                os.date('%H:%M', expiresAt)
            )
        end
    else
        label = string.format('%s → %s',
            fromStation and fromStation.shortName or ticketData.from,
            toStation and toStation.shortName or ticketData.to
        )
        description = string.format('Zone %s → Zone %s | $%d | Expires: %s',
            fromStation and fromStation.zone or '?',
            toStation and toStation.zone or '?',
            ticketData.fare,
            os.date('%H:%M', expiresAt)
        )
    end

    local metadata = {
        ticketId = ticketData.id,
        from = ticketData.from,
        to = ticketData.to,
        fromName = fromStation and fromStation.shortName or ticketData.from,
        toName = toStation and toStation.shortName or ticketData.to,
        fromZone = fromStation and fromStation.zone or nil,
        toZone = toStation and toStation.zone or nil,
        fare = ticketData.fare,
        expiresAt = expiresAt,
        purchasedAt = now,
        type = ticketType,
        label = label,            -- Custom item label for ox_inventory
        description = description -- Tooltip text
    }

    if inventory == 'ox_inventory' then
        -- ox_inventory format with enhanced metadata
        exports.ox_inventory:AddItem(source, 'transit_ticket', 1, metadata)
        Transit.Debug('Physical ticket given via ox_inventory to', source)
        return true
    elseif inventory == 'qs-inventory' then
        -- qs-inventory format
        exports['qs-inventory']:AddItem(source, 'transit_ticket', 1, nil, metadata)
        Transit.Debug('Physical ticket given via qs-inventory to', source)
        return true
    end

    return false
end

-- Update ticket remaining time display (for UI refresh)
function GetTicketRemainingTime(expiresAt)
    local now = os.time()
    local remaining = expiresAt - now

    if remaining <= 0 then
        return 'Expired'
    elseif remaining < 60 then
        return remaining .. 's'
    elseif remaining < 3600 then
        return math.floor(remaining / 60) .. 'm'
    else
        local hours = math.floor(remaining / 3600)
        local mins = math.floor((remaining % 3600) / 60)
        return hours .. 'h ' .. mins .. 'm'
    end
end

exports('GetTicketRemainingTime', GetTicketRemainingTime)

-- Check for ticket using detected inventory
function HasTicketItem(source, fromStation, toStation)
    local inventory = GetInventorySystem()
    if not inventory then
        return false, nil
    end

    local now = os.time()
    local items = nil

    if inventory == 'ox_inventory' then
        items = exports.ox_inventory:Search(source, 'slots', 'transit_ticket')
    elseif inventory == 'qs-inventory' then
        items = exports['qs-inventory']:GetItemsByName(source, 'transit_ticket')
    end

    if not items then return false, nil end

    for _, item in ipairs(items) do
        local meta = item.metadata or item.info or {}

        -- Check validity
        if meta.expiresAt and meta.expiresAt > now then
            if meta.type == 'daypass' then
                return true, item
            elseif meta.from == fromStation or meta.to == toStation then
                return true, item
            end
        end
    end

    return false, nil
end

-- Remove ticket using detected inventory
function RemoveTicketItem(source, slot)
    local inventory = GetInventorySystem()
    if not inventory then return false end

    if inventory == 'ox_inventory' then
        exports.ox_inventory:RemoveItem(source, 'transit_ticket', 1, nil, slot)
    elseif inventory == 'qs-inventory' then
        exports['qs-inventory']:RemoveItem(source, 'transit_ticket', 1, slot)
    end

    Transit.Debug('Ticket item removed for', source)
    return true
end

-- Override physical ticket functions to use detected inventory
GivePhysicalTicket = GiveTicketItem
HasPhysicalTicket = HasTicketItem
UsePhysicalTicket = function(source, slot)
    return RemoveTicketItem(source, slot)
end

-----------------------------------------------------------
-- SERVICE ALERTS & DELAY SYSTEM
-----------------------------------------------------------

local ActiveServiceAlerts = {}
local TrainDelays = {}

-- Broadcast a service alert to all players
function BroadcastServiceAlert(alertType, message, affectedLines)
    local alert = {
        id = Transit.GenerateTicketId(),
        alertType = alertType,  -- 'info', 'delay', 'disruption', 'emergency'
        message = message,
        affectedLines = affectedLines or {},
        createdAt = os.time()
    }

    ActiveServiceAlerts[alert.id] = alert

    -- Send to all clients
    TriggerClientEvent('dps-transit:client:serviceAlert', -1, {
        action = 'showServiceAlert',
        alertType = alertType,
        message = message,
        affectedLines = affectedLines
    })

    Transit.Debug('Service alert broadcast:', alertType, '-', message)

    return alert.id
end

-- Clear a service alert
function ClearServiceAlert(alertId)
    if ActiveServiceAlerts[alertId] then
        ActiveServiceAlerts[alertId] = nil
        TriggerClientEvent('dps-transit:client:serviceAlert', -1, {
            action = 'hideServiceAlert'
        })
        return true
    end
    return false
end

-- Set delay for a specific train
function SetTrainDelay(trainId, delayMinutes, reason)
    TrainDelays[trainId] = {
        delayMinutes = delayMinutes,
        reason = reason or 'Service delay',
        setAt = os.time()
    }

    -- Update train status
    if ActiveTrains[trainId] then
        ActiveTrains[trainId].delayed = delayMinutes
        ActiveTrains[trainId].delayReason = reason
    end

    -- Notify clients
    TriggerClientEvent('dps-transit:client:serviceAlert', -1, {
        action = 'updateDelays',
        delays = TrainDelays
    })

    -- If significant delay, broadcast alert
    if delayMinutes >= 10 then
        local train = ActiveTrains[trainId]
        local lineName = train and train.lineId or 'Unknown Line'

        BroadcastServiceAlert('delay',
            string.format('%s delayed by %d minutes - %s', lineName, delayMinutes, reason),
            { lineName }
        )
    end

    Transit.Debug('Train', trainId, 'delayed by', delayMinutes, 'minutes:', reason)
end

-- Clear delay for a train
function ClearTrainDelay(trainId)
    if TrainDelays[trainId] then
        TrainDelays[trainId] = nil

        if ActiveTrains[trainId] then
            ActiveTrains[trainId].delayed = nil
            ActiveTrains[trainId].delayReason = nil
        end

        TriggerClientEvent('dps-transit:client:serviceAlert', -1, {
            action = 'updateDelays',
            delays = TrainDelays
        })

        return true
    end
    return false
end

-- Get current service status
function GetServiceStatus()
    local status = {
        alerts = ActiveServiceAlerts,
        delays = TrainDelays,
        trainsRunning = Transit.TableLength(ActiveTrains),
        emergencyStops = Transit.TableLength(EmergencyStoppedTrains)
    }

    return status
end

-- Handle client requesting service alerts
RegisterNetEvent('dps-transit:client:requestAlerts', function()
    local source = source

    -- Send current alerts
    for _, alert in pairs(ActiveServiceAlerts) do
        TriggerClientEvent('dps-transit:client:serviceAlert', source, {
            action = 'showServiceAlert',
            alertType = alert.alertType,
            message = alert.message,
            affectedLines = alert.affectedLines
        })
    end

    -- Send current delays
    if next(TrainDelays) then
        TriggerClientEvent('dps-transit:client:serviceAlert', source, {
            action = 'updateDelays',
            delays = TrainDelays
        })
    end
end)

-- Export functions
exports('GetActiveTrains', function() return ActiveTrains end)
exports('GetTrainETA', CalculateETA)
exports('GetStationArrivals', GetStationArrivals)
exports('EmergencyBrakeNearestTrain', EmergencyBrakeNearestTrain)
exports('ReleaseEmergencyBrake', ReleaseEmergencyBrake)
exports('GetInventorySystem', GetInventorySystem)
exports('BroadcastServiceAlert', BroadcastServiceAlert)
exports('ClearServiceAlert', ClearServiceAlert)
exports('SetTrainDelay', SetTrainDelay)
exports('ClearTrainDelay', ClearTrainDelay)
exports('GetServiceStatus', GetServiceStatus)
