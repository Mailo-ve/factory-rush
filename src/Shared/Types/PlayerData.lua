-- PlayerData.lua
-- Defines the shape of all state tracked per player during a match
-- EconomyService owns money and currentIncome
-- MachineService owns machines
-- DataService owns savedWins
-- This type is the shared language all three use to talk about a player

export type PlayerData = {
    userId          : number,           -- Roblox unique player ID
    displayName     : string,           -- shown on leaderboard
    money           : number,           -- current authoritative balance
    currentIncome   : number,           -- income added per tick, recalculated on purchase
    machines        : {MachineData},    -- array of all machines this player owns
    upgradeChoices  : {[string]: string}, -- map of machineType → chosen branch
                                          -- e.g. { Harvester = "A", Assembler = "B" }
    savedWins       : number,           -- persisted across matches via DataStore
}