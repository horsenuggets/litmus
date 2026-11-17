local cells = require("../Cells")
local flux = require("../../Packages/Flux")
local label = require("./Label")
local outcome = require("../../Outcome")
local theme = require("../Theme")
local tone = require("../Tone")
local treeRow = require("./TreeRow")
local words = require("../Words")
local wrappedText = require("./WrappedText")

export type Props = {
    appendix: outcome.Appendix,
    opened: { [string]: boolean },

    layoutOrder: number?,
}

local TOP: number = 10
local GAP: number = 8
local LINE: number = 1

local STAT_GAP: number = 8
local KEY_GAP: number = 14
local SWATCH_SIZE: UDim2 = UDim2.fromOffset(12, 6)

local function appendix(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local function padded(position: number, name: string, children: any): Frame
        return scope:element "Frame" {
            Name = name,
            LayoutOrder = position,

            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.fromScale(1, 0),

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, theme.rowPadding),
                PaddingRight = UDim.new(0, theme.rowPadding),
            },

            children,
        }
    end

    local function heading(position: number, text: string): Frame
        return padded(position, "Heading", label(scope, {
            text = text,
            font = theme.boldFont,
            size = theme.bodyTextSize,
            color = colors.brightText,
        }))
    end

    local function text(position: number, shown: string): Frame
        return padded(position, "Text", wrappedText(scope, {
            text = words.plain(shown),
            font = theme.codeFont,
            size = theme.smallTextSize,
            color = colors.text,
        }))
    end

    local function stats(position: number, items: { outcome.Stat }): Frame
        local lines: { Instance } = {
            scope:element "UIListLayout" {
                Padding = UDim.new(0, theme.listGap),
            },
        }

        for index, item in items do
            table.insert(lines, scope:element "Frame" {
                Name = item.label,
                LayoutOrder = index,

                AutomaticSize = Enum.AutomaticSize.XY,
                Size = UDim2.new(),

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    Padding = UDim.new(0, STAT_GAP),
                },

                label(scope, {
                    layoutOrder = 1,

                    text = item.label,
                    font = theme.boldFont,
                    size = theme.smallTextSize,
                    color = colors.brightText,
                }),

                label(scope, {
                    layoutOrder = 2,

                    text = item.text,
                    font = theme.mainFont,
                    size = theme.smallTextSize,
                    color = colors.text,
                }),
            })
        end

        return padded(position, "Stats", lines)
    end

    local function legend(position: number, items: { outcome.Key }): Frame
        local keys: { Instance } = {
            scope:element "UIListLayout" {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, KEY_GAP),
                Wraps = true,
            },
        }

        for index, item in items do
            table.insert(keys, scope:element "Frame" {
                Name = item.label,
                LayoutOrder = index,

                AutomaticSize = Enum.AutomaticSize.XY,
                Size = UDim2.new(),

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    Padding = UDim.new(0, theme.rowGap),
                },

                scope:element "Frame" {
                    Name = "Swatch",
                    LayoutOrder = 1,

                    Size = SWATCH_SIZE,

                    BackgroundColor3 = tone.fill(colors, item.tone),
                    BackgroundTransparency = 0,
                },

                label(scope, {
                    layoutOrder = 2,

                    text = item.label,
                    font = theme.mainFont,
                    size = theme.smallTextSize,
                    color = colors.subText,
                }),
            })
        end

        return padded(position, "Legend", keys)
    end

    local function tree(position: number, rows: { outcome.Row }): Frame
        local widths: { number } = cells.widths(rows)

        local built: { Instance } = {
            scope:element "UIListLayout" {
                Padding = UDim.new(0, theme.listGap),
            },
        }

        for index, row in rows do
            table.insert(built, treeRow(scope, {
                layoutOrder = index,

                row = row,
                widths = widths,

                path = `{position}/{cells.nameOf(row, index)}`,
                opened = props.opened,
            }))
        end

        return scope:element "Frame" {
            Name = "Tree",
            LayoutOrder = position,

            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.fromScale(1, 0),

            built,
        }
    end

    local given: outcome.Appendix = props.appendix
    local pieces: { outcome.Piece } = if type(given) == "string" then { { kind = "text", text = given } } else given

    local built: { Instance } = {}
    for position, piece in pieces do
        local made: any = piece

        if made.kind == "heading" then
            table.insert(built, heading(position, made.text))
        elseif made.kind == "text" then
            table.insert(built, text(position, made.text))
        elseif made.kind == "stats" then
            table.insert(built, stats(position, made.items))
        elseif made.kind == "legend" then
            table.insert(built, legend(position, made.items))
        elseif made.kind == "tree" then
            table.insert(built, tree(position, made.rows))
        end
    end

    return scope:element "Frame" {
        Name = "Appendix",
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        scope:element "UIPadding" {
            PaddingTop = UDim.new(0, TOP),
        },

        scope:element "UIListLayout" {
            Padding = UDim.new(0, GAP),
        },

        scope:element "Frame" {
            Name = "Line",
            LayoutOrder = 0,

            Size = UDim2.new(1, 0, 0, LINE),

            BackgroundColor3 = colors.border,
            BackgroundTransparency = 0,
        },

        built,
    }
end

return appendix
