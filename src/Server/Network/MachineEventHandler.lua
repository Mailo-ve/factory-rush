-- MachineEventHandler.lua
-- CHANGED: BUY action renamed to BUILD, payload now includes padId

local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local ServerScriptService   = game:GetService("ServerScriptService")

local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local GameState     = require(ReplicatedStorage.Shared.State.GameState)
local MachineEvent  = ReplicatedStorage.Shared.RemoteEvents.MachineEvent
local MachineService = require(ServerScriptService.Server.Services.MachineService)

local function getMatchManager()
    return require(ServerScriptService.Server.Managers.MatchManager)
end

local MachineEventHandler = {}

local function isValidPayload(payload)
    return payload ~= nil and type(payload) == "table"
end

local function isValidMachineType(machineType)
    return type(machineType) == "string" and MachineConfig[machineType] ~= nil
end

local function isValidBranch(branch)
    return branch == "A" or branch == "B"
end

local function isValidPadId(padId)
    return type(padId) == "string" and padId ~= ""
end

local function isPlayerInMatch(player)
    return getMatchManager().getCurrentState() == GameState.PLAYING
end

-- CHANGED: was handleBuy, now handleBuild — includes padId
local function handleBuild(player, payload)
    if not isValidPayload(payload) then
        warn("MachineEventHandler.BUILD: invalid payload from "
            .. player.DisplayName)
        return
    end
    if not isValidMachineType(payload.machineType) then
        warn("MachineEventHandler.BUILD: invalid machineType from "
            .. player.DisplayName)
        return
    end
    if not isValidPadId(payload.padId) then
        warn("MachineEventHandler.BUILD: missing padId from "
            .. player.DisplayName)
        return
    end
    if not isPlayerInMatch(player) then return end

    local success, reason = MachineService.purchaseMachine(
        player,
        payload.machineType,
        payload.padId
    )
    if not success then
        warn("MachineEventHandler.BUILD: failed for "
            .. player.DisplayName .. ": " .. tostring(reason))
    end
end

local function handleUpgrade(player, payload)
    if not isValidPayload(payload) then return end
    if not isValidMachineType(payload.machineType) then return end
    if not isValidBranch(payload.branch) then return end
    if not isValidPadId(payload.padId) then return end
    if not isPlayerInMatch(player) then return end

    local success, reason = MachineService.purchaseUpgrade(
        player,
        payload.machineType,
        payload.branch,
        payload.padId
    )
    if not success then
        warn("MachineEventHandler.UPGRADE: failed for "
            .. player.DisplayName .. ": " .. tostring(reason))
    end
end

local function handleService(player, payload)
    if not isValidPayload(payload) then return end
    if not isValidPadId(payload.padId) then return end
    if not isPlayerInMatch(player) then return end

    local success, reason = MachineService.serviceMachine(
        player,
        payload.padId
    )
    if not success then
        warn("MachineEventHandler.SERVICE: failed for "
            .. player.DisplayName .. ": " .. tostring(reason))
    end
end

local actionHandlers = {
    BUILD   = handleBuild,
    UPGRADE = handleUpgrade,
    SERVICE = handleService,
}

function MachineEventHandler.init()
    MachineEvent.OnServerEvent:Connect(function(player, payload)
        if not isValidPayload(payload)
            or type(payload.action) ~= "string" then
            return
        end
        local handler = actionHandlers[payload.action]
        if handler then
            handler(player, payload)
        end
    end)
end

return MachineEventHandler