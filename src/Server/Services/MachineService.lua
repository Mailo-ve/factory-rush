-- MachineService.lua
-- Owns: machine purchasing and upgrade logic
-- CHANGED: purchaseMachine now takes padId
--          calls PadService and MachineSpawnService
--          handles construction duration timer

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

local function recalculateIncome(player : Player)
    local machines = playerMachines[player.UserId]
    if not machines then return end

    local harvesterIncome = 0
    if machines.Harvester then
        harvesterIncome = machines.Harvester:getSelfIncome()
    end

    local harvesterMultiplier = 1.0
    if machines.Assembler then
        harvesterMultiplier = machines.Assembler:getHarvesterMultiplier()
    end

    local boostedHarvesterIncome = harvesterIncome * harvesterMultiplier

    local assemblerIncome = 0
    if machines.Assembler then
        assemblerIncome = machines.Assembler:getSelfIncome()
    end

    local baseIncome = boostedHarvesterIncome + assemblerIncome

    local compoundBonus = 0
    if machines.Fabricator then
        local compoundRate = machines.Fabricator:getCompoundRate()
        compoundBonus = baseIncome * compoundRate
    end

    local totalIncome = baseIncome + compoundBonus
    getEconomyService().setCurrentIncome(player, math.floor(totalIncome))
end

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
        recalculateIncome(player)
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

-- CHANGED: now takes padId as third argument
-- Validates pad type matches machineType before purchasing
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

    -- Validate pad is available for this machine type
    if not getPadService().canOccupyPad(player, padId, machineType) then
        return false, "pad unavailable or type mismatch: " .. padId
    end

    if not machines[machineType] then
        machines[machineType] = Machine.new(machineType)
    end

    local machine           = machines[machineType]
    local EconomyService    = getEconomyService()
    local cost              = machine:getCopyCost()

    if not EconomyService.canAfford(player, cost) then
        return false, "cannot afford " .. machineType .. " (costs " .. cost .. ")"
    end

    -- All checks passed — commit purchase
    EconomyService.deductMoney(player, cost)
    machine:addCopy()

    -- Mark pad and spawn visual immediately
    getPadService().occupyPad(player, padId, machineType)
    getMachineSpawnService().spawnMachine(player, padId, machineType)

    -- Construction timer — recalculates income after ACTIVE
    runConstructionTimer(player, padId, machineType)

    return true, nil
end

-- CHANGED: now takes padId as third argument
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

    if machine:isUpgraded() then
        return false, machineType .. " already upgraded (branch "
            .. machine.upgradeBranch .. ")"
    end

    local upgradeConfig     = UpgradeConfig[machineType]
    local cost              = upgradeConfig.cost
    local EconomyService    = getEconomyService()

    if not EconomyService.canAfford(player, cost) then
        return false, "cannot afford upgrade for " .. machineType
    end

    -- All checks passed — commit upgrade
    EconomyService.deductMoney(player, cost)
    machine:applyUpgrade(branch)
    getMachineSpawnService().updateUpgraded(player, padId, machineType, branch)
    recalculateIncome(player)

    return true, nil
end

function MachineService.getPlayerMachines(player : Player)
    return playerMachines[player.UserId]
end

return MachineService