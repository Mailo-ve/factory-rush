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
    {
        id          = "Blackout",
        name        = "Power Outage",
        description = "The grid has failed! Restore power at both generators before it's too late.",
        duration    = 30,
    },
    {
        id          = "FloorIsLava",
        name        = "Floor Is Lava",
        description = "The factory floor is electrified! Get to a pad or machine immediately.",
        duration    = 30,
    },
    {
        id          = "FactoryEvacuation",
        name        = "Factory Evacuation",
        description = "Alarms are sounding! Evacuate to the marked safe zone immediately.",
        duration    = 15,
    }
}