local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

test("reports a spec by the names leading to it", function(): ()
    expect.same(anchor.run("Interface", "Groups").path, { "Interface", "Groups.spec" })
end)

test("reports a spec that registers nothing as loaded, with no tests", function(): ()
    local ran: litmus.SpecResult = anchor.run("Interface", "Empty")

    expect.equal(ran.failure, nil)
    expect.same(ran.tests, {})
end)
