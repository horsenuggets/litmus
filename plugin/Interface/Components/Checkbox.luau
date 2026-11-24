local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local icon = require("./Icon")
local outline = require("./Outline")
local ripple = require("./Ripple")
local theme = require("../Theme")

export type Props = {
    checked: flux.UsedAs<boolean>,
    activated: () -> (),

    layoutOrder: number?,
}

local SIZE: number = 28
local ICON_SIZE: number = 20

local RIPPLE_ALPHA: number = 0.2

local function checkbox(scope: flux.Scope, props: Props): TextButton
    local colors: theme.Colors = theme.colors(scope)

    local transparencyTarget: flux.Computed<number> = scope:computed(function(use: flux.Use): number
        return if use(props.checked) then 0 else 1
    end)

    local transparency: flux.Spring<number> = scope:spring(transparencyTarget, theme.toggleSpeed, theme.toggleDamping)

    local pressing: flux.Value<boolean> = scope:value(false)

    local press: ripple.Ripple = ripple(scope, {
        color = scope:computed(function(use: flux.Use): Color3
            return if use(props.checked) then theme.onBrand else use(colors.buttonHover)
        end),
        alpha = RIPPLE_ALPHA,
        pressing = pressing,
    })

    local cross: Frame = icon(scope, {
        name = "cross",
        size = ICON_SIZE,
        gradient = colors.mutedGradient,
    })

    local check: Frame = icon(scope, {
        name = "check",
        size = ICON_SIZE,
        gradient = theme.onBrandGradient,
        transparency = transparency,
    })

    return scope:element "TextButton" {
        Name = "Checkbox",
        LayoutOrder = props.layoutOrder,

        Size = UDim2.fromOffset(SIZE, SIZE),

        button({
            pressing = pressing,

            activated = function(): ()
                props.activated()
            end,
        }),

        press.start,

        outline(scope, { zIndex = 1 }),

        scope:hydrate(cross) { ZIndex = 2 },

        scope:element "Frame" {
            Name = "Fill",
            ZIndex = 3,

            BackgroundTransparency = transparency,

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            scope:element "UIGradient" { Color = theme.brandGradient },
        },

        scope:hydrate(check) { ZIndex = 4 },

        scope:hydrate(press.layer) { ZIndex = 5 },
    }
end

return checkbox
