local flux = require("../../Packages/Flux")
local outcome = require("../../Outcome")
local shares = require("../Shares")
local theme = require("../Theme")
local tone = require("./Tone")

export type Props = {
    parts: { outcome.Part },

    layoutOrder: number?,
}

type Stretch = {
    from: number,
    to: number,
    color: flux.Computed<Color3>,
}

local STEPS: number = 24
local STEP_WIDTH: number = 4
local HEIGHT: number = 8

local EDGE: number = 0.001
local WHITE: Color3 = Color3.new(1, 1, 1)

local function meter(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local values: { number } = {}
    for index, part in props.parts do
        values[index] = part.value
    end

    local stretches: { Stretch } = {}
    local passed: number = 0

    for index, steps in shares(values, STEPS) do
        if steps > 0 then
            table.insert(stretches, {
                from = passed / STEPS,
                to = (passed + steps) / STEPS,
                color = tone.fill(colors, props.parts[index].tone),
            })
        end

        passed += steps
    end

    return scope:element "Frame" {
        Name = "Meter",
        LayoutOrder = props.layoutOrder,

        Size = UDim2.fromOffset(STEPS * STEP_WIDTH, HEIGHT),

        BackgroundColor3 = WHITE,
        BackgroundTransparency = if #stretches > 0 then 0 else 1,

        scope:element "UICorner" { CornerRadius = UDim.new(1, 0) },

        scope:element "UIGradient" {
            Rotation = 0,

            Color = scope:computed(function(use: flux.Use): ColorSequence
                local points: { ColorSequenceKeypoint } = {}

                for position, stretch in stretches do
                    local color: Color3 = use(stretch.color)
                    local from: number = if position == 1 then 0 else stretch.from + EDGE
                    local to: number = if position == #stretches then 1 else stretch.to

                    table.insert(points, ColorSequenceKeypoint.new(from, color))
                    table.insert(points, ColorSequenceKeypoint.new(to, color))
                end

                if #points == 0 then
                    return ColorSequence.new(WHITE)
                end

                return ColorSequence.new(points)
            end),
        },
    }
end

return meter
