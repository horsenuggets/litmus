local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local highlight = require("./Highlight")
local icon = require("./Icon")
local theme = require("../Theme")

export type Props = {
    layoutOrder: number?,

    height: number,
    startsOpen: boolean,
    toggled: ((open: boolean) -> ())?,

    indent: number?,

    head: any,

    content: ((scope: flux.Scope) -> any)?,
}

local HOVER_ALPHA: number = 0.05

local SHUT_ROTATION: number = -90

local CONTENT_TOP: number = 4
local CONTENT_BOTTOM: number = 6

local function collapsible(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local content: ((scope: flux.Scope) -> any)? = props.content
    local canOpen: boolean = content ~= nil

    local open: flux.Value<boolean> = scope:value(canOpen and props.startsOpen)

    local built: flux.Value<boolean> = scope:value(flux.peek(open))

    local opennessTarget: flux.Computed<number> = scope:computed(function(use: flux.Use): number
        return if use(open) then 1 else 0
    end)

    local openness: flux.Spring<number> = scope:spring(opennessTarget, theme.toggleSpeed, theme.toggleDamping)

    local contentHeight: flux.Value<number> = scope:value(0)

    local function measure(measuring: flux.Scope, instance: Frame): ()
        contentHeight:set(instance.AbsoluteSize.Y)

        measuring:insert(instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function(): ()
            contentHeight:set(instance.AbsoluteSize.Y)
        end))
    end

    local hovering: flux.Value<boolean> = scope:value(false)

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

                    if props.toggled then
                        props.toggled(flux.peek(open))
                    end
                end,
            }),

            highlight(scope, {
                color = colors.buttonHover,
                opacity = scope:computed(function(use: flux.Use): number
                    return if canOpen and use(hovering) then HOVER_ALPHA else 0
                end),
            }),

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

                icon(scope, {
                    layoutOrder = 1,

                    name = "chevron",
                    gradient = colors.mutedGradient,

                    transparency = if canOpen then 0 else 1,

                    rotation = scope:computed(function(use: flux.Use): number
                        return SHUT_ROTATION * (1 - use(openness))
                    end),
                }),

                scope:element "Frame" {
                    Name = "Items",
                    LayoutOrder = 2,

                    Size = UDim2.fromScale(0, 1),

                    scope:element "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill },

                    scope:element "UIListLayout" {
                        FillDirection = Enum.FillDirection.Horizontal,
                        VerticalAlignment = Enum.VerticalAlignment.Center,
                        Padding = UDim.new(0, theme.rowGap),
                    },

                    props.head,
                },
            },
        },

        scope:element "Frame" {
            Name = "Body",
            LayoutOrder = 2,

            ClipsDescendants = true,

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
                        PaddingLeft = UDim.new(0, props.indent or theme.rowIndent),
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
