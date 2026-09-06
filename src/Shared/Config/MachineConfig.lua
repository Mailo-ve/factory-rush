-- MachineConfig.lua
-- Owns: all machine type definitions and base stats
-- Do not put upgrade values here, those live in UpgradeConfig

return {
    Harvester = {
        cost                = 50,
        baseIncome          = 25,   -- added to currentIncome per copy owned
        maxCopies           = 5,
        tier                = 1,
    },
    Assembler = {
        cost                = 1500,
        baseIncome          = 210,
        harvesterMultiplier = 1.4,  -- multiplies all of the player's Harvester income
        maxCopies           = 4,
        tier                = 2,
    },
    Fabricator = {
        cost                = 10000,
        baseIncome          = 0,    -- produces nothing directly
        compoundRate        = 0.12, -- adds this fraction of currentIncome per tick
        maxCopies           = 3,
        tier                = 3,
    },
}