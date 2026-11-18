local flux = require("../../Packages/Flux")
local theme = require("../Theme")

export type Props = {
    name: string,
    layoutOrder: number?,

    top: number?,
    bottom: number?,

    children: any,
}

local function padded(scope: flux.Scope, props: Props): Frame
    return scope:element "Frame" {
        Name = props.name,
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        scope:element "UIPadding" {
            PaddingLeft = UDim.new(0, theme.rowPadding),
            PaddingRight = UDim.new(0, theme.rowPadding),
            PaddingTop = UDim.new(0, props.top or 0),
            PaddingBottom = UDim.new(0, props.bottom or 0),
        },

        props.children,
    }
end

return padded
