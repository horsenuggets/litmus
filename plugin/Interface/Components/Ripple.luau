local flux = require("../../Packages/Flux")

export type Props = {
    color: flux.UsedAs<Color3>,

    alpha: number,
    pressing: flux.UsedAs<boolean>,
}

export type Ripple = {
    layer: Frame,
    start: (scope: flux.Scope, button: GuiButton) -> (),
}

local GROW_SPEED: number = 44
local GROW_DAMPING: number = 2
local FADE_SPEED: number = 31

local function reachFrom(point: Vector2, size: Vector2): number
    local furthest: Vector2 = Vector2.new(math.max(point.X, size.X - point.X), math.max(point.Y, size.Y - point.Y))
    return furthest.Magnitude
end

local function ripple(scope: flux.Scope, props: Props): Ripple
    local origin: flux.Value<Vector2> = scope:value(Vector2.zero)
    local reach: flux.Value<number> = scope:value(0)
    local target: flux.Value<number> = scope:value(0)

    local growth: flux.Spring<number> = scope:spring(target, GROW_SPEED, GROW_DAMPING)
    local opacityTarget: flux.Computed<number> = scope:computed(function(use: flux.Use): number
        return if use(props.pressing) then 1 else 0
    end)

    local opacity: flux.Spring<number> = scope:spring(opacityTarget, FADE_SPEED)

    local function start(listening: flux.Scope, button: GuiButton): ()
        listening:insert(button.InputBegan:Connect(function(input: InputObject): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            local pressedAt: Vector2 = Vector2.new(input.Position.X, input.Position.Y) - button.AbsolutePosition

            origin:set(pressedAt)
            reach:set(reachFrom(pressedAt, button.AbsoluteSize))

            growth:setPosition(0)
            opacity:setPosition(1)
            target:set(1)
        end))
    end

    local layer: Frame = scope:element "Frame" {
        Name = "Ripple",

        ClipsDescendants = true,

        scope:element "Frame" {
            Name = "Circle",

            Position = scope:computed(function(use: flux.Use): UDim2
                local centre: Vector2 = use(origin)
                return UDim2.fromOffset(centre.X, centre.Y)
            end),

            Size = scope:computed(function(use: flux.Use): UDim2
                local diameter: number = use(reach) * use(growth) * 2
                return UDim2.fromOffset(diameter, diameter)
            end),

            BackgroundColor3 = props.color,
            BackgroundTransparency = scope:computed(function(use: flux.Use): number
                return 1 - props.alpha * use(opacity)
            end),

            scope:element "UICorner" {},
        },
    }

    return { layer = layer, start = start }
end

return ripple
