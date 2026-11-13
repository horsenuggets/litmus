local package = script.Parent

local graph = require(package.Graph)
local node = require(package.Node)
local types = require(package.Types)

type Scope = types.Scope
type Value<T> = types.Value<T>

local value = {}
value.__index = value

setmetatable(value, node)

function value.new<T>(scope: Scope, initial: T): Value<T>
    local self: Value<T> = setmetatable(node.new(), value) :: any
    self._status = "current"
    self._time = graph.counter()
    self._value = initial

    scope:insert(self)

    return self
end

function value.set<T>(self: Value<T>, new: T): ()
    if self._dead then
        error("[Flux]: attempted to set dead node")
    end

    if graph.changed(self._value, new) then
        self._value = new
        self._time = graph.counter()

        graph.push(self)
        graph.flush()
    end
end

return value
