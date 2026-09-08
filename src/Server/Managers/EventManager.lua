-- EventManager.lua
-- Owns: the recurring mid-match event timer and dispatching each
--       event's effect to the service that actually owns it
-- Exposes: startEvents, stopEvents
-- Does not: implement any event's actual effect itself — it only
--           picks one and hands off to PadService/ResourceService/etc.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local MatchConfig  = require(ReplicatedStorage.Shared.Config.MatchConfig)
local MatchEvent    = ReplicatedStorage.Shared.RemoteEvents.MatchEvent

local function getPadService()
    return require(ServerScriptService.Server.Services.PadService)
end
local function getResourceService()
    return require(ServerScriptService.Server.Services.ResourceService)
end

local EventManager = {}

local eventThread = nil

-- id → handler. Events with no lasting state (AllMachinesBreak) just
-- fire once; ones with a duration (ResourceSurge) hand their own
-- timing off to the relevant service rather than EventManager tracking it
local EVENT_HANDLERS = {
    AllMachinesBreak = function()
        getPadService().breakAllActiveMachines()
    end,
    ResourceSurge = function(event)
        getResourceService().startSurge(event.duration)
    end,
}

-- Starts the recurring event timer
-- Called by MatchManager when a match starts
function EventManager.startEvents()
    if eventThread then
        warn("EventManager.startEvents: already running, ignoring")
        return
    end

    eventThread = task.spawn(function()
        while true do
            task.wait(MatchConfig.EVENT_INTERVAL)

            local event   = EventConfig[math.random(1, #EventConfig)]
            local handler = EVENT_HANDLERS[event.id]

            MatchEvent:FireAllClients({
                action      = "WORLD_EVENT",
                eventName   = event.name,
                description = event.description,
            })

            if handler then
                handler(event)
            else
                warn("EventManager: no handler registered for event id: " .. event.id)
            end
        end
    end)
end

-- Called by MatchManager when a match ends
function EventManager.stopEvents()
    if eventThread then
        task.cancel(eventThread)
        eventThread = nil
    end
end

return EventManager