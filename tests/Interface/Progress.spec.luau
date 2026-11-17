local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local function adapterFor(loads: { () -> () }): litmus.Adapter
    local specs: { litmus.Spec } = {}
    for index, load in loads do
        specs[index] = { path = { `Inline{index}.spec` }, load = load }
    end

    return {
        specs = specs,

        locate = function(_: string): { string }?
            return nil
        end,

        spawn = function(run: (() -> ()) | thread): ()
            task.spawn(run)
        end,
    }
end

local function show(event: litmus.Progress): string
    if event.kind == "loaded" then
        return `loaded {event.spec} with {event.tests}`
    elseif event.kind == "tested" then
        return `tested {event.spec} {if event.failed then "failed" else "passed"}`
    elseif event.kind == "settled" then
        return "settled"
    end

    return `{event.kind} {event.spec}`
end

local function eventsOf(loads: { () -> () }): { string }
    local events: { string } = {}

    litmus.run(adapterFor(loads), function(event: litmus.Progress): ()
        table.insert(events, show(event))
    end)

    return events
end

test("reports a spec loading, each test finishing, and the spec finishing", function(): ()
    local events: { string } = eventsOf({
        function(): ()
            litmus.test("passes", function(): () end)

            litmus.test("fails", function(): ()
                error("boom")
            end)
        end,
    })

    expect.same(events, {
        "loading 1",
        "loaded 1 with 2",
        "tested 1 passed",
        "tested 1 failed",
        "finished 1",
        "settled",
    })
end)

test("counts an after among a spec's tests, and reports it last", function(): ()
    local events: { string } = eventsOf({
        function(): ()
            litmus.after("cleans up", function(): () end)
            litmus.test("passes", function(): () end)
        end,
    })

    expect.same(events, {
        "loading 1",
        "loaded 1 with 2",
        "tested 1 passed",
        "tested 1 passed",
        "finished 1",
        "settled",
    })
end)

test("reports a spec that fails to load as loaded with no tests", function(): ()
    local events: { string } = eventsOf({
        function(): ()
            litmus.after("cleans up", function(): () end)
            litmus.test("never runs", function(): () end)

            error("boom")
        end,
    })

    expect.same(events, { "loading 1", "loaded 1 with 0", "finished 1", "settled" })
end)

test("numbers specs in the adapter's order, and loads the next while tests still wait", function(): ()
    local events: { string } = eventsOf({
        function(): ()
            litmus.test("waits", function(): ()
                task.wait(0.05)
            end)
        end,

        function(): () end,
    })

    expect.same(events, {
        "loading 1",
        "loaded 1 with 1",
        "loading 2",
        "loaded 2 with 0",
        "finished 2",
        "tested 1 passed",
        "finished 1",
        "settled",
    })
end)

test("reports that every test is done before the adapter gives its results", function(): ()
    local order: { string } = {}

    local adapter: litmus.Adapter = adapterFor({})
    adapter.results = function(_: { litmus.SpecResult }): litmus.Remarks?
        table.insert(order, "results")
        return nil
    end

    litmus.run(adapter, function(event: litmus.Progress): ()
        table.insert(order, event.kind)
    end)

    expect.same(order, { "settled", "results" })
end)

test("runs the same without anyone watching", function(): ()
    local ran: litmus.Run = litmus.run(adapterFor({
        function(): ()
            litmus.test("passes", function(): () end)
        end,
    }))

    expect.equal(#ran.specs[1].tests, 1)
end)
