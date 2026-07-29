-- RemoteEventSetup.server.lua
-- Creates all RemoteEvent instances if they don't already exist
-- Runs once at server startup before any other script needs them
-- This means the game works on any machine without manual Studio setup

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Ensure the folder structure exists
local function ensureFolder(parent, name)
    local folder = parent:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = parent
    end
    return folder
end

-- Creates a RemoteEvent if it doesn't already exist
local function ensureRemoteEvent(parent, name)
    if not parent:FindFirstChild(name) then
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = parent
    end
end

-- Ensure folder structure
local shared        = ensureFolder(ReplicatedStorage, "Shared")
local remoteEvents  = ensureFolder(shared, "RemoteEvents")

-- Create all four RemoteEvents
ensureRemoteEvent(remoteEvents, "MachineEvent")
ensureRemoteEvent(remoteEvents, "EconomyEvent")
ensureRemoteEvent(remoteEvents, "MatchEvent")
ensureRemoteEvent(remoteEvents, "LeaderboardEvent")

print("RemoteEventSetup: all RemoteEvents ready")