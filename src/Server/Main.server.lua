-- Main.server.lua
-- Boots the server by initializing all Managers and EventHandlers
-- in dependency order. Contains zero game logic.
-- If logic ends up here, it belongs in a Manager or Service instead.

local ServerScriptService = game:GetService("ServerScriptService")

-- ─────────────────────────────────────────
-- REQUIRE ALL MODULES
-- ─────────────────────────────────────────

-- Initialize RemoteEvents before anything else
require(ServerScriptService.Server.Network.RemoteEventSetup)

local MatchManager          = require(ServerScriptService.Server.Managers.MatchManager)
local MachineEventHandler   = require(ServerScriptService.Server.Network.MachineEventHandler)
local MatchEventHandler     = require(ServerScriptService.Server.Network.MatchEventHandler)
local EconomyEventHandler   = require(ServerScriptService.Server.Network.EconomyEventHandler)

-- Services are not initialized here directly
-- They are initialized by Managers at the correct point in the match lifecycle
-- Requiring them here would bypass that lifecycle and cause errors

-- ─────────────────────────────────────────
-- INITIALIZE IN DEPENDENCY ORDER
-- ─────────────────────────────────────────

-- EventHandlers first — connect listeners before any players can fire events
-- If MatchManager initialized first, a player could theoretically fire
-- MachineEvent before the listener exists
MachineEventHandler.init()
MatchEventHandler.init()
EconomyEventHandler.init()

-- MatchManager last — starts listening for players joining
-- By this point all listeners are connected and ready
MatchManager.init()