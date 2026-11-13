-- Stays at 1 unless a run reuses another run's _G or loads this module twice
_G.environmentLoads = (_G.environmentLoads or 0) + 1

local environment = {
    script = script,
}

return environment
