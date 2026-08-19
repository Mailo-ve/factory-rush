-- PlotSetup.server.lua
-- Clones PlotTemplate for each player at match start
-- Positions each clone using PlotConfig.PLOT_POSITIONS
-- Marks ownership via StringValue so PadController can find the player's plot
-- Creates ProximityPrompts on all empty pads

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig    = require(ReplicatedStorage.Shared.Config.PlotConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)

local PlotSetup = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Maps plotId → Model reference for active plots
local activePlots = {}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

-- Adds ProximityPrompts to all pads in a cloned plot
-- Each prompt shows machine type and cost from MachineConfig
local function setupPadPrompts(plotModel : Model)
    for _, part in ipairs(plotModel:GetDescendants()) do
        if not part:IsA("BasePart") then continue end

        local machineType = part.Name:match(PlotConfig.PAD_NAME_PATTERN)
        if not machineType then continue end

        local config = MachineConfig[machineType]
        if not config then continue end

        local prompt                    = Instance.new("ProximityPrompt")
        prompt.ActionText               = PlotConfig.EMPTY_PAD_ACTION_TEXT
        prompt.ObjectText               = machineType
            .. " — $" .. config.cost
        prompt.KeyboardKeyCode          = Enum.KeyCode.E
        prompt.MaxActivationDistance    = PlotConfig.PROMPT_DISTANCE
        prompt.HoldDuration             = PlotConfig.PROMPT_HOLD_DURATION
        prompt.Parent                   = part
    end
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Clones PlotTemplate, positions it, marks ownership
-- Returns the cloned Model so MatchManager can pass it
-- to MachineSpawnService.initPlayer
function PlotSetup.spawnPlot(player : Player, plotId : string) : Model?
    local template = workspace:FindFirstChild("PlotTemplate")
    if not template then
        warn("PlotSetup.spawnPlot: PlotTemplate not found in workspace")
        return nil
    end

    local position = PlotConfig.PLOT_POSITIONS[plotId]
    if not position then
        warn("PlotSetup.spawnPlot: no position defined for " .. plotId)
        return nil
    end

    -- Clone template
    local plotModel         = template:Clone()
    plotModel.Name          = plotId
    
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then
        plotsFolder = Instance.new("Folder")
        plotsFolder.Name = "Plots"
        plotsFolder.Parent = workspace
    end
    plotModel.Parent = plotsFolder

    -- Position using PrimaryPart (Platform)
    local primaryPart = plotModel:FindFirstChild("Platform")
    if primaryPart then
        plotModel.PrimaryPart = primaryPart

        local rotationY = (position.Z < 0) and 180 or 0
        plotModel:SetPrimaryPartCFrame(
            CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY), 0)
        )
    end

    -- Mark ownership so PadController can identify the player's plot
    local ownerValue        = Instance.new("StringValue")
    ownerValue.Name         = "OwnerId"
    ownerValue.Value        = tostring(player.UserId)
    ownerValue.Parent       = plotModel

    -- Setup pad prompts
    setupPadPrompts(plotModel)

    -- Store reference
    activePlots[plotId] = plotModel

    return plotModel
end

-- Destroys a plot model and clears its reference
function PlotSetup.despawnPlot(plotId : string)
    local plotModel = activePlots[plotId]
    if plotModel then
        plotModel:Destroy()
        activePlots[plotId] = nil
    end
end

-- Teleports a player's character to their plot's PlayerSpawn marker
function PlotSetup.teleportPlayerToPlot(player : Player, plotModel : Model)
    local character = player.Character
    if not character then return end

    local spawnPart = plotModel:FindFirstChild("PlayerSpawn")
    if not spawnPart then
        warn("PlotSetup.teleportPlayerToPlot: no PlayerSpawn found in plot")
        return
    end

    character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
end

-- Teleports a player's character back to the Lobby's Spawn point
function PlotSetup.teleportPlayerToLobby(player : Player)
    local character = player.Character
    if not character then return end

    local lobby = workspace:FindFirstChild("Lobby")
    local spawnPart = lobby and lobby:FindFirstChild("Spawn")
    if not spawnPart then
        warn("PlotSetup.teleportPlayerToLobby: no Lobby/Spawn found in workspace")
        return
    end

    character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
end

-- Despawns all active plots
-- Called by MatchManager at match end
function PlotSetup.despawnAllPlots()
    for plotId in pairs(activePlots) do
        PlotSetup.despawnPlot(plotId)
    end
end

-- Returns the active plot model for a plotId
function PlotSetup.getPlotModel(plotId : string) : Model?
    return activePlots[plotId]
end

return PlotSetup