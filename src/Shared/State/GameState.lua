-- GameState.lua
-- Owns: the canonical list of possible match states
-- MatchManager is the only module that writes to this
-- Any module may read it

return {
    WAITING     = "WAITING",       -- waiting for enough players
    COUNTDOWN   = "COUNTDOWN",     -- match about to start
    PLAYING     = "PLAYING",       -- match in progress
    ENDING      = "ENDING",        -- match over, showing results
}