-- MachineSpawnService.lua
-- Owns: spawning and updating visual machine models in the world
-- Runs server-side so all players see changes simultaneously
-- Exposes: initPlayer, removePlayer, spawnMachine,
--          setMachineActive, updateUpgraded, updateEfficiencyDisplay,
--          despawnMachine
-- Does not: calculate income, manage pad states, handle purchases,
--           know game rules, look up plot models itself
-- CHANGED: active machines are now cloned from real multi-part models
--          in ServerStorage.MachineModels instead of a single colored
--          Part. Each model needs a PrimaryPart, and optionally
--          children named DamageEffect/SparkEffect (Fire or
--          ParticleEmitter instances) that get toggled based on
--          efficiency — see updateEfficiencyDisplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")

local PlotConfig        = require(ReplicatedStorage.Shared.Config.PlotConfig)
local MaintenanceConfig = require(ReplicatedStorage.Shared.Config.MaintenanceConfig)

local MachineSpawnService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Keyed by player.UserId
-- Each entry:
-- {
--     plotModel : Model,       the player's plot clone in workspace
--     parts     : {[padId] = Instance}   the placeholder Part during
--         construction, replaced with the cloned Model once active
-- }
local playerData = {}

-- ─────────────────────────────────────────
-- CONSTRUCTION-PHASE PLACEHOLDER
-- ─────────────────────────────────────────

local PLACEHOLDER_SIZE = {
    Harvester  = Vector3.new(4, 5, 4),
    Assembler  = Vector3.new(5, 6, 5),
    Fabricator = Vector3.new(6, 8, 6),
}

local CONSTRUCTION_VISUAL = {
    color    = BrickColor.new("Bright yellow"),
    material = Enum.Material.Neon,
}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

local function getPadPart(userId : number, padId : string) : BasePart?
    local data = playerData[userId]
    if not data or not data.plotModel then return nil end
    return data.plotModel:FindFirstChild(padId)
end

local function positionOnPad(part : Part, pad : BasePart)
    part.Position = Vector3.new(
        pad.Position.X,
        pad.Position.Y + (pad.Size.Y / 2) + (part.Size.Y / 2),
        pad.Position.Z
    )
end

-- ─────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────

function MachineSpawnService.initPlayer(player : Player, plotModel : Model)
    assert(
        not playerData[player.UserId],
        "MachineSpawnService.initPlayer: already initialized: " .. player.DisplayName
    )
    playerData[player.UserId] = {
        plotModel = plotModel,
        parts     = {},
    }
end

function MachineSpawnService.removePlayer(player : Player)
    playerData[player.UserId] = nil
end

-- Spawns an UNDER_CONSTRUCTION placeholder on the pad — unchanged
-- from before, still a simple yellow neon box regardless of what
-- the final model looks like
function MachineSpawnService.spawnMachine(
    player      : Player,
    padId       : string,
    machineType : string
)
    local data = playerData[player.UserId]
    if not data then
        warn("MachineSpawnService.spawnMachine: player not initialized: "
            .. player.DisplayName)
        return
    end

    local pad = getPadPart(player.UserId, padId)
    if not pad then
        warn("MachineSpawnService.spawnMachine: pad not found: " .. padId
            .. " for " .. player.DisplayName)
        return
    end

    local size = PLACEHOLDER_SIZE[machineType]
    if not size then
        warn("MachineSpawnService.spawnMachine: unknown machineType: " .. machineType)
        return
    end

    local padPrompt = pad:FindFirstChildOfClass("ProximityPrompt")
    if padPrompt then
        padPrompt.Enabled = false
    end

    local part               = Instance.new("Part")
    part.Name                 = padId .. "_Machine"
    part.Size                  = size
    part.BrickColor             = CONSTRUCTION_VISUAL.color
    part.Material                = CONSTRUCTION_VISUAL.material
    part.Anchored                 = true
    part.CanCollide                = false
    part.TopSurface                 = Enum.SurfaceType.Smooth
    part.BottomSurface                = Enum.SurfaceType.Smooth
    positionOnPad(part, pad)
    part.Parent = pad

    data.parts[padId] = part
end

-- Shows or hides one effect instance, handling both particle-style
-- effects (Enabled) and plain Parts (Transparency) — a Part has no
-- Enabled property, so it needs different handling entirely
local function setEffectVisible(effect : Instance, visible : boolean)
    if effect:IsA("ParticleEmitter")
        or effect:IsA("Fire")
        or effect:IsA("Smoke")
        or effect:IsA("Sparkles")
    then
        effect.Enabled = visible
    elseif effect:IsA("BasePart") then
        effect.Transparency = visible and 0 or 1
        effect.CanCollide   = false
    end
end

-- Toggles every descendant of the model whose name starts with the
-- given prefix ("Damage" or "Spark") — lets you use as many parts
-- or particle effects per tier as you want, mixed freely
local function setEffectTierVisible(model : Model, prefix : string, visible : boolean)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant.Name:sub(1, #prefix) == prefix then
            setEffectVisible(descendant, visible)
        end
    end
end

-- Replaces the construction placeholder with the real model, cloned
-- from ServerStorage.MachineModels, positioned via its PrimaryPart
function MachineSpawnService.setMachineActive(
    player      : Player,
    padId       : string,
    machineType : string
)
    local data = playerData[player.UserId]
    if not data then return end

    local placeholder = data.parts[padId]
    local pad          = getPadPart(player.UserId, padId)
    if not pad then return end

    local template = ServerStorage:FindFirstChild("MachineModels")
        and ServerStorage.MachineModels:FindFirstChild(machineType)

    if not template then
        warn("MachineSpawnService.setMachineActive: no model found for "
            .. machineType .. " in ServerStorage.MachineModels")
        return
    end

    if not template.PrimaryPart then
        warn("MachineSpawnService.setMachineActive: " .. machineType
            .. " model has no PrimaryPart set")
        return
    end

    local model  = template:Clone()
    local height = model.PrimaryPart.Size.Y

    model:PivotTo(CFrame.new(
        pad.Position.X,
        pad.Position.Y + (pad.Size.Y / 2) + (height / 2),
        pad.Position.Z
    ))
    model.Parent = pad

    if placeholder then
        placeholder:Destroy()
    end

    -- Service prompt (E) — quick, resets efficiency, no menu
    local servicePrompt                 = Instance.new("ProximityPrompt")
    servicePrompt.Name                  = "ServicePrompt"
    servicePrompt.ActionText            = "Service"
    servicePrompt.ObjectText            = "Efficiency: "
        .. MaintenanceConfig.STARTING_EFFICIENCY .. "%"
    servicePrompt.KeyboardKeyCode       = Enum.KeyCode.E
    servicePrompt.MaxActivationDistance = PlotConfig.PROMPT_DISTANCE
    servicePrompt.HoldDuration          = PlotConfig.PROMPT_HOLD_DURATION
    servicePrompt.Parent                = model.PrimaryPart

    -- Upgrade/inspect prompt (F) — opens the StatsPanel
    local upgradePrompt                 = Instance.new("ProximityPrompt")
    upgradePrompt.Name                  = "UpgradePrompt"
    upgradePrompt.ActionText            = PlotConfig.BUILT_MACHINE_ACTION_TEXT
    upgradePrompt.ObjectText            = machineType
    upgradePrompt.KeyboardKeyCode       = Enum.KeyCode.F
    upgradePrompt.MaxActivationDistance = PlotConfig.PROMPT_DISTANCE
    upgradePrompt.HoldDuration          = PlotConfig.PROMPT_HOLD_DURATION
    upgradePrompt.Parent                = model.PrimaryPart

    -- Start with both damage effects off — updateEfficiencyDisplay
    -- turns them on as needed once decay starts
    setEffectTierVisible(model, "Spark", false)
    setEffectTierVisible(model, "Damage", false)

    data.parts[padId] = model
end

-- Updates machine appearance after an upgrade is applied
function MachineSpawnService.updateUpgraded(
    player      : Player,
    padId       : string,
    machineType : string,
    branch      : string
)
    local data = playerData[player.UserId]
    if not data then return end

    local model = data.parts[padId]
    if not model or not model:IsA("Model") then return end

    local prompt = model.PrimaryPart and model.PrimaryPart:FindFirstChild("UpgradePrompt")
    if prompt then
        prompt.ObjectText = machineType .. " [" .. branch .. "]"
    end

    for otherPadId, otherModel in pairs(data.parts) do
        if otherPadId ~= padId
            and otherPadId:sub(1, #machineType) == machineType
            and otherModel:IsA("Model")
            and otherModel.PrimaryPart
        then
            local otherPrompt = otherModel.PrimaryPart:FindFirstChild("UpgradePrompt")
            if otherPrompt and not otherPrompt.ObjectText:find("%[") then
                otherPrompt.ObjectText = machineType .. " (Locked: " .. branch .. ")"
            end
        end
    end
end

-- Updates the ServicePrompt's displayed efficiency, its hold
-- duration, and toggles the model's damage effects based on how
-- unhealthy the machine currently is:
--   100% down to the warning threshold: no effects
--   below the warning threshold: SparkEffect on
--   fully broken down (0%): both SparkEffect and DamageEffect on
function MachineSpawnService.updateEfficiencyDisplay(
    player      : Player,
    padId       : string,
    efficiency  : number
)
    local data = playerData[player.UserId]
    if not data then return end

    local model = data.parts[padId]
    if not model or not model:IsA("Model") or not model.PrimaryPart then return end

    local prompt = model.PrimaryPart:FindFirstChild("ServicePrompt")
    if prompt then
        local rounded = math.floor(efficiency + 0.5)

        if efficiency <= MaintenanceConfig.BREAKDOWN_EFFICIENCY then
            prompt.ObjectText   = "Broken down — hold to repair"
            prompt.HoldDuration = MaintenanceConfig.BROKEN_HOLD_DURATION
        elseif efficiency < MaintenanceConfig.WARNING_THRESHOLD then
            prompt.ObjectText   = "Low efficiency: " .. rounded .. "% — needs service"
            prompt.HoldDuration = PlotConfig.PROMPT_HOLD_DURATION
        else
            prompt.ObjectText   = "Efficiency: " .. rounded .. "%"
            prompt.HoldDuration = PlotConfig.PROMPT_HOLD_DURATION
        end
    end

    local isBroken   = efficiency <= MaintenanceConfig.BREAKDOWN_EFFICIENCY
    local isDecaying = efficiency < MaintenanceConfig.WARNING_THRESHOLD

    local isBroken   = efficiency <= MaintenanceConfig.BREAKDOWN_EFFICIENCY
    local isDecaying = efficiency < MaintenanceConfig.WARNING_THRESHOLD

    setEffectTierVisible(model, "Spark", isDecaying)
    setEffectTierVisible(model, "Damage", isBroken)
end

-- Destroys a machine model and re-enables the pad's ProximityPrompt
function MachineSpawnService.despawnMachine(player : Player, padId : string)
    local data = playerData[player.UserId]
    if not data then return end

    local part = data.parts[padId]
    if part then
        part:Destroy()
        data.parts[padId] = nil
    end

    local pad = getPadPart(player.UserId, padId)
    if pad then
        local padPrompt = pad:FindFirstChildOfClass("ProximityPrompt")
        if padPrompt then
            padPrompt.Enabled = true
        end
    end
end

return MachineSpawnService