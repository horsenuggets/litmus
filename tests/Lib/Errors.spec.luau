local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local ran: litmus.SpecResult = anchor.run("Interface", "Errors")

test("reports a thrown error with where it was thrown", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "reports a thrown error")

    expect.equal(failure.message, "Interface.Errors.spec:8: boom")
    expect.same(failure.source, { "Interface", "Errors.spec" })
    expect.equal(failure.line, 8)
end)

test("finds the line of an error thrown without a position", function(): ()
    local failure: litmus.Failure = anchor.failureOf(ran, "reports an error thrown without a position")

    expect.equal(failure.message, "boom")
    expect.equal(failure.line, 12)
end)

test("finds the line of an error the engine raised", function(): ()
    expect.equal(anchor.failureOf(ran, "reports an error the engine raised").line, 17)
end)

test("gives every failure a trace", function(): ()
    expect.equal(anchor.failureOf(ran, "reports a thrown error").trace ~= "", true)
end)

test("runs the tests after one that failed", function(): ()
    expect.equal(anchor.test(ran, "runs after earlier tests failed").failure, nil)
end)

test("refuses a test registered while tests run", function(): ()
    expect.equal(anchor.test(ran, "refuses a test registered while tests run").failure, nil)
end)

test("refuses a group opened while tests run", function(): ()
    expect.equal(anchor.test(ran, "refuses a group opened while tests run").failure, nil)
end)
