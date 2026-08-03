-- MachineSpawnService.lua
-- Owns: spawning and updating visual machine models in the world
-- Runs server-side so all players see changes simultaneously
-- Exposes: initPlayer, removePlayer, spawnMachine,
--          setMachineActive, updateUpgraded, despawnMachine
-- Does not: calculate income, manage pad states, handle purchases,
--           know game rules, look up plot models itself
-- Note: MatchManager passes the plotModel into initPlayer
--       so this service never needs to call PlotManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig    = require(ReplicatedStorage.Shared.Config.PlotConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)

local MachineSpawnService = {}

-- ─────────────────────────────────────────
-- PRIVATE STATE
-- ─────────────────────────────────────────

-- Keyed by player.UserId
-- Each entry:
-- {
--     plotModel : Model,       the player's plot clone in workspace
--     parts     : {[padId] = Part}   spawned machine Parts per pad
-- }
local playerData = {}

-- ─────────────────────────────────────────
-- VISUAL DEFINITIONS
-- ─────────────────────────────────────────

-- Placeholder visuals per machine type
-- Replace with real Model assets in a later pass
local MACHINE_VISUALS = {
    Harvester = {
        color    = BrickColor.new("Bright green"),
        material = Enum.Material.SmoothPlastic,
        size     = Vector3.new(4, 5, 4),
    },
    Assembler = {
        color    = BrickColor.new("Bright blue"),
        material = Enum.Material.SmoothPlastic,
        size     = Vector3.new(5, 6, 5),
    },
    Fabricator = {
        color    = BrickColor.new("Bright violet"),
        material = Enum.Material.SmoothPlastic,
        size     = Vector3.new(6, 8, 6),
    },
}

-- UNDER_CONSTRUCTION state appearance
-- Yellow neon signals "being built" clearly
local CONSTRUCTION_VISUAL = {
    color    = BrickColor.new("Bright yellow"),
    material = Enum.Material.Neon,
}

-- ─────────────────────────────────────────
-- PRIVATE HELPERS
-- ─────────────────────────────────────────

-- Finds a named pad Part inside the player's plot model
local function getPadPart(userId : number, padId : string) : BasePart?
    local data = playerData[userId]
    if not data or not data.plotModel then return nil end
    return data.plotModel:FindFirstChild(padId)
end

-- Positions a Part to sit centered on top of a pad Part
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

-- Registers a player with their assigned plot model
-- plotModel: the cloned PlotTemplate model in workspace
-- Called by MatchManager after plot assignment
-- Passing plotModel here means this service never calls PlotManager
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

-- Removes all tracking for a player
-- Physical models are destroyed automatically when the plot clone is destroyed
-- so we only need to clear the reference table here
function MachineSpawnService.removePlayer(player : Player)
    playerData[player.UserId] = nil
end

-- Spawns an UNDER_CONSTRUCTION placeholder on the pad
-- Called by MachineService immediately after purchase is committed
-- Visual: yellow neon box — clearly signals "being built"
-- ProximityPrompt is disabled during construction so player cannot interact
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

    local visual = MACHINE_VISUALS[machineType]
    if not visual then
        warn("MachineSpawnService.spawnMachine: unknown machineType: " .. machineType)
        return
    end

    -- Disable pad ProximityPrompt — pad is now occupied
    local padPrompt = pad:FindFirstChildOfClass("ProximityPrompt")
    if padPrompt then
        padPrompt.Enabled = false
    end

    -- Create placeholder Part
    local part              = Instance.new("Part")
    part.Name               = padId .. "_Machine"
    part.Size               = visual.size
    part.BrickColor         = CONSTRUCTION_VISUAL.color
    part.Material           = CONSTRUCTION_VISUAL.material
    part.Anchored           = true
    part.CanCollide         = false
    part.TopSurface         = Enum.SurfaceType.Smooth
    part.BottomSurface      = Enum.SurfaceType.Smooth
    positionOnPad(part, pad)

    -- Parent to pad so PadController can detect it via ChildAdded
    part.Parent = pad

    -- Store reference for later updates
    data.parts[padId] = part
end

-- Transitions machine from construction to active appearance
-- Called by MachineService after CONSTRUCTION_DURATION elapses
-- Visual changes from yellow neon to machine type color
-- ProximityPrompt added so player can now inspect and upgrade
function MachineSpawnService.setMachineActive(
    player      : Player,
    padId       : string,
    machineType : string
)
    local data = playerData[player.UserId]
    if not data then return end

    local part = data.parts[padId]
    if not part then
        warn("MachineSpawnService.setMachineActive: no spawned machine for: "
            .. padId .. " (" .. player.DisplayName .. ")")
        return
    end

    local visual = MACHINE_VISUALS[machineType]
    if not visual then return end

    -- Apply active appearance
    part.BrickColor = visual.color
    part.Material   = visual.material

    -- Add ProximityPrompt — player can now interact with this machine
    local prompt                    = Instance.new("ProximityPrompt")
    prompt.ActionText               = PlotConfig.BUILT_MACHINE_ACTION_TEXT
    prompt.ObjectText               = machineType
    prompt.KeyboardKeyCode          = Enum.KeyCode.E
    prompt.MaxActivationDistance    = PlotConfig.PROMPT_DISTANCE
    prompt.HoldDuration             = PlotConfig.PROMPT_HOLD_DURATION
    prompt.Parent                   = part

    -- ProximityPrompt parented to part triggers PadController.ChildAdded
    -- PadController connects inspect logic dynamically
end

-- Updates machine appearance after an upgrade is applied
-- Material changes to Neon to visually distinguish upgraded machines
-- ProximityPrompt text updated to show the chosen branch
function MachineSpawnService.updateUpgraded(
    player      : Player,
    padId       : string,
    machineType : string,
    branch      : string
)
    local data = playerData[player.UserId]
    if not data then return end

    local part = data.parts[padId]
    if not part then return end

    -- Neon material clearly signals this machine is upgraded
    part.Material = Enum.Material.Neon

    -- Update ProximityPrompt to show chosen branch
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        prompt.ObjectText = machineType .. " [" .. branch .. "]"
    end
end

-- Destroys a machine model and re-enables the pad's ProximityPrompt
-- Not used in MVP but available for a future sell or demolish mechanic
function MachineSpawnService.despawnMachine(player : Player, padId : string)
    local data = playerData[player.UserId]
    if not data then return end

    local part = data.parts[padId]
    if part then
        part:Destroy()
        data.parts[padId] = nil
    end

    -- Re-enable pad ProximityPrompt so it can be built on again
    local pad = getPadPart(player.UserId, padId)
    if pad then
        local padPrompt = pad:FindFirstChildOfClass("ProximityPrompt")
        if padPrompt then
            padPrompt.Enabled = true
        end
    end
end

return MachineSpawnService