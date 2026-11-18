local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local highlight = require("./Highlight")
local ripple = require("./Ripple")
local theme = require("../Theme")

export type Style = "solid" | "bordered"

export type Props = {
    text: string,
    style: Style,
    activated: () -> (),

    hasNotice: flux.UsedAs<boolean>?,

    layoutOrder: number?,
}

local HEIGHT: number = 34
local SIDE_PADDING: number = 15
local STROKE: number = 1

local FILL_ALPHA: { [Style]: number } = {
    solid = 0.2,
    bordered = theme.hoverAlpha,
}

local NOTICE_SIZE: number = 8
local NOTICE_INSET: number = 2
local NOTICE_RING: number = 2

local function textButton(scope: flux.Scope, props: Props): TextButton
    local colors: theme.Colors = theme.colors(scope)
    local solid: boolean = props.style == "solid"

    local fillColor: flux.UsedAs<Color3> = if solid then theme.onBrand else colors.buttonHover
    local fillAlpha: number = FILL_ALPHA[props.style]

    local hovering: flux.Value<boolean> = scope:value(false)
    local pressing: flux.Value<boolean> = scope:value(false)

    local press: ripple.Ripple = ripple(scope, {
        color = fillColor,
        alpha = fillAlpha,
        pressing = pressing,
    })

    return scope:element "TextButton" {
        Name = props.text,
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, HEIGHT),

        button({
            hovering = hovering,
            pressing = pressing,

            activated = function(): ()
                props.activated()
            end,
        }),

        press.start,

        if solid
            then scope:element "Frame" {
                Name = "Background",
                ZIndex = 1,

                BackgroundTransparency = 0,

                scope:element "UICorner" { CornerRadius = theme.cornerRadius },
                scope:element "UIGradient" { Color = theme.brandGradient },
            }
            else scope:element "Frame" {
                Name = "Outline",
                ZIndex = 1,

                Size = UDim2.new(1, -STROKE * 2, 1, -STROKE * 2),

                scope:element "UICorner" { CornerRadius = theme.cornerRadius },
                scope:element "UIStroke" { Color = colors.border, Thickness = STROKE },
            },

        scope:hydrate(highlight(scope, {
            color = fillColor,
            opacity = scope:computed(function(use: flux.Use): number
                return if use(hovering) then fillAlpha else 0
            end),
        })) { ZIndex = 2 },

        scope:element "TextLabel" {
            Name = "Label",
            ZIndex = 3,

            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),

            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromScale(0, 1),

            Text = props.text,
            TextScaled = false,
            TextSize = theme.largeTextSize,
            FontFace = theme.mainFont,
            TextColor3 = if solid then theme.onBrand else colors.buttonText,

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, SIDE_PADDING),
                PaddingRight = UDim.new(0, SIDE_PADDING),
            },
        },

        scope:hydrate(press.layer) { ZIndex = 4 },

        scope:element "Frame" {
            Name = "Notice",
            ZIndex = 5,

            scope:element "Frame" {
                Name = "Dot",

                Position = UDim2.new(1, -NOTICE_INSET, 0, NOTICE_INSET),
                Size = UDim2.fromOffset(NOTICE_SIZE, NOTICE_SIZE),
                Visible = props.hasNotice or false,

                BackgroundColor3 = colors.fail,
                BackgroundTransparency = 0,

                scope:element "UICorner" {},

                scope:element "UIStroke" { Color = colors.background, Thickness = NOTICE_RING },
            },
        },
    }
end

return textButton
