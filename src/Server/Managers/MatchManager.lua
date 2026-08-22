-- MatchManager.lua
-- Owns: GameState machine and full match lifecycle
-- Exposes: init
-- Coordinates: EconomyService, MachineService, DataService,
--              PlotManager, WinConditionManager
-- Does not: calculate money, handle machine purchases,
--           update UI directly, persist data itself

local Players               = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local ServerScriptService   = game:GetService("ServerScriptService")

local MatchConfig           = require(ReplicatedStorage.Shared.Config.MatchConfig)
local GameState             = require(ReplicatedStorage.Shared.State.GameState)
local MatchEvent            = ReplicatedStorage.Shared.RemoteEvents.MatchEvent

local EconomyService        = require(ServerScriptService.Server.Services.EconomyService)
local MachineService        = require(ServerScriptService.Server.Services.MachineService)
local DataService           = require(ServerScriptService.Server.Services.DataService)
local PlotManager           = require(ServerScriptService.Server.Managers.PlotManager)
local WinConditionManager   = require(ServerScriptService.Server.Managers.WinConditionManager)

local PlotSetup             = require(ServerScriptService.Server.Services.PlotSetup)
local MachineSpawnService   = require(ServerScriptService.Server.Services.MachineSpawnService)
local PadService            = require(ServerScriptService.Server.Services.PadService)

local ResourceService       = require(ServerScriptService.Server.Services.ResourceService)
local ModifierManager = require(ServerScriptService.Server.Managers.ModifierManager)

local MatchManager = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local currentState      = GameState.WAITING
local countdownThread   = nil   -- task thread for pre-match countdown
local matchTimerThread  = nil   -- task thread for hard match time cap

-- Players currently in the match, keyed by UserId for fast lookup
-- { [userId] = player }
local activePlayers = {}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

local function getActivePlayerCount() : number
    local count = 0
    for _ in pairs(activePlayers) do
        count = count + 1
    end
    return count
end

-- Returns a snapshot of activePlayers as an array
-- Snapshot is important: we iterate this while modifying activePlayers,
-- so we need a stable copy that won't change mid-loop
local function getActivePlayerSnapshot() : {Player}
    local snapshot = {}
    for _, player in pairs(activePlayers) do
        table.insert(snapshot, player)
    end
    return snapshot
end

-- Transitions to a new GameState and notifies all clients
local function transitionTo(newState : string, targetPlayers : {Player}?)
    currentState = newState

    local payload = {
        action   = "STATE_CHANGED",
        newState = newState,
    }

    if newState == GameState.COUNTDOWN then
        local modifier = ModifierManager.getCurrentModifier()
        if modifier then
            payload.modifierName        = modifier.name
            payload.modifierDescription = modifier.description
        end
    end

    if targetPlayers then
        for _, player in ipairs(targetPlayers) do
            MatchEvent:FireClient(player, payload)
        end
    else
        MatchEvent:FireAllClients(payload)
    end
end

-- Saves one player's data and removes them from all services
-- isWinner: true increments their savedWins before saving
-- Called both during endMatch and when a player leaves mid-match
local function cleanupPlayer(player : Player, isWinner : boolean)
    -- Load their existing saved data
    local data = DataService.loadPlayerData(player)

    -- Increment wins if this player won the match
    if isWinner then
        data.savedWins = (data.savedWins or 0) + 1
    end

    DataService.savePlayerData(player, data)
    EconomyService.removePlayer(player)

    PadService.releaseAllPads(player)
    MachineSpawnService.removePlayer(player)

    MachineService.removePlayer(player)
    activePlayers[player.UserId] = nil
end

-- ─────────────────────────────────────────
-- PRIVATE MATCH FLOW
-- ─────────────────────────────────────────

-- Ends the current match
-- winnerPlayer: the Player who triggered the win, nil if match timed out
local function endMatch(winnerPlayer : Player?)
    if currentState ~= GameState.PLAYING then return end

    EconomyService.stopTick()
    PadService.stopDecayTick()
    WinConditionManager.stopChecking()
    ModifierManager.clearModifier()

    if matchTimerThread and coroutine.running() ~= matchTimerThread then
        task.cancel(matchTimerThread)
    end
    matchTimerThread = nil

    local finishedPlayers = getActivePlayerSnapshot()
    transitionTo(GameState.ENDING, finishedPlayers)

    for _, player in ipairs(finishedPlayers) do
        local isWinner = winnerPlayer ~= nil and player.UserId == winnerPlayer.UserId
        cleanupPlayer(player, isWinner)
    end

    PlotManager.releaseAllPlots()
    PlotSetup.despawnAllPlots()
    ResourceService.stopSpawning()

    task.delay(10, function()
        for _, player in ipairs(finishedPlayers) do
            if player.Parent then -- guard: they may have disconnected during results
                PlotSetup.teleportPlayerToLobby(player)
            end
        end
        transitionTo(GameState.WAITING)
    end)
end

-- small public getter, used by QueueManager's guard
function MatchManager.isPlayerInMatch(player : Player) : boolean
    return activePlayers[player.UserId] ~= nil
end

-- Initializes all systems and starts the match
-- Only callable from COUNTDOWN state
local function startMatch(players : {Player})
    if currentState ~= GameState.COUNTDOWN then return end

    for _, player in ipairs(players) do
        activePlayers[player.UserId] = player
    end

    PlotManager.initPlots(MatchConfig.PLOT_IDS)

    for _, player in ipairs(players) do
        local plotId    = PlotManager.assignPlot(player)
        local plotModel = PlotSetup.spawnPlot(player, plotId)

        if plotModel then
            PlotSetup.teleportPlayerToPlot(player, plotModel)
            MachineSpawnService.initPlayer(player, plotModel)
        end

        EconomyService.initPlayer(player)
        MachineService.initPlayer(player)
        PadService.initPads(player)
    end

    transitionTo(GameState.PLAYING, players)

    -- Start the economy tick
    EconomyService.startTick()
    PadService.startDecayTick()
    ResourceService.startSpawning()

    -- Start win detection, passing endMatch as the callback
    -- WinConditionManager calls this when a player crosses WIN_CONDITION
    WinConditionManager.startChecking(players, function(winnerPlayer : Player)
        endMatch(winnerPlayer)
    end)

    -- Start the hard cap timer
    -- If nobody wins within MATCH_DURATION seconds, end the match anyway
    matchTimerThread = task.spawn(function()
        task.wait(MatchConfig.MATCH_DURATION)
        if currentState == GameState.PLAYING then
            warn("MatchManager: match time limit reached, forcing end")
            endMatch(nil)
        end
    end)
end

-- Starts the pre-match countdown
-- Only callable from WAITING state
function MatchManager.beginCountdown()
    if currentState ~= GameState.WAITING then return end

    local QueueManager = require(ServerScriptService.Server.Managers.QueueManager)
    local queuedAtStart = QueueManager.getQueueSnapshot()

    ModifierManager.rollModifier()
    transitionTo(GameState.COUNTDOWN, queuedAtStart)

    countdownThread = task.spawn(function()
        task.wait(MatchConfig.COUNTDOWN_DURATION)
        countdownThread = nil

        local queuedSnapshot = QueueManager.getQueueSnapshot()

        if #queuedSnapshot >= MatchConfig.MIN_PLAYERS then
            QueueManager.removePlayers(queuedSnapshot)
            startMatch(queuedSnapshot)
        else
            warn("MatchManager: not enough players after countdown, resetting")
            transitionTo(GameState.WAITING)
        end
    end)
end

function MatchManager.isCountingDown() : boolean
    return currentState == GameState.COUNTDOWN
end

function MatchManager.notifyLateJoiner(player : Player)
    MatchEvent:FireClient(player, { action = "STATE_CHANGED", newState = GameState.COUNTDOWN })
end

-- ─────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────

local function onPlayerRemoving(player : Player)
    if not activePlayers[player.UserId] then return end

    if currentState == GameState.PLAYING then
        cleanupPlayer(player, false)
        PlotManager.releasePlot(player)

        if getActivePlayerCount() <= 1 then
            warn("MatchManager: too few players remain, ending match")
            endMatch(nil)
        end
    else
        activePlayers[player.UserId] = nil
    end
end


-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Boots MatchManager and connects all player lifecycle events
-- Called once by Main.server.lua at server startup
function MatchManager.init()

    Players.PlayerRemoving:Connect(onPlayerRemoving)

end

-- Returns the current GameState string
-- Read-only — only MatchManager writes to currentState
function MatchManager.getCurrentState() : string
    return currentState
end

return MatchManager