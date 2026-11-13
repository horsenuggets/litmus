-- Everything specific to Roblox lives here, so running elsewhere means swapping this one file
-- Requires nothing, so an entry point can load this alone before any session exists

local SPEC_SUFFIX: string = ".spec"

local function resolvePath(from: ModuleScript, path: string): Instance?
    local names: { string } = string.split(path, "/")
    local root: string = names[1]
    local parent: Instance? = from.Parent

    local rootToInstance: { [string]: Instance? } = {
        ["@self"] = from,
        ["@game"] = game,

        ["."] = parent,
        [".."] = parent and parent.Parent,
    }

    local current: Instance? = rootToInstance[root]
    if not current then
        error(`[Litmus]: {from:GetFullName()} required "{path}", but "{root}" leads nowhere; a path starts with ./, ../, @self or @game`, 0)
    end

    for index = 2, #names do
        if not current then
            break
        end

        local name: string = names[index]
        current = if name == ".." then current.Parent else current:FindFirstChild(name)
    end

    return current
end

local function addIfSpec(specs: { ModuleScript }, instance: Instance): ()
    if instance:IsA("ModuleScript") and string.sub(instance.Name, -#SPEC_SUFFIX) == SPEC_SUFFIX then
        table.insert(specs, instance)
    end
end

local external = {}

function external.name(module: ModuleScript): string
    return module:GetFullName()
end

function external.resolve(from: ModuleScript, target: unknown): ModuleScript
    local found: Instance? = nil
    if typeof(target) == "Instance" then
        found = target
    elseif type(target) == "string" then
        found = resolvePath(from, target)
    end

    if not found or not found:IsA("ModuleScript") then
        error(`[Litmus]: {from:GetFullName()} required "{tostring(target)}", which isn't a ModuleScript`, 0)
    end

    return found
end

function external.load(module: ModuleScript, globals: { [string]: any }): (...any) -> ...any
    -- The "=" makes errors and tracebacks print the name bare, as they do for a real script
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(module.Source, `={module:GetFullName()}`)
    if not chunk then
        error(problem, 0)
    end

    local environment: { [string]: any } = table.clone(globals)
    environment.script = module

    setfenv(chunk, setmetatable(environment, { __index = getfenv(chunk) }) :: any)

    return chunk
end

function external.findSpecs(roots: { Instance }): { ModuleScript }
    local specs: { ModuleScript } = {}

    for _, root in roots do
        addIfSpec(specs, root)

        for _, descendant in root:GetDescendants() do
            addIfSpec(specs, descendant)
        end
    end

    table.sort(specs, function(a: ModuleScript, b: ModuleScript): boolean
        return a:GetFullName() < b:GetFullName()
    end)

    return specs
end

return external
