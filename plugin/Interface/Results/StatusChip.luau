local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local highlight = require("../Components/Highlight")
local statusStyle = require("./StatusStyle")
local theme = require("../Theme")

export type Props = {
    style: statusStyle.Style,
    count: flux.UsedAs<number>,

    selected: flux.UsedAs<boolean>,
    activated: () -> (),

    layoutOrder: number?,
}

local HEIGHT: number = 26
local DOT_SIZE: number = 8
local DOT_GAP: number = 6

local function statusChip(scope: flux.Scope, props: Props): TextButton
    local colors: theme.Colors = theme.colors(scope)
    local style: statusStyle.Style = props.style

    local hovering: flux.Value<boolean> = scope:value(false)

    local present: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        return use(props.count) > 0
    end)

    return scope:element "TextButton" {
        Name = style.word,
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, HEIGHT),

        button({
            hovering = hovering,

            activated = function(): ()
                if flux.peek(present) then
                    props.activated()
                end
            end,
        }),

        highlight(scope, {
            color = scope:computed(function(use: flux.Use): Color3
                return if use(props.selected) then use(style.color) else use(colors.buttonHover)
            end),

            opacity = scope:computed(function(use: flux.Use): number
                if use(props.selected) then
                    return 1 - theme.tintTransparency
                end

                return if use(present) and use(hovering) then theme.hoverAlpha else 0
            end),
        }),

        scope:element "Frame" {
            Name = "Dot",
            ZIndex = 2,

            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, theme.rowPadding, 0.5, 0),
            Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),

            BackgroundColor3 = scope:computed(function(use: flux.Use): Color3
                return if use(present) then use(style.color) else use(colors.subText)
            end),
            BackgroundTransparency = 0,

            scope:element "UICorner" {},
        },

        scope:element "TextLabel" {
            Name = "Label",
            ZIndex = 2,

            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),

            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromScale(0, 1),

            Text = scope:computed(function(use: flux.Use): string
                return `{use(props.count)} {style.word}`
            end),
            TextScaled = false,
            TextSize = theme.smallTextSize,
            FontFace = theme.mainFont,
            TextColor3 = scope:computed(function(use: flux.Use): Color3
                return if use(present) then use(colors.brightText) else use(colors.subText)
            end),

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, theme.rowPadding + DOT_SIZE + DOT_GAP),
                PaddingRight = UDim.new(0, theme.rowPadding),
            },
        },
    }
end

return statusChip
