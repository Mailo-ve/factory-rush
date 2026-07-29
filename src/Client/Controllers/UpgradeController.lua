-- UpgradeController.lua
-- Owns: upgrade branch button input
-- Fires MachineEvent(UPGRADE) to server when player clicks a branch button
-- Does not: lock branches in UI (UIService handles that on confirmation),
--           validate any game rules, touch any state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local MachineEvent = ReplicatedStorage.Shared.RemoteEvents.MachineEvent

local UpgradeController = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────
-- PRIVATE FUNCTIONS
-- ─────────────────────────────────────────

-- Fires an UPGRADE request to the server
-- machineType: string matching a key in MachineConfig
-- branch: "A" or "B"
local function requestUpgrade(machineType : string, branch : string)
    if type(machineType) ~= "string" or machineType == "" then
        warn("UpgradeController.requestUpgrade: invalid machineType: " .. tostring(machineType))
        return
    end

    if branch ~= "A" and branch ~= "B" then
        warn("UpgradeController.requestUpgrade: invalid branch: " .. tostring(branch))
        return
    end

    MachineEvent:FireServer({
        action      = "UPGRADE",
        machineType = machineType,
        branch      = branch,
    })
end

-- Connects upgrade buttons inside the upgrade panel
-- Each button is expected to have two attributes set in Studio:
--   MachineType : string  e.g. "Harvester"
--   Branch      : string  "A" or "B"
local function connectUpgradeButtons(upgradePanel)
    for _, button in ipairs(upgradePanel:GetDescendants()) do
        if button:IsA("TextButton")
            and button:GetAttribute("MachineType")
            and button:GetAttribute("Branch")
        then
            local machineType   = button:GetAttribute("MachineType")
            local branch        = button:GetAttribute("Branch")

            button.Activated:Connect(function()
                requestUpgrade(machineType, branch)
            end)
        end
    end
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Connects all upgrade branch buttons
-- Called once by Main.client.lua at startup
function UpgradeController.init()
    local hud           = playerGui:WaitForChild("HUD")
    local upgradePanel  = hud:WaitForChild("UpgradePanel")

    connectUpgradeButtons(upgradePanel)
end

return UpgradeController