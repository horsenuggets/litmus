local anchor = require("../Utils/Anchor")
local inline = require("../Utils/Inline")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local report = litmus.report
local test = litmus.test

test("reports a spec by the names leading to it", function(): ()
    expect.same(anchor.run("Lib", "Groups").path, { "Lib", "Groups.spec" })
end)

test("reports a spec that registers nothing as loaded, with no tests", function(): ()
    local spec: litmus.SpecResult = anchor.run("Lib", "Empty")

    expect.equal(spec.failure, nil)
    expect.same(spec.tests, {})
end)

group("appendix", function(): ()
    test("is whatever the adapter says of the results", function(): ()
        local ran: litmus.Run = litmus.run(inline({}, function(specs: { litmus.SpecResult }): litmus.Remarks?
            return { appendix = { report.text(`{#specs} specs`) } }
        end))

        expect.same(ran.appendix, { { kind = "text", text = "0 specs" } })
        expect.equal(ran.failure, nil)
    end)

    test("is left out when the adapter says nothing", function(): ()
        local silent: litmus.Run = litmus.run(inline({}, function(_: { litmus.SpecResult }): litmus.Remarks?
            return nil
        end))

        expect.equal(silent.appendix, nil)
        expect.equal(litmus.run(inline({})).appendix, nil)
    end)
end)

group("failure", function(): ()
    test("is the adapter's reason the run failed", function(): ()
        local ran: litmus.Run = litmus.run(inline({}, function(_: { litmus.SpecResult }): litmus.Remarks?
            return { failure = "too little ran" }
        end))

        expect.equal(ran.failure, "too little ran")
        expect.equal(ran.appendix, nil)
    end)

    test("is left out when the adapter fails nothing", function(): ()
        local empty: litmus.Run = litmus.run(inline({}, function(_: { litmus.SpecResult }): litmus.Remarks?
            return {}
        end))

        expect.equal(empty.failure, nil)
        expect.equal(litmus.run(inline({})).failure, nil)
    end)
end)

test("refuses results that aren't a table", function(): ()
    local function runWithText(): ()
        litmus.run(inline({}, function(_: { litmus.SpecResult }): litmus.Remarks?
            return "0 specs" :: any
        end))
    end

    expect.error(runWithText, "the adapter's results returned a string")
end)

test("refuses an appendix that isn't a list of pieces", function(): ()
    local function runWithTextAppendix(): ()
        litmus.run(inline({}, function(_: { litmus.SpecResult }): litmus.Remarks?
            return { appendix = "0 specs" :: any }
        end))
    end

    expect.error(runWithTextAppendix, "the adapter's results gave its appendix as a string")
end)
