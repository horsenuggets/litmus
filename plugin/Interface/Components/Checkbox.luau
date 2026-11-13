local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local icon = require("./Icon")
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

local function checkbox(scope: flux.Scope, props: Props): TextButton
    local colors: theme.Colors = theme.colors(scope)

    -- The filled box and its check fade in over the outlined box and its cross, which stay underneath
    local transparency: flux.Spring<number> = scope:spring(scope:computed(function(use: flux.Use): number
        return if use(props.checked) then 0 else 1
    end), FADE_SPEED, FADE_DAMPING)

    return scope:element "TextButton" {
        Name = "Checkbox",
        LayoutOrder = props.layoutOrder,

        Size = UDim2.fromOffset(SIZE, SIZE),

        button({
            activated = function(): ()
                props.activated()
            end,
        }),

        scope:element "Frame" {
            Name = "Outline",
            ZIndex = 1,

            -- A stroke is drawn outside its frame, so the frame gives up the room for it
            Size = UDim2.new(1, -STROKE * 2, 1, -STROKE * 2),

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            scope:element "UIStroke" { Color = colors.border, Thickness = STROKE },
        },

        icon(scope, {
            zIndex = 2,

            name = "cross",
            size = ICON_SIZE,
            gradient = colors.mutedGradient,
        }),

        scope:element "Frame" {
            Name = "Fill",
            ZIndex = 3,

            BackgroundTransparency = transparency,

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            scope:element "UIGradient" { Color = theme.brandGradient },
        },

        icon(scope, {
            zIndex = 4,

            name = "check",
            size = ICON_SIZE,
            gradient = theme.onBrandGradient,
            transparency = transparency,
        }),
    }
end

return checkbox
