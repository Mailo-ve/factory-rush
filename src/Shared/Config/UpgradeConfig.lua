-- UpgradeConfig.lua
-- Owns: all upgrade branch definitions and their effects
-- Each machine type has exactly one upgrade decision: branch A or branch B
-- Choosing one permanently locks the other for the rest of the match

return {
    Harvester = {
        cost = 150,
        A = {
            name                = "Overclock",
            description         = "Each Harvester produces 50% more income",
            incomeMultiplier    = 1.5,
        },

        B = {
            name                = "Steady Output",
            description         = "Each upgraded Harvester produces a flat 16 income per tick",
            selfIncomeOverride  = 16,
        },
    },
    Assembler = {
        cost = 1500,
        A = {
            name                    = "Amplifier",
            description             = "Harvester multiplier increases to 1.8x",
            harvesterMultiplier     = 1.8,
        },
        B = {
            name                    = "Overcharge",
            description             = "Assembler income increases to 150 per tick",
            selfIncomeOverride      = 150,
        },
    },
    Fabricator = {
        cost = 10000,
        A = {
            name            = "Compound Engine",
            description     = "Compound rate increases to 18%",
            compoundRate    = 0.18,
        },
        B = {
            name            = "Early Ignition",
            description     = "Compound rate applies twice per tick",
            ticksPerCycle   = 2,
        },
    },
}