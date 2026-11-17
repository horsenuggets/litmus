local litmus = require("../../Litmus")
local words = require("../../Plugin/Interface/Words")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

group("untagged", function(): ()
    test("takes the lib's tag off the front of a message", function(): ()
        expect.equal(words.untagged("[Litmus]: test called outside a spec"), "test called outside a spec")
    end)

    test("leaves a message without the tag alone", function(): ()
        expect.equal(words.untagged("expected 2, got 1"), "expected 2, got 1")
    end)

    test("leaves the tag alone anywhere but the front", function(): ()
        expect.equal(words.untagged("Thing:3: [Litmus]: late"), "Thing:3: [Litmus]: late")
    end)
end)

group("plain", function(): ()
    test("takes the colour codes a terminal reads out of a text", function(): ()
        expect.equal(words.plain("\27[1mCoverage\27[0m  \27[32m5%\27[0m"), "Coverage  5%")
    end)

    test("leaves a text without any alone", function(): ()
        expect.equal(words.plain("5% of [2] lines"), "5% of [2] lines")
    end)
end)

group("plural", function(): ()
    test("leaves one of a thing as it is", function(): ()
        expect.equal(words.plural(1, "test"), "1 test")
    end)

    test("adds an s for any other count", function(): ()
        expect.equal(words.plural(0, "test"), "0 tests")
        expect.equal(words.plural(2, "spec"), "2 specs")
    end)
end)

group("testNote", function(): ()
    test("counts the tests when none failed", function(): ()
        expect.equal(words.testNote(3, 0), "3 tests")
        expect.equal(words.testNote(1, 0), "1 test")
    end)

    test("says how many passed when some failed", function(): ()
        expect.equal(words.testNote(3, 1), "2 of 3 passed")
    end)
end)
