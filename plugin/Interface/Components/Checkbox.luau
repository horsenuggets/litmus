local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local icon = require("./Icon")
local ripple = require("./Ripple")
local theme = require("../Theme")

export type Props = {
    checked: flux.UsedAs<boolean>,
    activated: () -> (),

    layoutOrder: number?,
}

local SIZE: number = 28
local ICON_SIZE: number = 20
local STROKE: number = 1

local FADE_SPEED: number = 38
local FADE_DAMPING: number = 1.1

local RIPPLE_ALPHA: number = 0.2

local function checkbox(scope: flux.Scope, props: Props): TextButton
    local colors: theme.Colors = theme.colors(scope)

    -- The filled box and its check fade in over the outlined box and its cross, which stay underneath
    local transparency: flux.Spring<number> = scope:spring(scope:computed(function(use: flux.Use): number
        return if use(props.checked) then 0 else 1
    end), FADE_SPEED, FADE_DAMPING)

    local pressing: flux.Value<boolean> = scope:value(false)

    -- Drawn in what shows on the box as it stands: white over the fill, and the hover colour over the empty box
    local rippleLayer: Frame, startRipple: (flux.Scope, GuiButton) -> () = ripple(scope, {
        color = scope:computed(function(use: flux.Use): Color3
            return if use(props.checked) then theme.onBrand else use(colors.buttonHover)
        end),
        alpha = RIPPLE_ALPHA,
        pressing = pressing,
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

        startRipple,

        scope:element "Frame" {
            Name = "Outline",
            ZIndex = 1,

            -- A stroke is drawn outside its frame, so the frame gives up the room for it
            Size = UDim2.new(1, -STROKE * 2, 1, -STROKE * 2),

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            scope:element "UIStroke" { Color = colors.border, Thickness = STROKE },
        },

        scope:hydrate(icon(scope, {
            name = "cross",
            size = ICON_SIZE,
            gradient = colors.mutedGradient,
        })) { ZIndex = 2 },

        scope:element "Frame" {
            Name = "Fill",
            ZIndex = 3,

            BackgroundTransparency = transparency,

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            scope:element "UIGradient" { Color = theme.brandGradient },
        },

        scope:hydrate(icon(scope, {
            name = "check",
            size = ICON_SIZE,
            gradient = theme.onBrandGradient,
            transparency = transparency,
        })) { ZIndex = 4 },

        scope:hydrate(rippleLayer) { ZIndex = 5 },
    }
end

return checkbox
