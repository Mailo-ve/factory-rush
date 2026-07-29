-- Main.client.lua
-- Boots the client by initializing all Controllers and UIService
-- in dependency order. Contains zero game logic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Wait for shared resources to exist before requiring anything
-- This prevents errors if the client script loads before ReplicatedStorage
-- is fully populated
ReplicatedStorage:WaitForChild("Shared")

local ShopController    = require(Players.LocalPlayer
    .PlayerScripts.Client.Controllers.ShopController)
local UpgradeController = require(Players.LocalPlayer
    .PlayerScripts.Client.Controllers.UpgradeController)
local UIService         = require(Players.LocalPlayer
    .PlayerScripts.Client.Services.UIService)

-- UIService first — connect event listeners before any events could fire
UIService.init()

-- Controllers after — connect input handlers once UI is ready
ShopController.init()
UpgradeController.init()