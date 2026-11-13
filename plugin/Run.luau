local replicatedStorage = game:GetService("ReplicatedStorage")

local LIB_NAME: string = "Litmus"

local function moduleIn(parent: Instance, name: string): ModuleScript
    local found: Instance? = parent:FindFirstChild(name)
    if not found or not found:IsA("ModuleScript") then
        error(`[Litmus]: {parent:GetFullName()} has no module named {name}`, 0)
    end

    return found
end

-- Loads a module that requires nothing, straight from its source so Studio's require cache stays out of it
local function loadAlone(module: ModuleScript): any
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(module.Source, `={module:GetFullName()}`)
    if not chunk then
        error(`[Litmus]: {module:GetFullName()} didn't compile: {problem}`, 0)
    end

    return chunk()
end

local run = {}

-- Runs through the place's own copy of the lib, so the specs and the runner share one
function run.specs(specs: { Instance }): any
    local lib: ModuleScript = moduleIn(replicatedStorage, LIB_NAME)

    local loader: any = loadAlone(moduleIn(lib, "Loader"))
    local session: any = loader.new(loadAlone(moduleIn(lib, "External")))

    local litmus: any = session:require(lib)
    return litmus.run(session, specs)
end

return run
