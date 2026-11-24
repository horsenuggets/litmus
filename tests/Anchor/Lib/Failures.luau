local litmus = require("@game/ReplicatedStorage/Litmus")
local thrower = require("@game/ReplicatedStorage/Tests/Utils/Thrower")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

test("reports every line of a message", function(): ()
    error("first line\nsecond line\nthird line", 0)
end)

test("reports a long message", function(): ()
    expect.equal(string.rep("left ", 30), string.rep("right ", 30))
end)

test("reports a thrown table", function(): ()
    error({ code = 1 })
end)

test("points at the helper that threw", function(): ()
    thrower()
end)

test("points at a test registered while tests run", function(): ()
    test("too late", function(): () end)
end)

group("outer", function(): ()
    group("inner", function(): ()
        test("names every group it sits in", function(): ()
            expect.equal("actual", "expected")
        end)
    end)
end)

test("points at the test that ran a chunk nobody can place", function(): ()
    local unplaced: any = loadstring("error('from nowhere')", "=Nowhere")
    unplaced()
end)
