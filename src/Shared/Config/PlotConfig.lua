-- PlotConfig.lua
-- Owns: all plot and pad layout constants
-- Separate from MatchConfig intentionally:
--   MatchConfig = game rules (timers, economy, win condition)
--   PlotConfig  = world layout (positions, pad definitions, prompts)
-- If you rearrange plots or change pad counts, only this file changes

return {

    -- ── World positions for each plot clone ───────────────────────────────
    -- Plots arranged in two rows of four, 80 studs apart
    -- Adjust these if you want plots closer together or further apart
    PLOT_POSITIONS = {
        Plot1 = Vector3.new(-120, 0, -40),
        Plot2 = Vector3.new(-40,  0, -40),
        Plot3 = Vector3.new(40,   0, -40),
        Plot4 = Vector3.new(120,  0, -40),
        Plot5 = Vector3.new(-120, 0,  40),
        Plot6 = Vector3.new(-40,  0,  40),
        Plot7 = Vector3.new(40,   0,  40),
        Plot8 = Vector3.new(120,  0,  40),
    },

    -- ── Pad naming convention ─────────────────────────────────────────────
    -- Server reads pad names from PlotTemplate using this pattern
    -- Extracts machine type prefix: "HarvesterPad1" → "Harvester"
    PAD_NAME_PATTERN = "(%a+)Pad%d+",

    -- ── Pad counts per machine type ───────────────────────────────────────
    -- Must match the number of pads you place in PlotTemplate
    -- and the maxCopies values in MachineConfig
    PAD_COUNTS = {
        Harvester   = 5,
        Assembler   = 4,
        Fabricator  = 3,
    },

    -- ── Construction duration ─────────────────────────────────────────────
    -- How long a pad stays in UNDER_CONSTRUCTION state before
    -- transitioning to ACTIVE
    -- Set to 0 for instant builds during early testing
    CONSTRUCTION_DURATION = 1.5,    -- seconds

    -- ── ProximityPrompt settings ──────────────────────────────────────────
    PROMPT_DISTANCE = 8,            -- studs, how close player must be
    PROMPT_HOLD_DURATION = 0,       -- seconds held before triggering
                                    -- 0 = instant on press

    -- ── Empty pad prompt text ─────────────────────────────────────────────
    -- Shown on pads that have no machine yet
    -- {type} and {cost} are replaced at runtime
    EMPTY_PAD_ACTION_TEXT   = "Build",
    EMPTY_PAD_OBJECT_TEXT   = "{type} — ${cost}",

    -- ── Built machine prompt text ─────────────────────────────────────────
    BUILT_MACHINE_ACTION_TEXT   = "Inspect",
    BUILT_MACHINE_OBJECT_TEXT   = "{type}",
}