local cells = require("../Cells")
local collapsible = require("../Components/Collapsible")
local flux = require("../../Packages/Flux")
local label = require("../Components/Label")
local meter = require("./Meter")
local outcome = require("../../Outcome")
local theme = require("../Theme")
local tone = require("./Tone")

export type Props = {
    row: outcome.Row,
    widths: { number },

    path: string,
    opened: { [string]: boolean },

    layoutOrder: number?,
}

local HEIGHT: number = 24
local INDENT: number = 10
local CHARACTER_WIDTH: number = theme.smallTextSize * 0.6

local function cellOf(scope: flux.Scope, cell: outcome.Cell, column: number, width: number): Instance?
    local colors: theme.Colors = theme.colors(scope)

    local parts: { outcome.Part }? = cells.partsOf(cell)
    if parts then
        return meter(scope, { layoutOrder = column, parts = parts })
    end

    local text: cells.Text? = cells.textOf(cell)
    if not text then
        return nil
    end

    if column == 1 then
        return label(scope, {
            layoutOrder = column,
            truncated = true,

            text = text.text,
            font = theme.mainFont,
            size = theme.smallTextSize,
            color = tone.text(colors, text.tone),
        })
    end

    return scope:element "TextLabel" {
        LayoutOrder = column,

        Size = UDim2.new(0, math.ceil(width * CHARACTER_WIDTH), 1, 0),

        Text = text.text,
        TextScaled = false,
        TextSize = theme.smallTextSize,
        FontFace = theme.codeFont,
        TextColor3 = tone.text(colors, text.tone),
        TextXAlignment = if text.right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
    }
end

local treeRow: (scope: flux.Scope, props: Props) -> Frame

function treeRow(scope: flux.Scope, props: Props): Frame
    local row: outcome.Row = props.row
    local opened: { [string]: boolean } = props.opened
    local remembered: boolean? = opened[props.path]

    local head: { Instance } = {}
    for column, cell in row.cells do
        local built: Instance? = cellOf(scope, cell, column, props.widths[column] or 0)
        if built then
            table.insert(head, built)
        end
    end

    return collapsible(scope, {
        layoutOrder = props.layoutOrder,

        height = HEIGHT,
        indent = INDENT,
        startsOpen = if remembered ~= nil then remembered else row.open,

        toggled = function(open: boolean): ()
            opened[props.path] = open
        end,

        head = head,

        content = if #row.rows > 0
            then function(inner: flux.Scope): { Instance }
                local rows: { Instance } = {}

                for position, child in row.rows do
                    rows[position] = treeRow(inner, {
                        layoutOrder = position,

                        row = child,
                        widths = props.widths,

                        path = `{props.path}/{cells.nameOf(child, position)}`,
                        opened = opened,
                    })
                end

                return rows
            end
            else nil,
    })
end

return treeRow
