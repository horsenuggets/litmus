local package = script.Parent
local modules = package.Parent

local doCleaning = require(modules.DoCleaning)
local types = require(package.Types)

type Node = types.Node
type Capture = types.Capture
type ScopeInternal = types.ScopeInternal
type UsedAs<T> = types.UsedAs<T>
type Unwrap<T> = types.Unwrap<T>

type Set<T> = { [T]: true }

-- Runtime
local pending: Set<Node> = {}
local changedNodes: { Node } = {}
local batched: boolean = false

-- Monotonic logical clock for node update times
local currentTime: number = 0
local function counter(): number
    local id: number = currentTime
    currentTime += 1
    return id
end

-- Tables are always treated as changed, even if the reference is identical
local function changed(old: any, new: any): boolean
    return old ~= new or typeof(new) == "table"
end

-- Dependency management
local function depend(dependent: Node, dependency: Node)
    if dependency._dead or dependent._dead then
        return
    end

    dependent._dependencies[dependency] = true
    dependency._dependents[dependent] = true
end

local function clearDependencies(node: Node): Set<Node>
    local oldDependencies = node._dependencies
    for dependency in oldDependencies do
        dependency._dependents[node] = nil
    end
    node._dependencies = {}
    return oldDependencies
end

-- Push-pull
local flush: () -> ()

local function push(node: Node)
    if not pending[node] then
        pending[node] = true
        table.insert(changedNodes, node)
    end
end

local function evaluate(node: Node): ()

    -- Dead nodes silently no-op: erroring here
    -- surfaces the symptom far from the cause
    if node._dead then
        return
    end

    if node._status == "busy" then
        error("[Flux]: cyclic dependency graph detected", 0)
    end

    if node._status == "current" then
        return
    end

    local firstEvaluation: boolean = node._time == nil
    local shouldUpdate: boolean = firstEvaluation

    -- Verify a dependency has meaningfully changed
    if not firstEvaluation then
        for dependency in node._dependencies do
            evaluate(dependency)
            if dependency._time > node._checked then
                shouldUpdate = true
                break
            end
        end
    end

    if not shouldUpdate then
        node._status = "current"
        return
    end

    -- Read before updating, so a value the capture sets on itself still counts as newer
    local started: number = counter()
    node._status = "busy"

    local meaningfullyChanged: boolean = node:update()
    node._status = "current"

    node._checked = started
    if firstEvaluation or meaningfullyChanged then
        node._time = counter()
    end

    -- Runs what the capture set, now that this node is in a consistent state
    flush()
end

function flush(): ()
    if batched or #changedNodes == 0 then
        return
    end

    local eager: { Node } = {}

    -- Grows as dependents are pushed
    local index: number = 1
    while index <= #changedNodes do
        local node: Node = changedNodes[index]
        index += 1

        if node._dead then
            continue
        end

        node._status = "invalid"
        if node._execution == "eager" then
            table.insert(eager, node)
        end

        for dependent in node._dependents do
            push(dependent)
        end
    end

    table.clear(changedNodes)
    table.clear(pending)

    for _, node in eager do
        evaluate(node)
    end
end

local function peek<T>(input: T): Unwrap<T>
    if not types.isNode(input) then
        return input
    end

    local readable: any = input
    evaluate(readable)
    
    return readable._value
end

local function batch(callback: () -> ()): ()
    local alreadyBatching: boolean = batched
    batched = true

    local ok: boolean, err: any = (xpcall :: any)(callback, debug.traceback)

    batched = alreadyBatching
    flush()

    if not ok then
        error(`[Flux]: error while executing batch callback:\n{err}`, 0)
    end
end

--[[
    Runs a capture safely. Effects release their tasks first, since they can
    hold exclusive resources. A computed keeps its until the new run succeeds,
    so its value and what that value relies on stay valid together. On failure
    the node keeps both its old dependencies and the new ones, to retry when
    any of them change.
]]
local function runCapture(node: Capture): (boolean, any)
    local oldDependencies: Set<Node> = clearDependencies(node)

    local inner: ScopeInternal = node._inner
    local previous: { any } = inner._tasks

    if node._execution == "eager" then
        doCleaning(previous)
    elseif next(previous) ~= nil then
        inner._tasks = {}
    end

    -- Sets made by the capture wait until it has returned
    local alreadyBatching: boolean = batched
    batched = true

    local ok: boolean, result: any = (xpcall :: any)(node._capture, debug.traceback, node._use, inner)

    batched = alreadyBatching

    if not ok then
        doCleaning(inner._tasks)
        inner._tasks = previous

        for dependency in oldDependencies do
            depend(node, dependency)
        end
    end

    -- Destroying a node mid-capture leaves `previous` for us
    if (ok and inner._tasks ~= previous) or node._dead then
        doCleaning(previous)
    end

    return ok, result
end

return {
    changed = changed,
    depend = depend,
    evaluate = evaluate,
    flush = flush,
    push = push,

    batch = batch,
    runCapture = runCapture,

    peek = peek,
    counter = counter,
}
