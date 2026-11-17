export type Test = {
    name: string,
    groups: { string },
    run: () -> (),
}

export type Collected = {
    tests: { Test },
    afters: { Test },
}

-- Set only while a spec loads, so a call at any other time fails instead of vanishing
local collecting: Collected? = nil
local groups: { string } = {}

local collector = {}

function collector.test(name: string, run: () -> ()): ()
    if not collecting then
        error("[Litmus]: test called outside a spec", 2)
    end

    table.insert(collecting.tests, { name = name, groups = table.clone(groups), run = run })
end

function collector.group(name: string, body: () -> ()): ()
    if not collecting then
        error("[Litmus]: group called outside a spec", 2)
    end

    table.insert(groups, name)
    body()
    table.remove(groups)
end

function collector.after(name: string, run: () -> ()): ()
    if not collecting then
        error("[Litmus]: after called outside a spec", 2)
    end

    if #groups > 0 then
        error("[Litmus]: after called inside a group; it covers the whole spec", 2)
    end

    local step: Test = { name = name, groups = {}, run = run }
    table.insert(collecting.afters, step)
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
