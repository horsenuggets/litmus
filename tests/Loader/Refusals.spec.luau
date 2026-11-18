local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local function refusalOf(name: string): litmus.Failure
    return anchor.refusalOf(anchor.run("Loader", name))
end

test("refuses a path that starts nowhere", function(): ()
    local failure: litmus.Failure = refusalOf("BadPath")
    local refusal: string = `[Litmus]: can't require "@pkg/Thing": "@pkg" leads nowhere; a path starts with ./, ../, @self or @game`

    expect.equal(failure.message, refusal)
    expect.same(failure.source, { "Loader", "BadPath.spec" })
    expect.equal(failure.line, 1)
end)

test("refuses a path with no module at its end", function(): ()
    local failure: litmus.Failure = refusalOf("MissingModule")

    expect.equal(failure.message, `[Litmus]: can't require "./Missing": there is no ModuleScript at that path`)
    expect.same(failure.source, { "Loader", "MissingModule.spec" })
    expect.equal(failure.line, 1)
end)

test("names the modules that require each other in a cycle", function(): ()
    local failure: litmus.Failure = refusalOf("Cycle")
    local refusal: string = "[Litmus]: modules require each other in a cycle: Loader.CycleA -> Loader.CycleB -> Loader.CycleA"

    expect.equal(failure.message, refusal)
    expect.same(failure.source, { "Loader", "CycleB" })
    expect.equal(failure.line, 1)
end)

test("refuses a module that returns two values", function(): ()
    local failure: litmus.Failure = refusalOf("TwoValues")

    expect.equal(failure.message, "[Litmus]: Loader.ReturnsTwo returned 2 values; a module must return exactly one")
    expect.same(failure.source, { "Loader", "TwoValues.spec" })
    expect.equal(failure.line, 1)
end)

test("points a spec that doesn't compile at the line that stops it", function(): ()
    local failure: litmus.Failure = refusalOf("Syntax")

    expect.same(failure.source, { "Loader", "Syntax.spec" })
    expect.equal(failure.line, 2)
end)

test("reports an error thrown while a spec loads", function(): ()
    local failure: litmus.Failure = refusalOf("TopLevelError")

    expect.equal(failure.message, "Loader.TopLevelError.spec:7: boom")
    expect.same(failure.source, { "Loader", "TopLevelError.spec" })
    expect.equal(failure.line, 7)
end)

test("runs none of the tests of a spec that didn't load", function(): ()
    expect.same(anchor.run("Loader", "TopLevelError").tests, {})
end)
