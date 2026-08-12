-- PlotManager.lua
-- Owns: assignment of players to plots
-- Exposes: initPlots, assignPlot, releasePlot,
--          getPlotForPlayer, getOwnerOfPlot, releaseAllPlots
-- Does not: know what machines are on a plot, calculate income,
--           handle player data, communicate with any service

local PlotManager = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Maps plotId → userId of current owner (nil if unoccupied)
-- e.g. { Plot1 = 12345678, Plot2 = nil, Plot3 = 87654321 }
local plotOwners = {}

-- Maps userId → plotId for fast reverse lookup
-- e.g. { [12345678] = "Plot1", [87654321] = "Plot3" }
local playerPlots = {}

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Registers the available plot IDs with PlotManager
-- Must be called once by MatchManager before any match starts
-- plotIds: array of strings matching plot names in workspace
-- e.g. { "Plot1", "Plot2", "Plot3", "Plot4" }
function PlotManager.initPlots(plotIds : {string})
    plotOwners = {}
    playerPlots = {}

    for _, plotId in ipairs(plotIds) do
        plotOwners[plotId] = false     -- nil means unoccupied
    end
end

-- Assigns the first available plot to a player
-- Returns the plotId on success, nil if no plots are available
-- Called by MatchManager once per player when a match starts
function PlotManager.assignPlot(player : Player) : string?
    -- Guard: player already has a plot
    if playerPlots[player.UserId] then
        warn("PlotManager.assignPlot: " .. player.DisplayName .. " already has a plot")
        return playerPlots[player.UserId]
    end

    -- Find first unoccupied plot
    for plotId, ownerId in pairs(plotOwners) do
        if ownerId == false then
            plotOwners[plotId]          = player.UserId
            playerPlots[player.UserId]  = plotId
            return plotId
        end
    end

    -- No plots available
    warn("PlotManager.assignPlot: no available plots for " .. player.DisplayName)
    return nil
end

-- Releases a specific player's plot back to unoccupied
-- Called by MatchManager when a player leaves mid-match
function PlotManager.releasePlot(player : Player)
    local plotId = playerPlots[player.UserId]
    if not plotId then
        warn("PlotManager.releasePlot: " .. player.DisplayName .. " has no assigned plot")
        return
    end

    plotOwners[plotId]          = false
    playerPlots[player.UserId]  = nil
end

-- Returns the plotId assigned to a player, or nil if none
-- Any module can call this to find where a player's factory lives
function PlotManager.getPlotForPlayer(player : Player) : string?
    return playerPlots[player.UserId]
end

-- Returns the userId of the player who owns a plot, or nil if unoccupied
function PlotManager.getOwnerOfPlot(plotId : string) : number?
    return plotOwners[plotId]
end

-- Releases all plots at once
-- Called by MatchManager when a match ends
function PlotManager.releaseAllPlots()
    for plotId in pairs(plotOwners) do
        plotOwners[plotId] = false
    end
    playerPlots = {}
end

return PlotManager