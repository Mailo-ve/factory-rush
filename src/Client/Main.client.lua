-- Main.client.lua
-- Boots the client in dependency order
-- UIBuilder runs first so all UI elements exist before UIService connects events
-- PadController runs last since it needs the server to spawn plots first

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

ReplicatedStorage:WaitForChild("Shared")

local UIBuilder     = require(Players.LocalPlayer
    .PlayerScripts.Client.UIBuilder)
local UIService     = require(Players.LocalPlayer
    .PlayerScripts.Client.Services.UIService)
local PadController = require(Players.LocalPlayer
    .PlayerScripts.Client.Controllers.PadController)
local SprintController = require(Players.LocalPlayer
    .PlayerScripts.Client.Controllers.SprintController)

-- Build all UI elements before anything tries to reference them
UIBuilder.build()

-- Connect server event listeners
UIService.init()

-- Start watching for plot and connecting world interactions
PadController.init()

SprintController.init()