-- MaintenanceConfig.lua
-- Owns: all tuning values for the machine efficiency/maintenance system

return {
    STARTING_EFFICIENCY = 100,   -- efficiency a freshly-built machine starts at
    DECAY_RATE           = 0.75,  -- efficiency lost per second while active
    EFFICIENCY_FLOOR      = 50,    -- steady decay never drops below this
    WARNING_THRESHOLD     = 75,    -- below this, show the visual warning indicator

    BREAKDOWN_CHANCE_PER_TICK = 0.02,  -- chance per second a healthy machine fully breaks
    BREAKDOWN_EFFICIENCY      = 0,      -- efficiency set to this when a breakdown hits
}