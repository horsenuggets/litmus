local flux = require("../../Packages/Flux")
local imageIds = require("../../ImageIds")
local theme = require("../Theme")

export type Props = {
    layoutOrder: number?,
}

local HEIGHT: number = 32
local LOGO_SIZE: number = 28
local GAP: number = 8

local function header(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    return scope:element "Frame" {
        Name = "Header",
        LayoutOrder = props.layoutOrder,

        Size = UDim2.new(1, 0, 0, HEIGHT),

        scope:element "UIListLayout" {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, GAP),
        },

        scope:element "ImageLabel" {
            Name = "Logo",
            LayoutOrder = 1,

            Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),

            -- `icon` is drawn to show on a dark background, and `darkIcon` on a light one
            Image = scope:computed(function(use: flux.Use): string
                return if use(colors.isDark) then imageIds.icon else imageIds.darkIcon
            end),
        },

        scope:element "TextLabel" {
            Name = "Title",
            LayoutOrder = 2,

            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.new(),

            Text = "Litmus",
            TextScaled = false,
            TextSize = theme.titleTextSize,
            FontFace = theme.boldFont,
            TextColor3 = colors.brightText,
        },
    }
end

return header
