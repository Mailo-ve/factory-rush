-- UIBuilder.lua
-- Creates all UI elements programmatically
-- All element names must match UIService.collectUIReferences() exactly
-- Called once from Main.client.lua before UIService.init()
-- World-first design: ShopPanel removed, StatsPanel added
-- Gameplay interactions happen through world ProximityPrompts, not HUD buttons

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UIConfig      = require(ReplicatedStorage.Shared.Config.UIConfig)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIBuilder = {}

-- ─────────────────────────────────────────
-- COLORS AND FONTS
-- ─────────────────────────────────────────

local COLORS = {
    background      = Color3.fromRGB(30, 30, 40),
    panel           = Color3.fromRGB(45, 45, 60),
    button          = Color3.fromRGB(60, 120, 200),
    buttonBranch    = Color3.fromRGB(180, 100, 50),
    text            = Color3.fromRGB(255, 255, 255),
    subtext         = Color3.fromRGB(180, 180, 200),
    accent          = Color3.fromRGB(100, 220, 130),
    danger          = Color3.fromRGB(220, 80, 80),
    transparent     = Color3.fromRGB(0, 0, 0),
}

local FONTS = {
    header  = Enum.Font.GothamBold,
    body    = Enum.Font.Gotham,
    mono    = Enum.Font.RobotoMono,
}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

local function makeScreenGui(name, enabled)
    local gui               = Instance.new("ScreenGui")
    gui.Name                = name
    gui.ResetOnSpawn        = false
    gui.IgnoreGuiInset      = true
    gui.Enabled             = enabled
    gui.Parent              = playerGui
    return gui
end

local function makeFrame(parent, name, position, size, color, transparency)
    local frame                     = Instance.new("Frame")
    frame.Name                      = name
    frame.Position                  = position
    frame.Size                      = size
    frame.BackgroundColor3          = color or COLORS.panel
    frame.BackgroundTransparency    = transparency or 0
    frame.BorderSizePixel           = 0
    frame.Parent                    = parent
    return frame
end

local function makeLabel(parent, name, text, position, size, fontSize, color, font)
    local label                     = Instance.new("TextLabel")
    label.Name                      = name
    label.Text                      = text
    label.Position                  = position
    label.Size                      = size
    label.BackgroundTransparency    = 1
    label.TextColor3                = color or COLORS.text
    label.Font                      = font or FONTS.body
    label.TextSize                  = fontSize or 16
    label.TextXAlignment            = Enum.TextXAlignment.Left
    label.TextYAlignment            = Enum.TextYAlignment.Center
    label.Parent                    = parent
    return label
end

local function makeButton(parent, name, text, position, size, color)
    local button                    = Instance.new("TextButton")
    button.Name                     = name
    button.Text                     = text
    button.Position                 = position
    button.Size                     = size
    button.BackgroundColor3         = color or COLORS.button
    button.TextColor3               = COLORS.text
    button.Font                     = FONTS.header
    button.TextSize                 = 15
    button.BorderSizePixel          = 0
    button.AutoButtonColor          = true
    button.Parent                   = parent

    local corner        = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent       = button

    return button
end

local function addCorner(frame, radius)
    local corner        = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 12)
    corner.Parent       = frame
end

local function addPadding(frame, padding)
    local pad           = Instance.new("UIPadding")
    pad.PaddingTop      = UDim.new(0, padding)
    pad.PaddingBottom   = UDim.new(0, padding)
    pad.PaddingLeft     = UDim.new(0, padding)
    pad.PaddingRight    = UDim.new(0, padding)
    pad.Parent          = frame
end

local function addListLayout(frame, direction, padding)
    local layout                = Instance.new("UIListLayout")
    layout.FillDirection        = direction or Enum.FillDirection.Vertical
    layout.Padding              = UDim.new(0, padding or 8)
    layout.SortOrder            = Enum.SortOrder.LayoutOrder
    layout.Parent               = frame
end

-- ─────────────────────────────────────────
-- WAITING SCREEN
-- ─────────────────────────────────────────

local function buildWaitingScreen()
    local gui = makeScreenGui("WaitingScreen", false)
    gui.IgnoreGuiInset = false

    local card = makeFrame(gui, "Card",
        UDim2.new(0.5, -150, 0, 16),
        UDim2.new(0, 300, 0, 90),
        COLORS.panel, 0)
    addCorner(card, 16)
    addPadding(card, 16)

    local title = makeLabel(card, "Title", "Waiting for Players",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0.45, 0),
        18, COLORS.text, FONTS.header)
    title.TextXAlignment = Enum.TextXAlignment.Center

    local sub = makeLabel(card, "Subtitle",
        "Match starts when enough players join",
        UDim2.new(0, 0, 0.5, 0),
        UDim2.new(1, 0, 0.4, 0),
        13, COLORS.subtext, FONTS.body)
    sub.TextXAlignment = Enum.TextXAlignment.Center
end

-- ─────────────────────────────────────────
-- COUNTDOWN SCREEN
-- ─────────────────────────────────────────

local function buildCountdownScreen()
    local gui = makeScreenGui("CountdownScreen", false)

    local overlay = makeFrame(gui, "Overlay",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 1, 0),
        COLORS.background, 0.4)

    local card = makeFrame(overlay, "Card",
        UDim2.new(0.5, -120, 0.5, -120),
        UDim2.new(0, 240, 0, 240),
        COLORS.panel, 0)
    addCorner(card, 16)

    local title = makeLabel(card, "Title", "Match Starting",
        UDim2.new(0, 0, 0.05, 0),
        UDim2.new(1, 0, 0.25, 0),
        18, COLORS.subtext, FONTS.header)
    title.TextXAlignment = Enum.TextXAlignment.Center

    local countLabel = makeLabel(card, "CountdownLabel", "10",
        UDim2.new(0, 0, 0.3, 0),
        UDim2.new(1, 0, 0.6, 0),
        80, COLORS.accent, FONTS.header)
    countLabel.TextXAlignment = Enum.TextXAlignment.Center
end

-- ─────────────────────────────────────────
-- WIN SCREEN
-- ─────────────────────────────────────────

local function buildWinScreen()
    local gui = makeScreenGui("WinScreen", false)

    local overlay = makeFrame(gui, "Overlay",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 1, 0),
        COLORS.background, 0.3)

    local card = makeFrame(overlay, "Card",
        UDim2.new(0.5, -200, 0, 20),   -- was -120
        UDim2.new(0, 400, 0, 240),
        COLORS.panel, 0)
    addCorner(card, 16)
    addPadding(card, 28)

    local trophy = makeLabel(card, "Trophy", "🏆",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0.25, 0),
        40, COLORS.text, FONTS.header)
    trophy.TextXAlignment = Enum.TextXAlignment.Center

    local winLabel = makeLabel(card, "WinLabel", "",
        UDim2.new(0, 0, 0.3, 0),
        UDim2.new(1, 0, 0.45, 0),
        20, COLORS.text, FONTS.header)
    winLabel.TextXAlignment = Enum.TextXAlignment.Center
    winLabel.TextWrapped    = true

    local sub = makeLabel(card, "SubLabel", "Next match starting soon...",
        UDim2.new(0, 0, 0.78, 0),
        UDim2.new(1, 0, 0.2, 0),
        14, COLORS.subtext, FONTS.body)
    sub.TextXAlignment = Enum.TextXAlignment.Center
end

-- ─────────────────────────────────────────
-- HUD COMPONENTS
-- ─────────────────────────────────────────

local function buildMoneyDisplay(hud)
    local moneyFrame = makeFrame(hud, "MoneyDisplay",
        UDim2.new(0.5, -100, 0, 12),
        UDim2.new(0, 200, 0, 72),
        COLORS.panel, 0)
    addCorner(moneyFrame, 10)
    addPadding(moneyFrame, 10)

    makeLabel(moneyFrame, "MoneyLabel", "$0",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0.55, 0),
        26, COLORS.accent, FONTS.header)

    makeLabel(moneyFrame, "IncomeLabel", "$0 per tick",
        UDim2.new(0, 0, 0.55, 0),
        UDim2.new(1, 0, 0.4, 0),
        13, COLORS.subtext, FONTS.body)
end

local function buildLeaderboard(hud)
    local frame = makeFrame(hud, "Leaderboard",
        UDim2.new(1, -216, 0, 16),
        UDim2.new(0, 200, 0, 0),
        COLORS.panel, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    addCorner(frame, 10)
    addPadding(frame, 10)
    addListLayout(frame, Enum.FillDirection.Vertical, 4)

    local title = makeLabel(frame, "Title", "LEADERBOARD",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 20),
        12, COLORS.subtext, FONTS.header)
    title.TextXAlignment = Enum.TextXAlignment.Center

    -- Template entry cloned by UIService for each player
    local template = makeLabel(frame, "EntryTemplate", "1. Player  $0",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 22),
        13, COLORS.text, FONTS.mono)
    template.Visible = false
end

-- StatsPanel: shown when player presses E on a built machine
-- Contains machine type label, upgrade branch buttons, status label
-- ShopPanel has been removed — buying now happens through world ProximityPrompts
local function buildStatsPanel(hud)
    local panel = makeFrame(hud, "StatsPanel",
        UDim2.new(0.5, -180, 0.5, -220),
        UDim2.new(0, 360, 0, 440),
        COLORS.panel, 0)
    panel.Visible = false
    addCorner(panel, 14)
    addPadding(panel, 16)
    addListLayout(panel, Enum.FillDirection.Vertical, 10)

    makeLabel(panel, "Title", "⚙️  Machine Info",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 32),
        18, COLORS.text, FONTS.header)

    -- Shows the machine type name, populated by UIService.showStatsPanel()
    makeLabel(panel, "MachineTypeLabel", "",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 24),
        15, COLORS.subtext, FONTS.body)

    makeLabel(panel, "UpgradeTitle", "Choose Upgrade Path",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 22),
        13, COLORS.subtext, FONTS.header)

    -- Branch A button — text populated by UIService from UpgradeConfig
    local btnA = makeButton(panel, "UpgradeBranchA", "Branch A",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 70),
        COLORS.buttonBranch)
    btnA.TextWrapped = true

    -- Branch B button — text populated by UIService from UpgradeConfig
    local btnB = makeButton(panel, "UpgradeBranchB", "Branch B",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 70),
        COLORS.buttonBranch)
    btnB.TextWrapped = true

    -- Shown instead of branch buttons when machine is already upgraded
    local statusLabel = makeLabel(panel, "UpgradeStatusLabel", "",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 28),
        14, COLORS.accent, FONTS.body)
    statusLabel.Visible         = false
    statusLabel.TextXAlignment  = Enum.TextXAlignment.Center

    makeButton(panel, "CloseStats", "✕  Close",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 0, 40),
        COLORS.danger)
end

-- ─────────────────────────────────────────
-- HUD ROOT
-- ─────────────────────────────────────────

local function buildHUD()
    local gui = makeScreenGui("HUD", false)
    gui.IgnoreGuiInset = false

    buildMoneyDisplay(gui)
    buildLeaderboard(gui)
    buildStatsPanel(gui)
    -- ShopPanel intentionally omitted:
    -- machine purchases happen through world ProximityPrompts on pads
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Builds the entire UI tree
-- Must be called from Main.client.lua before UIService.init()
-- UIService.collectUIReferences() will fail if called before this
function UIBuilder.build()
    buildWaitingScreen()
    buildCountdownScreen()
    buildWinScreen()
    buildHUD()
    print("UIBuilder: all UI elements created")
end

return UIBuilder