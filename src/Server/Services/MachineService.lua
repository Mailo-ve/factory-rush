-- MachineService.lua
-- Owns: machine instances per player and upgrade state
-- Exposes: initPlayer, removePlayer, purchaseMachine,
--          purchaseUpgrade, getPlayerMachines
-- Does not: touch money directly (delegates to EconomyService),
--           handle plot layout, persist data, fire RemoteEvents

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineConfig     = require(ReplicatedStorage.Shared.Config.MachineConfig)
local UpgradeConfig     = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local Machine           = require(ReplicatedStorage.Shared.Classes.Machine)

-- EconomyService is required inside functions, not at the top
-- This prevents a load-order issue if both services load simultaneously
-- It is safe because by the time any function is called, all services are loaded
local function getEconomyService()
    return require(game:GetService("ServerScriptService").Server.Services.EconomyService)
end

local MachineService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Keyed by player.UserId
-- Each entry is a dictionary of machineType → Machine instance
-- e.g. { Harvester = <Machine>, Assembler = <Machine> }
-- A key only exists once the player has bought at least one copy
local playerMachines = {}

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Recalculates a player's total currentIncome from all owned machines
-- and pushes the result to EconomyService
-- Must be called after every purchase or upgrade
local function recalculateIncome(player : Player)
    local machines = playerMachines[player.UserId]
    if not machines then return end

    -- ── Step 1: Base Harvester income ──────────────────────────────────────
    -- getSelfIncome() accounts for Overclock (Branch A) automatically
    local harvesterIncome = 0
    if machines.Harvester then
        harvesterIncome = machines.Harvester:getSelfIncome()
    end

    -- ── Step 2: Apply Assembler's Harvester multiplier ─────────────────────
    -- getHarvesterMultiplier() returns 1.0 if no Assembler exists
    -- so this multiplication is always safe
    local harvesterMultiplier = 1.0
    if machines.Assembler then
        harvesterMultiplier = machines.Assembler:getHarvesterMultiplier()
    end
    local boostedHarvesterIncome = harvesterIncome * harvesterMultiplier

    -- ── Step 3: Add Assembler's own income ─────────────────────────────────
    -- getSelfIncome() accounts for Overcharge (Branch B) automatically
    local assemblerIncome = 0
    if machines.Assembler then
        assemblerIncome = machines.Assembler:getSelfIncome()
    end

    -- ── Step 4: currentIncome before compounding ───────────────────────────
    local baseIncome = boostedHarvesterIncome + assemblerIncome

    -- ── Step 5: Apply Fabricator compounding ───────────────────────────────
    -- getCompoundRate() returns effective rate including Branch upgrades
    -- Each Fabricator copy adds its own compoundRate fraction of baseIncome
    -- Result: small base = small bonus, large base = large bonus
    local compoundBonus = 0
    if machines.Fabricator then
        local compoundRate = machines.Fabricator:getCompoundRate()
        compoundBonus = baseIncome * compoundRate
    end

    local totalIncome = baseIncome + compoundBonus

    -- math.floor so currentIncome is always a whole number
    -- avoids floating point drift accumulating over hundreds of ticks
    getEconomyService().setCurrentIncome(player, math.floor(totalIncome))
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Registers a player into the machine system with no machines owned
-- Must be called by MatchManager before any other function for this player
function MachineService.initPlayer(player : Player)
    assert(
        not playerMachines[player.UserId],
        "MachineService.initPlayer: player already initialized: " .. player.DisplayName
    )
    playerMachines[player.UserId] = {}
end

-- Removes a player from the machine system
-- Called by MatchManager when a player leaves or the match ends
function MachineService.removePlayer(player : Player)
    playerMachines[player.UserId] = nil
end

-- Attempts to purchase one copy of a machine for the player
-- Validates: machineType exists, player under maxCopies, player can afford it
-- On success: deducts money, registers copy, recalculates income
-- Returns true on success, false with a reason string on failure
function MachineService.purchaseMachine(player : Player, machineType : string) : (boolean, string?)
    -- Validate machineType exists in config
    local machineConfig = MachineConfig[machineType]
    if not machineConfig then
        return false, "unknown machineType: " .. tostring(machineType)
    end

    local machines = playerMachines[player.UserId]
    assert(machines, "MachineService.purchaseMachine: player not initialized: " .. player.DisplayName)

    -- Get or create the Machine instance for this type
    if not machines[machineType] then
        machines[machineType] = Machine.new(machineType)
    end

    local machine       = machines[machineType]
    local EconomyService = getEconomyService()

    -- Validate: not at max copies
    if machine.copies >= machineConfig.maxCopies then
        return false, machineType .. " is already at max copies (" .. machineConfig.maxCopies .. ")"
    end

    -- Get effective cost (Bulk Order upgrade may reduce this)
    local cost = machine:getCopyCost()

    -- Validate: player can afford it
    if not EconomyService.canAfford(player, cost) then
        return false, "cannot afford " .. machineType .. " (costs " .. cost .. ")"
    end

    -- All checks passed — commit the purchase
    EconomyService.deductMoney(player, cost)
    machine:addCopy()
    recalculateIncome(player)

    return true, nil
end

-- Attempts to purchase an upgrade branch for a machine the player owns
-- Validates: machineType exists, player owns at least one copy,
--            not already upgraded, branch is valid, player can afford it
-- On success: deducts money, locks branch, recalculates income
-- Returns true on success, false with a reason string on failure
function MachineService.purchaseUpgrade(player : Player, machineType : string, branch : string) : (boolean, string?)
    -- Validate machineType exists in config
    if not MachineConfig[machineType] then
        return false, "unknown machineType: " .. tostring(machineType)
    end

    -- Validate branch value
    if branch ~= "A" and branch ~= "B" then
        return false, "invalid branch: " .. tostring(branch) .. " (must be A or B)"
    end

    local machines = playerMachines[player.UserId]
    assert(machines, "MachineService.purchaseUpgrade: player not initialized: " .. player.DisplayName)

    local machine = machines[machineType]

    -- Validate: player owns at least one copy of this machine
    if not machine or machine.copies == 0 then
        return false, "player does not own any " .. machineType
    end

    -- Validate: not already upgraded
    if machine:isUpgraded() then
        return false, machineType .. " is already upgraded (branch " .. machine.upgradeBranch .. ")"
    end

    local upgradeConfig  = UpgradeConfig[machineType]
    local cost           = upgradeConfig.cost
    local EconomyService = getEconomyService()

    -- Validate: player can afford it
    if not EconomyService.canAfford(player, cost) then
        return false, "cannot afford upgrade for " .. machineType .. " (costs " .. cost .. ")"
    end

    -- All checks passed — commit the upgrade
    EconomyService.deductMoney(player, cost)
    machine:applyUpgrade(branch)
    recalculateIncome(player)

    return true, nil
end

-- Returns the machine table for a player
-- EconomyService reads this during tick calculation
-- Returns nil if player is not initialized
function MachineService.getPlayerMachines(player : Player)
    return playerMachines[player.UserId]
end

return MachineService