local collector = require("./Collector")
local failure = require("./Failure")
local report = require("./Report")

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
    results: ((specs: { SpecResult }) -> Remarks?)?,
}

export type Remarks = {
    appendix: { report.Piece }?,
    failure: string?,
}

export type Run = {
    specs: { SpecResult },
    appendix: { report.Piece }?,
    failure: string?,
}

export type Progress =
    { kind: "loading", spec: number }
    | { kind: "loaded", spec: number, tests: number }
    | { kind: "tested", spec: number, failed: boolean }
    | { kind: "finished", spec: number }
    | { kind: "settled" }

type Tell = (event: Progress) -> ()

-- A failure knows its script only by the name the chunk ran under, which the adapter turns back into the script
local function placed(adapter: Adapter, caught: failure.Failure?): Failure?
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

    return placed(adapter, caught)
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

local function runSpec(adapter: Adapter, spec: Spec, index: number, running: Running, tell: Tell): SpecResult
    collector.begin()
    tell({ kind = "loading", spec = index })

    local problem: Failure? = catch(adapter, spec.load)

    local collected: collector.Collected = collector.finish()
    local tests: { collector.Test } = if problem then {} else collected.tests
    local results: { TestResult } = {}
    local unfinished: number = #tests

    local afterResults: { TestResult } = {}
    for position, step in collected.afters do
        afterResults[position] = { name = step.name, groups = step.groups }
    end

    tell({ kind = "loaded", spec = index, tests = if problem then 0 else #tests + #afterResults })

    local function runAfters(): ()
        start(adapter, running, function(): ()
            for position, step in collected.afters do
                local failure: Failure? = catch(adapter, step.run)
                afterResults[position].failure = failure

                if not problem then
                    tell({ kind = "tested", spec = index, failed = failure ~= nil })
                end
            end

            tell({ kind = "finished", spec = index })
        end)
    end

    for _, test in tests do
        local result: TestResult = { name = test.name, groups = test.groups }
        table.insert(results, result)

        start(adapter, running, function(): ()
            result.failure = catch(adapter, test.run)
            tell({ kind = "tested", spec = index, failed = result.failure ~= nil })

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

local function remarksOf(adapter: Adapter, results: { SpecResult }): Remarks
    local describe: ((specs: { SpecResult }) -> Remarks?)? = adapter.results
    local remarks: unknown = if describe then describe(results) else nil

    if remarks == nil then
        return {}
    end

    if type(remarks) ~= "table" then
        error(`[Litmus]: the adapter's results returned a {type(remarks)}; they return a table, with an appendix and a failure, both optional`, 0)
    end

    local appendix: unknown = (remarks :: any).appendix
    if appendix ~= nil and type(appendix) ~= "table" then
        error(`[Litmus]: the adapter's results gave its appendix as a {type(appendix)}; an appendix is a list of pieces, and report.text makes one of plain text`, 0)
    end

    return remarks :: any
end

local runner = {}

-- The adapter's specs must require this copy of the lib, or they register with another
function runner.run(adapter: Adapter, observe: Tell?): Run
    local results: { SpecResult } = {}
    local running: Running = { count = 0, waiter = nil }

    local function tell(event: Progress): ()
        if observe then
            observe(event)
        end
    end

    for index, spec in adapter.specs do
        table.insert(results, runSpec(adapter, spec, index, running, tell))
    end

    waitFor(running)
    tell({ kind = "settled" })

    local remarks: Remarks = remarksOf(adapter, results)

    return {
        specs = results,
        appendix = remarks.appendix,
        failure = remarks.failure,
    }
end

return runner
