export type Module = any

export type Host = {
    chunkName: (module: Module) -> string,
    resolve: (from: Module, target: unknown) -> Module,
    load: (module: Module, globals: { [string]: any }) -> (...any) -> ...any,
}

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
    _byChunk: { [string]: Module },
}

export type Class = setmetatable<Members, typeof(loader)>

function loader.new(host: Host): Class
    local self: Class = (setmetatable({}, loader) :: any)
    self._host = host
    self._loaded = {}
    self._byChunk = {}
    return self
end

function loader._findCycle(self: Class, requirer: Link?, module: Module): string?
    local names: { string } = { self._host.chunkName(module) }
    local link: Link? = requirer

    while link do
        table.insert(names, 1, self._host.chunkName(link.module))

        if link.module == module then
            return table.concat(names, " -> ")
        end

        link = link.requirer
    end

    return nil
end

function loader._run(self: Class, module: Module, requirer: Link?): { n: number, [number]: any }
    local link: Link = { module = module, requirer = requirer }

    self._byChunk[self._host.chunkName(module)] = module

    local chunk: (...any) -> ...any = self._host.load(module, {
        require = function(target: unknown): any
            return self:_load(self._host.resolve(module, target), link)
        end,
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
        error(`[Litmus]: {self._host.chunkName(module)} returned {results.n} values; a module must return exactly one`, 0)
    end

    self._loaded[module] = { value = results[1] }
    return results[1]
end

function loader.require(self: Class, module: Module): any
    return self:_load(module, nil)
end

function loader.moduleOf(self: Class, chunk: string): Module?
    return self._byChunk[chunk]
end

function loader.execute(self: Class, module: Module): ()
    self:_run(module, nil)
end

return loader
