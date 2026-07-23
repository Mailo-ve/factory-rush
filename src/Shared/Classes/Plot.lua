-- Plot.lua
-- Represents one player's factory plot
-- Owns: which player is assigned here, and the machines on this plot
-- Does not: calculate income, handle purchases, or touch money

local Plot = {}
Plot.__index = Plot

-- Constructor
-- plotId: unique identifier matching a plot object in workspace
-- e.g. "Plot1", "Plot2"
function Plot.new(plotId : string)
    local self = setmetatable({}, Plot)
    self.plotId     = plotId
    self.ownerId    = nil   -- userId of assigned player, nil if unassigned
    return self
end

-- Assigns this plot to a player
-- Returns false if already assigned
function Plot:assign(userId : number) : boolean
    if self.ownerId ~= nil then
        return false
    end
    self.ownerId = userId
    return true
end

-- Releases this plot back to unassigned state
function Plot:release()
    self.ownerId = nil
end

-- Returns true if this plot has an owner
function Plot:isOccupied() : boolean
    return self.ownerId ~= nil
end

-- Returns the userId of the current owner, or nil
function Plot:getOwner() : number?
    return self.ownerId
end

return Plot