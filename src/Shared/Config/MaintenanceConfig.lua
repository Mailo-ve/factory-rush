-- MaintenanceConfig.lua
-- Owns: all tuning values for the machine efficiency/maintenance system

return {
    STARTING_EFFICIENCY = 100,
    DECAY_RATE           = 0.25,
    EFFICIENCY_FLOOR      = 50,
    WARNING_THRESHOLD     = 60,

    BREAKDOWN_CHANCE_PER_TICK    = 0.01,
    BREAKDOWN_EFFICIENCY         = 0,
    BROKEN_HOLD_DURATION          = 2.5,   -- NEW: seconds to hold E when fully broken down

    DECAY_ONSET_CHANCE_PER_TICK  = 0.02,   -- NEW: chance per tick a healthy machine starts decaying (2× breakdown)
}