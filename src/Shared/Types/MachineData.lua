-- MachineData.lua
-- Defines the shape of a single machine instance owned by a player
-- This is not a class — it has no behavior
-- MachineService creates and manages values of this type

export type MachineData = {
    machineType     : string,   -- must match a key in MachineConfig
    copies          : number,   -- how many of this machine the player owns
    upgradeBranch   : string?,  -- "A", "B", or nil if not yet upgraded
                                -- the ? means this field is optional
}