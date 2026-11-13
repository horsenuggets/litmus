local flux = require("../../Packages/Flux")
local theme = require("../Theme")

export type Props = {
    color: flux.UsedAs<Color3>,

    -- How strongly the fill shows; it eases to this whenever it changes
    opacity: flux.UsedAs<number>,
}

-- A rounded fill over whatever holds it, for marking what is hovered or picked
local function highlight(scope: flux.Scope, props: Props): Frame
    local opacity: flux.Spring<number> = scope:spring(props.opacity, theme.hoverSpeed)

    return scope:element "Frame" {
        Name = "Highlight",

        BackgroundColor3 = props.color,
        BackgroundTransparency = scope:computed(function(use: flux.Use): number
            return 1 - use(opacity)
        end),

        scope:element "UICorner" { CornerRadius = theme.cornerRadius },
    }
end

return highlight
