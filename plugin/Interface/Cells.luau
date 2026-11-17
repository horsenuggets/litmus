local outcome = require("../Outcome")

export type Text = {
    text: string,
    right: boolean,
    tone: outcome.Tone,
}

local cells = {}

function cells.textOf(cell: outcome.Cell): Text?
    if type(cell) == "string" then
        return { text = cell, right = false, tone = "plain" }
    end

    local made: any = cell
    if made.kind ~= "cell" then
        return nil
    end

    return { text = made.text, right = made.align == "right", tone = made.tone }
end

function cells.partsOf(cell: outcome.Cell): { outcome.Part }?
    local made: any = cell

    return if type(cell) ~= "string" and made.kind == "meter" then made.parts else nil
end

function cells.nameOf(row: outcome.Row, position: number): string
    local first: outcome.Cell? = row.cells[1]
    local text: Text? = if first then cells.textOf(first) else nil

    return if text then text.text else tostring(position)
end

function cells.widths(rows: { outcome.Row }): { number }
    local widths: { number } = {}

    local function measure(under: { outcome.Row }): ()
        for _, row in under do
            for column, cell in row.cells do
                local text: Text? = cells.textOf(cell)
                local length: number = if text then utf8.len(text.text) or #text.text else 0

                widths[column] = math.max(widths[column] or 0, length)
            end

            measure(row.rows)
        end
    end

    measure(rows)

    return widths
end

return cells
