-- MatchData.lua
-- Defines the shape of the current match's state
-- MatchManager owns a value of this type
-- Nobody else writes to it

export type MatchData = {
    state           : string,           -- must be a value from GameState.lua
    players         : {PlayerData},     -- all players currently in the match
    startTime       : number,           -- os.clock() value when match began
    winnerId        : number?,          -- userId of winner, nil until match ends
}