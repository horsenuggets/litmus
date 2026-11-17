local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local ran: litmus.SpecResult = anchor.run("Lib", "Failures")

test("keeps every line of a message", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "reports every line of a message")

    expect.equal(failure.message, "first line\nsecond line\nthird line")
end)

test("keeps a long message whole", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "reports a long message")

    expect.equal(failure.message, `expected "{string.rep("right ", 30)}", got "{string.rep("left ", 30)}"`)
end)

test("points a failed expectation at the line that made it", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "reports a long message")

    expect.same(failure.source, { "Lib", "Failures.spec" })
    expect.equal(failure.line, 13)
end)

test("finds the line of a thrown table", function(): ()
    expect.equal(anchor.failureOf(ran, "reports a thrown table").line, 17)
end)

test("points at the helper that threw", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "points at the helper that threw")

    expect.equal(failure.message, "ReplicatedStorage.Tests.Utils.Thrower:3: thrown from a helper")
    expect.same(failure.source, { "ReplicatedStorage", "Tests", "Utils", "Thrower" })
    expect.equal(failure.line, 3)
end)

test("points an error the lib raised at the test that caused it", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "points at a test registered while tests run")

    expect.equal(failure.message, "Lib.Failures.spec:25: [Litmus]: test called outside a spec")
    expect.same(failure.source, { "Lib", "Failures.spec" })
    expect.equal(failure.line, 25)
end)

test("points at the test when what threw can't be placed", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "points at the test that ran a chunk nobody can place")

    expect.equal(failure.message, "Nowhere:1: from nowhere")
    expect.same(failure.source, { "Lib", "Failures.spec" })
    expect.equal(failure.line, 38)
end)

test("fails a test inside groups like any other", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "names every group it sits in")

    expect.equal(failure.message, 'expected "expected", got "actual"')
    expect.equal(failure.line, 31)
end)
