-- ResourceService.lua
-- Owns: spawning, tracking, and collecting Resource Opportunity nodes
-- Exposes: startSpawning, stopSpawning
-- Does not: know about plots, machines, or match state directly —
--           MatchManager starts/stops this the same way it does
--           EconomyService and PadService's ticks
-- One node exists at a time by design — keeps the MVP simple and
-- avoids players needing to choose between multiple simultaneous nodes

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ResourceConfig = require(ReplicatedStorage.Shared.Config.ResourceConfig)
local PlotConfig      = require(ReplicatedStorage.Shared.Config.PlotConfig)

local function getEconomyService()
    return require(ServerScriptService.Server.Services.EconomyService)
end

local ResourceService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local activeNode   = nil   -- the currently spawned node Part, or nil
local spawnThread   = nil   -- the recurring spawn-loop thread, nil when stopped
local despawnThread  = nil   -- lifetime timer for the current node, nil when none active

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

local function getSpawnPoints() : {BasePart}
    local folder = workspace:FindFirstChild("ResourceSpawnPoints")
    if not folder then return {} end

    local points = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(points, child)
        end
    end
    return points
end

-- Removes the currently active node, if any, and cancels its lifetime timer
local function clearActiveNode()
    if despawnThread then
        task.cancel(despawnThread)
        despawnThread = nil
    end
    if activeNode then
        activeNode:Destroy()
        activeNode = nil
    end
end

-- Spawns a fresh node at a random spawn point
local function spawnNode()
    local points = getSpawnPoints()
    if #points == 0 then
        warn("ResourceService: no ResourceSpawnPoints found in workspace")
        return
    end

    local spawnPoint = points[math.random(1, #points)]
    local payout      = math.random(ResourceConfig.PAYOUT_MIN, ResourceConfig.PAYOUT_MAX)

    local node          = Instance.new("Part")
    node.Name             = "ResourceNode"
    node.Shape             = Enum.PartType.Ball
    node.Size              = Vector3.new(3, 3, 3)
    node.Material          = Enum.Material.Neon
    node.BrickColor        = BrickColor.new("New Yeller")
    node.Anchored          = true
    node.CanCollide        = false
    node.Position           = spawnPoint.Position + Vector3.new(0, 2, 0)

    local prompt                 = Instance.new("ProximityPrompt")
    prompt.ActionText             = "Collect"
    prompt.ObjectText             = "Resource Cache — $" .. payout
    prompt.MaxActivationDistance  = PlotConfig.PROMPT_DISTANCE
    prompt.HoldDuration            = PlotConfig.PROMPT_HOLD_DURATION
    prompt.Parent                  = node

    -- Guards against two players triggering it in the same instant
    -- before Destroy() actually removes it
    local claimed = false

    prompt.Triggered:Connect(function(player : Player)
        if claimed or node ~= activeNode then return end
        claimed = true

        getEconomyService().addMoney(player, payout)
        clearActiveNode()
    end)

    node.Parent = workspace
    activeNode  = node

    despawnThread = task.delay(ResourceConfig.LIFETIME, function()
        despawnThread = nil
        clearActiveNode()
    end)
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Starts the recurring spawn loop
-- Called by MatchManager when a match starts
function ResourceService.startSpawning()
    if spawnThread then
        warn("ResourceService.startSpawning: already running, ignoring")
        return
    end

    spawnThread = task.spawn(function()
        while true do
            local waitTime = math.random(
                ResourceConfig.SPAWN_INTERVAL_MIN,
                ResourceConfig.SPAWN_INTERVAL_MAX
            )
            task.wait(waitTime)

            if not activeNode then
                spawnNode()
            end
        end
    end)
end

-- Stops the spawn loop and clears any node left over from the match
-- Called by MatchManager when a match ends
function ResourceService.stopSpawning()
    if spawnThread then
        task.cancel(spawnThread)
        spawnThread = nil
    end
    clearActiveNode()
end

return ResourceService