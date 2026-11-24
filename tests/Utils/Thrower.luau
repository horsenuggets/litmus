local function thrower(): never
    error("thrown from a helper")
end

return thrower
