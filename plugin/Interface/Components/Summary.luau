local button = require("../../Packages/Interface/Hooks/Button")
local flux = require("../../Packages/Flux")
local icon = require("./Icon")
local outcome = require("../Outcome")
local theme = require("../Theme")

export type Props = {
    -- The strip and the bar under it together
    height: number,
    tally: flux.Computed<outcome.Tally>,

    -- The outcome the list is narrowed to, if any; pressing an outcome's count asks to change it
    selected: flux.Computed<outcome.Status?>,
    statusActivated: (status: outcome.Status) -> (),
}

type Stat = {
    status: outcome.Status,
    label: string,
    color: flux.Computed<Color3>,
    count: flux.Computed<number>,
}

local BAR_HEIGHT: number = 4
local BAR_GAP: number = 4

-- A chip's own padding brings its dot to where the rows below start, so the strip itself keeps only the rest
local STRIP_LEFT: number = 8
local STRIP_RIGHT: number = 16

local CHIP_HEIGHT: number = 26
local CHIP_GAP: number = 4
local CHIP_PADDING: number = 8
local DOT_SIZE: number = 8
local DOT_GAP: number = 6

-- How the run went at a glance: each outcome's count of specs, the tests in a line, and the proportions as a bar
local function summary(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local tally: flux.Computed<outcome.Tally> = props.tally

    local function count(read: (outcome.Tally) -> number): flux.Computed<number>
        return scope:computed(function(use: flux.Use): number
            return read(use(tally))
        end)
    end

    local stats: { Stat } = {
        {
            status = "FAIL",
            label = "failed",
            color = colors.fail,
            count = count(function(counted: outcome.Tally): number
                return counted.failedSpecs
            end),
        },
        {
            status = "ERROR",
            label = "errored",
            color = colors.error,
            count = count(function(counted: outcome.Tally): number
                return counted.erroredSpecs
            end),
        },
        {
            status = "PASS",
            label = "passed",
            color = colors.pass,
            count = count(function(counted: outcome.Tally): number
                return counted.passedSpecs
            end),
        },
    }

    -- With nothing wrong there is nothing to pick between, so the counts give way to one line saying so
    local allPassed: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        local counted: outcome.Tally = use(tally)
        return counted.passedSpecs > 0 and counted.failedSpecs + counted.erroredSpecs == 0
    end)

    local function chip(building: flux.Scope, layoutOrder: number, stat: Stat): TextButton
        local hovering: flux.Value<boolean> = building:value(false)

        -- An outcome nothing had is shown greyed, and can't be picked
        local present: flux.Computed<boolean> = building:computed(function(use: flux.Use): boolean
            return use(stat.count) > 0
        end)

        local fill: flux.Spring<number> = building:spring(building:computed(function(use: flux.Use): number
            if use(props.selected) == stat.status then
                return 1 - theme.tintTransparency
            end

            return if use(present) and use(hovering) then theme.hoverAlpha else 0
        end), theme.hoverSpeed)

        return building:element "TextButton" {
            Name = stat.label,
            LayoutOrder = layoutOrder,

            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromOffset(0, CHIP_HEIGHT),

            button({
                hovering = hovering,

                activated = function(): ()
                    if flux.peek(present) then
                        props.statusActivated(stat.status)
                    end
                end,
            }),

            building:element "Frame" {
                Name = "Fill",
                ZIndex = 1,

                BackgroundColor3 = building:computed(function(use: flux.Use): Color3
                    return if use(props.selected) == stat.status then use(stat.color) else use(colors.buttonHover)
                end),
                BackgroundTransparency = building:computed(function(use: flux.Use): number
                    return 1 - use(fill)
                end),

                building:element "UICorner" { CornerRadius = theme.cornerRadius },
            },

            building:element "Frame" {
                Name = "Dot",
                ZIndex = 2,

                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, CHIP_PADDING, 0.5, 0),
                Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),

                BackgroundColor3 = building:computed(function(use: flux.Use): Color3
                    return if use(present) then use(stat.color) else use(colors.subText)
                end),
                BackgroundTransparency = 0,

                building:element "UICorner" {},
            },

            building:element "TextLabel" {
                Name = "Label",
                ZIndex = 2,

                AnchorPoint = Vector2.zero,
                Position = UDim2.new(),

                -- The chip takes its width from this label, padding included
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromScale(0, 1),

                Text = building:computed(function(use: flux.Use): string
                    return `{use(stat.count)} {stat.label}`
                end),
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.mainFont,
                TextColor3 = building:computed(function(use: flux.Use): Color3
                    return if use(present) then use(colors.brightText) else use(colors.subText)
                end),

                building:element "UIPadding" {
                    PaddingLeft = UDim.new(0, CHIP_PADDING + DOT_SIZE + DOT_GAP),
                    PaddingRight = UDim.new(0, CHIP_PADDING),
                },
            },
        }
    end

    local function allPassedLine(building: flux.Scope): { Instance }
        return {
            icon(building, {
                layoutOrder = 1,

                name = "check",
                gradient = colors.passGradient,
            }),

            building:element "TextLabel" {
                LayoutOrder = 2,

                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromScale(0, 1),

                Text = building:computed(function(use: flux.Use): string
                    return `All {outcome.plural(use(tally).passedSpecs, "spec")} passed`
                end),
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.boldFont,
                TextColor3 = colors.pass,
            },
        }
    end

    local barSegments: { Frame } = {}
    for index, stat in stats do
        barSegments[index] = scope:element "Frame" {
            Name = stat.label,
            LayoutOrder = index,

            Size = UDim2.fromScale(0, 1),
            Visible = scope:computed(function(use: flux.Use): boolean
                return use(stat.count) > 0
            end),

            BackgroundColor3 = stat.color,
            BackgroundTransparency = 0,

            scope:element "UICorner" {},

            -- Segments share the bar's width in proportion to their counts
            scope:element "UIFlexItem" {
                FlexMode = Enum.UIFlexMode.Custom,
                GrowRatio = stat.count,
            },
        }
    end

    return scope:element "Frame" {
        Name = "Summary",

        AnchorPoint = Vector2.zero,
        Position = UDim2.new(),
        Size = UDim2.new(1, 0, 0, props.height),

        scope:element "Frame" {
            Name = "Strip",

            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),
            Size = UDim2.new(1, 0, 1, -BAR_HEIGHT),

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, STRIP_LEFT),
                PaddingRight = UDim.new(0, STRIP_RIGHT),
            },

            scope:element "Frame" {
                Name = "Specs",

                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5),

                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromOffset(0, CHIP_HEIGHT),

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    Padding = UDim.new(0, CHIP_GAP),
                },

                scope:computed(function(use: flux.Use, inner: flux.Scope): { Instance }
                    if use(allPassed) then
                        -- Sits where a chip's dot would, since it has no chip around it to pad it
                        return {
                            inner:element "Frame" {
                                AutomaticSize = Enum.AutomaticSize.X,
                                Size = UDim2.fromScale(0, 1),

                                inner:element "UIPadding" { PaddingLeft = UDim.new(0, CHIP_PADDING) },

                                inner:element "UIListLayout" {
                                    FillDirection = Enum.FillDirection.Horizontal,
                                    VerticalAlignment = Enum.VerticalAlignment.Center,
                                    Padding = UDim.new(0, DOT_GAP),
                                },

                                allPassedLine(inner),
                            },
                        }
                    end

                    local chips: { Instance } = {}
                    for index, stat in stats do
                        chips[index] = chip(inner, index, stat)
                    end

                    return chips
                end),
            },

            scope:element "TextLabel" {
                Name = "Tests",

                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.fromScale(1, 0.5),

                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromScale(0, 1),

                Text = scope:computed(function(use: flux.Use): string
                    local counted: outcome.Tally = use(tally)
                    local parts: { string } = { outcome.plural(counted.failedTests + counted.passedTests, "test") }

                    -- With no test failed, the total alone already says they all passed
                    if counted.failedTests > 0 then
                        table.insert(parts, `<font color="#{use(colors.fail):ToHex()}">{counted.failedTests} failed</font>`)
                        table.insert(parts, `<font color="#{use(colors.pass):ToHex()}">{counted.passedTests} passed</font>`)
                    end

                    return table.concat(parts, "  ·  ")
                end),
                RichText = true,
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.mainFont,
                TextColor3 = colors.subText,
            },
        },

        -- Stands in for a line between the strip and the list, and is inset to where the strip's own content starts and ends
        scope:element "Frame" {
            Name = "Bar",

            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.new(1, -STRIP_RIGHT * 2, 0, BAR_HEIGHT),

            scope:element "UIListLayout" {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, BAR_GAP),
            },

            barSegments,
        },
    }
end

return summary
