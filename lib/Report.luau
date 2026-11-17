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

export type Component =
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

local function refuse(piece: string, problem: string): never
    error(`[Litmus]: report.{piece} {problem}`, 3)
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

function report.heading(text: string): Component
    if type(text) ~= "string" then
        refuse("heading", `takes its text as a string, and got a {type(text)}`)
    end

    return { kind = "heading", text = text }
end

function report.text(text: string): Component
    if type(text) ~= "string" then
        refuse("text", `takes its text as a string, and got a {type(text)}`)
    end

    return { kind = "text", text = text }
end

function report.stats(entries: { { string } }): Component
    if not isList(entries) then
        refuse("stats", "takes a list of pairs, each a label and its text")
    end

    local items: { Stat } = {}
    for index, pair in entries do
        if type(pair) ~= "table" or type(pair[1]) ~= "string" or type(pair[2]) ~= "string" then
            refuse("stats", `takes each pair as a label and its text, both strings, and pair {index} isn't`)
        end

        items[index] = { label = pair[1], text = pair[2] }
    end

    return { kind = "stats", items = items }
end

function report.legend(entries: { { string } }): Component
    if not isList(entries) then
        refuse("legend", "takes a list of pairs, each a label and its tone")
    end

    local items: { Key } = {}
    for index, pair in entries do
        if type(pair) ~= "table" or type(pair[1]) ~= "string" or not TONES[pair[2]] then
            refuse("legend", `takes each pair as a label and a tone of good, plain or dim, and pair {index} isn't`)
        end

        items[index] = { label = pair[1], tone = pair[2] :: Tone }
    end

    return { kind = "legend", items = items }
end

function report.part(value: number, tone: Tone): Part
    if type(value) ~= "number" or value < 0 then
        refuse("part", `takes its value as a number of zero or more, and got {tostring(value)}`)
    end

    if not TONES[tone] then
        refuse("part", `takes a tone of good, plain or dim, and got {tostring(tone)}`)
    end

    return { value = value, tone = tone }
end

function report.meter(parts: { Part }): Meter
    if not isList(parts) or #parts > MAX_PARTS then
        refuse("meter", `takes a list of up to {MAX_PARTS} parts, each made with report.part`)
    end

    for index, part in parts do
        if type(part) ~= "table" or type(part.value) ~= "number" or not TONES[part.tone] then
            refuse("meter", `takes parts made with report.part, and part {index} isn't one`)
        end
    end

    return { kind = "meter", parts = parts }
end

function report.cell(text: string, options: CellOptions?): Styled
    if type(text) ~= "string" then
        refuse("cell", `takes its text as a string, and got a {type(text)}`)
    end

    local align: Align = if options and options.align then options.align else "left"
    local tone: Tone = if options and options.tone then options.tone else "plain"

    if not ALIGNS[align] then
        refuse("cell", `takes an align of left or right, and got {tostring(align)}`)
    end

    if not TONES[tone] then
        refuse("cell", `takes a tone of good, plain or dim, and got {tostring(tone)}`)
    end

    return { kind = "cell", text = text, align = align, tone = tone }
end

function report.row(cells: { Cell }, options: RowOptions?): Row
    if not isList(cells) then
        refuse("row", "takes a list of cells, each a string, a report.cell or a report.meter")
    end

    for index, cell in cells do
        if not isCell(cell) then
            refuse("row", `takes each cell as a string, a report.cell or a report.meter, and cell {index} isn't`)
        end
    end

    local rows: { Row } = if options and options.rows then options.rows else {}
    if not isList(rows) then
        refuse("row", "takes the rows under it as a list of rows made with report.row")
    end

    return {
        cells = cells,
        open = options ~= nil and options.open == true,
        rows = rows,
    }
end

function report.tree(rows: { Row }): Component
    if not isList(rows) then
        refuse("tree", "takes a list of rows, each made with report.row")
    end

    for index, row in rows do
        if type(row) ~= "table" or not isList(row.cells) then
            refuse("tree", `takes rows made with report.row, and row {index} isn't one`)
        end
    end

    return { kind = "tree", rows = rows }
end

return report
