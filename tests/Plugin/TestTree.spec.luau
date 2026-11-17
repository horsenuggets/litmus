local litmus = require("../../Litmus")
local outcome = require("../../Plugin/Outcome")
local testTree = require("../../Plugin/Interface/TestTree")

local expect = litmus.expect
local test = litmus.test

local FAILURE: outcome.Failure = { message = "wrong", source = { "Place", "Thing.spec" }, line = 1, trace = "" }

local function passing(name: string, groups: { string }): outcome.TestResult
    return { name = name, groups = groups }
end

local function failing(name: string, groups: { string }): outcome.TestResult
    return { name = name, groups = groups, failure = FAILURE }
end

-- A group's entries in order: a test as its name, and a group as its name with its own entries under it
local function outline(group: testTree.Group): { any }
    local lines: { any } = {}

    for index, entry in group.entries do
        if entry.kind == "test" then
            lines[index] = entry.test.name
        else
            lines[index] = { group = entry.group.name, entries = outline(entry.group) }
        end
    end

    return lines
end

test("has no entries for no tests", function(): ()
    expect.same(outline(testTree({})), {})
end)

test("nests each test under the groups it names, in the order the tests came", function(): ()
    local root: testTree.Group = testTree({
        passing("first", {}),
        passing("second", { "outer" }),
        passing("third", { "outer", "inner" }),
        passing("fourth", { "outer" }),
        passing("fifth", {}),
    })

    expect.same(outline(root), {
        "first",
        {
            group = "outer",
            entries = {
                "second",
                { group = "inner", entries = { "third" } },
                "fourth",
            },
        },
        "fifth",
    })
end)

test("gathers a group opened twice where it was first opened", function(): ()
    local root: testTree.Group = testTree({
        passing("first", { "same" }),
        passing("second", { "other" }),
        passing("third", { "same" }),
    })

    expect.same(outline(root), {
        { group = "same", entries = { "first", "third" } },
        { group = "other", entries = { "second" } },
    })
end)

test("keeps groups with one name apart when different groups hold them", function(): ()
    local root: testTree.Group = testTree({
        passing("first", { "left", "inner" }),
        passing("second", { "right", "inner" }),
    })

    expect.same(outline(root), {
        { group = "left", entries = { { group = "inner", entries = { "first" } } } },
        { group = "right", entries = { { group = "inner", entries = { "second" } } } },
    })
end)

test("counts a group's tests and failures through the groups inside it", function(): ()
    local root: testTree.Group = testTree({
        passing("first", { "outer" }),
        failing("second", { "outer", "inner" }),
        passing("third", { "outer", "inner" }),
    })

    local outer: testTree.Group = root.byName.outer
    local inner: testTree.Group = outer.byName.inner

    expect.equal(outer.total, 3)
    expect.equal(outer.failed, 1)

    expect.equal(inner.total, 2)
    expect.equal(inner.failed, 1)
end)
