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

local PlotSetup             = require(ServerScriptService.Server.Network.PlotSetup)
local MachineSpawnService   = require(ServerScriptService.Server.Services.MachineSpawnService)
local PadService            = require(ServerScriptService.Server.Services.PadService)

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
local function transitionTo(newState : string)
    currentState = newState
    MatchEvent:FireAllClients({
        action   = "STATE_CHANGED",
        newState = newState,
    })
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

    MachineService.removePlayer(player)
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
    -- Guard: only end from PLAYING state
    -- Prevents double-calls from timer expiry and win detection racing
    if currentState ~= GameState.PLAYING then return end

    -- Stop all running systems immediately
    EconomyService.stopTick()
    WinConditionManager.stopChecking()

    -- Cancel the hard cap timer if it's still running
    if matchTimerThread then
        task.cancel(matchTimerThread)
        matchTimerThread = nil
    end

    transitionTo(GameState.ENDING)

    -- Save and clean up every active player
    -- Using snapshot so cleanup doesn't break the iteration
    for _, player in ipairs(getActivePlayerSnapshot()) do
        local isWinner = winnerPlayer ~= nil
            and player.UserId == winnerPlayer.UserId
        cleanupPlayer(player, isWinner)
    end

    -- Release all plots back to unoccupied
    PlotManager.releaseAllPlots()
    PlotSetup.despawnAllPlots()

    -- Wait for win screen to display, then reset to WAITING
    task.delay(10, function()
        transitionTo(GameState.WAITING)
    end)
end

-- Initializes all systems and starts the match
-- Only callable from COUNTDOWN state
local function startMatch()
    if currentState ~= GameState.COUNTDOWN then return end

    -- Initialize plots from MatchConfig
    PlotManager.initPlots(MatchConfig.PLOT_IDS)

    -- Initialize every active player across all services
    for _, player in ipairs(getActivePlayerSnapshot()) do
        local plotId    = PlotManager.assignPlot(player)
        local plotModel = PlotSetup.spawnPlot(player, plotId)

        EconomyService.initPlayer(player)
        MachineService.initPlayer(player)
        PadService.initPads(player)

        if plotModel then
            MachineSpawnService.initPlayer(player, plotModel)
        end
    end

    transitionTo(GameState.PLAYING)

    -- Start the economy tick
    EconomyService.startTick()

    -- Start win detection, passing endMatch as the callback
    -- WinConditionManager calls this when a player crosses WIN_CONDITION
    WinConditionManager.startChecking(function(winnerPlayer : Player)
        endMatch(winnerPlayer)
    end)

    -- Start the hard cap timer
    -- If nobody wins within MATCH_DURATION seconds, end the match anyway
    matchTimerThread = task.spawn(function()
        task.wait(MatchConfig.MATCH_DURATION)
        if currentState == GameState.PLAYING then
            warn("MatchManager: match time limit reached, forcing end")
            endMatch(nil)   -- nil = no winner, time ran out
        end
    end)
end

-- Starts the pre-match countdown
-- Only callable from WAITING state
local function startCountdown()
    if currentState ~= GameState.WAITING then return end

    transitionTo(GameState.COUNTDOWN)

    countdownThread = task.spawn(function()
        task.wait(MatchConfig.COUNTDOWN_DURATION)
        countdownThread = nil

        -- Re-check player count after countdown
        -- Players may have left during the 10 seconds
        if getActivePlayerCount() >= MatchConfig.MIN_PLAYERS then
            startMatch()
        else
            -- Not enough players remained, reset
            warn("MatchManager: not enough players after countdown, resetting")
            transitionTo(GameState.WAITING)
        end
    end)
end

-- ─────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────

local function onPlayerAdded(player : Player)
    -- Players who join during an active match wait for the next one
    -- Only WAITING and COUNTDOWN accept new players
    if currentState == GameState.PLAYING or currentState == GameState.ENDING then
        return
    end

    activePlayers[player.UserId] = player

    -- Check if we now have enough to start
    if currentState == GameState.WAITING then
        if getActivePlayerCount() >= MatchConfig.MIN_PLAYERS then
            startCountdown()
        end
    end
end

local function onPlayerRemoving(player : Player)
    -- Ignore players who aren't tracked (joined during PLAYING/ENDING)
    if not activePlayers[player.UserId] then return end

    if currentState == GameState.PLAYING then
        -- Clean up and release their plot individually
        cleanupPlayer(player, false)
        PlotManager.releasePlot(player)

        -- If only one player remains, match is uncontested — end it
        if getActivePlayerCount() <= 1 then
            warn("MatchManager: too few players remain, ending match")
            endMatch(nil)
        end

    elseif currentState == GameState.COUNTDOWN then
        activePlayers[player.UserId] = nil

        -- If we drop below minimum during countdown, cancel and reset
        if getActivePlayerCount() < MatchConfig.MIN_PLAYERS then
            if countdownThread then
                task.cancel(countdownThread)
                countdownThread = nil
            end
            warn("MatchManager: player left during countdown, not enough players")
            transitionTo(GameState.WAITING)
        end

    else
        -- WAITING or ENDING — just remove them from tracking
        activePlayers[player.UserId] = nil
    end
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Boots MatchManager and connects all player lifecycle events
-- Called once by Main.server.lua at server startup
function MatchManager.init()
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Handle players who joined before this script loaded
    -- This happens frequently in Studio solo testing
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
end

-- Returns the current GameState string
-- Read-only — only MatchManager writes to currentState
function MatchManager.getCurrentState() : string
    return currentState
end

return MatchManager