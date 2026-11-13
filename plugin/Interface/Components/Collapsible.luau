local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local icons = require("../Icons")
local theme = require("../Theme")

export type Props = {
    layoutOrder: number?,

    height: number,
    startsOpen: boolean,

    -- Set for content that starts at the row's own left edge, and not under whatever follows the arrow
    flush: boolean?,

    -- Laid out in a row after the arrow, by their layout order
    head: any,

    -- Builds what the row opens to show, the first time it opens; a row without this can't open
    content: ((scope: flux.Scope) -> any)?,
}

-- Fainter than a button's hover fill, since a row is wide and its fill covers far more
local HOVER_ALPHA: number = 0.05

local OPEN_SPEED: number = 38
local OPEN_DAMPING: number = 1.1

-- The arrow is drawn pointing down, and is turned to point right while the row is shut
local SHUT_ROTATION: number = -90

-- Content starts under whatever follows the arrow, so a row nested in it puts its own arrow there
local CONTENT_INDENT: number = theme.iconSize + theme.rowGap

-- Room above the content, so the head's hover fill doesn't sit flush against what it opened
local CONTENT_TOP: number = 4
local CONTENT_BOTTOM: number = 6

-- A row that opens to show more below it, sliding open and shut
local function collapsible(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local content: ((scope: flux.Scope) -> any)? = props.content
    local canOpen: boolean = content ~= nil

    local open: flux.Value<boolean> = scope:value(canOpen and props.startsOpen)

    -- Content is only built once the row first opens, since most rows of a passing run never do
    local built: flux.Value<boolean> = scope:value(flux.peek(open))

    local openness: flux.Spring<number> = scope:spring(scope:computed(function(use: flux.Use): number
        return if use(open) then 1 else 0
    end), OPEN_SPEED, OPEN_DAMPING)

    local contentHeight: flux.Value<number> = scope:value(0)

    local function measure(measuring: flux.Scope, instance: Frame): ()
        contentHeight:set(instance.AbsoluteSize.Y)

        measuring:insert(instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function(): ()
            contentHeight:set(instance.AbsoluteSize.Y)
        end))
    end

    local hovering: flux.Value<boolean> = scope:value(false)
    local hover: flux.Spring<number> = scope:spring(scope:computed(function(use: flux.Use): number
        return if canOpen and use(hovering) then 1 else 0
    end), theme.hoverSpeed)

    return scope:element "Frame" {
        Name = "Collapsible",
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        scope:element "UIListLayout" {},

        scope:element "TextButton" {
            Name = "Head",
            LayoutOrder = 1,

            Size = UDim2.new(1, 0, 0, props.height),

            button({
                hovering = hovering,

                activated = function(): ()
                    if not canOpen then
                        return
                    end

                    built:set(true)
                    open:set(not flux.peek(open))
                end,
            }),

            scope:element "Frame" {
                Name = "Hover",
                ZIndex = 1,

                BackgroundColor3 = colors.buttonHover,
                BackgroundTransparency = scope:computed(function(use: flux.Use): number
                    return 1 - HOVER_ALPHA * use(hover)
                end),

                scope:element "UICorner" { CornerRadius = theme.cornerRadius },
            },

            scope:element "Frame" {
                Name = "Line",
                ZIndex = 2,

                scope:element "UIPadding" {
                    PaddingLeft = UDim.new(0, theme.rowPadding),
                    PaddingRight = UDim.new(0, theme.rowPadding),
                },

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    Padding = UDim.new(0, theme.rowGap),
                },

                -- The layout places this holder, and the arrow turns inside it, out of the layout's hands
                scope:element "Frame" {
                    Name = "Arrow",
                    LayoutOrder = 0,

                    Size = UDim2.fromOffset(theme.iconSize, theme.iconSize),

                    scope:element "ImageLabel" {
                        Name = "Image",

                        -- A row that can't open keeps the arrow's room, so its head lines up with the rows that can
                        Image = icons.arrow,
                        ImageColor3 = colors.subText,
                        ImageTransparency = if canOpen then 0 else 1,

                        Rotation = scope:computed(function(use: flux.Use): number
                            return SHUT_ROTATION * (1 - use(openness))
                        end),
                    },
                },

                props.head,
            },
        },

        scope:element "Frame" {
            Name = "Body",
            LayoutOrder = 2,

            ClipsDescendants = true,

            -- The height follows what the content measures, scaled by how far open the row is
            Size = scope:computed(function(use: flux.Use): UDim2
                return UDim2.new(1, 0, 0, use(contentHeight) * use(openness))
            end),

            scope:computed(function(use: flux.Use, inner: flux.Scope): Frame?
                if not content or not use(built) then
                    return nil
                end

                return inner:element "Frame" {
                    Name = "Content",

                    AnchorPoint = Vector2.zero,
                    Position = UDim2.new(),

                    AutomaticSize = Enum.AutomaticSize.Y,
                    Size = UDim2.fromScale(1, 0),

                    measure,

                    inner:element "UIPadding" {
                        PaddingLeft = UDim.new(0, if props.flush then 0 else CONTENT_INDENT),
                        PaddingTop = UDim.new(0, CONTENT_TOP),
                        PaddingBottom = UDim.new(0, CONTENT_BOTTOM),
                    },

                    inner:element "UIListLayout" {
                        Padding = UDim.new(0, theme.listGap),
                    },

                    content(inner),
                }
            end),
        },
    }
end

return collapsible
