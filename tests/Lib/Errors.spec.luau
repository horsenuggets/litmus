local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local spec: litmus.SpecResult = anchor.run("Lib", "Errors")

test("reports a thrown error with where it was thrown", function(): ()
    local failure: litmus.Failure = anchor.failureOf(spec, "reports a thrown error")

    expect.equal(failure.message, "Lib.Errors.spec:8: boom")
    expect.same(failure.source, { "Lib", "Errors.spec" })
    expect.equal(failure.line, 8)
end)

test("finds the line of an error thrown without a position", function(): ()
    local failure: litmus.Failure = anchor.failureOf(spec, "reports an error thrown without a position")

    expect.equal(failure.message, "boom")
    expect.equal(failure.line, 12)
end)

test("finds the line of an error the engine raised", function(): ()
    expect.equal(anchor.failureOf(spec, "reports an error the engine raised").line, 17)
end)

test("gives every failure a trace", function(): ()
    expect.never.equal(anchor.failureOf(spec, "reports a thrown error").trace, "")
end)

test("runs the tests after one that failed", function(): ()
    expect.truthy(anchor.passed(spec, "runs after earlier tests failed"))
end)

test("refuses a test registered while tests run", function(): ()
    expect.truthy(anchor.passed(spec, "refuses a test registered while tests run"))
end)

test("refuses a group opened while tests run", function(): ()
    expect.truthy(anchor.passed(spec, "refuses a group opened while tests run"))
end)
