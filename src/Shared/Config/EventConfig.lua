-- EventConfig.lua
-- Owns: the pool of possible mid-match world events
-- One is picked at random roughly every EVENT_INTERVAL seconds
-- Pure metadata here — EventManager owns what each id actually does

return {
    {
        id          = "AllMachinesBreak",
        name        = "Factory Malfunction",
        description = "Every machine just broke down at once — get repairing!",
        duration    = 0,
    },
    {
        id          = "ResourceSurge",
        name        = "Resource Surge",
        description = "Resource caches have appeared everywhere on the map",
        duration    = 20,
    },
}