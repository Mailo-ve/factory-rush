local ContextActionService = game:GetService("ContextActionService")
local Players               = game:GetService("Players")

local SprintController = {}

local WALK_SPEED   = 16
local SPRINT_SPEED = 26
local player        = Players.LocalPlayer

local function getHumanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function handleSprint(actionName, inputState)
    local humanoid = getHumanoid()
    if not humanoid then return Enum.ContextActionResult.Pass end

    if inputState == Enum.UserInputState.Begin then
        humanoid.WalkSpeed = SPRINT_SPEED
    elseif inputState == Enum.UserInputState.End then
        humanoid.WalkSpeed = WALK_SPEED
    end

    return Enum.ContextActionResult.Pass
end

function SprintController.init()
    ContextActionService:BindAction(
        "Sprint",
        handleSprint,
        true,  -- createTouchButton
        Enum.KeyCode.LeftShift,
        Enum.KeyCode.LeftControl
    )
    ContextActionService:SetTitle("Sprint", "Sprint")
end

return SprintController