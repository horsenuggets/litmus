local litmus = require("@game/ReplicatedStorage/Litmus")

local after = litmus.after
local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local finished: number = 0

after("fails like a test", function(): ()
    error("boom")
end)

after("runs once every test has finished", function(): ()
    expect.equal(finished, 3)
end)

test("finishes at once", function(): ()
    finished += 1
end)

test("finishes after a wait", function(): ()
    task.wait(0.05)
    finished += 1
end)

test("fails", function(): ()
    finished += 1
    error("boom")
end)

group("inner", function(): ()
    local refused: boolean = not pcall(after, "never registered", function(): () end)

    test("refuses an after registered inside a group", function(): ()
        expect.equal(refused, true)
    end)
end)

test("refuses an after registered while tests run", function(): ()
    expect.error(function(): ()
        after("never registered", function(): () end)
    end)
end)
