local flux = require("../../Packages/Flux")
local theme = require("../Theme")

export type Props = {
    zIndex: number?,
}

local function outline(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    return scope:element "Frame" {
        Name = "Outline",
        ZIndex = props.zIndex,

        Size = UDim2.new(1, -theme.stroke * 2, 1, -theme.stroke * 2),

        scope:element "UICorner" { CornerRadius = theme.cornerRadius },
        scope:element "UIStroke" { Color = colors.border, Thickness = theme.stroke },
    }
end

return outline
