local anchor = require("../Utils/Anchor")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local ran: litmus.SpecResult = anchor.run("Lib", "Expect")

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

    test("passes when the error contains the text", function(): ()
        expect.equal(passed("passes when the error contains the text"), true)
    end)

    test("looks past the position in front of the text", function(): ()
        expect.equal(passed("passes when a position comes before the text"), true)
    end)

    test("takes the text as written, never as a pattern", function(): ()
        expect.equal(passed("takes the text as written, never as a pattern"), true)
    end)

    test("says what the error said in place of the text", function(): ()
        local message: string = messageOf("fails when the error says something else")

        expect.equal(message, 'expected an error containing "no fuse", got "the fuse is lit"')
    end)

    test("says which text never came", function(): ()
        local message: string = messageOf("fails when the function meant to throw the text returns")

        expect.equal(message, 'expected an error containing "fuse", got none')
    end)
end)

group("truthy", function(): ()
    test("passes on a value that counts as true", function(): ()
        expect.equal(passed("passes on a value that counts as true"), true)
    end)

    test("fails on nil", function(): ()
        expect.equal(messageOf("fails on nil"), "expected a truthy value, got nil")
    end)

    test("fails on false", function(): ()
        expect.equal(messageOf("fails on false"), "expected a truthy value, got false")
    end)
end)

group("never", function(): ()
    test("passes on different values", function(): ()
        expect.equal(passed("passes on different values"), true)
    end)

    test("passes on separate tables with the same contents", function(): ()
        expect.equal(passed("passes on separate tables with the same contents"), true)
    end)

    test("says which value it expected not to get", function(): ()
        expect.equal(messageOf("fails on equal values"), 'expected anything but "left"')
    end)

    test("passes where a nested value differs", function(): ()
        expect.equal(passed("passes where a nested value differs"), true)
    end)

    test("fails on tables with the same contents", function(): ()
        local message: string = messageOf("fails on tables with the same contents")

        expect.equal(message, "expected different contents, got the same")
    end)

    test("passes on nil and on false", function(): ()
        expect.equal(passed("passes on nil and on false"), true)
    end)

    test("says which value counted as true", function(): ()
        expect.equal(messageOf("fails on a value that counts as true"), 'expected nil or false, got "set"')
    end)
end)
