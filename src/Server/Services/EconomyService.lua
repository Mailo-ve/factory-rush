-- EconomyService.lua
-- Owns: all player money balances and the production tick
-- Exposes: getMoney, addMoney, deductMoney, canAfford, setCurrentIncome,
--          initPlayer, removePlayer, startTick, stopTick
-- Does not: know what machines exist, handle purchasing logic,
--           persist data, check win conditions

local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local MatchConfig        = require(ReplicatedStorage.Shared.Config.MatchConfig)
local EconomyEvent       = ReplicatedStorage.Shared.RemoteEvents.EconomyEvent
local LeaderboardEvent   = ReplicatedStorage.Shared.RemoteEvents.LeaderboardEvent
local ModifierManager = require(ServerScriptService.Server.Managers.ModifierManager)

local EconomyService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- All economy data, keyed by player.UserId
-- Structure per entry:
-- {
--     player        : Player,
--     money         : number,
--     currentIncome : number,   -- set by MachineService on every purchase
-- }
local playerEconomy = {}

local tickThread    = nil    -- running task thread, nil when stopped
local matchStartTime = 0     -- os.clock() recorded when startTick is called

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Fires the current money and income state to one player's client
local function fireMoneyUpdate(userId : number)
    local data = playerEconomy[userId]
    if not data then return end

    EconomyEvent:FireClient(data.player, {
        action        = "MONEY_UPDATED",
        newBalance    = data.money,
        currentIncome = data.currentIncome,
    })
end

-- Builds a sorted leaderboard array and fires it to all clients
local function fireLeaderboardUpdate()
    local entries = {}

    for _, data in pairs(playerEconomy) do
        table.insert(entries, {
            name  = data.player.DisplayName,
            money = data.money,
        })
    end

    -- Sort descending by money so the leading player is always first
    table.sort(entries, function(a, b)
        return a.money > b.money
    end)

    LeaderboardEvent:FireAllClients({
        action  = "UPDATED",
        players = entries,
    })
end

-- Returns the income multiplier based on how long the match has been running
-- Returns 1.0 during normal play, ACCELERATOR_MULTIPLIER after ACCELERATOR_START
-- This prevents matches from running over the hard cap
local function getAcceleratorMultiplier() : number
    local elapsed = os.clock() - matchStartTime
    if elapsed >= MatchConfig.ACCELERATOR_START then
        return MatchConfig.ACCELERATOR_MULTIPLIER
    end
    return 1.0
end

-- Runs one economy tick: adds income to every player's balance
-- and fires update events to clients
local function processTick()
    local multiplier = getAcceleratorMultiplier()

    for userId, data in pairs(playerEconomy) do
        if data.currentIncome > 0 then
            local earned = math.floor(data.currentIncome * multiplier)
            data.money   = data.money + earned
            fireMoneyUpdate(userId)
        end

        local marketBossReward = ModifierManager.checkMarketBoss(data.player, data.money)
        if marketBossReward then
            data.money = data.money + marketBossReward
            fireMoneyUpdate(userId)
        end
    end
    -- Leaderboard fires once per tick to all clients, not per player
    fireLeaderboardUpdate()
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Registers a player into the economy system with starting money
-- Must be called by MatchManager before any other function is used for this player
function EconomyService.initPlayer(player : Player)
    assert(
        not playerEconomy[player.UserId],
        "EconomyService.initPlayer: player already initialized: " .. player.DisplayName
    )

    local startingMoney = ModifierManager.getStartingMoney() or MatchConfig.STARTING_MONEY

    playerEconomy[player.UserId] = {
        player        = player,
        money         = startingMoney,
        currentIncome = 0,
    }
    -- Push initial state to client immediately so UI starts correctly
    fireMoneyUpdate(player.UserId)
end

-- Removes a player from the economy system
-- Called by MatchManager when a player leaves or the match ends
function EconomyService.removePlayer(player : Player)
    playerEconomy[player.UserId] = nil
end

-- Returns the player's current authoritative money balance
function EconomyService.getMoney(player : Player) : number
    local data = playerEconomy[player.UserId]
    assert(data, "EconomyService.getMoney: player not initialized: " .. player.DisplayName)
    return data.money
end

-- Adds a non-negative amount to the player's money balance
-- Fires MONEY_UPDATED to client
function EconomyService.addMoney(player : Player, amount : number)
    assert(amount >= 0, "EconomyService.addMoney: amount must be non-negative, got: " .. amount)
    local data = playerEconomy[player.UserId]
    assert(data, "EconomyService.addMoney: player not initialized: " .. player.DisplayName)

    data.money = data.money + math.floor(amount)
    fireMoneyUpdate(player.UserId)
end

-- Attempts to deduct an amount from the player's money balance
-- Returns true and fires MONEY_UPDATED on success
-- Returns false without modifying state if player cannot afford it
function EconomyService.deductMoney(player : Player, amount : number) : boolean
    assert(amount >= 0, "EconomyService.deductMoney: amount must be non-negative, got: " .. amount)
    local data = playerEconomy[player.UserId]
    assert(data, "EconomyService.deductMoney: player not initialized: " .. player.DisplayName)

    if data.money < amount then
        return false
    end

    data.money = data.money - amount
    fireMoneyUpdate(player.UserId)
    return true
end

-- Returns true if the player has enough money to afford the given amount
-- Does not modify any state
function EconomyService.canAfford(player : Player, amount : number) : boolean
    local data = playerEconomy[player.UserId]
    assert(data, "EconomyService.canAfford: player not initialized: " .. player.DisplayName)
    return data.money >= amount
end

-- Updates the player's cached currentIncome value
-- This is the ONLY way currentIncome changes
-- Must be called by MachineService after every machine purchase or upgrade
-- EconomyService never calculates income itself — it only stores and applies it
function EconomyService.setCurrentIncome(player : Player, amount : number)
    assert(amount >= 0, "EconomyService.setCurrentIncome: amount must be non-negative, got: " .. amount)
    local data = playerEconomy[player.UserId]
    assert(data, "EconomyService.setCurrentIncome: player not initialized: " .. player.DisplayName)

    data.currentIncome = amount

    -- Fire immediately so UI reflects the new income rate right away
    -- not just on the next tick
    fireMoneyUpdate(player.UserId)
end

-- Starts the production tick loop
-- Called by MatchManager when GameState transitions to PLAYING
-- Guard prevents double-starting if called twice
function EconomyService.startTick()
    if tickThread then
        warn("EconomyService.startTick: tick already running, ignoring")
        return
    end

    matchStartTime = os.clock()

    tickThread = task.spawn(function()
        while true do
            task.wait(MatchConfig.ECONOMY_TICK_RATE)
            processTick()
        end
    end)
end

-- Stops the production tick loop
-- Called by MatchManager when GameState transitions to ENDING
function EconomyService.stopTick()
    if tickThread then
        task.cancel(tickThread)
        tickThread = nil
    end
end

return EconomyService