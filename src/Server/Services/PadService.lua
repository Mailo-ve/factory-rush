-- PadService.lua
-- Owns: pad states per player, including per-pad efficiency and upgrade status
-- Tracks what is built on each pad and each pad's lifecycle state
-- Exposes: initPads, removePlayer, getPadState, getPadMachineType,
--          canOccupyPad, occupyPad, setPadActive,
--          releasePad, releaseAllPads, getPlayerPads,
--          getEfficiency, getAverageEfficiency, serviceMachine,
--          isPadUpgraded, setPadUpgraded,
--          startDecayTick, stopDecayTick
-- Does not: spawn visuals, calculate income, handle purchases,
--           know anything about the physical world
-- CHANGED: steady decay is no longer automatic — a healthy machine now
--          rolls a chance each tick to START decaying (isDecaying flag),
--          same as it already rolled a chance to fully break down.
--          Once decaying, it loses efficiency every tick as before,
--          until serviced (which also clears isDecaying).

local Players           = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlotConfig        = require(ReplicatedStorage.Shared.Config.PlotConfig)
local MatchConfig        = require(ReplicatedStorage.Shared.Config.MatchConfig)
local MaintenanceConfig  = require(ReplicatedStorage.Shared.Config.MaintenanceConfig)
local PadState           = require(ReplicatedStorage.Shared.State.PadState)

local PadService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Keyed by player.UserId
-- Each entry is a dictionary of padId → pad record:
-- {
--     state       : string,   PadState value
--     machineType : string?,  nil when EMPTY
--     efficiency  : number,   0-100, only meaningful once ACTIVE
--     upgraded    : boolean,  has THIS specific pad been individually upgraded
--     isDecaying  : boolean,  has THIS pad started losing efficiency yet
-- }
local playerPads = {}

local decayThread = nil    -- running task thread, nil when stopped

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

local function getMachineTypeFromPadId(padId : string) : string?
    return padId:match(PlotConfig.PAD_NAME_PATTERN)
end

local function generateAllPadIds() : {string}
    local padIds = {}
    for machineType, count in pairs(PlotConfig.PAD_COUNTS) do
        for i = 1, count do
            table.insert(padIds, machineType .. "Pad" .. i)
        end
    end
    return padIds
end

-- Processes one tick for every ACTIVE pad for every player:
--   1. Roll for a full breakdown — overrides everything if it hits
--   2. If not already decaying, roll for decay onset
--   3. If decaying, lose one tick's worth of efficiency, clamped at the floor
-- A pad already at/below breakdown efficiency is left alone — only
-- servicing brings it back up, it does not recover on its own.
local function decayAllPads(maintenanceMultiplier : number)
    for _, pads in pairs(playerPads) do
        for _, record in pairs(pads) do
            if record.state == PadState.ACTIVE
                and record.efficiency > MaintenanceConfig.BREAKDOWN_EFFICIENCY
            then
                if math.random() < MaintenanceConfig.BREAKDOWN_CHANCE_PER_TICK * maintenanceMultiplier then
                    record.efficiency = MaintenanceConfig.BREAKDOWN_EFFICIENCY
                    record.isDecaying = false
                else
                    if not record.isDecaying
                        and math.random() < MaintenanceConfig.DECAY_ONSET_CHANCE_PER_TICK * maintenanceMultiplier
                    then
                        record.isDecaying = true
                    end

                    if record.isDecaying
                        and record.efficiency > MaintenanceConfig.EFFICIENCY_FLOOR
                    then
                        record.efficiency = math.max(
                            MaintenanceConfig.EFFICIENCY_FLOOR,
                            record.efficiency - (MaintenanceConfig.DECAY_RATE * maintenanceMultiplier)
                        )
                    end
                end
            end
        end
    end
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

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
            efficiency  = 0,
            upgraded    = false,
            isDecaying  = false,
        }
    end

    playerPads[player.UserId] = pads
end

function PadService.removePlayer(player : Player)
    playerPads[player.UserId] = nil
end

function PadService.getPadState(player : Player, padId : string) : string?
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return nil end
    return pads[padId].state
end

function PadService.getPadMachineType(player : Player, padId : string) : string?
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return nil end
    return pads[padId].machineType
end

function PadService.canOccupyPad(
    player      : Player,
    padId       : string,
    machineType : string
) : boolean
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then
        return false
    end

    if pads[padId].state ~= PadState.EMPTY then
        return false
    end

    local padType = getMachineTypeFromPadId(padId)
    if padType ~= machineType then
        return false
    end

    return true
end

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
-- Also (re)sets efficiency to full and clears any prior upgrade/decay
-- flags — this is a freshly built machine
function PadService.setPadActive(player : Player, padId : string)
    local pads = playerPads[player.UserId]
    assert(
        pads and pads[padId],
        "PadService.setPadActive: pad not found: " .. tostring(padId)
        .. " for " .. player.DisplayName
    )

    pads[padId].state       = PadState.ACTIVE
    pads[padId].efficiency  = MaintenanceConfig.STARTING_EFFICIENCY
    pads[padId].upgraded    = false
    pads[padId].isDecaying  = false
end

function PadService.releasePad(player : Player, padId : string)
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return end

    pads[padId].state       = PadState.EMPTY
    pads[padId].machineType = nil
    pads[padId].efficiency  = 0
    pads[padId].upgraded    = false
    pads[padId].isDecaying  = false
end

function PadService.releaseAllPads(player : Player)
    playerPads[player.UserId] = nil
end

function PadService.getPlayerPads(player : Player)
    return playerPads[player.UserId]
end

-- Returns a specific pad's current efficiency, or nil if not found/not active
function PadService.getEfficiency(player : Player, padId : string) : number?
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return nil end
    return pads[padId].efficiency
end

-- Average efficiency across all of a player's ACTIVE pads of one type.
-- Returns 100 (a no-op multiplier) if they have none active yet.
function PadService.getAverageEfficiency(player : Player, machineType : string) : number
    local pads = playerPads[player.UserId]
    if not pads then return 100 end

    local total = 0
    local count = 0

    for _, record in pairs(pads) do
        if record.machineType == machineType and record.state == PadState.ACTIVE then
            total += record.efficiency
            count += 1
        end
    end

    if count == 0 then
        return 100
    end

    return total / count
end

function PadService.isPadUpgraded(player : Player, padId : string) : boolean
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return false end
    return pads[padId].upgraded
end

function PadService.setPadUpgraded(player : Player, padId : string)
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return end
    pads[padId].upgraded = true
end

-- Resets one pad's efficiency to full and clears its decay state.
-- Returns false if the pad doesn't exist or isn't currently ACTIVE.
function PadService.serviceMachine(player : Player, padId : string) : boolean
    local pads = playerPads[player.UserId]
    if not pads or not pads[padId] then return false end
    if pads[padId].state ~= PadState.ACTIVE then return false end

    pads[padId].efficiency  = MaintenanceConfig.STARTING_EFFICIENCY
    pads[padId].isDecaying  = false
    return true
end

-- Starts the decay tick. After each pass, tells MachineService to
-- recompute income for every player with at least one pad on record,
-- since their efficiency (and therefore income) may have just changed.
function PadService.startDecayTick()
    if decayThread then
        warn("PadService.startDecayTick: tick already running, ignoring")
        return
    end

    local MachineService      = require(ServerScriptService.Server.Services.MachineService)
    local MachineSpawnService = require(ServerScriptService.Server.Services.MachineSpawnService)
    local ModifierManager      = require(ServerScriptService.Server.Managers.ModifierManager)

    decayThread = task.spawn(function()
        while true do
            task.wait(MatchConfig.ECONOMY_TICK_RATE)
            decayAllPads(ModifierManager.getMaintenanceMultiplier())

            for userId, pads in pairs(playerPads) do
                local player = Players:GetPlayerByUserId(userId)
                if player then
                    for padId, record in pairs(pads) do
                        if record.state == PadState.ACTIVE then
                            MachineSpawnService.updateEfficiencyDisplay(
                                player, padId, record.efficiency
                            )
                        end
                    end
                    MachineService.recalculateIncome(player)
                end
            end
        end
    end)
end

function PadService.stopDecayTick()
    if decayThread then
        task.cancel(decayThread)
        decayThread = nil
    end
end

return PadService