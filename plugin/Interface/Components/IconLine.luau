local flux = require("../../Packages/Flux")
local icon = require("./Icon")
local theme = require("../Theme")
local wrappedText = require("./WrappedText")

export type Props = {
    icon: icon.Name,
    gradient: flux.UsedAs<ColorSequence>,

    text: string,
    color: flux.UsedAs<Color3>,

    children: any?,

    layoutOrder: number?,
}

local PADDING: number = 4
local GAP: number = 6

local TEXT_INDENT: number = theme.iconSize + theme.rowGap

local function iconLine(scope: flux.Scope, props: Props): Frame
    local glyph: Frame = icon(scope, { name = props.icon, gradient = props.gradient })

    return scope:element "Frame" {
        Name = props.text,
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        scope:element "UIPadding" {
            PaddingLeft = UDim.new(0, theme.rowPadding),
            PaddingRight = UDim.new(0, theme.rowPadding),
            PaddingTop = UDim.new(0, PADDING),
            PaddingBottom = UDim.new(0, PADDING),
        },

        scope:hydrate(glyph) {
            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),
        },

        scope:element "Frame" {
            Name = "Body",

            AnchorPoint = Vector2.zero,
            Position = UDim2.fromOffset(TEXT_INDENT, 0),

            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, -TEXT_INDENT, 0, 0),

            scope:element "UIListLayout" {
                Padding = UDim.new(0, GAP),
            },

            wrappedText(scope, {
                layoutOrder = 1,

                text = props.text,
                font = theme.mainFont,
                size = theme.bodyTextSize,
                color = props.color,
            }),

            if props.children
                then scope:element "Frame" {
                    Name = "Under",
                    LayoutOrder = 2,

                    AutomaticSize = Enum.AutomaticSize.Y,
                    Size = UDim2.fromScale(1, 0),

                    props.children,
                }
                else nil,
        },
    }
end

return iconLine
