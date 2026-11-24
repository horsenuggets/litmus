local httpService = game:GetService("HttpService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local LIB_NAME: string = "Litmus"

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
local entry: ModuleScript = moduleIn(find({ replicatedStorage.Name, LIB_NAME, "Adapter" }), "Roblox")

local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
if not chunk then
    error(`[Litmus]: {entry:GetFullName()} didn't compile: {problem}`, 0)
end

return httpService:JSONEncode(chunk().run(lib, specs))
