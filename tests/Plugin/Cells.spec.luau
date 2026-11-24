local cells = require("../../Plugin/Interface/Cells")
local litmus = require("../../Litmus")
local outcome = require("../../Plugin/Outcome")

local expect = litmus.expect
local test = litmus.test

local METER: outcome.Cell = { kind = "meter", parts = { { value = 2, tone = "good" } } }
local COUNT: outcome.Cell = { kind = "cell", text = "1,024", align = "right", tone = "dim" }

local function row(cellsOf: { outcome.Cell }, rows: { outcome.Row }?): outcome.Row
    return { cells = cellsOf, open = false, rows = rows or {} }
end

test("reads a bare string as plain text to the left", function(): ()
    expect.same(cells.textOf("Source"), { text = "Source", right = false, tone = "plain" })
end)

test("reads a made cell's text, side and tone", function(): ()
    expect.same(cells.textOf(COUNT), { text = "1,024", right = true, tone = "dim" })
end)

test("tells a meter from text", function(): ()
    expect.equal(cells.textOf(METER), nil)
    expect.same(cells.partsOf(METER), { { value = 2, tone = "good" } })
    expect.equal(cells.partsOf("Source"), nil)
    expect.equal(cells.partsOf(COUNT), nil)
end)

test("names a row by its first cell, or by its place when that is no text", function(): ()
    expect.equal(cells.nameOf(row({ "Source", METER }), 3), "Source")
    expect.equal(cells.nameOf(row({ METER }), 3), "3")
    expect.equal(cells.nameOf(row({}), 3), "3")
end)

test("measures each column by its longest text, at any depth", function(): ()
    local deep: outcome.Row = row({ "a much longer name", METER, COUNT })
    local rows: { outcome.Row } = { row({ "Source", METER, "9" }, { row({ "Game" }, { deep }) }) }

    expect.same(cells.widths(rows), { 18, 0, 5 })
end)
