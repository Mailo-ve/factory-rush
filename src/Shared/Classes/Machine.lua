-- Machine.lua
-- Represents a single machine type owned by a player
-- Owns: income calculation for one machine type, and how many of its
--       copies have been individually upgraded
-- Does not: touch money directly, communicate with any service, or
--           know WHICH physical pad each copy corresponds to (PadService owns that)

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MachineConfig      = require(ReplicatedStorage.Shared.Config.MachineConfig)
local UpgradeConfig      = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

local Machine = {}
Machine.__index = Machine

function Machine.new(machineType : string)
    assert(MachineConfig[machineType], "Machine.new: unknown machineType: " .. machineType)

    local self = setmetatable({}, Machine)
    self.machineType     = machineType
    self.copies          = 0
    self.upgradeBranch   = nil   -- nil until the FIRST upgrade purchase locks it in
    self.upgradedCopies  = 0     -- how many owned copies have actually been upgraded
    return self
end

function Machine:addCopy() : boolean
    local config = MachineConfig[self.machineType]
    if self.copies >= config.maxCopies then
        return false
    end
    self.copies = self.copies + 1
    return true
end

-- Upgrades ONE additional copy into the given branch. The first call
-- locks the branch for this type; every later call must match it.
-- Fails if every owned copy is already upgraded, or if requesting
-- the branch that's already locked out.
function Machine:applyUpgrade(branch : string) : boolean
    if branch ~= "A" and branch ~= "B" then
        return false
    end
    if self.upgradeBranch ~= nil and self.upgradeBranch ~= branch then
        return false    -- locked into the other branch already
    end
    if self.upgradedCopies >= self.copies then
        return false    -- every owned copy is already upgraded
    end

    self.upgradeBranch  = branch
    self.upgradedCopies = self.upgradedCopies + 1
    return true
end

-- True once a branch has been chosen, regardless of how many
-- individual copies have actually been upgraded yet
function Machine:isUpgraded() : boolean
    return self.upgradeBranch ~= nil
end

function Machine:getUpgradedCount() : number
    return self.upgradedCopies
end

-- True if there's at least one owned copy still eligible to upgrade
function Machine:hasUpgradeableCopy() : boolean
    return self.upgradedCopies < self.copies
end

-- Flat cost to buy one more copy of this machine
function Machine:getCopyCost() : number
    return MachineConfig[self.machineType].cost
end

-- Flat cost to upgrade one more copy into the locked-in branch
function Machine:getUpgradeCost() : number
    return UpgradeConfig[self.machineType].cost
end

-- Income this machine contributes per tick. Non-upgraded copies earn
-- the base rate; upgraded copies earn whatever the locked branch grants.
-- Does NOT account for cross-machine effects (Assembler multiplying Harvesters).
function Machine:getSelfIncome() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]

    if config.baseIncome == 0 then
        return 0
    end

    local plainCopies = self.copies - self.upgradedCopies
    local income = config.baseIncome * plainCopies

    if self.upgradedCopies > 0 then
        if self.upgradeBranch == "A" and upgradeConfig.A.incomeMultiplier then
            income += config.baseIncome * upgradeConfig.A.incomeMultiplier * self.upgradedCopies
        elseif self.upgradeBranch == "B" and upgradeConfig.B.selfIncomeOverride then
            income += upgradeConfig.B.selfIncomeOverride * self.upgradedCopies
        else
            income += config.baseIncome * self.upgradedCopies
        end
    end

    return income
end

-- Compound rate this machine adds per tick (Fabricator only)
function Machine:getCompoundRate() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]

    if not config.compoundRate then
        return 0
    end

    local plainCopies = self.copies - self.upgradedCopies
    local rate = config.compoundRate * plainCopies

    if self.upgradedCopies > 0 then
        if self.upgradeBranch == "A" and upgradeConfig.A.compoundRate then
            rate += upgradeConfig.A.compoundRate * self.upgradedCopies
        elseif self.upgradeBranch == "B" and upgradeConfig.B.ticksPerCycle then
            rate += config.compoundRate * upgradeConfig.B.ticksPerCycle * self.upgradedCopies
        else
            rate += config.compoundRate * self.upgradedCopies
        end
    end

    return rate
end

-- Harvester multiplier this machine applies (Assembler only). Not
-- scaled by copies — matches the original design, where this was
-- always one flat multiplier rather than a per-copy stacking effect.
function Machine:getHarvesterMultiplier() : number
    local config        = MachineConfig[self.machineType]
    local upgradeConfig = UpgradeConfig[self.machineType]

    if not config.harvesterMultiplier then
        return 1.0
    end

    if self.upgradedCopies > 0
        and self.upgradeBranch == "A"
        and upgradeConfig.A.harvesterMultiplier
    then
        return upgradeConfig.A.harvesterMultiplier
    end

    return config.harvesterMultiplier
end

return Machine