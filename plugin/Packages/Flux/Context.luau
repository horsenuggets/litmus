local package = script.Parent

local types = require(package.Types)

type Context<T> = types.Context<T>
type Scope = types.Scope
type ScopeInternal = types.ScopeInternal

local context = {}
context.__index = context

function context.new<T>(default: T): Context<T>
    local self: Context<T> = setmetatable({}, context) :: any
    self._default = default
    return self
end

-- Seen by `scope`, and everything under it
function context.provide<T>(self: Context<T>, scope: Scope, provided: T): ()
    local target: ScopeInternal = types.internal(scope)

    local provisions: { [any]: any } = target._context or {}
    provisions[self] = provided
    target._context = provisions
end

function context.consume<T>(self: Context<T>, scope: Scope): T
    local current: ScopeInternal? = types.internal(scope)
    while current do
        local provisions: { [any]: any }? = current._context
        if provisions and provisions[self] ~= nil then
            return provisions[self]
        end

        current = current._parent
    end

    return self._default
end

return context
