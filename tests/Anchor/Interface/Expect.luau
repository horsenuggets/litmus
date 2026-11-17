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

group("truthy", function(): ()
    test("passes on a value that counts as true", function(): ()
        expect.truthy(0)
    end)

    test("fails on nil", function(): ()
        expect.truthy(nil)
    end)

    test("fails on false", function(): ()
        expect.truthy(false)
    end)
end)

group("never.equal", function(): ()
    test("passes on different values", function(): ()
        expect.never.equal(1, 2)
    end)

    test("passes on separate tables with the same contents", function(): ()
        expect.never.equal({}, {})
    end)

    test("fails on equal values", function(): ()
        expect.never.equal("left", "left")
    end)
end)

group("never.same", function(): ()
    test("passes where a nested value differs", function(): ()
        expect.never.same({ outer = { inner = 1 } }, { outer = { inner = 2 } })
    end)

    test("fails on tables with the same contents", function(): ()
        expect.never.same({ name = "a", list = { 1, 2 } }, { name = "a", list = { 1, 2 } })
    end)
end)

group("never.truthy", function(): ()
    test("passes on nil and on false", function(): ()
        expect.never.truthy(nil)
        expect.never.truthy(false)
    end)

    test("fails on a value that counts as true", function(): ()
        expect.never.truthy("set")
    end)
end)

group("error", function(): ()
    local function explode(): ()
        error("the fuse is lit", 0)
    end

    local function locate(): ()
        error("lost")
    end

    local function charge(): ()
        error("costs 50% (more)", 0)
    end

    local function settle(): () end

    test("passes when the error contains the text", function(): ()
        expect.error(explode, "fuse")
    end)

    test("passes when a position comes before the text", function(): ()
        expect.error(locate, "lost")
    end)

    test("takes the text as written, never as a pattern", function(): ()
        expect.error(charge, "50% (more)")
    end)

    test("fails when the error says something else", function(): ()
        expect.error(explode, "no fuse")
    end)

    test("fails when the function meant to throw the text returns", function(): ()
        expect.error(settle, "fuse")
    end)
end)
