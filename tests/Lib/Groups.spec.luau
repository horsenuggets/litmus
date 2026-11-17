local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local ran: litmus.SpecResult = anchor.run("Interface", "Groups")

local function groupsOf(name: string): { string }
    return anchor.test(ran, name).groups
end

test("lists tests in the order they were registered", function(): ()
    local names: { string } = {}
    for index, result in ran.tests do
        names[index] = result.name
    end

    expect.same(names, {
        "sits outside every group",
        "sits in one group",
        "sits in two groups",
        "sits after a nested group",
        "sits after every group",
    })
end)

test("gives a test outside every group no groups", function(): ()
    expect.same(groupsOf("sits outside every group"), {})
end)

test("names the groups a test sits in from the outside in", function(): ()
    expect.same(groupsOf("sits in one group"), { "outer" })
    expect.same(groupsOf("sits in two groups"), { "outer", "inner" })
end)

test("leaves a group when its body ends", function(): ()
    expect.same(groupsOf("sits after a nested group"), { "outer" })
    expect.same(groupsOf("sits after every group"), {})
end)

test("passes a test whose body does nothing", function(): ()
    expect.equal(anchor.test(ran, "sits in one group").failure, nil)
end)
