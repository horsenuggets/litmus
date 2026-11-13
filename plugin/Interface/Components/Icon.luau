local flux = require("../../Packages/Flux")
local imageIds = require("../../ImageIds")
local theme = require("../Theme")

export type Name = "check" | "chevron" | "cross" | "warn"

export type Props = {
    name: Name,

    -- The images are white, and take their colour from this, top to bottom
    gradient: flux.UsedAs<ColorSequence>,

    -- The side of the square the icon is laid out as; an icon takes a row's usual room unless told otherwise
    size: number?,
    transparency: flux.UsedAs<number>?,

    -- Turns the image inside its square, which stays put for whatever lays the icon out
    rotation: flux.UsedAs<number>?,

    layoutOrder: number?,
}

type Drawing = {
    image: string,

    -- Each image leaves its own margin around its glyph, so each is drawn larger than its square by what makes the glyphs match
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
