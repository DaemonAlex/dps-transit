--[[
    DPS-Transit Station Interactions
    Kiosk menus, ticket purchasing, schedule viewing
]]

-- Current station context
local CurrentStation = nil

-- Initialize station interactions
CreateThread(function()
    Wait(2000)

    -- Create ox_target zones for each station
    for stationId, station in pairs(Config.Stations) do
        -- Skip if coordinates not set
        if station.platform.x == 0 and station.platform.y == 0 then
            goto continue
        end

        -- Kiosk interaction
        if station.kiosk then
            exports.ox_target:addBoxZone({
                coords = station.kiosk.xyz,
                size = vec3(1.5, 1.5, 2.0),
                rotation = station.kiosk.w,
                debug = Config.Debug,
                options = {
                    {
                        name = 'transit_kiosk_' .. stationId,
                        icon = 'fa-solid fa-ticket',
                        label = 'Purchase Ticket',
                        onSelect = function()
                            OpenTicketKiosk(stationId)
                        end
                    },
                    {
                        name = 'transit_schedule_' .. stationId,
                        icon = 'fa-solid fa-clock',
                        label = 'View Schedule',
                        onSelect = function()
                            OpenScheduleDisplay(stationId)
                        end
                    },
                    {
                        name = 'transit_arrivals_' .. stationId,
                        icon = 'fa-solid fa-train',
                        label = 'Next Arrivals',
                        onSelect = function()
                            ShowNextArrivals(stationId)
                        end
                    }
                }
            })
        end

        -- Platform boarding zone
        exports.ox_target:addBoxZone({
            coords = station.platform.xyz,
            size = vec3(20.0, 5.0, 3.0),
            rotation = station.platform.w,
            debug = Config.Debug,
            options = {
                {
                    name = 'transit_board_' .. stationId,
                    icon = 'fa-solid fa-door-open',
                    label = 'Board Train',
                    canInteract = function()
                        return IsTrainBoardingAtStation(stationId)
                    end,
                    onSelect = function()
                        BoardTrain(stationId)
                    end
                }
            }
        })

        ::continue::
    end

    Transit.Debug('Station interactions created')
end)

-- Check if any train is boarding at station
function IsTrainBoardingAtStation(stationId)
    for trainId, train in pairs(LocalTrains) do
        if train.data.currentStation == stationId and train.data.status == 'boarding' then
            return true
        end
    end
    return false
end

-- Get boarding train at station
function GetBoardingTrain(stationId)
    for trainId, train in pairs(LocalTrains) do
        if train.data.currentStation == stationId and train.data.status == 'boarding' then
            return trainId, train
        end
    end
    return nil
end

-- Open ticket kiosk menu
function OpenTicketKiosk(stationId)
    CurrentStation = stationId
    local station = Config.Stations[stationId]

    -- Build destination options
    local destinations = {}
    for _, destId in ipairs(Config.StationOrder) do
        if destId ~= stationId then
            local dest = Config.Stations[destId]
            if dest and dest.platform.x ~= 0 then
                local fare = Transit.CalculateFare(stationId, destId)
                table.insert(destinations, {
                    title = dest.name,
                    description = 'Zone ' .. dest.zone .. ' | $' .. fare,
                    icon = 'train',
                    metadata = {
                        { label = 'Zone', value = dest.zone },
                        { label = 'Fare', value = '$' .. fare }
                    },
                    onSelect = function()
                        ConfirmTicketPurchase(stationId, destId, fare)
                    end
                })
            end
        end
    end

    -- Add day pass option
    table.insert(destinations, {
        title = 'Day Pass',
        description = 'Unlimited travel for 24 hours | $' .. Config.Fares.dayPass,
        icon = 'calendar-day',
        onSelect = function()
            ConfirmDayPassPurchase()
        end
    })

    lib.registerContext({
        id = 'transit_kiosk',
        title = station.shortName .. ' Station',
        options = destinations
    })

    lib.showContext('transit_kiosk')
end

-- Confirm ticket purchase
function ConfirmTicketPurchase(fromStation, toStation, fare)
    local from = Config.Stations[fromStation]
    local to = Config.Stations[toStation]

    local alert = lib.alertDialog({
        header = 'Purchase Ticket',
        content = 'From: ' .. from.shortName .. '\nTo: ' .. to.shortName .. '\nFare: $' .. fare,
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Pay $' .. fare,
            cancel = 'Cancel'
        }
    })

    if alert == 'confirm' then
        SelectPaymentMethod(fromStation, toStation)
    end
end

-- Select payment method
function SelectPaymentMethod(fromStation, toStation)
    local options = {}

    if Config.Fares.acceptCash then
        table.insert(options, {
            title = 'Pay with Cash',
            icon = 'money-bill',
            onSelect = function()
                ProcessTicketPurchase(fromStation, toStation, 'cash')
            end
        })
    end

    if Config.Fares.acceptBank then
        table.insert(options, {
            title = 'Pay with Card',
            icon = 'credit-card',
            onSelect = function()
                ProcessTicketPurchase(fromStation, toStation, 'bank')
            end
        })
    end

    lib.registerContext({
        id = 'transit_payment',
        title = 'Payment Method',
        menu = 'transit_kiosk',
        options = options
    })

    lib.showContext('transit_payment')
end

-- Process ticket purchase
function ProcessTicketPurchase(fromStation, toStation, paymentMethod)
    local success, result = lib.callback.await('dps-transit:server:purchaseTicket', false, fromStation, toStation, paymentMethod)

    if success then
        lib.notify({
            title = 'Ticket Purchased',
            description = 'Ticket #' .. result.id,
            type = 'success',
            duration = 5000
        })

        -- Store ticket locally
        table.insert(PlayerState.tickets, result)
    else
        lib.notify({
            title = 'Purchase Failed',
            description = result or 'Unknown error',
            type = 'error',
            duration = 5000
        })
    end
end

-- Confirm day pass purchase
function ConfirmDayPassPurchase()
    local alert = lib.alertDialog({
        header = 'Purchase Day Pass',
        content = 'Unlimited travel for 24 hours\nCost: $' .. Config.Fares.dayPass,
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Pay $' .. Config.Fares.dayPass,
            cancel = 'Cancel'
        }
    })

    if alert == 'confirm' then
        local options = {}

        if Config.Fares.acceptCash then
            table.insert(options, {
                title = 'Pay with Cash',
                icon = 'money-bill',
                onSelect = function()
                    ProcessDayPassPurchase('cash')
                end
            })
        end

        if Config.Fares.acceptBank then
            table.insert(options, {
                title = 'Pay with Card',
                icon = 'credit-card',
                onSelect = function()
                    ProcessDayPassPurchase('bank')
                end
            })
        end

        lib.registerContext({
            id = 'transit_daypass_payment',
            title = 'Payment Method',
            options = options
        })

        lib.showContext('transit_daypass_payment')
    end
end

-- Process day pass purchase
function ProcessDayPassPurchase(paymentMethod)
    local success, result = lib.callback.await('dps-transit:server:purchaseDayPass', false, paymentMethod)

    if success then
        lib.notify({
            title = 'Day Pass Purchased',
            description = 'Valid for 24 hours',
            type = 'success',
            duration = 5000
        })

        table.insert(PlayerState.tickets, result)
    else
        lib.notify({
            title = 'Purchase Failed',
            description = result or 'Unknown error',
            type = 'error',
            duration = 5000
        })
    end
end

-- Open schedule display
function OpenScheduleDisplay(stationId)
    local station = Config.Stations[stationId]
    local schedule = lib.callback.await('dps-transit:server:getSchedule', false)

    local options = {
        {
            title = 'Current Schedule',
            description = string.upper(schedule.period) .. ' service',
            icon = 'clock',
            metadata = {
                { label = 'Frequency', value = 'Every ' .. schedule.frequency .. ' minutes' },
                { label = 'Active Trains', value = schedule.trainCount }
            }
        }
    }

    -- Add next departures
    if schedule.nextDepartures then
        for _, departure in ipairs(schedule.nextDepartures) do
            local depStation = Config.Stations[departure.station]
            if depStation then
                local timeUntil = departure.time - os.time()
                table.insert(options, {
                    title = depStation.shortName .. ' → ' .. departure.destination,
                    description = Transit.FormatETA(timeUntil),
                    icon = 'train'
                })
            end
        end
    end

    lib.registerContext({
        id = 'transit_schedule',
        title = station.shortName .. ' Schedule',
        options = options
    })

    lib.showContext('transit_schedule')
end

-- Show next arrivals at station
function ShowNextArrivals(stationId)
    local station = Config.Stations[stationId]
    local arrivals = lib.callback.await('dps-transit:server:getStationArrivals', false, stationId)

    local options = {}

    if #arrivals == 0 then
        table.insert(options, {
            title = 'No trains arriving soon',
            description = 'Check schedule for departure times',
            icon = 'info'
        })
    else
        for _, arrival in ipairs(arrivals) do
            local dest = Config.Stations[arrival.destination]
            local destName = dest and dest.shortName or 'Unknown'

            table.insert(options, {
                title = 'To ' .. destName,
                description = Transit.FormatETA(arrival.eta),
                icon = 'train',
                metadata = {
                    { label = 'Direction', value = arrival.direction and 'Northbound' or 'Southbound' },
                    { label = 'Status', value = arrival.status }
                }
            })
        end
    end

    lib.registerContext({
        id = 'transit_arrivals',
        title = station.shortName .. ' Arrivals',
        options = options
    })

    lib.showContext('transit_arrivals')
end

-- Board train
function BoardTrain(stationId)
    local trainId, train = GetBoardingTrain(stationId)

    if not trainId then
        lib.notify({
            title = 'No Train',
            description = 'No train is currently boarding',
            type = 'error'
        })
        return
    end

    -- Check for valid ticket
    local hasTicket, ticket = lib.callback.await('dps-transit:server:hasValidTicket', false, stationId, train.data.nextStation)

    if not hasTicket then
        lib.notify({
            title = 'No Ticket',
            description = 'You need a valid ticket to board',
            type = 'error'
        })

        -- Offer to buy ticket
        lib.alertDialog({
            header = 'No Valid Ticket',
            content = 'Would you like to purchase a ticket?',
            centered = true,
            cancel = true,
            labels = { confirm = 'Buy Ticket', cancel = 'Cancel' }
        })

        return
    end

    -- Board the train
    local ped = PlayerPedId()
    local trainEntity = train.entity

    -- Find available seat
    local carriage = trainEntity  -- For now, use main train
    local seatIndex = GetVehicleMaxNumberOfPassengers(carriage) - 1

    for i = 0, seatIndex do
        if IsVehicleSeatFree(carriage, i) then
            TaskWarpPedIntoVehicle(ped, carriage, i)

            PlayerState.currentTrain = trainId
            PlayerState.currentZone = Config.Stations[stationId].zone

            -- Notify server that player boarded
            TriggerServerEvent('dps-transit:server:playerBoarded', trainId)

            lib.notify({
                title = 'Boarded',
                description = 'You boarded the train to ' .. Config.Stations[Transit.GetFinalDestination(train.data.direction)].shortName,
                type = 'success'
            })

            return
        end
    end

    lib.notify({
        title = 'Train Full',
        description = 'No available seats',
        type = 'error'
    })
end

-- Exit train at station
function ExitTrain()
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    -- Check if in a train
    if not IsThisModelATrain(GetEntityModel(vehicle)) then
        return
    end

    -- Get current station
    local isAtStation, stationId = IsPlayerAtStation()

    if isAtStation then
        local trainId = PlayerState.currentTrain

        TaskLeaveVehicle(ped, vehicle, 0)
        PlayerState.currentTrain = nil
        PlayerState.currentZone = nil

        -- Notify server that player exited
        if trainId then
            TriggerServerEvent('dps-transit:server:playerExited', trainId)
        end

        local station = Config.Stations[stationId]
        lib.notify({
            title = 'Arrived',
            description = 'You arrived at ' .. station.shortName,
            type = 'inform'
        })
    else
        lib.notify({
            title = 'Cannot Exit',
            description = 'Wait until the train stops at a station',
            type = 'error'
        })
    end
end

-- Key binding to exit train
RegisterCommand('exittrain', function()
    ExitTrain()
end, false)

RegisterKeyMapping('exittrain', 'Exit Train at Station', 'keyboard', 'E')
