local collector = require("./Collector")
local failure = require("./Failure")
local loader = require("./Loader")

-- Annotated so analysis fails here if External stops providing what Host asks for
local external: loader.Host = require("./External")

export type Failure = {
    message: string,

    -- The names leading to the script from the top of the place
    source: { string },
    line: number,
    trace: string,
}

export type TestResult = {
    name: string,
    groups: { string },
    failure: Failure?,
}

export type SpecResult = {
    path: { string },
    tests: { TestResult },

    -- Set when the spec itself didn't load, in which case none of its tests ran
    failure: Failure?,
}

-- A failure knows its script only by the name the chunk ran under, which the session turns back into the script
local function report(session: loader.Class, caught: failure.Failure?): Failure?
    if not caught then
        return nil
    end

    local module: loader.Module? = session:named(caught.source)

    return {
        message = caught.message,

        -- A chunk the session never ran has nothing but that name to go by
        source = if module ~= nil then external.path(module) else { caught.source },
        line = caught.line,
        trace = caught.trace,
    }
end

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
                failure = report(session, failure.catch(test.run)),
            })
        end
    end

    return {
        path = external.path(spec),
        tests = results,
        failure = report(session, problem),
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
