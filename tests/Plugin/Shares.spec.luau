local litmus = require("../../Litmus")
local shares = require("../../Plugin/Interface/Shares")

local expect = litmus.expect
local test = litmus.test

test("shares the steps out by size", function(): ()
    expect.same(shares({ 259, 750, 1000 }, 24), { 3, 9, 12 })
    expect.same(shares({ 1, 1, 1 }, 24), { 8, 8, 8 })
    expect.same(shares({ 9 }, 24), { 24 })
end)

test("gives a value too small for a step one anyway, out of the widest", function(): ()
    expect.same(shares({ 1, 1, 100000 }, 24), { 1, 1, 22 })
end)

test("gives a value of nothing no step", function(): ()
    expect.same(shares({ 0, 5, 0 }, 24), { 0, 24, 0 })
end)

test("gives the last value every step when there is nothing to share", function(): ()
    expect.same(shares({ 0, 0 }, 24), { 0, 24 })
    expect.same(shares({}, 24), {})
end)
