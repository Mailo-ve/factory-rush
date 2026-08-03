-- PadService.lua
-- Owns: pad states per player
-- Tracks what is built on each pad and each pad's lifecycle state
-- Exposes: initPads, removePlayer, getPadState, getPadMachineType,
--          canOccupyPad, occupyPad, setPadActive,
--          releasePad, releaseAllPads, getPlayerPads
-- Does not: spawn visuals, calculate income, handle purchases,
--           know anything about the physical world

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig    = require(ReplicatedStorage.Shared.Config.PlotConfig)
local PadState      = require(ReplicatedStorage.Shared.State.PadState)

local PadService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Keyed by player.UserId
-- Each entry is a dictionary of padId → pad record:
-- {
--     state       : string,   PadState value
--     machineType : string?,  nil when EMPTY
-- }
local playerPads = {}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

-- Extracts machine type from a pad name using PlotConfig pattern
-- "HarvesterPad1" → "Harvester"
-- Returns nil if name does not match
local function getMachineTypeFromPadId(padId : string) : string?
    return padId:match(PlotConfig.PAD_NAME_PATTERN)
end

-- Generates all pad IDs from PlotConfig.PAD_COUNTS
-- Returns: {"HarvesterPad1", "HarvesterPad2", ..., "AssemblerPad1", ...}
-- This is the single source of truth for which pads exist
local function generateAllPadIds() : {string}
    local padIds = {}
    for machineType, count in pairs(PlotConfig.PAD_COUNTS) do
        for i = 1, count do
            table.insert(padIds, machineType .. "Pad" .. i)
        end
    end
    return padIds
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Initializes all pads for a player in EMPTY state
-- Must be called by MatchManager before any other function for this player
function PadService.initPads(player : Player)
    assert(
        not playerPads[player.UserId],
        "PadService.initPads: player already initialized: " .. player.DisplayName
    )

    local pads = {}
    for _, padId in ipairs(generateAllPadIds()) do
        pads[padId] = {
            state       = PadState.EMPTY,
            machineType = nil,
        }
    end

    playerPads[player.UserId] = pads
end

-- Removes all pad data for a player
-- Called by MatchManager when a player leaves or the match ends
function PadService.removePlayer(player : Player)
    playerPads[player.UserId] = nil
end

-- Returns the current PadState value for a specific pad
-- Returns nil if player or pad not found
function PadService.getPadState(player : Player, padId : string) : string?
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return nil end
    return pads[padId].state
end

-- Returns the machineType currently occupying a pad
-- Returns nil if the pad is EMPTY or not found
function PadService.getPadMachineType(player : Player, padId : string) : string?
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return nil end
    return pads[padId].machineType
end

-- Returns true if all three conditions are met:
--   1. The pad exists for this player
--   2. The pad is currently EMPTY
--   3. The pad type matches the requested machineType
-- Called by MachineService before committing a purchase
function PadService.canOccupyPad(
    player      : Player,
    padId       : string,
    machineType : string
) : boolean
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then
        return false
    end

    -- Pad must be EMPTY
    if pads[padId].state ~= PadState.EMPTY then
        return false
    end

    -- Pad type must match machineType
    -- Prevents building an Assembler on a HarvesterPad
    local padType = getMachineTypeFromPadId(padId)
    if padType ~= machineType then
        return false
    end

    return true
end

-- Marks a pad as UNDER_CONSTRUCTION and records which machine is being built
-- Called by MachineService immediately after a purchase is committed
-- The pad stays in this state until MachineService calls setPadActive
function PadService.occupyPad(player : Player, padId : string, machineType : string)
    local pads = playerPads[player.UserId]
    assert(
        pads and pads[padId],
        "PadService.occupyPad: pad not found: " .. tostring(padId)
        .. " for " .. player.DisplayName
    )

    pads[padId].state       = PadState.UNDER_CONSTRUCTION
    pads[padId].machineType = machineType
end

-- Transitions a pad from UNDER_CONSTRUCTION to ACTIVE
-- Called by MachineService after the construction duration elapses
function PadService.setPadActive(player : Player, padId : string)
    local pads = playerPads[player.UserId]
    assert(
        pads and pads[padId],
        "PadService.setPadActive: pad not found: " .. tostring(padId)
        .. " for " .. player.DisplayName
    )

    pads[padId].state = PadState.ACTIVE
end

-- Releases a pad back to EMPTY and clears its machine record
-- Not used in MVP but available for a future sell or demolish mechanic
function PadService.releasePad(player : Player, padId : string)
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return end

    pads[padId].state       = PadState.EMPTY
    pads[padId].machineType = nil
end

-- Releases all pad data for a player in one call
-- Called by MatchManager at match end as part of cleanup
function PadService.releaseAllPads(player : Player)
    playerPads[player.UserId] = nil
end

-- Returns the full pad table for a player
-- Used by MachineSpawnService to sync visuals
-- Returns nil if player not initialized
function PadService.getPlayerPads(player : Player)
    return playerPads[player.UserId]
end

return PadService