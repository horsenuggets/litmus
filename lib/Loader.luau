-- Requires nothing, so an entry point can load this alone and load everything else through it

-- A host's own handle for a module; `any` so each host can type it as what it really is
export type Module = any

-- What the lib needs from the platform it runs on; External is the implementation
export type Host = {
    name: (module: Module) -> string,
    resolve: (from: Module, target: unknown) -> Module,
    load: (module: Module, globals: { [string]: any }) -> (...any) -> ...any,
    findSpecs: (roots: { any }) -> { Module },
}

-- Boxed because a module can return nil
type Loaded = { value: any }

type Link = {
    module: Module,
    requirer: Link?,
}

local loader = {}
loader.__index = loader

type Members = {
    _host: Host,
    _loaded: { [Module]: Loaded },
    _globals: { [any]: any },
}

export type Class = setmetatable<Members, typeof(loader)>

function loader.new(host: Host): Class
    local self: Class = (setmetatable({}, loader) :: any)
    self._host = host
    self._loaded = {}
    self._globals = {}
    return self
end

-- The chain of requires leading back to `module`, if it's still loading further up
function loader._findCycle(self: Class, requirer: Link?, module: Module): string?
    local names: { string } = { self._host.name(module) }
    local link: Link? = requirer

    while link do
        table.insert(names, 1, self._host.name(link.module))

        if link.module == module then
            return table.concat(names, " -> ")
        end

        link = link.requirer
    end

    return nil
end

function loader._run(self: Class, module: Module, requirer: Link?): { n: number, [number]: any }
    local link: Link = { module = module, requirer = requirer }

    local chunk: (...any) -> ...any = self._host.load(module, {
        require = function(target: unknown): any
            return self:_load(self._host.resolve(module, target), link)
        end,
        _G = self._globals,
    })

    return table.pack(chunk())
end

function loader._load(self: Class, module: Module, requirer: Link?): any
    local loaded: Loaded? = self._loaded[module]
    if loaded then
        return loaded.value
    end

    local cycle: string? = self:_findCycle(requirer, module)
    if cycle then
        error(`[Litmus]: modules require each other in a cycle: {cycle}`, 0)
    end

    local results: { n: number, [number]: any } = self:_run(module, requirer)
    if results.n ~= 1 then
        error(`[Litmus]: {self._host.name(module)} returned {results.n} values; a module must return exactly one`, 0)
    end

    self._loaded[module] = { value = results[1] }
    return results[1]
end

function loader.require(self: Class, module: Module): any
    return self:_load(module, nil)
end

-- For a spec: runs it for what it registers, caching nothing and ignoring what it returns
function loader.execute(self: Class, module: Module): ()
    self:_run(module, nil)
end

return loader
