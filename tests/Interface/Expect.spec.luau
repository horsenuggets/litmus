local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local ran: litmus.SpecResult = anchor.run("Interface", "Expect")

local function passed(name: string): boolean
    return anchor.test(ran, name).failure == nil
end

local function messageOf(name: string): string
    return anchor.failureOf(ran, name).message
end

group("equal", function(): ()
    test("passes on equal values", function(): ()
        expect.equal(passed("passes on equal values"), true)
    end)

    test("says what it expected and what it got", function(): ()
        expect.equal(messageOf("fails on different values"), "expected 2, got 1")
    end)

    test("quotes strings", function(): ()
        expect.equal(messageOf("quotes strings"), 'expected "right", got "left"')
    end)

    test("fails on separate tables with the same contents", function(): ()
        expect.equal(passed("fails on separate tables with the same contents"), false)
    end)
end)

group("same", function(): ()
    test("passes on tables with the same contents", function(): ()
        expect.equal(passed("passes on tables with the same contents"), true)
    end)

    test("passes on tables that contain themselves", function(): ()
        expect.equal(passed("passes on tables that contain themselves"), true)
    end)

    test("says where a nested value differs", function(): ()
        expect.equal(messageOf("fails where a nested value differs"), "expected 2, got 1 at outer.inner")
    end)

    test("says which entry is missing", function(): ()
        expect.equal(messageOf("fails on a missing entry"), "expected 2, got nil at [2]")
    end)

    test("says which entry is extra", function(): ()
        expect.equal(messageOf("fails on an extra entry"), "expected nil, got 3 at [3]")
    end)
end)

group("error", function(): ()
    test("passes when the function throws", function(): ()
        expect.equal(passed("passes when the function throws"), true)
    end)

    test("fails when the function returns", function(): ()
        expect.equal(messageOf("fails when the function returns"), "expected an error, got none")
    end)
end)
