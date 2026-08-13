local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")

local SprintController = {}

local WALK_SPEED   = 16
local SPRINT_SPEED = 26
local player        = Players.LocalPlayer

local function getHumanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function setSprinting(isSprinting : boolean)
    local humanoid = getHumanoid()
    if humanoid then
        humanoid.WalkSpeed = isSprinting and SPRINT_SPEED or WALK_SPEED
    end
end

function SprintController.init()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.LeftShift
            or input.KeyCode == Enum.KeyCode.LeftControl then
            setSprinting(true)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.LeftShift
            or input.KeyCode == Enum.KeyCode.LeftControl then
            setSprinting(false)
        end
    end)
end

return SprintController