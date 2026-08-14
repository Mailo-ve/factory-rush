-- QueueManager.lua
-- Owns: the pre-match queue roster (players waiting to be matched)
-- Exposes: init, joinQueue, leaveQueue, getQueueSnapshot, removePlayers, isPlayerQueued
-- Coordinates: MatchManager — requests a match, never touches GameState itself
-- Does not: spawn plots, touch GameState, calculate economy

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Shared.Config.MatchConfig)
local PlotConfig   = require(ReplicatedStorage.Shared.Config.PlotConfig)
local QueueEvent   = ReplicatedStorage.Shared.RemoteEvents.QueueEvent

local MatchManager -- assigned lazily in init() to avoid a circular require

local QueueManager = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local queuedPlayers = {}   -- { [userId] = player }
local queuePrompt    = nil  -- the physical prompt in the Lobby

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

local function getQueueCount() : number
    local count = 0
    for _ in pairs(queuedPlayers) do
        count = count + 1
    end
    return count
end

local function getQueueSnapshot() : {Player}
    local snapshot = {}
    for _, player in pairs(queuedPlayers) do
        table.insert(snapshot, player)
    end
    return snapshot
end

-- Updates the world-visible prompt text and every queued player's HUD
local function broadcastQueueStatus()
    local count = getQueueCount()

    if queuePrompt then
        queuePrompt.ObjectText = "Waiting for players — "
            .. count .. "/" .. MatchConfig.MAX_PLAYERS
    end

    for _, player in pairs(queuedPlayers) do
        QueueEvent:FireClient(player, {
            action = "QUEUE_UPDATE",
            count  = count,
            needed = MatchConfig.MIN_PLAYERS,
            max    = MatchConfig.MAX_PLAYERS,
        })
    end
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

function QueueManager.isPlayerQueued(player : Player) : boolean
    return queuedPlayers[player.UserId] ~= nil
end

function QueueManager.getQueueSnapshot() : {Player}
    return getQueueSnapshot()
end

-- Adds a player to the queue. Rejects: already queued, already in a
-- match, or queue full — matches the doc's "no duplicate entries" rule
function QueueManager.joinQueue(player : Player)
    if queuedPlayers[player.UserId] then return end

    if MatchManager.isPlayerInMatch(player) then
        warn("QueueManager.joinQueue: " .. player.DisplayName .. " is already in a match")
        return
    end

    if getQueueCount() >= MatchConfig.MAX_PLAYERS then
        warn("QueueManager.joinQueue: queue is full")
        return
    end

    queuedPlayers[player.UserId] = player
    QueueEvent:FireClient(player, { action = "QUEUE_JOINED" })
    broadcastQueueStatus()

    if getQueueCount() >= MatchConfig.MIN_PLAYERS then
        MatchManager.beginCountdown()
    end
end

-- Voluntary leave (walked away) or disconnect
function QueueManager.leaveQueue(player : Player)
    if not queuedPlayers[player.UserId] then return end

    queuedPlayers[player.UserId] = nil
    QueueEvent:FireClient(player, { action = "QUEUE_LEFT" })
    broadcastQueueStatus()
end

-- Called by MatchManager once it actually starts a match with these
-- players. Silent — no QUEUE_LEFT, since STATE_CHANGED already
-- drives their UI into the countdown screen instead.
function QueueManager.removePlayers(players : {Player})
    for _, player in ipairs(players) do
        queuedPlayers[player.UserId] = nil
    end
    broadcastQueueStatus()
end

function QueueManager.init()
    MatchManager = require(ServerScriptService.Server.Managers.MatchManager)

    local lobby = workspace:FindFirstChild("Lobby")
    if not lobby then
        warn("QueueManager.init: no Lobby found in workspace")
        return
    end

    local queueArea = lobby:FindFirstChild("QueueArea")
    if not queueArea then
        warn("QueueManager.init: no QueueArea found inside Lobby")
        return
    end

    queuePrompt = Instance.new("ProximityPrompt")
    queuePrompt.ActionText            = "Join Queue"
    queuePrompt.ObjectText            = "Waiting for players — 0/" .. MatchConfig.MAX_PLAYERS
    queuePrompt.KeyboardKeyCode       = Enum.KeyCode.E
    queuePrompt.MaxActivationDistance = PlotConfig.PROMPT_DISTANCE
    queuePrompt.HoldDuration          = PlotConfig.PROMPT_HOLD_DURATION
    queuePrompt.Parent                = queueArea

    queuePrompt.Triggered:Connect(function(player : Player)
        QueueManager.joinQueue(player)
    end)

    -- Walking away from the queue area cancels it automatically —
    -- covers the doc's "leave the queue area" cancel method
    queueArea.TouchEnded:Connect(function(otherPart : BasePart)
        local character = otherPart.Parent
        local player = character and Players:GetPlayerFromCharacter(character)
        if player and QueueManager.isPlayerQueued(player) then
            QueueManager.leaveQueue(player)
        end
    end)

    Players.PlayerRemoving:Connect(function(player : Player)
        QueueManager.leaveQueue(player)
    end)
end

return QueueManager