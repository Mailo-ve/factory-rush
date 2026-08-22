-- ModifierConfig.lua
-- Owns: the pool of possible per-match modifiers
-- One is rolled at random each match and announced during Countdown
-- Each modifier can carry multiple effects (e.g. Heat Wave affects
-- both construction speed and breakdown risk at once)
-- To add a new modifier, add an entry here — no other code changes
-- needed unless it introduces a genuinely new effect "type"

return {
    {
        id          = "StartingCapital",
        name        = "Starting Capital",
        description = "Everyone starts with $500 instead of $100",
        effects     = {
            { type = "startingMoney", value = 500 },
        },
    },
    {
        id          = "PoorStart",
        name        = "Poor Start",
        description = "Everyone starts with $25",
        effects     = {
            { type = "startingMoney", value = 25 },
        },
    },
    {
        id          = "MarketBoss",
        name        = "Market Boss",
        description = "First player to reach $5,000 gets an extra $5,000",
        effects     = {
            { type = "marketBoss", threshold = 5000, reward = 5000 },
        },
    },
    {
        id          = "HeatWave",
        name        = "Heat Wave",
        description = "Construction is twice as fast, but breakdown risk is doubled",
        effects     = {
            { type = "constructionMultiplier", value = 0.5 },
            { type = "maintenanceMultiplier",  value = 2.0 },
        },
    },
    {
        id          = "GoldRush",
        name        = "Gold Rush",
        description = "Resource cache payouts doubled",
        effects     = {
            { type = "resourceMultiplier", value = 2.0 },
        },
    },
    {
        id          = "FragileMachines",
        name        = "Fragile Machines",
        description = "Decay and breakdown chance doubled",
        effects     = {
            { type = "maintenanceMultiplier", value = 2.0 },
        },
    },
}