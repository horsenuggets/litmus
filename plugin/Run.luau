local replicatedStorage = game:GetService("ReplicatedStorage")

local outcome = require("./Outcome")

local LIB_NAME: string = "Litmus"

-- Where a place keeps its code, and so where its specs can be; the rest of the DataModel holds places a plugin can't read
local CODE_SERVICES: { string } = {
    "Workspace",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
}

local NO_SPECS: string = "This place has no .spec modules to run."
local BUSY: string = "Another run is still going."

-- Held for as long as a run takes, which is longer than one step only if a test yields
local running: boolean = false

local function moduleIn(parent: Instance, name: string): ModuleScript
    local found: Instance? = parent:FindFirstChild(name)
    if not found or not found:IsA("ModuleScript") then
        error(`[Litmus]: {parent:GetFullName()} has no module named {name}`, 0)
    end

    return found
end

local function folderIn(parent: Instance, name: string): Instance
    local found: Instance? = parent:FindFirstChild(name)
    if not found then
        error(`[Litmus]: {parent:GetFullName()} has nothing named {name}`, 0)
    end

    return found
end

-- Goes through the place's own copy of the lib, so the specs and the runner share one
local function runThroughLib(roots: { Instance }): outcome.LibRun
    local lib: ModuleScript = moduleIn(replicatedStorage, LIB_NAME)
    local entry: ModuleScript = moduleIn(folderIn(lib, "Adapter"), "Roblox")

    -- Loaded straight from its source, so Studio's require cache stays out of it
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
    if not chunk then
        error(`[Litmus]: {entry:GetFullName()} didn't compile: {problem}`, 0)
    end

    return chunk().run(lib, roots)
end

local run = {}

-- Runs every spec under `roots`, a spec being a root itself or anything beneath one
-- Never throws: a run that couldn't happen comes back as the problem that stopped it
function run.specs(roots: { Instance }): outcome.Run
    if running then
        return { kind = "problem", message = BUSY }
    end

    running = true
    local ok: boolean, result: any = pcall(runThroughLib, roots)
    running = false

    if not ok then
        return { kind = "problem", message = tostring(result) }
    end

    return outcome.ofLib(result)
end

-- Runs every spec the place has, for a run nobody handed a list to
function run.all(): outcome.Run
    local roots: { Instance } = {}

    for _, name in CODE_SERVICES do
        table.insert(roots, game:GetService(name))
    end

    local ran: outcome.Run = run.specs(roots)
    if ran.kind == "results" and #ran.specs == 0 then
        return { kind = "problem", message = NO_SPECS }
    end

    return ran
end

return run
