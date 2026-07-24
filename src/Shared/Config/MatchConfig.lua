-- MatchConfig.lua
-- Owns: all match-level constants
-- Do not put machine or upgrade values here

return {
    STARTING_MONEY = 100,
    WIN_CONDITION           = 1000000,  -- first to this amount wins
    MATCH_DURATION          = 600,      -- hard cap in seconds
    COUNTDOWN_DURATION      = 10,       -- seconds before match starts
    MIN_PLAYERS             = 2,        -- match won't start below this
    MAX_PLAYERS             = 8,
    ECONOMY_TICK_RATE       = 1,        -- seconds between income ticks
    LEADERBOARD_TICK_RATE   = 1,        -- seconds between leaderboard updates
    ACCELERATOR_START       = 480,      -- seconds at which economy accelerates
    ACCELERATOR_MULTIPLIER  = 2.0,      -- income multiplier after accelerator
}