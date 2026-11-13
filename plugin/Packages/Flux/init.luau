local package = script

local capture = require(package.Capture)
local context = require(package.Context)
local graph = require(package.Graph)
local instances = require(package.Instances)
local scope = require(package.Scope)
local spring = require(package.Spring)
local types = require(package.Types)
local value = require(package.Value)

export type Value<T> = types.Value<T>
export type Computed<T> = types.Computed<T>
export type Spring<T> = types.Spring<T>
export type Context<T> = types.Context<T>
export type Scope = types.Scope

export type UsedAs<T> = types.UsedAs<T>
export type Unwrap<T> = types.Unwrap<T>
export type Use = types.Use

export type HydrateProperties<T> = types.HydrateProperties<T>

-- Annotated so the implementations are checked against what Scope promises
local methods: Scope = {
    value = value.new,
    computed = capture.computed,
    effect = capture.effect,
    spring = spring.new,

    element = instances.element,
    hydrate = instances.hydrate,

    insert = scope.insert,
    inner = scope.inner,
    destroy = scope.destroy,

    -- The solver rejects `S & A` even against an identical signature
    with = scope.with :: any,
}

local rootMetatable = { __index = methods }

local function scoped(): Scope
    return scope.create(rootMetatable)
end

local flux = {
    scope = scoped,
    context = context.new,

    peek = graph.peek,
    batch = graph.batch,
}

return flux
