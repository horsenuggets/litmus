local litmus = require("@game/ReplicatedStorage/Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

group("equal", function(): ()
    test("passes on equal values", function(): ()
        expect.equal(1 + 1, 2)
    end)

    test("fails on different values", function(): ()
        expect.equal(1, 2)
    end)

    test("quotes strings", function(): ()
        expect.equal("left", "right")
    end)

    test("fails on separate tables with the same contents", function(): ()
        expect.equal({}, {})
    end)
end)

group("same", function(): ()
    test("passes on tables with the same contents", function(): ()
        expect.same({ name = "a", list = { 1, 2 } }, { name = "a", list = { 1, 2 } })
    end)

    test("fails where a nested value differs", function(): ()
        expect.same({ outer = { inner = 1 } }, { outer = { inner = 2 } })
    end)

    test("fails on a missing entry", function(): ()
        expect.same({ 1 }, { 1, 2 })
    end)

    test("fails on an extra entry", function(): ()
        expect.same({ 1, 2, 3 }, { 1, 2 })
    end)
end)

group("error", function(): ()
    test("passes when the function throws", function(): ()
        expect.error(function(): ()
            error("boom")
        end)
    end)

    test("fails when the function returns", function(): ()
        expect.error(function(): () end)
    end)
end)

-- Added at the end, so the tests above keep the line numbers the anchor expects of them
group("same", function(): ()
    test("passes on tables that contain themselves", function(): ()
        local first: { [string]: any } = { name = "a" }
        first.own = first

        local second: { [string]: any } = { name = "a" }
        second.own = second

        expect.same(first, second)
    end)
end)
