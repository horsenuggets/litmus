local package = script.Parent

local graph = require(package.Graph)
local node = require(package.Node)
local scope = require(package.Scope)
local types = require(package.Types)

type Capture = types.Capture
type Computed<T> = types.Computed<T>
type Scope = types.Scope
type ScopeInternal = types.ScopeInternal
type Use = types.Use

local capture = {}
capture.__index = capture
setmetatable(capture, node)

local function new(owner: ScopeInternal, callback: (Use, Scope) -> any, execution: "eager" | "lazy"): Capture
    local self: Capture = setmetatable(node.new(), capture) :: any
    self._execution = execution

    self._inner = scope.derive(owner)
    self._capture = callback

    self._use = function(dependency: any): any
        if not types.isNode(dependency) then
            return dependency
        end

        graph.depend(self, dependency)
        graph.evaluate(dependency)
        return dependency._value
    end

    owner:insert(self)
    graph.evaluate(self)

    return self
end

function capture.computed<T, S>(owner: S, callback: (Use, S) -> T): Computed<T>
    return new(owner, callback, "lazy")
end

function capture.effect<S>(owner: S, callback: (Use, S) -> ()): ()
    new(owner, callback, "eager")
end

function capture.update(self: Capture): boolean
    local ok: boolean, result: any = graph.runCapture(self)
    if not ok then
        warn(`[Flux]: error while running capture: {result}`)
        return false
    end

    local meaningfullyChanged: boolean = graph.changed(self._value, result)
    self._value = result

    return meaningfullyChanged
end

function capture.destroy(self: Capture): ()
    node.destroy(self)
    self._inner:destroy()
end

return capture
