export type Test = {
    name: string,
    groups: { string },
    run: () -> (),
}

export type Collected = {
    tests: { Test },
    afters: { Test },
}

local collecting: Collected? = nil
local groups: { string } = {}

local function collectingFor(call: string): Collected
    local collected: Collected? = collecting
    if not collected then
        error(`[Litmus]: {call} called outside a spec`, 3)
    end

    return collected
end

local collector = {}

function collector.test(name: string, run: () -> ()): ()
    local collected: Collected = collectingFor("test")
    table.insert(collected.tests, { name = name, groups = table.clone(groups), run = run })
end

function collector.group(name: string, body: () -> ()): ()
    collectingFor("group")

    table.insert(groups, name)
    body()
    table.remove(groups)
end

function collector.after(name: string, run: () -> ()): ()
    local collected: Collected = collectingFor("after")

    if #groups > 0 then
        error("[Litmus]: after called inside a group; it covers the whole spec", 2)
    end

    local step: Test = { name = name, groups = {}, run = run }
    table.insert(collected.afters, step)
end

function collector.begin(): ()
    collecting = { tests = {}, afters = {} }
    groups = {}
end

function collector.finish(): Collected
    local collected: Collected? = collecting
    if not collected then
        error("[Litmus]: finish called without begin")
    end

    collecting = nil
    return collected
end

return collector
