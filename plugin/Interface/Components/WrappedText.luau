local flux = require("../../Packages/Flux")

export type Props = {
    text: flux.UsedAs<string>,
    font: Font,
    size: number,
    color: flux.UsedAs<Color3>,

    richText: boolean?,

    layoutOrder: number?,
}

local function wrappedText(scope: flux.Scope, props: Props): TextLabel
    return scope:element "TextLabel" {
        LayoutOrder = props.layoutOrder,

        AnchorPoint = Vector2.zero,
        Position = UDim2.new(),

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        Text = props.text,
        RichText = props.richText,
        TextScaled = false,
        TextSize = props.size,
        FontFace = props.font,
        TextColor3 = props.color,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,

        function(_: flux.Scope, label: TextLabel): ()
            label.TextWrapped = true
        end,
    }
end

return wrappedText
