local flux = require("../../Packages/Flux")
local imageIds = require("../../ImageIds")
local theme = require("../Theme")

export type Name = "check" | "chevron" | "cross" | "warn"

export type Props = {
    name: Name,

    gradient: flux.UsedAs<ColorSequence>,

    size: number?,
    transparency: flux.UsedAs<number>?,

    rotation: flux.UsedAs<number>?,

    layoutOrder: number?,
}

type Drawing = {
    image: string,

    scale: number,
}

local DRAWINGS: { [Name]: Drawing } = {
    check = { image = imageIds.check, scale = 1.5 },
    chevron = { image = imageIds.chevron, scale = 1.125 },
    cross = { image = imageIds.cross, scale = 1.5 },
    warn = { image = imageIds.warn, scale = 1.125 },
}

local function icon(scope: flux.Scope, props: Props): Frame
    local drawing: Drawing = DRAWINGS[props.name]
    local size: number = props.size or theme.iconSize

    return scope:element "Frame" {
        Name = props.name,
        LayoutOrder = props.layoutOrder,

        Size = UDim2.fromOffset(size, size),

        scope:element "ImageLabel" {
            Size = UDim2.fromScale(drawing.scale, drawing.scale),

            Image = drawing.image,
            ImageTransparency = props.transparency,
            Rotation = props.rotation,
            ScaleType = Enum.ScaleType.Fit,

            scope:element "UIGradient" { Color = props.gradient },
        },
    }
end

return icon
