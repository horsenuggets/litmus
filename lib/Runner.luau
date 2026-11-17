local collector = require("./Collector")
local failure = require("./Failure")

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

export type Spec = {
    path: { string },
    load: () -> (),
}

export type Adapter = {
    specs: { Spec },
    locate: (chunk: string) -> { string }?,
    spawn: (run: (() -> ()) | thread) -> (),
    results: ((specs: { SpecResult }) -> string?)?,
}

export type Run = {
    specs: { SpecResult },
    appendix: string?,
}

-- A failure knows its script only by the name the chunk ran under, which the adapter turns back into the script
local function report(adapter: Adapter, caught: failure.Failure?): Failure?
    if not caught then
        return nil
    end

    return {
        message = caught.message,

        -- A chunk the adapter can't place has nothing but that name to go by
        source = adapter.locate(caught.source) or { caught.source },
        line = caught.line,
        trace = caught.trace,
    }
end

local function catch(adapter: Adapter, body: () -> ()): Failure?
    local caught: failure.Failure? = failure.catch(body, function(chunk: string): boolean
        return adapter.locate(chunk) ~= nil
    end)

    return report(adapter, caught)
end

type Running = {
    count: number,
    waiter: thread?,
}

local function start(adapter: Adapter, running: Running, body: () -> ()): ()
    running.count += 1

    adapter.spawn(function(): ()
        body()
        running.count -= 1

        if running.count == 0 and running.waiter then
            adapter.spawn(running.waiter)
        end
    end)
end

local function waitFor(running: Running): ()
    if running.count > 0 then
        running.waiter = coroutine.running()
        coroutine.yield()
    end
end

local function runSpec(adapter: Adapter, spec: Spec, running: Running): SpecResult
    collector.begin()

    local problem: Failure? = catch(adapter, spec.load)

    local collected: collector.Collected = collector.finish()
    local tests: { collector.Test } = if problem then {} else collected.tests
    local results: { TestResult } = {}
    local unfinished: number = #tests

    local afterResults: { TestResult } = {}
    for index, step in collected.afters do
        afterResults[index] = { name = step.name, groups = step.groups }
    end

    local function runAfters(): ()
        start(adapter, running, function(): ()
            for index, step in collected.afters do
                afterResults[index].failure = catch(adapter, step.run)
            end
        end)
    end

    for _, test in tests do
        local result: TestResult = { name = test.name, groups = test.groups }
        table.insert(results, result)

        start(adapter, running, function(): ()
            result.failure = catch(adapter, test.run)

            unfinished -= 1
            if unfinished == 0 then
                runAfters()
            end
        end)
    end

    if #tests == 0 then
        runAfters()
    end

    if not problem then
        table.move(afterResults, 1, #afterResults, #results + 1, results)
    end

    return {
        path = spec.path,
        tests = results,
        failure = problem,
    }
end

local runner = {}

-- The adapter's specs must require this copy of the lib, or they register with another
function runner.run(adapter: Adapter): Run
    local results: { SpecResult } = {}
    local running: Running = { count = 0, waiter = nil }

    for _, spec in adapter.specs do
        table.insert(results, runSpec(adapter, spec, running))
    end

    waitFor(running)

    local describe: ((specs: { SpecResult }) -> string?)? = adapter.results

    return {
        specs = results,
        appendix = if describe then describe(results) else nil,
    }
end

return runner
