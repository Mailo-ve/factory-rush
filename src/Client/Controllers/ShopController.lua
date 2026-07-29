-- ShopController.lua
-- Owns: buy button input from the shop UI
-- Fires MachineEvent(BUY) to server when player clicks a buy button
-- Does not: validate affordability, update UI, know any game rules

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local MachineEvent  = ReplicatedStorage.Shared.RemoteEvents.MachineEvent
local UIConfig      = require(ReplicatedStorage.Shared.Config.UIConfig)

local ShopController = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local player        = Players.LocalPlayer
local playerGui     = player:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Fires a BUY request to the server
-- machineType: string matching a key in MachineConfig
-- Server validates everything — client only sends the intent
local function requestPurchase(machineType : string)
    if type(machineType) ~= "string" or machineType == "" then
        warn("ShopController.requestPurchase: invalid machineType: " .. tostring(machineType))
        return
    end

    MachineEvent:FireServer({
        action      = "BUY",
        machineType = machineType,
    })
end

-- Connects buy buttons inside the shop panel
-- Each buy button is expected to have an attribute "MachineType"
-- set in Studio, matching a key in MachineConfig
-- e.g. a button named "BuyHarvester" with attribute MachineType = "Harvester"
local function connectShopButtons(shopPanel)
    for _, button in ipairs(shopPanel:GetDescendants()) do
        if button:IsA("TextButton") and button:GetAttribute("MachineType") then
            local machineType = button:GetAttribute("MachineType")

            button.Activated:Connect(function()
                requestPurchase(machineType)
            end)
        end
    end
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Connects all shop buy buttons
-- Called once by Main.client.lua at startup
-- WaitForChild ensures this works even if UI loads slightly after the script
function ShopController.init()
    local hud       = playerGui:WaitForChild("HUD")
    local shopPanel = hud:WaitForChild("ShopPanel")

    connectShopButtons(shopPanel)
end

return ShopController