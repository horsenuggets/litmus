local replicatedStorage = game:GetService("ReplicatedStorage")

local outcome = require("./Outcome")

local LIB_NAME: string = "Litmus"

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

local function runThroughLib(roots: { Instance }): outcome.LibRun
    local lib: ModuleScript = moduleIn(replicatedStorage, LIB_NAME)
    local entry: ModuleScript = moduleIn(folderIn(lib, "Adapter"), "Roblox")

    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
    if not chunk then
        error(`[Litmus]: {entry:GetFullName()} didn't compile: {problem}`, 0)
    end

    return chunk().run(lib, roots)
end

local harness = {}

function harness.specs(roots: { Instance }): outcome.Run
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

function harness.all(): outcome.Run
    local roots: { Instance } = {}

    for _, name in CODE_SERVICES do
        table.insert(roots, game:GetService(name))
    end

    local ran: outcome.Run = harness.specs(roots)
    if ran.kind == "results" and #ran.specs == 0 then
        return { kind = "problem", message = NO_SPECS }
    end

    return ran
end

return harness
