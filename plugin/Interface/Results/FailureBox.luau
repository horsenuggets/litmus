local codeAround = require("../CodeAround")
local flux = require("../../Packages/Flux")
local outcome = require("../../Outcome")
local paths = require("../Paths")
local sources = require("../Sources")
local theme = require("../Theme")
local words = require("../Words")
local wrappedText = require("../Components/WrappedText")

export type Props = {
    failure: outcome.Failure,

    color: flux.UsedAs<Color3>,
}

local STROKE: number = 1
local PADDING: Vector2 = Vector2.new(12, 10)
local SECTION_GAP: number = 10

local CODE_LINE_HEIGHT: number = 20
local CODE_NUMBER_WIDTH: number = 32
local CODE_GAP: number = 12
local CODE_CORNER: UDim = UDim.new(0, 3)

local function tidy(failure: outcome.Failure): string
    local message: string = failure.message

    local position: string = `{paths.fullName(failure.source)}:{failure.line}: `
    if string.sub(message, 1, #position) == position then
        message = string.sub(message, #position + 1)
    end

    return words.untagged(message)
end

local function failureBox(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local failure: outcome.Failure = props.failure

    local function codeLine(layoutOrder: number, entry: codeAround.Line): Frame
        local pointedAt: boolean = entry.number == failure.line

        return scope:element "Frame" {
            Name = `Line{entry.number}`,
            LayoutOrder = layoutOrder,

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

    local source: string? = sources.read(scope, failure.source)

    local codeLines: { Frame } = {}
    for index, entry in if source then codeAround(source, failure.line) else {} do
        codeLines[index] = codeLine(index, entry)
    end

    return scope:element "Frame" {
        Name = "Failure",

        AnchorPoint = Vector2.zero,
        Position = UDim2.new(),

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        scope:element "UIPadding" {
            PaddingLeft = UDim.new(0, STROKE),
            PaddingRight = UDim.new(0, STROKE),
            PaddingTop = UDim.new(0, STROKE),
            PaddingBottom = UDim.new(0, STROKE),
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

                text = `{paths.fullName(failure.source)}:{failure.line}`,
                font = theme.mainFont,
                size = theme.smallTextSize,
                color = colors.subText,
            }),
        },
    }
end

return failureBox
