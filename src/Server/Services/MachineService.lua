-- MachineService.lua
-- Owns: machine purchasing, per-copy upgrade purchasing, and servicing
-- CHANGED: recalculateIncome is now public and efficiency-aware, so
--          PadService's decay tick can trigger it directly.
--          purchaseUpgrade now validates per-pad, not per-type — each
--          physical copy needs its own upgrade purchase.

local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local ServerScriptService   = game:GetService("ServerScriptService")

local MachineConfig     = require(ReplicatedStorage.Shared.Config.MachineConfig)
local UpgradeConfig     = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local PlotConfig        = require(ReplicatedStorage.Shared.Config.PlotConfig)
local Machine           = require(ReplicatedStorage.Shared.Classes.Machine)

local function getEconomyService()
    return require(ServerScriptService.Server.Services.EconomyService)
end
local function getPadService()
    return require(ServerScriptService.Server.Services.PadService)
end
local function getMachineSpawnService()
    return require(ServerScriptService.Server.Services.MachineSpawnService)
end

local MachineService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Keyed by player.UserId
-- Each entry is a dictionary of machineType → Machine instance
local playerMachines = {}

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Handles construction timer and transitions pad to ACTIVE
local function runConstructionTimer(
    player      : Player,
    padId       : string,
    machineType : string
)
    task.delay(PlotConfig.CONSTRUCTION_DURATION, function()
        -- Guard: player may have left during construction
        if not playerMachines[player.UserId] then return end

        getPadService().setPadActive(player, padId)
        getMachineSpawnService().setMachineActive(player, padId, machineType)
        MachineService.recalculateIncome(player)
    end)
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

function MachineService.initPlayer(player : Player)
    assert(
        not playerMachines[player.UserId],
        "MachineService.initPlayer: already initialized: " .. player.DisplayName
    )
    playerMachines[player.UserId] = {}
end

function MachineService.removePlayer(player : Player)
    playerMachines[player.UserId] = nil
end

-- Recomputes total income from scratch and pushes it to EconomyService.
-- Public so PadService's decay tick can call it whenever efficiency
-- changes, not just after a purchase or upgrade.
-- Each machine type's contribution is scaled by that type's average
-- pad efficiency, so decayed or broken-down machines earn less.
function MachineService.recalculateIncome(player : Player)
    local machines = playerMachines[player.UserId]
    if not machines then return end

    local PadService = getPadService()

    local harvesterIncome = 0
    if machines.Harvester then
        local efficiency = PadService.getAverageEfficiency(player, "Harvester") / 100
        harvesterIncome = machines.Harvester:getSelfIncome() * efficiency
    end

    local harvesterMultiplier = 1.0
    if machines.Assembler then
        harvesterMultiplier = machines.Assembler:getHarvesterMultiplier()
    end

    local boostedHarvesterIncome = harvesterIncome * harvesterMultiplier

    local assemblerIncome = 0
    if machines.Assembler then
        local efficiency = PadService.getAverageEfficiency(player, "Assembler") / 100
        assemblerIncome = machines.Assembler:getSelfIncome() * efficiency
    end

    local baseIncome = boostedHarvesterIncome + assemblerIncome

    local compoundBonus = 0
    if machines.Fabricator then
        local efficiency = PadService.getAverageEfficiency(player, "Fabricator") / 100
        local compoundRate = machines.Fabricator:getCompoundRate() * efficiency
        compoundBonus = baseIncome * compoundRate
    end

    local totalIncome = baseIncome + compoundBonus
    getEconomyService().setCurrentIncome(player, math.floor(totalIncome))
end

function MachineService.purchaseMachine(
    player      : Player,
    machineType : string,
    padId       : string
) : (boolean, string?)

    local machineConfig = MachineConfig[machineType]
    if not machineConfig then
        return false, "unknown machineType: " .. tostring(machineType)
    end

    local machines      = playerMachines[player.UserId]
    assert(machines,
        "MachineService.purchaseMachine: player not initialized: "
        .. player.DisplayName)

    if not getPadService().canOccupyPad(player, padId, machineType) then
        return false, "pad unavailable or type mismatch: " .. padId
    end

    if not machines[machineType] then
        machines[machineType] = Machine.new(machineType)
    end

    local machine           = machines[machineType]
    local EconomyService    = getEconomyService()
    local cost               = machine:getCopyCost()

    if not EconomyService.canAfford(player, cost) then
        return false, "cannot afford " .. machineType .. " (costs " .. cost .. ")"
    end

    EconomyService.deductMoney(player, cost)
    machine:addCopy()

    getPadService().occupyPad(player, padId, machineType)
    getMachineSpawnService().spawnMachine(player, padId, machineType)

    runConstructionTimer(player, padId, machineType)

    return true, nil
end

-- Upgrades ONE specific pad's machine into the given branch.
-- The first upgrade purchase for a machine type locks that type into
-- the chosen branch; every copy after that must be upgraded
-- individually (and can only use the same branch).
function MachineService.purchaseUpgrade(
    player      : Player,
    machineType : string,
    branch      : string,
    padId       : string
) : (boolean, string?)

    if not MachineConfig[machineType] then
        return false, "unknown machineType: " .. tostring(machineType)
    end

    if branch ~= "A" and branch ~= "B" then
        return false, "invalid branch: " .. tostring(branch)
    end

    local machines = playerMachines[player.UserId]
    assert(machines,
        "MachineService.purchaseUpgrade: player not initialized: "
        .. player.DisplayName)

    local machine = machines[machineType]
    if not machine or machine.copies == 0 then
        return false, "player does not own any " .. machineType
    end

    local PadService = getPadService()

    if PadService.getPadMachineType(player, padId) ~= machineType then
        return false, "pad does not match machine type: " .. padId
    end

    if PadService.isPadUpgraded(player, padId) then
        return false, "this " .. machineType .. " is already upgraded"
    end

    if not machine:hasUpgradeableCopy() then
        return false, "every " .. machineType .. " you own is already upgraded"
    end

    local cost               = machine:getUpgradeCost()
    local EconomyService     = getEconomyService()

    if not EconomyService.canAfford(player, cost) then
        return false, "cannot afford upgrade for " .. machineType
    end

    -- Attempt the branch lock/count increment before spending money,
    -- so a rejected branch mismatch never costs the player anything
    if not machine:applyUpgrade(branch) then
        return false, machineType .. " is locked into the other branch"
    end

    EconomyService.deductMoney(player, cost)
    PadService.setPadUpgraded(player, padId)
    getMachineSpawnService().updateUpgraded(player, padId, machineType, branch)
    MachineService.recalculateIncome(player)

    return true, nil
end

-- Resets one pad's machine back to full efficiency. This is the
-- "hold E to service" action — free, instant, no purchase involved.
function MachineService.serviceMachine(
    player : Player,
    padId  : string
) : (boolean, string?)
    local ok = getPadService().serviceMachine(player, padId)
    if not ok then
        return false, "pad not found or not active: " .. tostring(padId)
    end

    MachineService.recalculateIncome(player)
    return true, nil
end

function MachineService.getPlayerMachines(player : Player)
    return playerMachines[player.UserId]
end

return MachineService