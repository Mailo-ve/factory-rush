-- WinConditionManager.lua
-- Owns: win detection
-- Exposes: startChecking, stopChecking
-- Does not: modify money, end the match, update UI, save data
-- Note: calls EconomyService.getMoney() directly on its own tick
--       MatchManager listens to MatchEvent(GAME_WON) and handles everything after

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local MatchConfig       = require(ReplicatedStorage.Shared.Config.MatchConfig)
local MatchEvent        = ReplicatedStorage.Shared.RemoteEvents.MatchEvent

-- Lazy require for same reason as MachineService → EconomyService
-- Avoids load order issues between Managers and Services
local function getEconomyService()
    return require(game:GetService("ServerScriptService").Server.Services.EconomyService)
end

local WinConditionManager = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local checkThread   = nil   -- running task thread, nil when stopped
local isChecking    = false -- guard flag, prevents double-starting
local onWinnerFound = nil   -- callback set by startChecking

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Checks every player's money against the win threshold
-- If any player has crossed it, fires GAME_WON and stops checking
-- Returns true if a winner was found, false otherwise
local function checkForWinner(players : {Player}) : boolean
    local EconomyService = getEconomyService()

    for _, player in ipairs(players) do
        local money = EconomyService.getMoney(player)

        if money >= MatchConfig.WIN_CONDITION then
            for _, matchPlayer in ipairs(players) do
                MatchEvent:FireClient(matchPlayer, {
                    action      = "GAME_WON",
                    winnerName  = player.DisplayName,
                    winnerMoney = money,
                })
            end
            if onWinnerFound then
                onWinnerFound(player)
            end
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Starts the win condition check loop
-- Called by MatchManager when GameState transitions to PLAYING
-- callback: function(winnerPlayer : Player) called when a winner is found
function WinConditionManager.startChecking(players : {Player}, callback : (Player) -> ())
    if isChecking then
        warn("WinConditionManager.startChecking: already checking, ignoring")
        return
    end

    onWinnerFound = callback
    isChecking    = true

    checkThread = task.spawn(function()
        while isChecking do
            task.wait(MatchConfig.ECONOMY_TICK_RATE)
            if checkForWinner(players) then
                WinConditionManager.stopChecking()
            end
        end
    end)
end

-- Stops the win condition check loop
-- Called automatically when a winner is found
-- Also called by MatchManager when transitioning to ENDING
-- safe to call even if not currently checking
function WinConditionManager.stopChecking()
    isChecking = false

    if checkThread then
        task.cancel(checkThread)
        checkThread = nil
    end
end

return WinConditionManager