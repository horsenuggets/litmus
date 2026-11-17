local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local function adapterWith(results: ((specs: { litmus.SpecResult }) -> litmus.Remarks?)?): litmus.Adapter
    return {
        specs = {},

        locate = function(_: string): { string }?
            return nil
        end,

        spawn = function(run: (() -> ()) | thread): ()
            task.spawn(run)
        end,

        results = results,
    }
end

test("reports a spec by the names leading to it", function(): ()
    expect.same(anchor.run("Interface", "Groups").path, { "Interface", "Groups.spec" })
end)

test("reports a spec that registers nothing as loaded, with no tests", function(): ()
    local ran: litmus.SpecResult = anchor.run("Interface", "Empty")

    expect.equal(ran.failure, nil)
    expect.same(ran.tests, {})
end)

group("appendix", function(): ()
    test("is whatever the adapter says of the results", function(): ()
        local ran: litmus.Run = litmus.run(adapterWith(function(specs: { litmus.SpecResult }): litmus.Remarks?
            return { appendix = `{#specs} specs` }
        end))

        expect.equal(ran.appendix, "0 specs")
        expect.equal(ran.failure, nil)
    end)

    test("is left out when the adapter says nothing", function(): ()
        local silent: litmus.Run = litmus.run(adapterWith(function(_: { litmus.SpecResult }): litmus.Remarks?
            return nil
        end))

        expect.equal(silent.appendix, nil)
        expect.equal(litmus.run(adapterWith(nil)).appendix, nil)
    end)
end)

group("failure", function(): ()
    test("is the adapter's reason the run failed", function(): ()
        local ran: litmus.Run = litmus.run(adapterWith(function(_: { litmus.SpecResult }): litmus.Remarks?
            return { failure = "too little ran" }
        end))

        expect.equal(ran.failure, "too little ran")
        expect.equal(ran.appendix, nil)
    end)

    test("is left out when the adapter fails nothing", function(): ()
        local empty: litmus.Run = litmus.run(adapterWith(function(_: { litmus.SpecResult }): litmus.Remarks?
            return {}
        end))

        expect.equal(empty.failure, nil)
        expect.equal(litmus.run(adapterWith(nil)).failure, nil)
    end)
end)

test("refuses results that aren't a table", function(): ()
    local function runWithText(): ()
        litmus.run(adapterWith(function(_: { litmus.SpecResult }): litmus.Remarks?
            return "0 specs" :: any
        end))
    end

    expect.error(runWithText, "the adapter's results returned a string")
end)
