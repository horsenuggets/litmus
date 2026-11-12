export type Test = {
    name: string,
    groups: { string },
    run: () -> (),
}

-- Set only while a spec loads, so a call at any other time fails instead of vanishing
local collecting: { Test }? = nil
local groups: { string } = {}

local collector = {}

function collector.test(name: string, run: () -> ()): ()
    if not collecting then
        error("[Litmus]: test called outside a spec", 2)
    end

    table.insert(collecting, { name = name, groups = table.clone(groups), run = run })
end

function collector.group(name: string, body: () -> ()): ()
    if not collecting then
        error("[Litmus]: group called outside a spec", 2)
    end

    table.insert(groups, name)
    body()
    table.remove(groups)
end

function collector.begin(): ()
    collecting = {}
    groups = {}
end

function collector.finish(): { Test }
    local tests: { Test }? = collecting
    if not tests then
        error("[Litmus]: finish called without begin")
    end

    collecting = nil
    return tests
end

return collector
