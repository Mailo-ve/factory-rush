-- Machine.lua
-- Represents a single machine type owned by a player
-- Owns: income calculation for one machine type
-- Does not: touch money directly, communicate with any service,
--           or know anything about other machine types

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MachineConfig      = require(ReplicatedStorage.Shared.Config.MachineConfig)
local UpgradeConfig      = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

local Machine = {}
Machine.__index = Machine

-- Constructor
-- machineType: string key matching a key in MachineConfig e.g. "Harvester"
function Machine.new(machineType : string)
    assert(MachineConfig[machineType], "Machine.new: unknown machineType: " .. machineType)

    local self = setmetatable({}, Machine)
    self.machineType    = machineType
    self.copies         = 0
    self.upgradeBranch  = nil   -- nil until player makes upgrade choice
    return self
end

-- Adds one copy of this machine
-- Returns false if already at max copies, true on success
function Machine:addCopy() : boolean
    local config = MachineConfig[self.machineType]
    if self.copies >= config.maxCopies then
        return false
    end
    self.copies = self.copies + 1
    return true
end

-- Locks in an upgrade branch for this machine
-- branch: "A" or "B"
-- Returns false if already upgraded or invalid branch
function Machine:applyUpgrade(branch : string) : boolean
    if self.upgradeBranch ~= nil then
        return false    -- already upgraded, locked
    end
    if branch ~= "A" and branch ~= "B" then
        return false    -- invalid branch
    end
    self.upgradeBranch = branch
    return true
end

-- Returns true if this machine has been upgraded
function Machine:isUpgraded() : boolean
    return self.upgradeBranch ~= nil
end

-- Returns the effective cost to buy one more copy
-- Accounts for Bulk Order upgrade (Harvester branch B)
function Machine:getCopyCost() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]
    local baseCost      = config.cost

    if self.upgradeBranch == "B" and upgradeConfig.B.costMultiplier then
        return math.floor(baseCost * upgradeConfig.B.costMultiplier)
    end

    return baseCost
end

-- Returns the income this machine contributes per tick
-- Does NOT account for cross-machine effects (Assembler multiplying Harvesters)
-- That cross-machine calculation lives in EconomyService
function Machine:getSelfIncome() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]

    -- Fabricator produces no direct income
    if config.baseIncome == 0 then
        return 0
    end

    local baseTotal = config.baseIncome * self.copies

    -- Overclock upgrade: Harvester branch A
    if self.upgradeBranch == "A" and upgradeConfig.A.incomeMultiplier then
        return baseTotal * upgradeConfig.A.incomeMultiplier
    end

    -- Overcharge upgrade: Assembler branch B overrides per-copy income
    if self.upgradeBranch == "B" and upgradeConfig.B.selfIncomeOverride then
        return upgradeConfig.B.selfIncomeOverride * self.copies
    end

    return baseTotal
end

-- Returns the compound rate this machine adds per tick
-- Only relevant for Fabricator
function Machine:getCompoundRate() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]

    if not config.compoundRate then
        return 0
    end

    -- Branch A: Compound Engine — higher rate
    if self.upgradeBranch == "A" and upgradeConfig.A.compoundRate then
        return upgradeConfig.A.compoundRate * self.copies
    end

    -- Branch B: Early Ignition — same rate but applied twice per tick
    -- multiply by ticksPerCycle to get effective total rate
    if self.upgradeBranch == "B" and upgradeConfig.B.ticksPerCycle then
        return config.compoundRate * self.copies * upgradeConfig.B.ticksPerCycle
    end

    return config.compoundRate * self.copies
end

-- Returns the Harvester multiplier this machine applies
-- Only relevant for Assembler
function Machine:getHarvesterMultiplier() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]

    if not config.harvesterMultiplier then
        return 1.0  -- neutral multiplier for non-Assembler machines
    end

    -- Amplifier upgrade: Assembler branch A increases multiplier
    if self.upgradeBranch == "A" and upgradeConfig.A.harvesterMultiplier then
        return upgradeConfig.A.harvesterMultiplier
    end

    return config.harvesterMultiplier
end

return Machine