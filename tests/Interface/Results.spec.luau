local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local function adapterWith(results: ((specs: { litmus.SpecResult }) -> string?)?): litmus.Adapter
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
        local ran: litmus.Run = litmus.run(adapterWith(function(specs: { litmus.SpecResult }): string?
            return `{#specs} specs`
        end))

        expect.equal(ran.appendix, "0 specs")
    end)

    test("is left out when the adapter says nothing", function(): ()
        local silent: litmus.Run = litmus.run(adapterWith(function(_: { litmus.SpecResult }): string?
            return nil
        end))

        expect.equal(silent.appendix, nil)
        expect.equal(litmus.run(adapterWith(nil)).appendix, nil)
    end)
end)
