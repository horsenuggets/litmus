local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local theme = require("../Theme")

export type Style = "solid" | "bordered"

export type Props = {
    text: string,
    style: Style,
    activated: () -> (),

    -- Shows a dot on the button's corner, for something new behind it that hasn't been looked at
    hasNotice: flux.UsedAs<boolean>?,

    layoutOrder: number?,
}

local HEIGHT: number = 34

-- The dot sits just inside the button's top right corner, overlapping its edge
local NOTICE_SIZE: number = 8
local NOTICE_INSET: number = 2
local NOTICE_RING: number = 2
local SIDE_PADDING: number = 15
local STROKE: number = 1

-- How strongly the hover fill and the ripple show over each style
local FILL_ALPHA: { [Style]: number } = {
    solid = 0.2,
    bordered = theme.hoverAlpha,
}

local RIPPLE_GROW_SPEED: number = 44
local RIPPLE_GROW_DAMPING: number = 2
local RIPPLE_FADE_SPEED: number = 31

-- How far the furthest corner of a `size` rectangle is from `point` inside it
local function reachFrom(point: Vector2, size: Vector2): number
    local furthest: Vector2 = Vector2.new(math.max(point.X, size.X - point.X), math.max(point.Y, size.Y - point.Y))
    return furthest.Magnitude
end

local function textButton(scope: flux.Scope, props: Props): TextButton
    local colors: theme.Colors = theme.colors(scope)
    local solid: boolean = props.style == "solid"

    local fillColor: flux.UsedAs<Color3> = if solid then theme.onBrand else colors.buttonHover
    local fillAlpha: number = FILL_ALPHA[props.style]

    local hovering: flux.Value<boolean> = scope:value(false)
    local pressing: flux.Value<boolean> = scope:value(false)

    local hover: flux.Spring<number> = scope:spring(scope:computed(function(use: flux.Use): number
        return if use(hovering) then 1 else 0
    end), theme.hoverSpeed)

    -- A press starts a circle at the pointer that grows to cover the button, and fades once the press ends
    local rippleOrigin: flux.Value<Vector2> = scope:value(Vector2.zero)
    local rippleReach: flux.Value<number> = scope:value(0)
    local rippleTarget: flux.Value<number> = scope:value(0)

    local rippleGrowth: flux.Spring<number> = scope:spring(rippleTarget, RIPPLE_GROW_SPEED, RIPPLE_GROW_DAMPING)
    local rippleOpacity: flux.Spring<number> = scope:spring(scope:computed(function(use: flux.Use): number
        return if use(pressing) then 1 else 0
    end), RIPPLE_FADE_SPEED)

    local function startRipple(_: flux.Scope, instance: TextButton): ()
        scope:insert(instance.InputBegan:Connect(function(input: InputObject): ()
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            local origin: Vector2 = Vector2.new(input.Position.X, input.Position.Y) - instance.AbsolutePosition

            rippleOrigin:set(origin)
            rippleReach:set(reachFrom(origin, instance.AbsoluteSize))

            -- Both jump to where a new ripple starts, since the last one may still be showing
            rippleGrowth:setPosition(0)
            rippleOpacity:setPosition(1)
            rippleTarget:set(1)
        end))
    end

    return scope:element "TextButton" {
        Name = props.text,
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, HEIGHT),

        button({
            hovering = hovering,
            pressing = pressing,

            activated = function(): ()
                props.activated()
            end,
        }),

        startRipple,

        if solid
            then scope:element "Frame" {
                Name = "Background",
                ZIndex = 1,

                BackgroundTransparency = 0,

                scope:element "UICorner" { CornerRadius = theme.cornerRadius },
                scope:element "UIGradient" { Color = theme.brandGradient },
            }
            else scope:element "Frame" {
                Name = "Outline",
                ZIndex = 1,

                -- A stroke is drawn outside its frame, so the frame gives up the room for it
                Size = UDim2.new(1, -STROKE * 2, 1, -STROKE * 2),

                scope:element "UICorner" { CornerRadius = theme.cornerRadius },
                scope:element "UIStroke" { Color = colors.border, Thickness = STROKE },
            },

        scope:element "Frame" {
            Name = "Hover",
            ZIndex = 2,

            BackgroundColor3 = fillColor,
            BackgroundTransparency = scope:computed(function(use: flux.Use): number
                return 1 - fillAlpha * use(hover)
            end),

            scope:element "UICorner" { CornerRadius = theme.cornerRadius },
        },

        scope:element "TextLabel" {
            Name = "Label",
            ZIndex = 3,

            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),

            -- The button takes its width from this label, padding included
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromScale(0, 1),

            Text = props.text,
            TextScaled = false,
            TextSize = theme.largeTextSize,
            FontFace = theme.mainFont,
            TextColor3 = if solid then theme.onBrand else colors.buttonText,

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, SIDE_PADDING),
                PaddingRight = UDim.new(0, SIDE_PADDING),
            },
        },

        scope:element "Frame" {
            Name = "Ripple",
            ZIndex = 4,

            ClipsDescendants = true,

            scope:element "Frame" {
                Name = "Circle",

                Position = scope:computed(function(use: flux.Use): UDim2
                    local origin: Vector2 = use(rippleOrigin)
                    return UDim2.fromOffset(origin.X, origin.Y)
                end),

                Size = scope:computed(function(use: flux.Use): UDim2
                    local diameter: number = use(rippleReach) * use(rippleGrowth) * 2
                    return UDim2.fromOffset(diameter, diameter)
                end),

                BackgroundColor3 = fillColor,
                BackgroundTransparency = scope:computed(function(use: flux.Use): number
                    return 1 - fillAlpha * use(rippleOpacity)
                end),

                scope:element "UICorner" {},
            },
        },

        -- Held in a layer of its own, so the dot is neither clipped with the ripple nor counted in the button's width
        scope:element "Frame" {
            Name = "Notice",
            ZIndex = 5,

            scope:element "Frame" {
                Name = "Dot",

                Position = UDim2.new(1, -NOTICE_INSET, 0, NOTICE_INSET),
                Size = UDim2.fromOffset(NOTICE_SIZE, NOTICE_SIZE),
                Visible = props.hasNotice or false,

                BackgroundColor3 = colors.fail,
                BackgroundTransparency = 0,

                scope:element "UICorner" {},

                -- A ring in the background's colour sets the dot apart from the button's own edge
                scope:element "UIStroke" { Color = colors.background, Thickness = NOTICE_RING },
            },
        },
    }
end

return textButton
