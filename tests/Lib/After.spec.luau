local anchor = require("../Utils/Anchor")
local inline = require("../Utils/Inline")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local spec: litmus.SpecResult = anchor.run("Lib", "After")

test("lists every after last, in the order registered", function(): ()
    local names: { string } = {}
    for index, result in spec.tests do
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
    expect.truthy(anchor.passed(spec, "runs once every test has finished"))
end)

test("reports an after that fails as a failed test", function(): ()
    local failure: litmus.Failure = anchor.failureOf(spec, "fails like a test")

    expect.equal(failure.message, "Lib.After.spec:11: boom")
    expect.same(failure.source, { "Lib", "After.spec" })
    expect.equal(failure.line, 11)
end)

test("gives an after no groups", function(): ()
    expect.same(anchor.resultOf(spec, "runs once every test has finished").groups, {})
end)

test("refuses an after registered inside a group", function(): ()
    expect.truthy(anchor.passed(spec, "refuses an after registered inside a group"))
end)

test("refuses an after registered while tests run", function(): ()
    expect.truthy(anchor.passed(spec, "refuses an after registered while tests run"))
end)

test("runs the afters of a spec with no tests", function(): ()
    local cleaned: boolean = false

    local function cleansUp(): ()
        litmus.after("cleans up", function(): ()
            cleaned = true
        end)
    end

    local ran: litmus.Run = litmus.run(inline({ cleansUp }))

    expect.equal(cleaned, true)
    expect.equal(#ran.specs[1].tests, 1)
end)

test("runs the afters registered before a spec failed to load, and reports none of them", function(): ()
    local cleaned: boolean = false

    local function cleansUpThenFails(): ()
        litmus.after("cleans up", function(): ()
            cleaned = true
        end)

        error("boom")
    end

    local ran: litmus.Run = litmus.run(inline({ cleansUpThenFails }))

    expect.equal(cleaned, true)
    expect.truthy(ran.specs[1].failure)
    expect.same(ran.specs[1].tests, {})
end)
