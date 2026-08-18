--[[
    dps-transit - Framework Bridge Loader
    Auto-detects QBCore or ESX and loads the appropriate bridge
]]

Bridge = {}
local context = IsDuplicityVersion() and 'server' or 'client'

-- Auto-detect framework if not set in config
-- Order matters: qbx_core is checked FIRST so a box running both qbx_core and a
-- qb-core compat shim prefers the native qbx bridge (this build has NO GetCoreObject).
if not Config.Framework or Config.Framework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        Config.Framework = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        Config.Framework = 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        Config.Framework = 'esx'
    else
        print('[^1dps-transit^7] No supported framework detected!')
        Config.Framework = 'qb' -- Default fallback
    end
end

-- Load the correct bridge file
local bridgeFile = ('bridge/%s.lua'):format(Config.Framework)
local fileContent = LoadResourceFile(GetCurrentResourceName(), bridgeFile)

if fileContent then
    local chunk, err = load(fileContent, bridgeFile)
    if chunk then
        -- Wrap execution so a bridge error (e.g. a bad export on an unexpected
        -- framework build) is non-fatal AND visible, instead of propagating and
        -- killing the shared script for the whole resource.
        local ok, runErr = pcall(chunk)
        if ok then
            print(('[^4dps-transit^7] Loaded ^5%s^7 bridge for %s'):format(Config.Framework:upper(), context))
        else
            print(('[^1dps-transit^7] Bridge ^5%s^7 threw on load (%s): %s'):format(Config.Framework:upper(), context, runErr))
        end
    else
        print(('[^1dps-transit^7] Failed to compile bridge: %s'):format(err))
    end
else
    print(('[^1dps-transit^7] Bridge file not found: %s'):format(bridgeFile))
end
