local flux = require("../../Packages/Flux")
local outcome = require("../../Outcome")
local shares = require("../Shares")
local theme = require("../Theme")
local tone = require("../Tone")

export type Props = {
    parts: { outcome.Part },

    layoutOrder: number?,
}

local CELLS: number = 24
local CELL_WIDTH: number = 4
local HEIGHT: number = 6

local function meter(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local values: { number } = {}
    for index, part in props.parts do
        values[index] = part.value
    end

    local given: { number } = shares(values, CELLS)
    local fills: { Instance } = {}

    for index, part in props.parts do
        if given[index] > 0 then
            table.insert(fills, scope:element "Frame" {
                Name = part.tone,
                LayoutOrder = index,

                Size = UDim2.fromOffset(given[index] * CELL_WIDTH, HEIGHT),

                BackgroundColor3 = tone.fill(colors, part.tone),
                BackgroundTransparency = 0,
            })
        end
    end

    return scope:element "Frame" {
        Name = "Meter",
        LayoutOrder = props.layoutOrder,

        Size = UDim2.fromOffset(CELLS * CELL_WIDTH, HEIGHT),

        scope:element "UIListLayout" {
            FillDirection = Enum.FillDirection.Horizontal,
        },

        fills,
    }
end

return meter
