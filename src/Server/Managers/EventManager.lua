-- EventManager.lua
-- Owns: the recurring mid-match event timer, announcing each event,
--       and dispatching its effect to the service that owns it
-- Exposes: startEvents, stopEvents
-- Does not: implement machine/economy logic itself — delegates to
--           PadService/ResourceService/EconomyService as needed

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players              = game:GetService("Players")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local MatchConfig  = require(ReplicatedStorage.Shared.Config.MatchConfig)
local PlotConfig    = require(ReplicatedStorage.Shared.Config.PlotConfig)
local MatchEvent      = ReplicatedStorage.Shared.RemoteEvents.MatchEvent

local function getPadService()
    return require(ServerScriptService.Server.Services.PadService)
end
local function getResourceService()
    return require(ServerScriptService.Server.Services.ResourceService)
end
local function getEconomyService()
    return require(ServerScriptService.Server.Services.EconomyService)
end
local function getPlotSetup()
    return require(ServerScriptService.Server.Services.PlotSetup)
end
local function getMatchManager()
    return require(ServerScriptService.Server.Managers.MatchManager)
end

local EventManager = {}

local eventThread = nil

-- ─────────────────────────────────────────
-- SHARED HELPERS
-- ─────────────────────────────────────────

-- True if the player is standing directly on the Platform part
-- specifically — pads and machines don't count, by design
local function isPlayerOnPlatform(player : Player) : boolean
    local character = player.Character
    if not character then return false end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local params = RaycastParams.new()
    params.FilterType                 = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances  = { character }

    local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -10, 0), params)
    return result ~= nil and result.Instance.Name == "Platform"
end

-- ─────────────────────────────────────────
-- EVENT HANDLERS
-- ─────────────────────────────────────────

local function applyAllMachinesBreak()
    getPadService().breakAllActiveMachines()
end

local function applyResourceSurge(event)
    getResourceService().startSurge(event.duration)
end

-- Two generators, placed in Studio as PowerSupplyA / PowerSupplyB.
-- Fixing either one pays $25k to whoever fixed it; a player who
-- personally fixes both ends up with $50k total, naturally, with no
-- extra bonus logic needed. Blackout ends the moment both are fixed,
-- or after its full duration if nobody manages both in time.
local function applyBlackout(event)
    local supplyA = workspace:FindFirstChild("PowerSupplyA")
    local supplyB = workspace:FindFirstChild("PowerSupplyB")

    if not supplyA or not supplyB then
        warn("EventManager: PowerSupplyA/PowerSupplyB not found in workspace")
        return
    end

    MatchEvent:FireAllClients({ action = "BLACKOUT_START" })

    local EconomyService = getEconomyService()
    local fixedCount      = 0
    local connections      = {}

    local function connectSupply(supply : Instance, key : string)
        local prompt = supply:FindFirstChildOfClass("ProximityPrompt")
        if not prompt then
            prompt = Instance.new("ProximityPrompt")
            prompt.Parent = supply
        end
        prompt.ActionText            = "Restore Power"
        prompt.ObjectText            = "Generator " .. key
        prompt.HoldDuration           = 3
        prompt.MaxActivationDistance  = PlotConfig.PROMPT_DISTANCE
        prompt.Enabled                 = true

        local claimed = false
        local conn
        conn = prompt.Triggered:Connect(function(player : Player)
            if claimed then return end
            claimed = true
            prompt.Enabled = false

            EconomyService.addMoney(player, 25000)
            MatchEvent:FireAllClients({
                action     = "BLACKOUT_SUPPLY_FIXED",
                playerName = player.DisplayName,
                supply     = key,
            })

            fixedCount += 1
            if fixedCount >= 2 then
                MatchEvent:FireAllClients({ action = "BLACKOUT_END" })
            end
        end)
        table.insert(connections, conn)
    end

    connectSupply(supplyA, "A")
    connectSupply(supplyB, "B")

    task.delay(event.duration, function()
        if fixedCount < 2 then
            MatchEvent:FireAllClients({ action = "BLACKOUT_END" })
        end
        for _, conn in ipairs(connections) do
            conn:Disconnect()
        end
    end)
end

-- The countdown itself already happened before this runs (see
-- startEvents below) — the instant this fires, touching Platform kills
local function applyFloorIsLava(event)
    local MatchManager = getMatchManager()
    local PlotSetup      = getPlotSetup()

    MatchEvent:FireAllClients({ action = "FLOOR_IS_LAVA_START" })

    local endTime = os.clock() + event.duration

    task.spawn(function()
        while os.clock() < endTime do
            for _, player in ipairs(Players:GetPlayers()) do
                if MatchManager.isPlayerInMatch(player) and isPlayerOnPlatform(player) then
                    PlotSetup.killAndRespawnAtPlot(player)
                end
            end
            task.wait(0.3)
        end
        MatchEvent:FireAllClients({ action = "FLOOR_IS_LAVA_END" })
    end)
end

-- Unlike Floor Is Lava, this only checks once, at the deadline — you
-- have the full duration to travel to the safe zone, not instant danger
local function applyFactoryEvacuation(event)
    local MatchManager = getMatchManager()
    local PlotSetup      = getPlotSetup()

    local safeZone = workspace:FindFirstChild("SafeZone")
    if not safeZone then
        warn("EventManager: no SafeZone found in workspace")
        return
    end

    MatchEvent:FireAllClients({ action = "EVACUATION_START" })

    local radius = math.max(safeZone.Size.X, safeZone.Size.Z) / 2

    task.delay(event.duration, function()
        for _, player in ipairs(Players:GetPlayers()) do
            if MatchManager.isPlayerInMatch(player) then
                local character = player.Character
                local rootPart    = character and character:FindFirstChild("HumanoidRootPart")

                if rootPart then
                    local distance = (rootPart.Position - safeZone.Position).Magnitude
                    if distance > radius then
                        PlotSetup.killAndRespawnAtPlot(player)
                    end
                end
            end
        end
        MatchEvent:FireAllClients({ action = "EVACUATION_END" })
    end)
end

local EVENT_HANDLERS = {
    AllMachinesBreak  = applyAllMachinesBreak,
    ResourceSurge     = applyResourceSurge,
    Blackout          = applyBlackout,
    FloorIsLava       = applyFloorIsLava,
    FactoryEvacuation = applyFactoryEvacuation,
}

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

-- Starts the recurring event timer. Every event follows the same
-- announce → wait → apply flow, so no individual event needs its own
-- countdown logic — Floor Is Lava's "5 second warning" IS this.
function EventManager.startEvents()
    if eventThread then
        warn("EventManager.startEvents: already running, ignoring")
        return
    end

    eventThread = task.spawn(function()
        while true do
            task.wait(MatchConfig.EVENT_INTERVAL)

            local event = EventConfig[math.random(1, #EventConfig)]

            MatchEvent:FireAllClients({
                action      = "EVENT_ANNOUNCE",
                eventName   = event.name,
                description = event.description,
                countdown   = MatchConfig.EVENT_WARNING_DURATION,
            })

            task.wait(MatchConfig.EVENT_WARNING_DURATION)

            local handler = EVENT_HANDLERS[event.id]
            if handler then
                handler(event)
            else
                warn("EventManager: no handler registered for event id: " .. event.id)
            end
        end
    end)
end

function EventManager.stopEvents()
    if eventThread then
        task.cancel(eventThread)
        eventThread = nil
    end
end

return EventManager