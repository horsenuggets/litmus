local codeAround = require("../../Plugin/Interface/CodeAround")
local litmus = require("../../Litmus")

local expect = litmus.expect
local test = litmus.test

local SOURCE: string = "one\ntwo\nthree\nfour\nfive"

test("gives the line with the one on each side of it", function(): ()
    expect.same(codeAround(SOURCE, 3), {
        { number = 2, text = "two" },
        { number = 3, text = "three" },
        { number = 4, text = "four" },
    })
end)

test("stops at the first line", function(): ()
    expect.same(codeAround(SOURCE, 1), {
        { number = 1, text = "one" },
        { number = 2, text = "two" },
    })
end)

test("stops at the last line", function(): ()
    expect.same(codeAround(SOURCE, 5), {
        { number = 4, text = "four" },
        { number = 5, text = "five" },
    })
end)

test("gives nothing for a line the source doesn't have", function(): ()
    expect.same(codeAround(SOURCE, 0), {})
    expect.same(codeAround(SOURCE, 6), {})
end)

test("takes off the indentation the lines share", function(): ()
    expect.same(codeAround("    if ready then\n        go()\n    end", 2), {
        { number = 1, text = "if ready then" },
        { number = 2, text = "    go()" },
        { number = 3, text = "end" },
    })
end)

test("reads a tab as four spaces", function(): ()
    expect.same(codeAround("\tif ready then\n\t\tgo()\n\tend", 2), {
        { number = 1, text = "if ready then" },
        { number = 2, text = "    go()" },
        { number = 3, text = "end" },
    })
end)

test("leaves a blank line out of what the lines share", function(): ()
    expect.same(codeAround("    one\n\n    three", 2), {
        { number = 1, text = "one" },
        { number = 2, text = "" },
        { number = 3, text = "three" },
    })
end)

test("drops the carriage returns of Windows line endings", function(): ()
    expect.same(codeAround("one\r\ntwo\r\nthree", 2), {
        { number = 1, text = "one" },
        { number = 2, text = "two" },
        { number = 3, text = "three" },
    })
end)
