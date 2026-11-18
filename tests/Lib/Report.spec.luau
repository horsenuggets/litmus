local inline = require("../Utils/Inline")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local report = litmus.report
local test = litmus.test

group("pieces of text", function(): ()
    test("a heading and a text hold what they were given", function(): ()
        expect.same(report.heading("Lines run"), { kind = "heading", text = "Lines run" })
        expect.same(report.text("one\ntwo"), { kind = "text", text = "one\ntwo" })
    end)

    test("stats keep their pairs in order, as labels and texts", function(): ()
        expect.same(report.stats({ { "Coverage", "5%" }, { "Loaded", "2 of 3" } }), {
            kind = "stats",
            items = { { label = "Coverage", text = "5%" }, { label = "Loaded", text = "2 of 3" } },
        })
    end)

    test("a legend keeps its pairs in order, as labels and tones", function(): ()
        expect.same(report.legend({ { "ran", "good" }, { "never loaded", "dim" } }), {
            kind = "legend",
            items = { { label = "ran", tone = "good" }, { label = "never loaded", tone = "dim" } },
        })
    end)
end)

group("a tree", function(): ()
    test("a cell is plain and to the left unless told otherwise", function(): ()
        expect.same(report.cell("name"), { kind = "cell", text = "name", align = "left", tone = "plain" })
        expect.same(report.cell("9", { align = "right", tone = "dim" }), {
            kind = "cell",
            text = "9",
            align = "right",
            tone = "dim",
        })
    end)

    test("a meter holds its parts in order", function(): ()
        expect.same(report.meter({ report.part(2, "good"), report.part(0, "dim") }), {
            kind = "meter",
            parts = { { value = 2, tone = "good" }, { value = 0, tone = "dim" } },
        })
    end)

    test("a row is shut and has nothing under it unless told otherwise", function(): ()
        expect.same(report.row({ "name" }), { cells = { "name" }, open = false, rows = {} })
    end)

    test("a row holds its cells and the rows under it", function(): ()
        local inner: litmus.Row = report.row({ "inner", report.cell("1") })
        local outer: litmus.Row = report.row({ "outer", report.meter({}) }, { open = true, rows = { inner } })

        expect.equal(outer.open, true)
        expect.equal(outer.rows[1], inner)
        expect.same(outer.cells, { "outer", { kind = "meter", parts = {} } })
        expect.same(report.tree({ outer }), { kind = "tree", rows = { outer } })
    end)
end)

group("refusals", function(): ()
    test("name the piece and what it takes", function(): ()
        local function headingOfNumber(): ()
            report.heading(5 :: any)
        end

        local function statsOfText(): ()
            report.stats({ { "Coverage" } })
        end

        local function partBelowZero(): ()
            report.part(-1, "good")
        end

        local function partOfNoTone(): ()
            report.part(1, "loud" :: any)
        end

        local function meterOfNumbers(): ()
            report.meter({ 1 :: any })
        end

        local function meterOfTooMany(): ()
            report.meter(table.create(11, report.part(1, "good")))
        end

        local function cellToTheMiddle(): ()
            report.cell("name", { align = "middle" :: any })
        end

        local function rowOfNumbers(): ()
            report.row({ 5 :: any })
        end

        local function treeOfText(): ()
            report.tree({ "row" :: any })
        end

        expect.error(headingOfNumber, "report.heading takes its text as a string, and got a number")
        expect.error(statsOfText, "pair 1 isn't")
        expect.error(partBelowZero, "report.part takes its value as a number of zero or more, and got -1")
        expect.error(partOfNoTone, "a tone of good, plain or dim, and got loud")
        expect.error(meterOfNumbers, "part 1 isn't one")
        expect.error(meterOfTooMany, "report.meter takes a list of up to 10 parts")
        expect.error(cellToTheMiddle, "an align of left or right, and got middle")
        expect.error(rowOfNumbers, "cell 1 isn't")
        expect.error(treeOfText, "row 1 isn't one")
    end)
end)

test("a run carries the pieces an adapter gives as its appendix", function(): ()
    local pieces: { litmus.Piece } = { report.heading("Lines run"), report.tree({ report.row({ "Source" }) }) }

    local function withPieces(_: { litmus.SpecResult }): litmus.Remarks?
        return { appendix = pieces }
    end

    expect.equal(litmus.run(inline({}, withPieces)).appendix, pieces)
end)
