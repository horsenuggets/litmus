local flux = require("../../Packages/Flux")

export type Props = {
    text: flux.UsedAs<string>,
    font: Font,
    size: number,
    color: flux.UsedAs<Color3>,

    richText: boolean?,

    -- Takes whatever width its row has left and cuts off what doesn't fit, where it would otherwise be as wide as its text
    truncated: boolean?,

    layoutOrder: number?,
}

-- One line of text, sized to itself; Flux starts a label scaled and filling its parent, which a row of text never wants
local function label(scope: flux.Scope, props: Props): TextLabel
    local truncated: boolean = props.truncated == true

    return scope:element "TextLabel" {
        LayoutOrder = props.layoutOrder,

        AutomaticSize = if truncated then Enum.AutomaticSize.None else Enum.AutomaticSize.XY,
        Size = if truncated then UDim2.fromScale(0, 1) else UDim2.new(),

        Text = props.text,
        RichText = props.richText,
        TextScaled = false,
        TextSize = props.size,
        FontFace = props.font,
        TextColor3 = props.color,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = if truncated then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,

        if truncated then scope:element "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill } else nil,
    }
end

return label
