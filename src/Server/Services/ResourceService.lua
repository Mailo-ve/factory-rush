-- ResourceService.lua
-- Owns: spawning, tracking, and collecting Resource Opportunity nodes
-- Exposes: startSpawning, stopSpawning, startSurge
-- Does not: know about plots, machines, or match state directly —
--           MatchManager starts/stops this the same way it does
--           EconomyService and PadService's ticks
-- Normal spawning keeps one node active at a time. startSurge is a
-- separate mode used by the ResourceSurge world event — spawns one
-- node at every marked point simultaneously, for a fixed duration,
-- independent of the normal one-at-a-time rule.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ResourceConfig  = require(ReplicatedStorage.Shared.Config.ResourceConfig)
local PlotConfig       = require(ReplicatedStorage.Shared.Config.PlotConfig)

local ModifierManager = require(ServerScriptService.Server.Managers.ModifierManager)

local function getEconomyService()
    return require(ServerScriptService.Server.Services.EconomyService)
end

local ResourceService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

local activeNode    = nil   -- normal mode's single node, or nil
local spawnThread    = nil   -- normal mode's recurring spawn loop, nil when stopped
local despawnThread   = nil   -- normal mode's lifetime timer, nil when none active

local surgeNodes = {}   -- surge mode's list of simultaneously active nodes

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

-- Creates one resource node at the given spawn point. onCollected is
-- called once someone successfully claims it (after the payout has
-- already been given) — the caller decides what "claimed" means for
-- its own tracking, this function doesn't know about active/surge modes
local function createNode(
    spawnPoint  : BasePart,
    onCollected : (Instance) -> ()
) : Instance
    local payout = math.floor(
        math.random(ResourceConfig.PAYOUT_MIN, ResourceConfig.PAYOUT_MAX)
        * ModifierManager.getResourceMultiplier()
    )

    local node       = Instance.new("Part")
    node.Name          = "ResourceNode"
    node.Shape           = Enum.PartType.Ball
    node.Size              = Vector3.new(3, 3, 3)
    node.Material            = Enum.Material.Neon
    node.BrickColor            = BrickColor.new("New Yeller")
    node.Anchored               = true
    node.CanCollide               = false
    node.Position                   = spawnPoint.Position + Vector3.new(0, 2, 0)

    local prompt                          = Instance.new("ProximityPrompt")
    prompt.ActionText                       = "Collect"
    prompt.ObjectText                         = "Resource Cache — $" .. payout
    prompt.MaxActivationDistance                = PlotConfig.PROMPT_DISTANCE
    prompt.HoldDuration                           = PlotConfig.PROMPT_HOLD_DURATION
    prompt.Parent                                   = node

    -- Guards against two players triggering it in the same instant
    -- before Destroy() actually removes it
    local claimed = false

    prompt.Triggered:Connect(function(player : Player)
        if claimed then return end
        claimed = true

        getEconomyService().addMoney(player, payout)
        onCollected(node)
    end)

    node.Parent = workspace
    return node
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

-- Spawns a fresh single node at a random spawn point (normal mode)
local function spawnNode()
    local points = getSpawnPoints()
    if #points == 0 then
        warn("ResourceService: no ResourceSpawnPoints found in workspace")
        return
    end

    local spawnPoint = points[math.random(1, #points)]

    activeNode = createNode(spawnPoint, function(collectedNode)
        if collectedNode == activeNode then
            clearActiveNode()
        end
    end)

    despawnThread = task.delay(ResourceConfig.LIFETIME, function()
        despawnThread = nil
        clearActiveNode()
    end)
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Starts the recurring single-node spawn loop
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
    for _, node in ipairs(surgeNodes) do
        if node.Parent then
            node:Destroy()
        end
    end
    surgeNodes = {}
end

-- Spawns one node at every marked ResourceSpawnPoint simultaneously,
-- all clearing themselves automatically after `duration` seconds.
-- Used by the ResourceSurge world event — independent of the normal
-- one-node-at-a-time loop, which keeps running unaffected alongside it.
function ResourceService.startSurge(duration : number)
    local points = getSpawnPoints()
    if #points == 0 then
        warn("ResourceService.startSurge: no ResourceSpawnPoints found in workspace")
        return
    end

    for _, point in ipairs(points) do
        local node = createNode(point, function(collectedNode)
            for i, existing in ipairs(surgeNodes) do
                if existing == collectedNode then
                    table.remove(surgeNodes, i)
                    break
                end
            end
        end)
        table.insert(surgeNodes, node)
    end

    task.delay(duration, function()
        for _, node in ipairs(surgeNodes) do
            if node.Parent then
                node:Destroy()
            end
        end
        surgeNodes = {}
    end)
end

return ResourceService