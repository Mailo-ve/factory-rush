-- PadState.lua
-- Owns: the canonical list of possible pad states
-- PadManager is the only module that writes pad states
-- Any module may read them

return {
    EMPTY               = "EMPTY",              -- no machine built yet
    UNDER_CONSTRUCTION  = "UNDER_CONSTRUCTION", -- briefly after purchase,
                                                -- placeholder visible
    ACTIVE              = "ACTIVE",             -- machine built and producing
}