local package = script.Parent
local modules = package.Parent

local doCleaning = require(modules.DoCleaning)
local types = require(package.Types)

type Scope = types.Scope
type ScopeInternal = types.ScopeInternal

type Metatable = { __index: any }

local function create(metatable: Metatable, parent: ScopeInternal?): ScopeInternal
    return setmetatable({ _tasks = {}, _dead = false, _parent = parent }, metatable) :: any
end

-- For a node's capture scope, which the node owns rather than `parent`
local function derive(parent: ScopeInternal): ScopeInternal
    return create(getmetatable(parent :: any), parent)
end

local function insert<T>(self: Scope, job: T): T
    local scope: ScopeInternal = types.internal(self)
    if scope._dead then
        doCleaning(job)
        error("[Flux]: attempted to use a destroyed scope", 2)
    end

    table.insert(scope._tasks, job)
    return job
end

local function inner<S>(self: S): S
    local scope: ScopeInternal = self :: any
    return scope:insert(derive(scope)) :: any
end

local function with<S, A>(self: S, extra: A): S & A
    local scope: ScopeInternal = self :: any
    local metatable: Metatable = getmetatable(scope :: any)
    local index: any = setmetatable(table.clone(extra :: any), { __index = metatable.__index })

    return scope:insert(create({ __index = index }, scope)) :: any
end

local function destroy(self: Scope): ()
    local scope: ScopeInternal = types.internal(self)
    if scope._dead then
        return
    end

    scope._dead = true

    -- Ensure a long-lived parent doesn't collect scopes destroyed early
    local parent: ScopeInternal? = scope._parent
    if parent and not parent._dead then
        local index: number? = table.find(parent._tasks, scope)
        if index then
            table.remove(parent._tasks, index)
        end
    end

    doCleaning(scope._tasks)
end

return {
    create = create,
    derive = derive,

    insert = insert,
    inner = inner,
    with = with,
    destroy = destroy,
}
