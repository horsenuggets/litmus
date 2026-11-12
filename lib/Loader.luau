-- Requires nothing, so an entry point can load this alone and load everything else through it

export type ReadSource = (module: ModuleScript) -> string

-- Boxed because a module can return nil
type Loaded = { value: any }

type Link = {
    module: ModuleScript,
    requirer: Link?,
}

-- The chain of requires leading back to `module`, if it's still loading further up
local function findCycle(requirer: Link?, module: ModuleScript): string?
    local names: { string } = { module:GetFullName() }
    local link: Link? = requirer

    while link do
        table.insert(names, 1, link.module:GetFullName())

        if link.module == module then
            return table.concat(names, " -> ")
        end

        link = link.requirer
    end

    return nil
end

local function resolvePath(from: ModuleScript, path: string): Instance?
    local names: { string } = string.split(path, "/")
    local root: string = names[1]
    local parent: Instance? = from.Parent

    local current: Instance? = nil
    if root == "@self" then
        current = from
    elseif root == "@game" then
        current = game
    elseif root == "." then
        current = parent
    elseif root == ".." then
        current = parent and parent.Parent
    else
        error(`[Litmus]: {from:GetFullName()} required "{path}"; a path starts with ./, ../, @self or @game`, 0)
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

local function resolve(from: ModuleScript, target: unknown): ModuleScript
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

local loader = {}
loader.__index = loader

type Members = {
    _readSource: ReadSource,
    _loaded: { [ModuleScript]: Loaded },
    _globals: { [any]: any },
}

export type Class = setmetatable<Members, typeof(loader)>

function loader.new(readSource: ReadSource): Class
    local self: Class = (setmetatable({}, loader) :: any)
    self._readSource = readSource
    self._loaded = {}
    self._globals = {}
    return self
end

function loader._run(self: Class, module: ModuleScript, requirer: Link?): { n: number, [number]: any }
    -- The "=" makes errors and tracebacks print the name bare, as they do for a real script
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(self._readSource(module), `={module:GetFullName()}`)
    if not chunk then
        error(problem, 0)
    end

    local link: Link = { module = module, requirer = requirer }

    local environment: { [string]: any } = setmetatable({
        require = function(target: unknown): any
            return self:_load(resolve(module, target), link)
        end,
        script = module,
        _G = self._globals,
    }, { __index = getfenv(chunk) }) :: any

    setfenv(chunk, environment)

    return table.pack(chunk())
end

function loader._load(self: Class, module: ModuleScript, requirer: Link?): any
    local loaded: Loaded? = self._loaded[module]
    if loaded then
        return loaded.value
    end

    local cycle: string? = findCycle(requirer, module)
    if cycle then
        error(`[Litmus]: modules require each other in a cycle: {cycle}`, 0)
    end

    local results: { n: number, [number]: any } = self:_run(module, requirer)
    if results.n ~= 1 then
        error(`[Litmus]: {module:GetFullName()} returned {results.n} values; a module must return exactly one`, 0)
    end

    self._loaded[module] = { value = results[1] }
    return results[1]
end

function loader.require(self: Class, module: ModuleScript): any
    return self:_load(module, nil)
end

-- For a spec: runs it for what it registers, caching nothing and ignoring what it returns
function loader.execute(self: Class, module: ModuleScript): ()
    self:_run(module, nil)
end

return loader
