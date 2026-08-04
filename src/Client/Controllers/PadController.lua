-- PadController.lua
-- Replaces ShopController and UpgradeController entirely
-- Owns: ProximityPrompt connections on pads and machines
--       StatsPanel open/close logic
--       Fires MachineEvent(BUILD) and MachineEvent(UPGRADE) to server
-- Does not: validate affordability, calculate income,
--           update money UI, know game rules

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local MachineEvent  = ReplicatedStorage.Shared.RemoteEvents.MachineEvent
local PlotConfig    = require(ReplicatedStorage.Shared.Config.PlotConfig)

-- Lazy require — UIService loads after UIBuilder.build()
local function getUIService()
    return require(Players.LocalPlayer
        .PlayerScripts.Client.Services.UIService)
end

local PadController = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local player    = Players.LocalPlayer

-- Active StatsPanel button connections — disconnected when panel closes
local activeBtnConnections = {}

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Clears all active button connections
local function clearButtonConnections()
    for _, conn in ipairs(activeBtnConnections) do
        conn:Disconnect()
    end
    activeBtnConnections = {}
end

-- Fires BUILD event to server
local function requestBuild(machineType : string, padId : string)
    MachineEvent:FireServer({
        action      = "BUILD",
        machineType = machineType,
        padId       = padId,
    })
end

-- Fires UPGRADE event to server and closes StatsPanel
local function requestUpgrade(
    machineType : string,
    padId       : string,
    branch      : string
)
    MachineEvent:FireServer({
        action      = "UPGRADE",
        machineType = machineType,
        padId       = padId,
        branch      = branch,
    })
    clearButtonConnections()
    getUIService().hideStatsPanel()
end

-- Opens the StatsPanel for a built machine
-- isUpgraded: detected from prompt ObjectText containing "["
local function openStatsPanel(
    machineType : string,
    padId       : string,
    isUpgraded  : boolean
)
    local UIService = getUIService()
    UIService.showStatsPanel(machineType, isUpgraded)

    -- Connect upgrade buttons if not already upgraded
    if not isUpgraded then
        clearButtonConnections()
        local buttons = UIService.getStatsPanelButtons()

        table.insert(activeBtnConnections,
            buttons.branchA.Activated:Connect(function()
                requestUpgrade(machineType, padId, "A")
            end)
        )
        table.insert(activeBtnConnections,
            buttons.branchB.Activated:Connect(function()
                requestUpgrade(machineType, padId, "B")
            end)
        )
        table.insert(activeBtnConnections,
            buttons.close.Activated:Connect(function()
                clearButtonConnections()
                UIService.hideStatsPanel()
            end)
        )
    end
end

-- Connects a ProximityPrompt on a built machine to open StatsPanel
local function connectMachinePrompt(prompt : ProximityPrompt, padId : string)
    prompt.Triggered:Connect(function()
        -- Extract machineType from ObjectText
        -- "Harvester [A]" → "Harvester", "Assembler" → "Assembler"
        local objectText    = prompt.ObjectText
        local machineType   = objectText:match("^(%a+)")
        local isUpgraded    = objectText:find("%[") ~= nil

        if machineType then
            openStatsPanel(machineType, padId, isUpgraded)
        end
    end)
end

-- Watches a machine part for a ProximityPrompt to be added
-- Called when machine part appears on pad (UNDER_CONSTRUCTION state)
-- Prompt appears after construction completes (ACTIVE state)
local function watchMachinePartForPrompt(machinePart : BasePart, padId : string)
    -- Check if prompt already exists (rare but guard for it)
    local existing = machinePart:FindFirstChildOfClass("ProximityPrompt")
    if existing then
        connectMachinePrompt(existing, padId)
        return
    end

    -- Watch for prompt to be added after construction completes
    machinePart.ChildAdded:Connect(function(child)
        if child:IsA("ProximityPrompt") then
            connectMachinePrompt(child, padId)
        end
    end)
end

-- Connects ProximityPrompt on an empty pad for building
local function connectPadPrompt(padPart : BasePart, machineType : string)
    local prompt = padPart:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        warn("PadController: no ProximityPrompt on pad " .. padPart.Name)
        return
    end

    prompt.Triggered:Connect(function()
        requestBuild(machineType, padPart.Name)
    end)

    -- Watch for machine part being added to this pad
    -- When it appears, connect its inspect prompt
    padPart.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") then
            watchMachinePartForPrompt(child, padPart.Name)
        end
    end)
end

-- Connects all pads on the player's plot
local function connectPlotPads(plotModel : Model)
    for _, part in ipairs(plotModel:GetDescendants()) do
        if not part:IsA("BasePart") then continue end

        -- Extract machine type from pad name
        -- "HarvesterPad1" → "Harvester"
        local machineType = part.Name:match(PlotConfig.PAD_NAME_PATTERN)
        if machineType then
            connectPadPrompt(part, machineType)
        end
    end
end

-- Searches the Plots folder for the model with OwnerId matching this player
-- Polls until found or timeout reached
local function findPlayerPlot() : Model?
    local plotsFolder = workspace:WaitForChild("Plots", 60)
    if not plotsFolder then
        warn("PadController: Plots folder not found in workspace")
        return nil
    end

    -- Check already-existing children first
    for _, model in ipairs(plotsFolder:GetChildren()) do
        if model:IsA("Model") then
            local ownerValue = model:FindFirstChild("OwnerId")
            if ownerValue
                and ownerValue.Value == tostring(player.UserId)
            then
                return model
            end
        end
    end

    -- Plot not spawned yet — wait for it
    local found     = nil
    local conn      = plotsFolder.ChildAdded:Connect(function(child)
        -- Small wait to allow OwnerId StringValue to replicate
        task.wait()
        if child:IsA("Model") then
            local ownerValue = child:FindFirstChild("OwnerId")
            if ownerValue
                and ownerValue.Value == tostring(player.UserId)
            then
                found = child
            end
        end
    end)

    local timeout   = 60
    local elapsed   = 0
    while not found and elapsed < timeout do
        task.wait(0.5)
        elapsed = elapsed + 0.5
    end
    conn:Disconnect()

    if not found then
        warn("PadController: could not find player plot after "
            .. timeout .. "s")
    end

    return found
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Starts watching for the player's plot and connects all interactions
-- Runs in a background thread so it doesn't block Main.client.lua startup
function PadController.init()
    task.spawn(function()
        local plotModel = findPlayerPlot()
        if not plotModel then return end
        connectPlotPads(plotModel)
    end)
end

return PadController