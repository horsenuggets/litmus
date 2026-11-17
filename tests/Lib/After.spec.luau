local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local ran: litmus.SpecResult = anchor.run("Lib", "After")

local function adapterFor(load: () -> ()): litmus.Adapter
    return {
        specs = { { path = { "Inline.spec" }, load = load } },

        locate = function(_: string): { string }?
            return nil
        end,

        spawn = function(run: (() -> ()) | thread): ()
            task.spawn(run)
        end,
    }
end

test("lists every after last, in the order registered", function(): ()
    local names: { string } = {}
    for index, result in ran.tests do
        names[index] = result.name
    end

    expect.same(names, {
        "finishes at once",
        "finishes after a wait",
        "fails",
        "refuses an after registered inside a group",
        "refuses an after registered while tests run",
        "fails like a test",
        "runs once every test has finished",
    })
end)

test("runs an after once every test has finished, whether it waited or failed", function(): ()
    expect.equal(anchor.test(ran, "runs once every test has finished").failure, nil)
end)

test("reports an after that fails as a failed test", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "fails like a test")

    expect.equal(failure.message, "Lib.After.spec:11: boom")
    expect.same(failure.source, { "Lib", "After.spec" })
    expect.equal(failure.line, 11)
end)

test("gives an after no groups", function(): ()
    expect.same(anchor.test(ran, "runs once every test has finished").groups, {})
end)

test("refuses an after registered inside a group", function(): ()
    expect.equal(anchor.test(ran, "refuses an after registered inside a group").failure, nil)
end)

test("refuses an after registered while tests run", function(): ()
    expect.equal(anchor.test(ran, "refuses an after registered while tests run").failure, nil)
end)

test("runs the afters of a spec with no tests", function(): ()
    local cleaned: boolean = false

    local inline: litmus.Run = litmus.run(adapterFor(function(): ()
        litmus.after("cleans up", function(): ()
            cleaned = true
        end)
    end))

    expect.equal(cleaned, true)
    expect.equal(#inline.specs[1].tests, 1)
end)

test("runs the afters registered before a spec failed to load, and reports none of them", function(): ()
    local cleaned: boolean = false

    local inline: litmus.Run = litmus.run(adapterFor(function(): ()
        litmus.after("cleans up", function(): ()
            cleaned = true
        end)

        error("boom")
    end))

    expect.equal(cleaned, true)
    expect.equal(inline.specs[1].failure ~= nil, true)
    expect.same(inline.specs[1].tests, {})
end)
