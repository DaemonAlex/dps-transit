--[[
    DPS-Transit Train Configuration
    Train consists and model definitions

    NOTE: Train variation IDs for CreateMissionTrain:
    - 0-14: Standard freight configs
    - 15-24: Extended freight configs
    - 25: Metro train (2x metrotrain)

    Custom variations can be defined in trains.xml
    See: BigDaddy-Trains for reference configurations
]]

Config.Lines = {
    --[[
        REGIONAL LINE (Track 0)
        Main island loop: LSIA → Paleto → loops back
        Service: 70% Passenger / 30% Freight
    ]]
    ['regional'] = {
        name = 'Regional Rail',
        shortName = 'REG',
        track = 0,
        enabled = true,
        color = 1,  -- Red blip

        -- 70/30 passenger/freight split
        schedule = {
            passengerRatio = 70,
            freightRatio = 30,
        },

        -- Station route for this line
        stations = { 'lsia', 'davis', 'downtown', 'del_perro', 'paleto_junction' },

        -- Terminus stations
        terminus = {
            south = 'lsia',
            north = 'paleto_junction'
        }
    },

    --[[
        LS METRO (Track 3)
        Urban light rail within Los Santos
        Service: 100% Passenger (no freight on metro)
    ]]
    ['metro'] = {
        name = 'LS Metro',
        shortName = 'MET',
        track = 3,
        enabled = true,
        color = 3,  -- Blue blip

        schedule = {
            passengerRatio = 100,
            freightRatio = 0,
        },

        -- Metro stations (to be defined)
        stations = { 'metro_airport', 'metro_davis', 'metro_downtown', 'metro_del_perro' },

        terminus = {
            south = 'metro_airport',
            north = 'metro_del_perro'
        }
    },

    --[[
        ROXWOOD LINE (Track 13)
        Expansion area rail service
        Service: 70% Passenger / 30% Freight
    ]]
    ['roxwood'] = {
        name = 'Roxwood Rail',
        shortName = 'ROX',
        track = 13,
        enabled = false,  -- Disabled until coords are set
        color = 2,  -- Green blip

        schedule = {
            passengerRatio = 70,
            freightRatio = 30,
        },

        stations = { 'paleto_junction', 'roxwood' },

        terminus = {
            south = 'paleto_junction',
            north = 'roxwood'
        }
    }
}

--[[
    TRAIN CONSISTS
    Model configurations for passenger and freight trains

    These use CreateMissionTrain() variation indices or custom models
    streamed via BigDaddy-Trains or similar
]]

Config.Consists = {
    --[[
        PASSENGER CONSISTS
        Used for scheduled passenger service
    ]]
    passenger = {
        -- Regional passenger - commuter consist
        ['regional_commuter'] = {
            name = 'Regional Commuter',
            variation = 25,  -- Default variation, can be overridden
            locomotive = 'streakcoaster',
            cars = {
                'streakc',
                'streakc',
                'streakc',
                'streakc',
                'streakc'
            },
            maxPassengers = 50,
            lines = { 'regional' },

            -- If using custom trains.xml config
            customConfig = 'passenger_config01'
        },

        -- Regional express - fewer stops, faster
        ['regional_express'] = {
            name = 'Regional Express',
            variation = 25,
            locomotive = 'streakcoaster',
            cars = {
                'streakc',
                'streakc',
                'streakc',
                'streakcoastercab'  -- Cab car for push-pull
            },
            maxPassengers = 35,
            lines = { 'regional' },
            customConfig = 'passenger_config02'
        },

        -- Metro light rail
        ['metro_light'] = {
            name = 'Metro Light Rail',
            variation = 25,
            locomotive = 'metrotrain',
            cars = {
                'metrotrain'
            },
            maxPassengers = 8,
            lines = { 'metro' },
            customConfig = 'metro_config01'
        },

        -- Roxwood passenger
        ['roxwood_passenger'] = {
            name = 'Roxwood Passenger',
            variation = 25,
            locomotive = 'streakcoaster',
            cars = {
                'streakc',
                'streakc',
                'streakc'
            },
            maxPassengers = 28,
            lines = { 'roxwood' },
            customConfig = 'passenger_config02'
        }
    },

    --[[
        FREIGHT CONSISTS
        Used for scheduled freight service (30% of main line traffic)
        Players cannot board freight trains
    ]]
    freight = {
        -- Mixed freight - intermodal
        ['freight_mixed'] = {
            name = 'Intermodal Freight',
            variation = 0,  -- Native freight variation
            locomotive = 'sd70mac',
            cars = {
                'freightcont',
                'freightcont',
                'freightstack',
                'freightstack',
                'freightboxlarge',
                'freightcaboose'
            },
            lines = { 'regional', 'roxwood' },
            customConfig = 'freight_config01'
        },

        -- Tanker train - oil/chemical
        ['freight_tanker'] = {
            name = 'Tanker Train',
            variation = 1,
            locomotive = 'sd70mac',
            cars = {
                'freighttanklong',
                'freighttanklong',
                'freighttankbulk',
                'freighttankbulk',
                'freighttanklong',
                'freightcaboose'
            },
            lines = { 'regional' },
            customConfig = 'freight_config02'
        },

        -- Bulk freight - coal/grain
        ['freight_bulk'] = {
            name = 'Bulk Freight',
            variation = 2,
            locomotive = 'sd70mac',
            cars = {
                'freightcoal',
                'freightcoal',
                'freightgraincar',
                'freightgraincar',
                'freighthopper',
                'freightcaboose'
            },
            lines = { 'regional' },
            customConfig = 'freight_config03'
        },

        -- Flatbed freight - construction materials
        ['freight_flatbed'] = {
            name = 'Flatbed Freight',
            variation = 3,
            locomotive = 'freight',  -- Native freight loco
            cars = {
                'freightflat',
                'freightflatlogs',
                'freightflattank',
                'freightbeam',
                'freightcaboose'
            },
            lines = { 'regional', 'roxwood' },
            customConfig = 'freight_config04'
        },

        -- Short freight - for Roxwood line
        ['freight_short'] = {
            name = 'Short Haul Freight',
            variation = 4,
            locomotive = 'sd70mac',
            cars = {
                'freightcont',
                'freightboxlarge',
                'freightcaboose'
            },
            lines = { 'roxwood' },
            customConfig = 'freight_config05'
        }
    }
}

--[[
    SCHEDULE SLOTS
    70/30 distribution across 10 slots per hour
    7 passenger, 3 freight

    Pattern repeats every hour:
    :00 - Passenger (slot 1)
    :06 - Passenger (slot 2)
    :12 - Passenger (slot 3)
    :18 - FREIGHT  (slot 4)
    :24 - Passenger (slot 5)
    :30 - Passenger (slot 6)
    :36 - FREIGHT  (slot 7)
    :42 - Passenger (slot 8)
    :48 - Passenger (slot 9)
    :54 - FREIGHT  (slot 10)
]]

Config.ScheduleSlots = {
    regional = {
        -- Each slot: { minute, trainType, consistKey }
        { minute = 0,  type = 'passenger', consist = 'regional_commuter' },
        { minute = 6,  type = 'passenger', consist = 'regional_express' },
        { minute = 12, type = 'passenger', consist = 'regional_commuter' },
        { minute = 18, type = 'freight',   consist = 'freight_mixed' },
        { minute = 24, type = 'passenger', consist = 'regional_commuter' },
        { minute = 30, type = 'passenger', consist = 'regional_express' },
        { minute = 36, type = 'freight',   consist = 'freight_tanker' },
        { minute = 42, type = 'passenger', consist = 'regional_commuter' },
        { minute = 48, type = 'passenger', consist = 'regional_commuter' },
        { minute = 54, type = 'freight',   consist = 'freight_bulk' }
    },

    metro = {
        -- Metro runs every 5 minutes, passengers only
        { minute = 0,  type = 'passenger', consist = 'metro_light' },
        { minute = 5,  type = 'passenger', consist = 'metro_light' },
        { minute = 10, type = 'passenger', consist = 'metro_light' },
        { minute = 15, type = 'passenger', consist = 'metro_light' },
        { minute = 20, type = 'passenger', consist = 'metro_light' },
        { minute = 25, type = 'passenger', consist = 'metro_light' },
        { minute = 30, type = 'passenger', consist = 'metro_light' },
        { minute = 35, type = 'passenger', consist = 'metro_light' },
        { minute = 40, type = 'passenger', consist = 'metro_light' },
        { minute = 45, type = 'passenger', consist = 'metro_light' },
        { minute = 50, type = 'passenger', consist = 'metro_light' },
        { minute = 55, type = 'passenger', consist = 'metro_light' }
    },

    roxwood = {
        -- Roxwood runs every 15 minutes, 70/30 split (4 slots = 3P + 1F)
        { minute = 0,  type = 'passenger', consist = 'roxwood_passenger' },
        { minute = 15, type = 'passenger', consist = 'roxwood_passenger' },
        { minute = 30, type = 'freight',   consist = 'freight_short' },
        { minute = 45, type = 'passenger', consist = 'roxwood_passenger' }
    }
}

-- Time period multipliers
-- Adjusts frequency based on time of day
Config.TimePeriods = {
    peak = {
        hours = { 7, 8, 9, 17, 18, 19 },  -- 7-9 AM, 5-7 PM
        multiplier = 1.0,  -- Full schedule
        minTrains = 3
    },

    offPeak = {
        hours = { 6, 10, 11, 12, 13, 14, 15, 16, 20, 21 },
        multiplier = 0.75,  -- 75% of slots
        minTrains = 2
    },

    night = {
        hours = { 22, 23, 0, 1, 2, 3, 4, 5 },
        multiplier = 0.5,  -- 50% of slots
        minTrains = 1
    }
}

--[[
    HELPER FUNCTIONS
]]

-- Get consist by key and type
function GetConsist(trainType, consistKey)
    if trainType == 'passenger' then
        return Config.Consists.passenger[consistKey]
    elseif trainType == 'freight' then
        return Config.Consists.freight[consistKey]
    end
    return nil
end

-- Get all consists for a line
function GetConsistsForLine(lineId)
    local consists = {
        passenger = {},
        freight = {}
    }

    for key, consist in pairs(Config.Consists.passenger) do
        for _, line in ipairs(consist.lines) do
            if line == lineId then
                table.insert(consists.passenger, key)
                break
            end
        end
    end

    for key, consist in pairs(Config.Consists.freight) do
        for _, line in ipairs(consist.lines) do
            if line == lineId then
                table.insert(consists.freight, key)
                break
            end
        end
    end

    return consists
end

-- Get next scheduled train for a line
function GetNextScheduledTrain(lineId, currentMinute)
    local slots = Config.ScheduleSlots[lineId]
    if not slots then return nil end

    currentMinute = currentMinute or tonumber(os.date('%M'))

    for _, slot in ipairs(slots) do
        if slot.minute >= currentMinute then
            return slot
        end
    end

    -- Wrap around to next hour
    return slots[1]
end

-- Get current time period
function GetCurrentTimePeriod()
    local hour = tonumber(os.date('%H'))

    for periodName, period in pairs(Config.TimePeriods) do
        for _, h in ipairs(period.hours) do
            if h == hour then
                return periodName, period
            end
        end
    end

    return 'offPeak', Config.TimePeriods.offPeak
end

-- Check if slot should run based on time period
function ShouldSlotRun(slotIndex, lineId)
    local periodName, period = GetCurrentTimePeriod()
    local slots = Config.ScheduleSlots[lineId]
    if not slots then return false end

    local totalSlots = #slots
    local activeSlots = math.ceil(totalSlots * period.multiplier)

    -- Always run the first N slots
    return slotIndex <= activeSlots
end

-- Export for scheduler
exports('GetConsist', GetConsist)
exports('GetConsistsForLine', GetConsistsForLine)
exports('GetNextScheduledTrain', GetNextScheduledTrain)
exports('GetCurrentTimePeriod', GetCurrentTimePeriod)
