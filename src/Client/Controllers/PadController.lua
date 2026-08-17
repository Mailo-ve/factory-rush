-- PadController.lua
-- Replaces ShopController and UpgradeController entirely
-- Owns: ProximityPrompt connections on pads and machines
--       StatsPanel open/close logic
--       Fires MachineEvent(BUILD), MachineEvent(UPGRADE), MachineEvent(SERVICE)
-- Does not: validate affordability, calculate income,
--           update money UI, know game rules
-- CHANGED: active machines now have two prompts — ServicePrompt (E),
--          fired instantly with no menu, and UpgradePrompt (F), which
--          keeps the original StatsPanel flow unchanged

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

-- Fires SERVICE event to server — instant, no menu, no confirmation
local function requestService(padId : string)
    MachineEvent:FireServer({
        action = "SERVICE",
        padId  = padId,
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

-- Connects the Service prompt (E) — fires immediately, no menu involved
local function connectServicePrompt(prompt : ProximityPrompt, padId : string)
    prompt.Triggered:Connect(function()
        requestService(padId)
    end)
end

-- Connects the Upgrade/Inspect prompt (F) — opens the StatsPanel
local function connectUpgradePrompt(prompt : ProximityPrompt, padId : string)
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

-- Watches a machine part for its two ProximityPrompts (ServicePrompt,
-- UpgradePrompt) and connects each to the right handler as it appears.
-- Checks existing children first, then keeps listening — order between
-- the two isn't guaranteed since MachineSpawnService adds them one
-- after another in the same frame.
local function watchMachinePartForPrompt(machinePart : BasePart, padId : string)
    local function tryConnect(child : Instance)
        if not child:IsA("ProximityPrompt") then return end

        if child.Name == "ServicePrompt" then
            connectServicePrompt(child, padId)
        elseif child.Name == "UpgradePrompt" then
            connectUpgradePrompt(child, padId)
        end
    end

    for _, child in ipairs(machinePart:GetChildren()) do
        tryConnect(child)
    end

    machinePart.ChildAdded:Connect(tryConnect)
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
    -- When it appears, connect its two prompts
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

-- Searches the Plots folder for the model with OwnerId matching this player.
-- Waits indefinitely — there's no fixed upper bound on how long a player
-- may sit in the lobby before a match actually starts, and this runs in
-- a background thread, so waiting doesn't block anything else.
local function findPlayerPlot() : Model?
    local plotsFolder = workspace:WaitForChild("Plots")

    for _, model in ipairs(plotsFolder:GetChildren()) do
        if model:IsA("Model") then
            local ownerValue = model:FindFirstChild("OwnerId")
            if ownerValue and ownerValue.Value == tostring(player.UserId) then
                return model
            end
        end
    end

    local found = nil
    local conn
    conn = plotsFolder.ChildAdded:Connect(function(child)
        task.wait()
        if child:IsA("Model") then
            local ownerValue = child:FindFirstChild("OwnerId")
            if ownerValue and ownerValue.Value == tostring(player.UserId) then
                found = child
                conn:Disconnect()
            end
        end
    end)

    while not found do
        task.wait(0.5)
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
        while true do
            local plotModel = findPlayerPlot()
            if not plotModel then
                task.wait(1)
                continue
            end

            connectPlotPads(plotModel)

            plotModel.Destroying:Wait()
            task.wait()  -- let destruction fully finish before searching again
        end
    end)
end

return PadController