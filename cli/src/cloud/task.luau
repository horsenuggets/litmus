local httpService = game:GetService("HttpService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local LIB_NAME: string = "Litmus"

-- The CLI wraps this file in a function and calls it with the specs to run, as JSON
local specsJson: string = ...

local function moduleIn(parent: Instance, name: string): ModuleScript
    local found: Instance? = parent:FindFirstChild(name)
    if not found or not found:IsA("ModuleScript") then
        error(`[Litmus]: {parent:GetFullName()} has no module named {name}`, 0)
    end

    return found
end

local function find(path: { string }): Instance
    local current: Instance? = game

    for _, name in path do
        if not current then
            break
        end

        current = current:FindFirstChild(name)
    end

    if not current then
        error(`[Litmus]: the place has nothing at {table.concat(path, ".")}`, 0)
    end

    return current
end

local specs: { Instance } = {}
for _, path in httpService:JSONDecode(specsJson) do
    table.insert(specs, find(path))
end

local lib: ModuleScript = moduleIn(replicatedStorage, LIB_NAME)
local entry: ModuleScript = moduleIn(lib, "External")

local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
if not chunk then
    error(`[Litmus]: {entry:GetFullName()} didn't compile: {problem}`, 0)
end

-- Encoded here and not left to Open Cloud, so the results reach the CLI in the form the plugin sends them
return httpService:JSONEncode(chunk().run(lib, specs))
