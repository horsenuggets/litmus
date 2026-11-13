local replicatedStorage = game:GetService("ReplicatedStorage")

local LIB_NAME: string = "Litmus"

local function moduleIn(parent: Instance, name: string): ModuleScript
    local found: Instance? = parent:FindFirstChild(name)
    if not found or not found:IsA("ModuleScript") then
        error(`[Litmus]: {parent:GetFullName()} has no module named {name}`, 0)
    end

    return found
end

local run = {}

-- Runs through the place's own copy of the lib, so the specs and the runner share one
function run.specs(specs: { Instance }): any
    local lib: ModuleScript = moduleIn(replicatedStorage, LIB_NAME)
    local entry: ModuleScript = moduleIn(lib, "External")

    -- Loaded straight from its source, so Studio's require cache stays out of it
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
    if not chunk then
        error(`[Litmus]: {entry:GetFullName()} didn't compile: {problem}`, 0)
    end

    return chunk().run(lib, specs)
end

return run
