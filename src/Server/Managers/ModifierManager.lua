-- ModifierManager.lua
-- Owns: picking and tracking the current match's modifier
-- Exposes: rollModifier, clearModifier, getCurrentModifier,
--          getIncomeMultiplier, getMaintenanceMultiplier,
--          getResourceMultiplier, getConstructionMultiplier,
--          getStartingMoney, checkMarketBoss
-- Does not: apply any effect itself — other services query the
--           relevant getter and apply it to their own calculations
-- A modifier can carry multiple effects at once (e.g. Heat Wave
-- affects both construction speed and breakdown risk)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModifierConfig     = require(ReplicatedStorage.Shared.Config.ModifierConfig)

local ModifierManager = {}

-- The currently active modifier definition, or nil between matches
local currentModifier   = nil

-- Whether this match's Market Boss bonus has already been claimed
-- Irrelevant when Market Boss isn't the active modifier
local marketBossClaimed = false

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

-- Returns the first effect of the given type on the current modifier,
-- or nil if there's no active modifier or it doesn't have one
local function findEffect(effectType : string)
    if not currentModifier then return nil end
    for _, effect in ipairs(currentModifier.effects) do
        if effect.type == effectType then
            return effect
        end
    end
    return nil
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Picks a random modifier for the upcoming match
-- Called by MatchManager right before Countdown begins
function ModifierManager.rollModifier()
    currentModifier   = ModifierConfig[math.random(1, #ModifierConfig)]
    marketBossClaimed = false
    return currentModifier
end

-- Called by MatchManager when a match ends
function ModifierManager.clearModifier()
    currentModifier   = nil
    marketBossClaimed = false
end

function ModifierManager.getCurrentModifier()
    return currentModifier
end

-- Returns the income multiplier for one machine type — 1.0 (no-op)
-- unless the current modifier specifically targets that type
-- Kept separate from findEffect since it needs a second match key
function ModifierManager.getIncomeMultiplier(machineType : string) : number
    if not currentModifier then return 1.0 end
    for _, effect in ipairs(currentModifier.effects) do
        if effect.type == "incomeMultiplier" and effect.machineType == machineType then
            return effect.value
        end
    end
    return 1.0
end

-- Applies to decay rate, decay onset chance, and breakdown chance alike
function ModifierManager.getMaintenanceMultiplier() : number
    local effect = findEffect("maintenanceMultiplier")
    return effect and effect.value or 1.0
end

function ModifierManager.getResourceMultiplier() : number
    local effect = findEffect("resourceMultiplier")
    return effect and effect.value or 1.0
end

function ModifierManager.getConstructionMultiplier() : number
    local effect = findEffect("constructionMultiplier")
    return effect and effect.value or 1.0
end

-- Returns the overridden starting money amount, or nil if the current
-- modifier doesn't touch starting money (caller should fall back to
-- MatchConfig.STARTING_MONEY in that case)
function ModifierManager.getStartingMoney() : number?
    local effect = findEffect("startingMoney")
    return effect and effect.value or nil
end

-- Checks whether this player just crossed the Market Boss threshold
-- for the first time this match. Returns the reward amount if so
-- (and marks it claimed so nobody else can also trigger it), or nil
-- if Market Boss isn't active, already claimed, or not yet reached
function ModifierManager.checkMarketBoss(player : Player, money : number) : number?
    if marketBossClaimed then return nil end

    local effect = findEffect("marketBoss")
    if not effect then return nil end

    if money >= effect.threshold then
        marketBossClaimed = true
        return effect.reward
    end

    return nil
end

return ModifierManager