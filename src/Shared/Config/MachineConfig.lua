-- MachineConfig.lua
-- Owns: all machine type definitions and base stats
-- Do not put upgrade values here, those live in UpgradeConfig

return {
    Harvester = {
        cost                = 50,
        baseIncome          = 10,   -- added to currentIncome per copy owned
        maxCopies           = 5,
        tier                = 1,
    },
    Assembler = {
        cost                = 500,
        baseIncome          = 75,
        harvesterMultiplier = 1.4,  -- multiplies all of the player's Harvester income
        maxCopies           = 4,
        tier                = 2,
    },
    Fabricator = {
        cost                = 5000,
        baseIncome          = 0,    -- produces nothing directly
        compoundRate        = 0.10, -- adds this fraction of currentIncome per tick
        maxCopies           = 3,
        tier                = 3,
    },
}