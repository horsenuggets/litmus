local inline = require("../Utils/Inline")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

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

local function eventsOf(loads: { () -> () }, options: litmus.Options?): { string }
    local events: { string } = {}

    litmus.run(inline(loads), function(event: litmus.Progress): ()
        table.insert(events, show(event))
    end, options)

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

test("loads the next spec only once one finishes, when one spec may run at a time", function(): ()
    local events: { string } = eventsOf({
        function(): ()
            litmus.test("waits", function(): ()
                task.wait(0.05)
            end)
        end,

        function(): () end,
    }, { specsAtOnce = 1 })

    expect.same(events, {
        "loading 1",
        "loaded 1 with 1",
        "tested 1 passed",
        "finished 1",
        "loading 2",
        "loaded 2 with 0",
        "finished 2",
        "settled",
    })
end)

test("keeps as many specs running as the limit lets", function(): ()
    local function waits(seconds: number): () -> ()
        return function(): ()
            litmus.test("waits", function(): ()
                task.wait(seconds)
            end)
        end
    end

    local events: { string } = eventsOf({ waits(0.05), waits(0.15), function(): () end }, { specsAtOnce = 2 })

    expect.same(events, {
        "loading 1",
        "loaded 1 with 1",
        "loading 2",
        "loaded 2 with 1",
        "tested 1 passed",
        "finished 1",
        "loading 3",
        "loaded 3 with 0",
        "finished 3",
        "tested 2 passed",
        "finished 2",
        "settled",
    })
end)

test("refuses a limit that isn't a whole number from 1", function(): ()
    for _, limit in { 0, 1.5, "1" } do
        expect.error(function(): ()
            litmus.run(inline({}), nil, { specsAtOnce = limit :: any })
        end, `specsAtOnce is {limit}`)
    end
end)

test("reports that every test is done before the adapter gives its results", function(): ()
    local order: { string } = {}

    local adapter: litmus.Adapter = inline({})
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
    local ran: litmus.Run = litmus.run(inline({
        function(): ()
            litmus.test("passes", function(): () end)
        end,
    }))

    expect.equal(#ran.specs[1].tests, 1)
end)
