local litmus = require("@game/ReplicatedStorage/Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

test("reports a thrown error", function(): ()
    error("boom")
end)

test("reports an error thrown without a position", function(): ()
    error("boom", 0)
end)

test("reports an error the engine raised", function(): ()
    local nothing: any = nil
    local _ = nothing.field
end)

test("runs after earlier tests failed", function(): () end)

test("refuses a test registered while tests run", function(): ()
    expect.error(function(): ()
        test("never registered", function(): () end)
    end)
end)

test("refuses a group opened while tests run", function(): ()
    expect.error(function(): ()
        group("never opened", function(): () end)
    end)
end)
