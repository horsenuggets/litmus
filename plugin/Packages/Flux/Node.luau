local package = script.Parent

local types = require(package.Types)

type Node = types.Node

local node = {}
node.__index = node

function node.new(): Node
    local self: Node = setmetatable({}, node) :: any
    self._execution = "lazy"
    self._status = "invalid"

    self._dead = false
    self._dependencies = {}
    self._dependents = {}

    return self
end

function node.update(self: Node): boolean
    return true
end

function node.destroy(self: Node): ()
    if self._dead then
        return
    end

    self._dead = true

    for dependency in self._dependencies do
        dependency._dependents[self] = nil
    end

    for dependent in self._dependents do
        dependent._dependencies[self] = nil
    end

    table.clear(self._dependencies)
    table.clear(self._dependents)
end

return node
