-- DataService.lua
-- Owns: all DataStore read and write operations
-- Exposes: loadPlayerData, savePlayerData
-- Does not: know what the data means, make game decisions,
--           interact with any other service

local DataStoreService  = game:GetService("DataStoreService")

local DataService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- The DataStore bucket this game writes to
-- Changing this string creates a fresh store — useful for wiping test data
local STORE_NAME    = "FactoryRush_v1"
local playerStore   = DataStoreService:GetDataStore(STORE_NAME)

-- Retry configuration
-- Roblox DataStore calls can fail transiently under load
-- We retry up to MAX_RETRIES times before giving up
local MAX_RETRIES   = 3
local RETRY_DELAY   = 2     -- seconds between retries

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Builds the DataStore key for a player
-- Using UserId (not DisplayName) so the key never changes
-- if a player changes their Roblox username
local function getKey(player : Player) : string
    return "player_" .. player.UserId
end

-- Wraps a DataStore call with retry logic
-- operation: a function that performs the actual DataStore call
-- Returns the result on success, nil on total failure
local function withRetry(operation : () -> any) : any
    local attempts  = 0
    local success   = false
    local result    = nil

    while attempts < MAX_RETRIES and not success do
        attempts = attempts + 1
        success, result = pcall(operation)

        if not success then
            warn(
                "DataService: DataStore call failed (attempt " ..
                attempts .. "/" .. MAX_RETRIES .. "): " ..
                tostring(result)
            )

            if attempts < MAX_RETRIES then
                task.wait(RETRY_DELAY)
            end
        end
    end

    if not success then
        warn("DataService: all retries exhausted, operation failed")
        return nil
    end

    return result
end

-- Returns a default data table for a brand new player
-- Used when no saved data exists in the DataStore
local function getDefaultData() : {savedWins : number}
    return {
        savedWins = 0,
    }
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Loads a player's persisted data from the DataStore
-- Returns saved data on success, default data if none exists,
-- and default data on failure (so the game always has something to work with)
-- Called by MatchManager when a player joins
function DataService.loadPlayerData(player : Player) : {savedWins : number}
    local key = getKey(player)

    local data = withRetry(function()
        return playerStore:GetAsync(key)
    end)

    -- GetAsync returns nil if the key has never been written
    -- In that case we give the player fresh default data
    if data == nil then
        return getDefaultData()
    end

    return data
end

-- Saves a player's data to the DataStore
-- data: table matching the shape returned by loadPlayerData
-- Returns true on success, false on total failure
-- Called by MatchManager at match end and when a player leaves
function DataService.savePlayerData(player : Player, data : {savedWins : number}) : boolean
    local key       = getKey(player)
    local succeeded = false

    local attempts  = 0

    while attempts < MAX_RETRIES and not succeeded do
        attempts = attempts + 1
        local ok, err = pcall(function()
            playerStore:SetAsync(key, data)
        end)

        if ok then
            succeeded = true
        else
            warn(
                "DataService.savePlayerData: attempt " ..
                attempts .. "/" .. MAX_RETRIES ..
                " failed for " .. player.DisplayName ..
                ": " .. tostring(err)
            )
            if attempts < MAX_RETRIES then
                task.wait(RETRY_DELAY)
            end
        end
    end

    if not succeeded then
        warn("DataService.savePlayerData: all retries exhausted for " .. player.DisplayName)
    end

    return succeeded
end

return DataService