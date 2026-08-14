-- UIService.lua
-- Owns: all UI state and rendering
-- Listens to all server RemoteEvents and updates UI accordingly
-- Does not: fire RemoteEvents, make game decisions,
--           store authoritative state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local GameState         = require(ReplicatedStorage.Shared.State.GameState)
local UIConfig          = require(ReplicatedStorage.Shared.Config.UIConfig)
local EconomyEvent      = ReplicatedStorage.Shared.RemoteEvents.EconomyEvent
local LeaderboardEvent  = ReplicatedStorage.Shared.RemoteEvents.LeaderboardEvent
local MatchEvent        = ReplicatedStorage.Shared.RemoteEvents.MatchEvent

local QueueEvent = ReplicatedStorage.Shared.RemoteEvents.QueueEvent

local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

local UIService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI element references — populated in init()
-- All names must match exactly what is built in Studio
local ui = {
    -- HUD elements
    moneyLabel      = nil,  -- TextLabel showing current balance
    incomeLabel     = nil,  -- TextLabel showing currentIncome per tick
    shopPanel       = nil,  -- Frame containing machine buy buttons
    upgradePanel    = nil,  -- Frame containing upgrade branch buttons

    -- Leaderboard elements
    leaderboardFrame    = nil,  -- Frame containing leaderboard entries
    leaderboardTemplate = nil,  -- Template TextLabel cloned per entry

    -- Full-screen panels
    waitingScreen   = nil,  -- shown during WAITING
    countdownScreen = nil,  -- shown during COUNTDOWN
    countdownLabel  = nil,  -- TextLabel showing countdown number
    hudScreen       = nil,  -- shown during PLAYING
    winScreen       = nil,  -- shown during ENDING
    winLabel        = nil,  -- TextLabel showing winner name and money
}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

-- Formats a number as a readable money string
-- 1000 → "$1,000"   1000000 → "$1,000,000"
local function formatMoney(amount : number) : string
    local formatted = tostring(math.floor(amount))
    local result    = ""
    local length    = #formatted

    for i = 1, length do
        if i > 1 and (length - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. string.sub(formatted, i, i)
    end

    return UIConfig.CURRENCY_SYMBOL .. result
end

-- Hides all full-screen panels
-- Called before showing the correct one for the current state
local function hideAllScreens()
    if ui.waitingScreen   then ui.waitingScreen.Enabled   = false end
    if ui.countdownScreen then ui.countdownScreen.Enabled = false end
    if ui.hudScreen       then ui.hudScreen.Enabled       = false end
    if ui.winScreen       then ui.winScreen.Enabled       = false end
end

-- ─────────────────────────────────────────
-- PRIVATE EVENT HANDLERS
-- ─────────────────────────────────────────

-- Called when server fires EconomyEvent(MONEY_UPDATED)
-- Updates the player's money and income labels
local function onMoneyUpdated(payload)
    if not payload or type(payload) ~= "table" then return end

    if ui.moneyLabel then
        ui.moneyLabel.Text = formatMoney(payload.newBalance)
    end

    if ui.incomeLabel then
        ui.incomeLabel.Text = formatMoney(payload.currentIncome)
            .. " " .. UIConfig.INCOME_LABEL
    end
end

-- Called when server fires LeaderboardEvent(UPDATED)
-- Rebuilds the leaderboard UI from the sorted player array
local function onLeaderboardUpdated(payload)
    if not payload or type(payload) ~= "table" then return end
    if not ui.leaderboardFrame or not ui.leaderboardTemplate then return end

    -- Clear existing entries (except the template itself)
    for _, child in ipairs(ui.leaderboardFrame:GetChildren()) do
        if child ~= ui.leaderboardTemplate and child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    -- Rebuild from sorted payload
    for rank, entry in ipairs(payload.players) do
        local label = ui.leaderboardTemplate:Clone()
        label.Text    = rank .. ". " .. entry.name .. "  " .. formatMoney(entry.money)
        label.Visible = true
        label.Parent  = ui.leaderboardFrame
    end
end

-- Called when server fires MatchEvent(STATE_CHANGED)
-- Shows the correct full-screen panel for the new state
local function onStateChanged(payload)
    if not payload or type(payload) ~= "table" then return end
    hideAllScreens()
    local newState = payload.newState

    if newState == GameState.COUNTDOWN then
        if ui.countdownScreen then ui.countdownScreen.Enabled = true end
    elseif newState == GameState.PLAYING then
        if ui.hudScreen then ui.hudScreen.Enabled = true end
    elseif newState == GameState.ENDING then
        if ui.winScreen then ui.winScreen.Enabled = true end
    end
end

-- Called when server fires MatchEvent(GAME_WON)
-- Displays the win screen with winner information
local function onGameWon(payload)
    if not payload or type(payload) ~= "table" then return end

    hideAllScreens()

    if ui.winScreen then ui.winScreen.Enabled = true end

    if ui.winLabel then
        if payload.winnerName then
            ui.winLabel.Text = payload.winnerName
                .. " " .. UIConfig.WIN_MESSAGE
                .. "\n" .. formatMoney(payload.winnerMoney)
        else
            -- nil winnerName means match ended by timeout
            ui.winLabel.Text = "Time's up!\nNo winner this match."
        end
    end
end

-- ─────────────────────────────────────────
-- PRIVATE SETUP
-- ─────────────────────────────────────────

local function onQueueStatus(payload)
    if not payload or type(payload) ~= "table" then return end

    if payload.action == "QUEUE_JOINED" then
        if ui.waitingScreen then ui.waitingScreen.Enabled = true end

    elseif payload.action == "QUEUE_UPDATE" then
        if ui.waitingScreen then ui.waitingScreen.Enabled = true end
        if ui.waitingSubtitle then
            ui.waitingSubtitle.Text = payload.count .. " / " .. payload.max
                .. " players — need " .. payload.needed .. " to start"
        end

    elseif payload.action == "QUEUE_LEFT" then
        if ui.waitingScreen then ui.waitingScreen.Enabled = false end
    end
end

-- Connects all RemoteEvent listeners
local function connectEvents()
    -- EconomyEvent carries multiple actions in future
    -- Route by action field same pattern as server EventHandlers
    EconomyEvent.OnClientEvent:Connect(function(payload)
        if not payload then return end
        if payload.action == "MONEY_UPDATED" then
            onMoneyUpdated(payload)
        end
    end)

    LeaderboardEvent.OnClientEvent:Connect(function(payload)
        if not payload then return end
        if payload.action == "UPDATED" then
            onLeaderboardUpdated(payload)
        end
    end)

    MatchEvent.OnClientEvent:Connect(function(payload)
        if not payload then return end
        if payload.action == "STATE_CHANGED" then
            onStateChanged(payload)
        elseif payload.action == "GAME_WON" then
            onGameWon(payload)
        end
    end)

    QueueEvent.OnClientEvent:Connect(onQueueStatus)

end

-- Collects all UI element references from PlayerGui
-- WaitForChild used throughout so script works even if UI loads slightly late
-- All names here must match exactly what is built in Studio
local function collectUIReferences()
    local hud = playerGui:WaitForChild("HUD")

    -- HUD elements

    -- was: ui.moneyLabel = hud:WaitForChild("MoneyLabel")
    local moneyDisplay = hud:WaitForChild("MoneyDisplay")
    ui.moneyLabel   = moneyDisplay:WaitForChild("MoneyLabel")
    ui.incomeLabel  = moneyDisplay:WaitForChild("IncomeLabel")

    -- Leaderboard
    local leaderboard       = hud:WaitForChild("Leaderboard")
    ui.leaderboardFrame     = leaderboard
    ui.leaderboardTemplate  = leaderboard:WaitForChild("EntryTemplate")
    ui.leaderboardTemplate.Visible = false  -- hide template, only clones are shown

    -- Full-screen panels
    ui.waitingScreen    = playerGui:WaitForChild("WaitingScreen")
    ui.countdownScreen   = playerGui:WaitForChild("CountdownScreen")
    local countdownCard  = ui.countdownScreen:WaitForChild("Overlay"):WaitForChild("Card")
    ui.countdownLabel    = countdownCard:WaitForChild("CountdownLabel")

    -- Reference to Subtitle
    local waitingCard  = ui.waitingScreen:WaitForChild("Overlay"):WaitForChild("Card")
    ui.waitingSubtitle = waitingCard:WaitForChild("Subtitle")


    ui.hudScreen         = hud

    ui.winScreen         = playerGui:WaitForChild("WinScreen")
    local winCard        = ui.winScreen:WaitForChild("Overlay"):WaitForChild("Card")
    ui.winLabel          = winCard:WaitForChild("WinLabel")

    -- StatsPanel
    local statsPanel            = hud:WaitForChild("StatsPanel")
    ui.statsPanel               = statsPanel
    ui.statsMachineTypeLabel    = statsPanel:WaitForChild("MachineTypeLabel")
    ui.statsUpgradeBranchA      = statsPanel:WaitForChild("UpgradeBranchA")
    ui.statsUpgradeBranchB      = statsPanel:WaitForChild("UpgradeBranchB")
    ui.statsUpgradeStatusLabel  = statsPanel:WaitForChild("UpgradeStatusLabel")
    ui.statsCloseButton         = statsPanel:WaitForChild("CloseStats")

    ui.statsCloseButton.Activated:Connect(function()
        UIService.hideStatsPanel()
    end)

end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Initializes UIService by collecting UI references and connecting events
-- Called once by Main.client.lua at startup
function UIService.init()
    collectUIReferences()
    connectEvents()
    hideAllScreens()

    -- Show waiting screen as the default starting state
    if ui.waitingScreen then
        ui.waitingScreen.Enabled = true
    end
end

-- Shows the StatsPanel populated with machine info and upgrade options
-- isUpgraded: true hides buttons and shows status label instead
-- Returns button references so PadController can connect upgrade logic
function UIService.showStatsPanel(
    machineType : string,
    isUpgraded  : boolean
)
    local upgradeConfig = UpgradeConfig[machineType]

    ui.statsMachineTypeLabel.Text = machineType

    if isUpgraded then
        ui.statsUpgradeBranchA.Visible      = false
        ui.statsUpgradeBranchB.Visible      = false
        ui.statsUpgradeStatusLabel.Visible  = true
        ui.statsUpgradeStatusLabel.Text     = "Already upgraded"
    else
        ui.statsUpgradeStatusLabel.Visible  = false
        ui.statsUpgradeBranchA.Visible      = true
        ui.statsUpgradeBranchB.Visible      = true

        if upgradeConfig then
            ui.statsUpgradeBranchA.Text = upgradeConfig.A.name
                .. "\n" .. upgradeConfig.A.description
                .. "\nCost: $" .. upgradeConfig.cost
            ui.statsUpgradeBranchB.Text = upgradeConfig.B.name
                .. "\n" .. upgradeConfig.B.description
                .. "\nCost: $" .. upgradeConfig.cost
        end
    end

    ui.statsPanel.Visible = true
end

-- Hides the StatsPanel
function UIService.hideStatsPanel()
    if ui.statsPanel then
        ui.statsPanel.Visible = false
    end
end

-- Returns upgrade buttons so PadController can connect them
function UIService.getStatsPanelButtons()
    return {
        branchA = ui.statsUpgradeBranchA,
        branchB = ui.statsUpgradeBranchB,
        close   = ui.statsCloseButton,
    }
end

return UIService