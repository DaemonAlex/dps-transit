--[[
    dps-transit - Qbox (qbx_core) Bridge
    Wraps qbx_core in standard Bridge.* calls.

    IMPORTANT: This qbx_core build exposes NO GetCoreObject().
    Both exports['qb-core']:GetCoreObject() and exports.qbx_core:GetCoreObject()
    THROW on this box. We therefore acquire nothing at file scope and use the
    discrete qbx_core native exports directly (GetPlayer / GetPlayerData /
    GetQBPlayers / GetMoney / AddMoney / RemoveMoney). The DATA layer is still
    qb-shaped once we hold the Player object (PlayerData.job / .charinfo /
    .citizenid), so only object-acquisition differs from bridge/qb.lua.

    Notifications route through ox_lib (lib.notify / ox_lib:notify), since qbx
    ships ox_lib rather than a qb-core Notify.
]]

if IsDuplicityVersion() then
    -----------------------------------------------------------
    -- SERVER SIDE
    -----------------------------------------------------------

    ---@param source number Player server ID
    ---@return table|nil Player object
    function Bridge.GetPlayer(source)
        return exports.qbx_core:GetPlayer(source)
    end

    ---@param source number Player server ID
    ---@return string Full character name
    function Bridge.GetCharacterName(source)
        local Player = exports.qbx_core:GetPlayer(source)
        if not Player then return 'Unknown' end
        local charinfo = Player.PlayerData.charinfo
        return charinfo.firstname .. ' ' .. charinfo.lastname
    end

    ---@param source number Player server ID
    ---@return string, number Job name and grade
    function Bridge.GetJob(source)
        local Player = exports.qbx_core:GetPlayer(source)
        if not Player then return 'unemployed', 0 end
        return Player.PlayerData.job.name, Player.PlayerData.job.grade.level
    end

    ---@param source number Player server ID
    ---@return string|nil Player identifier (citizenid)
    function Bridge.GetIdentifier(source)
        local Player = exports.qbx_core:GetPlayer(source)
        if not Player then return nil end
        return Player.PlayerData.citizenid
    end

    ---@param source number Player server ID
    ---@param account string 'cash' or 'bank'
    ---@param amount number Amount to remove
    ---@return boolean Success
    function Bridge.RemoveMoney(source, account, amount)
        -- qbx money types match qb ('cash' / 'bank'); no remap needed
        return exports.qbx_core:RemoveMoney(source, account, amount, 'transit-ticket') and true or false
    end

    ---@param source number Player server ID
    ---@param account string 'cash' or 'bank'
    ---@param amount number Amount to add
    ---@return boolean Success
    function Bridge.AddMoney(source, account, amount)
        return exports.qbx_core:AddMoney(source, account, amount, 'transit-refund') and true or false
    end

    ---@param source number Player server ID
    ---@param account string 'cash' or 'bank'
    ---@return number Balance
    function Bridge.GetMoney(source, account)
        return exports.qbx_core:GetMoney(source, account) or 0
    end

    ---@return table Array of player server IDs
    function Bridge.GetPlayers()
        local playerIds = {}
        -- GetQBPlayers() returns a table keyed by numeric server id
        for src in pairs(exports.qbx_core:GetQBPlayers()) do
            playerIds[#playerIds + 1] = src
        end
        return playerIds
    end

    ---@param source number Player server ID
    ---@param title string Notification title
    ---@param msg string Notification message
    ---@param type string 'success', 'error', 'inform'
    function Bridge.Notify(source, title, msg, type)
        TriggerClientEvent('ox_lib:notify', source, {
            title = title,
            description = msg,
            type = type
        })
    end

    ---@param cb function Callback when player loads (receives source)
    function Bridge.OnPlayerLoaded(cb)
        -- qbx_core emits the QBCore compat event server-side
        RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
            cb(source)
        end)
    end

    ---@param cb function Callback when player unloads (receives source)
    function Bridge.OnPlayerUnload(cb)
        RegisterNetEvent('QBCore:Server:OnPlayerUnload', function()
            cb(source)
        end)
    end

else
    -----------------------------------------------------------
    -- CLIENT SIDE
    -----------------------------------------------------------

    ---@return table Player data
    function Bridge.GetPlayerData()
        return exports.qbx_core:GetPlayerData()
    end

    ---@return string, number Job name and grade
    function Bridge.GetJob()
        local PlayerData = exports.qbx_core:GetPlayerData()
        if not PlayerData or not PlayerData.job then return 'unemployed', 0 end
        return PlayerData.job.name, PlayerData.job.grade.level
    end

    ---@return boolean Is player loaded
    function Bridge.IsPlayerLoaded()
        local PlayerData = exports.qbx_core:GetPlayerData()
        return PlayerData ~= nil and PlayerData.citizenid ~= nil
    end

    ---@param cb function Callback when player loads
    function Bridge.OnPlayerLoaded(cb)
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            cb()
        end)
    end

    ---@param cb function Callback when player unloads
    function Bridge.OnPlayerUnload(cb)
        RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
            cb()
        end)
    end

    ---@param cb function Callback when job updates
    function Bridge.OnJobUpdate(cb)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
            cb(job)
        end)
    end

    ---@param msg string Notification message
    ---@param type string 'success', 'error', 'inform'
    function Bridge.Notify(msg, type)
        lib.notify({
            description = msg,
            type = type
        })
    end
end
