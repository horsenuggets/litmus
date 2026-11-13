local flux = require("../../Packages/Flux")
local outcome = require("../Outcome")
local theme = require("../Theme")
local wrappedText = require("./WrappedText")

export type Props = {
    failure: outcome.Failure,

    -- The outcome's colour, which marks the line the failure points at
    color: flux.UsedAs<Color3>,

    -- The source of the script with this full name, if it can still be found
    readSource: (name: string) -> string?,

    layoutOrder: number?,
    indent: number,
}

type CodeLine = {
    number: number,
    text: string,
}

-- The lib tags its own errors with this, which says nothing beside a failure in this window
local LIB_TAG: string = "[Litmus]: "

-- How many lines are shown on each side of the one a failure points at
local CONTEXT_LINES: number = 1
local TAB: string = "    "

local STROKE: number = 1
local PADDING: Vector2 = Vector2.new(12, 10)
local SECTION_GAP: number = 10
local BOTTOM_MARGIN: number = 6

local CODE_LINE_HEIGHT: number = 20
local CODE_NUMBER_WIDTH: number = 32
local CODE_GAP: number = 12
local CODE_CORNER: UDim = UDim.new(0, 3)

-- Luau starts a thrown message with where it was thrown, which the location below it already says
local function tidy(failure: outcome.Failure): string
    local message: string = failure.message

    local position: string = `{failure.source}:{failure.line}: `
    if string.sub(message, 1, #position) == position then
        message = string.sub(message, #position + 1)
    end

    if string.sub(message, 1, #LIB_TAG) == LIB_TAG then
        message = string.sub(message, #LIB_TAG + 1)
    end

    return message
end

-- The line a failure points at with the lines around it, shifted left by the indentation they share
local function codeAround(source: string, line: number): { CodeLine }
    local all: { string } = string.split(source, "\n")
    if line < 1 or line > #all then
        return {}
    end

    local lines: { CodeLine } = {}
    local shared: number = math.huge

    for number = math.max(1, line - CONTEXT_LINES), math.min(#all, line + CONTEXT_LINES) do
        local text: string = string.gsub(string.gsub(all[number], "\r", ""), "\t", TAB)

        local indentation: string? = string.match(text, "^( *)%S")
        if indentation then
            shared = math.min(shared, #indentation)
        end

        table.insert(lines, { number = number, text = text })
    end

    if shared ~= math.huge then
        for _, entry in lines do
            entry.text = string.sub(entry.text, shared + 1)
        end
    end

    return lines
end

local function failureBox(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local failure: outcome.Failure = props.failure

    local source: string? = props.readSource(failure.source)
    local code: { CodeLine } = if source then codeAround(source, failure.line) else {}

    local codeLines: { Frame } = {}
    for index, entry in code do
        local pointedAt: boolean = entry.number == failure.line

        codeLines[index] = scope:element "Frame" {
            Name = `Line{entry.number}`,
            LayoutOrder = index,

            Size = UDim2.new(1, 0, 0, CODE_LINE_HEIGHT),

            BackgroundColor3 = props.color,
            BackgroundTransparency = if pointedAt then theme.tintTransparency else 1,

            scope:element "UICorner" { CornerRadius = CODE_CORNER },

            scope:element "TextLabel" {
                Name = "Number",

                AnchorPoint = Vector2.zero,
                Position = UDim2.new(),
                Size = UDim2.new(0, CODE_NUMBER_WIDTH, 1, 0),

                Text = tostring(entry.number),
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.codeFont,
                TextColor3 = if pointedAt then props.color else colors.subText,
                TextXAlignment = Enum.TextXAlignment.Right,
            },

            scope:element "TextLabel" {
                Name = "Code",

                AnchorPoint = Vector2.zero,
                Position = UDim2.fromOffset(CODE_NUMBER_WIDTH + CODE_GAP, 0),
                Size = UDim2.new(1, -(CODE_NUMBER_WIDTH + CODE_GAP), 1, 0),

                Text = entry.text,
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.codeFont,
                TextColor3 = if pointedAt then colors.brightText else colors.text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            },
        }
    end

    return scope:element "Frame" {
        Name = "Failure",
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        -- The box sits in from the edges, so its stroke stays inside whatever clips this
        scope:element "UIPadding" {
            PaddingLeft = UDim.new(0, props.indent),
            PaddingRight = UDim.new(0, theme.rowPadding),
            PaddingTop = UDim.new(0, STROKE),
            PaddingBottom = UDim.new(0, BOTTOM_MARGIN),
        },

        scope:element "Frame" {
            Name = "Box",

            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),

            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.fromScale(1, 0),

            BackgroundColor3 = colors.inputBackground,
            BackgroundTransparency = 0,

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            scope:element "UIStroke" { Color = colors.border, Thickness = STROKE },

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, PADDING.X),
                PaddingRight = UDim.new(0, PADDING.X),
                PaddingTop = UDim.new(0, PADDING.Y),
                PaddingBottom = UDim.new(0, PADDING.Y),
            },

            scope:element "UIListLayout" {
                Padding = UDim.new(0, SECTION_GAP),
            },

            wrappedText(scope, {
                layoutOrder = 1,

                text = tidy(failure),
                font = theme.codeFont,
                size = theme.bodyTextSize,
                color = colors.brightText,
            }),

            if #codeLines > 0
                then scope:element "Frame" {
                    Name = "Code",
                    LayoutOrder = 2,

                    AutomaticSize = Enum.AutomaticSize.Y,
                    Size = UDim2.fromScale(1, 0),

                    scope:element "UIListLayout" {},

                    codeLines,
                }
                else nil,

            wrappedText(scope, {
                layoutOrder = 3,

                text = `{failure.source}:{failure.line}`,
                font = theme.mainFont,
                size = theme.smallTextSize,
                color = colors.subText,
            }),
        },
    }
end

return failureBox
