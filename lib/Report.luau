export type Tone = "good" | "plain" | "dim"
export type Align = "left" | "right"

export type Part = {
    value: number,
    tone: Tone,
}

export type Meter = {
    kind: "meter",
    parts: { Part },
}

export type Styled = {
    kind: "cell",
    text: string,
    align: Align,
    tone: Tone,
}

export type Cell = string | Styled | Meter

export type Row = {
    cells: { Cell },
    open: boolean,
    rows: { Row },
}

export type Key = {
    label: string,
    tone: Tone,
}

export type Stat = {
    label: string,
    text: string,
}

export type Piece =
    { kind: "heading", text: string }
    | { kind: "text", text: string }
    | { kind: "stats", items: { Stat } }
    | { kind: "legend", items: { Key } }
    | { kind: "tree", rows: { Row } }

export type CellOptions = {
    align: Align?,
    tone: Tone?,
}

export type RowOptions = {
    open: boolean?,
    rows: { Row }?,
}

local TONES: { [string]: true } = { good = true, plain = true, dim = true }
local ALIGNS: { [string]: true } = { left = true, right = true }

local MAX_PARTS: number = 10

local function refusal(piece: string, problem: string): string
    return `[Litmus]: report.{piece} {problem}`
end

local function notText(text: unknown): string
    return `takes its text as a string, and got a {type(text)}`
end

local function notTone(tone: unknown): string
    return `takes a tone of good, plain or dim, and got {tostring(tone)}`
end

local function isList(value: unknown): boolean
    return type(value) == "table" and (#(value :: { unknown }) > 0 or next(value :: { unknown }) == nil)
end

local function isCell(value: unknown): boolean
    if type(value) == "string" then
        return true
    end

    local kind: unknown = if type(value) == "table" then (value :: any).kind else nil
    return kind == "cell" or kind == "meter"
end

local report = {}

function report.heading(text: string): Piece
    if type(text) ~= "string" then
        error(refusal("heading", notText(text)), 2)
    end

    return { kind = "heading", text = text }
end

function report.text(text: string): Piece
    if type(text) ~= "string" then
        error(refusal("text", notText(text)), 2)
    end

    return { kind = "text", text = text }
end

function report.stats(entries: { { string } }): Piece
    if not isList(entries) then
        error(refusal("stats", "takes a list of pairs, each a label and its text"), 2)
    end

    local items: { Stat } = {}
    for index, pair in entries do
        if type(pair) ~= "table" or type(pair[1]) ~= "string" or type(pair[2]) ~= "string" then
            error(refusal("stats", `takes each pair as a label and its text, both strings, and pair {index} isn't`), 2)
        end

        items[index] = { label = pair[1], text = pair[2] }
    end

    return { kind = "stats", items = items }
end

function report.legend(entries: { { string } }): Piece
    if not isList(entries) then
        error(refusal("legend", "takes a list of pairs, each a label and its tone"), 2)
    end

    local items: { Key } = {}
    for index, pair in entries do
        if type(pair) ~= "table" or type(pair[1]) ~= "string" or not TONES[pair[2]] then
            error(refusal("legend", `takes each pair as a label and a tone of good, plain or dim, and pair {index} isn't`), 2)
        end

        items[index] = { label = pair[1], tone = pair[2] :: Tone }
    end

    return { kind = "legend", items = items }
end

function report.part(value: number, tone: Tone): Part
    if type(value) ~= "number" or value < 0 then
        error(refusal("part", `takes its value as a number of zero or more, and got {tostring(value)}`), 2)
    end

    if not TONES[tone] then
        error(refusal("part", notTone(tone)), 2)
    end

    return { value = value, tone = tone }
end

function report.meter(parts: { Part }): Meter
    if not isList(parts) or #parts > MAX_PARTS then
        error(refusal("meter", `takes a list of up to {MAX_PARTS} parts, each made with report.part`), 2)
    end

    for index, part in parts do
        if type(part) ~= "table" or type(part.value) ~= "number" or not TONES[part.tone] then
            error(refusal("meter", `takes parts made with report.part, and part {index} isn't one`), 2)
        end
    end

    return { kind = "meter", parts = parts }
end

function report.cell(text: string, options: CellOptions?): Styled
    if type(text) ~= "string" then
        error(refusal("cell", notText(text)), 2)
    end

    local align: Align = if options and options.align then options.align else "left"
    local tone: Tone = if options and options.tone then options.tone else "plain"

    if not ALIGNS[align] then
        error(refusal("cell", `takes an align of left or right, and got {tostring(align)}`), 2)
    end

    if not TONES[tone] then
        error(refusal("cell", notTone(tone)), 2)
    end

    return { kind = "cell", text = text, align = align, tone = tone }
end

function report.row(cells: { Cell }, options: RowOptions?): Row
    if not isList(cells) then
        error(refusal("row", "takes a list of cells, each a string, a report.cell or a report.meter"), 2)
    end

    for index, cell in cells do
        if not isCell(cell) then
            error(refusal("row", `takes each cell as a string, a report.cell or a report.meter, and cell {index} isn't`), 2)
        end
    end

    local rows: { Row } = if options and options.rows then options.rows else {}
    if not isList(rows) then
        error(refusal("row", "takes the rows under it as a list of rows made with report.row"), 2)
    end

    return {
        cells = cells,
        open = options ~= nil and options.open == true,
        rows = rows,
    }
end

function report.tree(rows: { Row }): Piece
    if not isList(rows) then
        error(refusal("tree", "takes a list of rows, each made with report.row"), 2)
    end

    for index, row in rows do
        if type(row) ~= "table" or not isList(row.cells) then
            error(refusal("tree", `takes rows made with report.row, and row {index} isn't one`), 2)
        end
    end

    return { kind = "tree", rows = rows }
end

return report
