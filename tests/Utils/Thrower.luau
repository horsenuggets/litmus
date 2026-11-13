-- Throws from here, so a failure can be seen pointing at a module other than the spec
local function thrower(): never
    error("thrown from a helper")
end

return thrower
