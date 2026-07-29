-- MachineEventHandler.lua
-- Owns: inbound MachineEvent handling from clients
-- Validates all payloads before delegating to MachineService
-- Contains zero business logic — validation and delegation only
-- Does not: touch money, update UI, know game rules

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local GameState     = require(ReplicatedStorage.Shared.State.GameState)
local MachineEvent  = ReplicatedStorage.Shared.RemoteEvents.MachineEvent

local MachineService = require(ServerScriptService.Server.Services.MachineService)

local MachineEventHandler = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Reference to MatchManager's current state
-- Lazy-required to avoid load order issues
local function getMatchManager()
    return require(ServerScriptService.Server.Managers.MatchManager)
end

-- ─────────────────────────────────────────
-- PRIVATE VALIDATION
-- ─────────────────────────────────────────

-- Returns true if the payload is a non-nil table
-- Every action check starts here
local function isValidPayload(payload : any) : boolean
    return payload ~= nil and type(payload) == "table"
end

-- Returns true if machineType is a non-empty string
-- that exists as a key in MachineConfig
local function isValidMachineType(machineType : any) : boolean
    return type(machineType) == "string"
        and MachineConfig[machineType] ~= nil
end

-- Returns true if branch is exactly "A" or "B"
local function isValidBranch(branch : any) : boolean
    return branch == "A" or branch == "B"
end

-- Returns true if the player is currently in a PLAYING match
-- EventHandler is the first line of defense — no game logic
-- runs for players who aren't in an active match
local function isPlayerInMatch(player : Player) : boolean
    return getMatchManager().getCurrentState() == GameState.PLAYING
end

-- ─────────────────────────────────────────
-- PRIVATE HANDLERS
-- ─────────────────────────────────────────

local function handleBuy(player : Player, payload : any)
    -- Validate payload structure
    if not isValidPayload(payload) then
        warn("MachineEventHandler.BUY: invalid payload from " .. player.DisplayName)
        return
    end

    -- Validate machineType
    if not isValidMachineType(payload.machineType) then
        warn("MachineEventHandler.BUY: invalid machineType '"
            .. tostring(payload.machineType)
            .. "' from " .. player.DisplayName)
        return
    end

    -- Validate player is in an active match
    if not isPlayerInMatch(player) then
        warn("MachineEventHandler.BUY: player not in active match: " .. player.DisplayName)
        return
    end

    -- All checks passed — delegate to MachineService
    local success, reason = MachineService.purchaseMachine(player, payload.machineType)

    if not success then
        -- Log server-side for debugging
        -- No error is sent back to client in MVP
        warn("MachineEventHandler.BUY: purchase failed for "
            .. player.DisplayName .. ": " .. tostring(reason))
    end
end

local function handleUpgrade(player : Player, payload : any)
    -- Validate payload structure
    if not isValidPayload(payload) then
        warn("MachineEventHandler.UPGRADE: invalid payload from " .. player.DisplayName)
        return
    end

    -- Validate machineType
    if not isValidMachineType(payload.machineType) then
        warn("MachineEventHandler.UPGRADE: invalid machineType '"
            .. tostring(payload.machineType)
            .. "' from " .. player.DisplayName)
        return
    end

    -- Validate branch
    if not isValidBranch(payload.branch) then
        warn("MachineEventHandler.UPGRADE: invalid branch '"
            .. tostring(payload.branch)
            .. "' from " .. player.DisplayName)
        return
    end

    -- Validate player is in an active match
    if not isPlayerInMatch(player) then
        warn("MachineEventHandler.UPGRADE: player not in active match: " .. player.DisplayName)
        return
    end

    -- All checks passed — delegate to MachineService
    local success, reason = MachineService.purchaseUpgrade(
        player,
        payload.machineType,
        payload.branch
    )

    if not success then
        warn("MachineEventHandler.UPGRADE: upgrade failed for "
            .. player.DisplayName .. ": " .. tostring(reason))
    end
end

-- ─────────────────────────────────────────
-- ACTION ROUTER
-- ─────────────────────────────────────────

-- Routes incoming payloads to the correct handler by action string
-- Any unknown action is silently dropped
local actionHandlers = {
    BUY     = handleBuy,
    UPGRADE = handleUpgrade,
}

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Connects the RemoteEvent listener
-- Called once by Main.server.lua at startup
function MachineEventHandler.init()
    MachineEvent.OnServerEvent:Connect(function(player : Player, payload : any)
        -- First check: does an action field exist at all?
        if not isValidPayload(payload) or type(payload.action) ~= "string" then
            warn("MachineEventHandler: missing or invalid action from " .. player.DisplayName)
            return
        end

        -- Route to the correct handler
        local handler = actionHandlers[payload.action]

        if handler then
            handler(player, payload)
        else
            warn("MachineEventHandler: unknown action '"
                .. payload.action
                .. "' from " .. player.DisplayName)
        end
    end)
end

return MachineEventHandler