local flux = require("../../Packages/Flux")

export type Props = {
    text: flux.UsedAs<string>,
    font: Font,
    size: number,
    color: flux.UsedAs<Color3>,

    layoutOrder: number?,
}

-- Text as wide as what holds it and as tall as its wrapped lines
local function wrappedText(scope: flux.Scope, props: Props): TextLabel
    return scope:element "TextLabel" {
        LayoutOrder = props.layoutOrder,

        AnchorPoint = Vector2.zero,
        Position = UDim2.new(),

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        Text = props.text,
        TextScaled = false,
        TextSize = props.size,
        FontFace = props.font,
        TextColor3 = props.color,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,

        -- Set once every property is on: Flux starts a label scaled, which holds wrapping on, and wrapping set
        -- before scaling is turned off may not be kept
        function(_: flux.Scope, label: TextLabel): ()
            label.TextWrapped = true
        end,
    }
end

return wrappedText
