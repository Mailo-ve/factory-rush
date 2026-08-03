-- MachineData.lua
-- Defines the shape of a single machine instance owned by a player
-- This is not a class — it has no behavior
-- MachineService creates and manages values of this type

-- CHANGED: added padId and state fields
-- padId tracks which physical pad this machine occupies
-- state tracks the machine's current lifecycle stage

export type MachineData = {
    machineType     : string,   -- must match a key in MachineConfig
    padId           : string,   -- must match a pad name in PlotTemplate
                                -- e.g. "HarvesterPad1"
    copies          : number,   -- how many of this machine the player owns
    upgradeBranch   : string?,  -- "A", "B", or nil if not yet upgraded
    state           : string,   -- must be a value from PadState.lua
                                -- "EMPTY", "UNDER_CONSTRUCTION", "ACTIVE"
}