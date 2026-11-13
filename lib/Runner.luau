local collector = require("./Collector")
local failure = require("./Failure")
local loader = require("./Loader")

-- Annotated so analysis fails here if External stops providing what Host asks for
local external: loader.Host = require("./External")

export type TestResult = {
    name: string,
    groups: { string },
    failure: failure.Failure?,
}

export type SpecResult = {
    path: string,
    tests: { TestResult },

    -- Set when the spec itself didn't load, in which case none of its tests ran
    failure: failure.Failure?,
}

local function runSpec(session: loader.Class, spec: loader.Module): SpecResult
    collector.begin()

    local problem: failure.Failure? = failure.catch(function(): ()
        session:execute(spec)
    end)

    local tests: { collector.Test } = collector.finish()
    local results: { TestResult } = {}

    if not problem then
        for _, test in tests do
            table.insert(results, {
                name = test.name,
                groups = test.groups,
                failure = failure.catch(test.run),
            })
        end
    end

    return {
        path = external.name(spec),
        tests = results,
        failure = problem,
    }
end

local runner = {}

-- `session` must be the one this lib was loaded through, or specs register with another copy
function runner.run(session: loader.Class, roots: { any }): { SpecResult }
    local results: { SpecResult } = {}

    for _, spec in external.findSpecs(roots) do
        table.insert(results, runSpec(session, spec))
    end

    return results
end

return runner
