local flux = require("../../Packages/Flux")
local icon = require("../Components/Icon")
local label = require("../Components/Label")
local outcome = require("../../Outcome")
local statusChip = require("./StatusChip")
local statusStyle = require("./StatusStyle")
local theme = require("../Theme")
local words = require("../Words")

export type Props = {
    tally: flux.Computed<outcome.Tally>,

    -- The outcome the list is narrowed to, if any; pressing an outcome's chip asks to change it
    selected: flux.Computed<outcome.Status?>,
    statusActivated: (status: outcome.Status) -> (),
}

-- The order the outcomes are shown in, with what needs attention first
local STATUSES: { outcome.Status } = { "FAIL", "ERROR", "PASS" }

local STRIP_HEIGHT: number = 40
local BAR_HEIGHT: number = 4
local BAR_GAP: number = 6

-- Where the strip's content starts and ends, which the bar under it keeps to as well
local INSET: number = 16

local CHIP_GAP: number = 4
local ICON_GAP: number = 6

-- How the run went at a glance: each outcome's count of specs, the tests in a line, and the proportions as a bar
local function summary(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local tally: flux.Computed<outcome.Tally> = props.tally

    local function countOf(building: flux.Scope, status: outcome.Status): flux.Computed<number>
        return building:computed(function(use: flux.Use): number
            return outcome.specCount(use(tally), status)
        end)
    end

    -- With nothing wrong there is nothing to pick between, so the chips give way to one line saying so
    local allPassed: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        local counted: outcome.Tally = use(tally)
        return counted.passedSpecs > 0 and counted.failedSpecs + counted.erroredSpecs == 0
    end)

    local function chips(building: flux.Scope): { Instance }
        local built: { Instance } = {}

        for index, status in STATUSES do
            built[index] = statusChip(building, {
                layoutOrder = index,

                style = statusStyle(building, status),
                count = countOf(building, status),

                selected = building:computed(function(use: flux.Use): boolean
                    return use(props.selected) == status
                end),

                activated = function(): ()
                    props.statusActivated(status)
                end,
            })
        end

        return built
    end

    local function allPassedLine(building: flux.Scope): Frame
        return building:element "Frame" {
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromScale(0, 1),

            -- Sits where a chip's dot would, since it has no chip around it to pad it
            building:element "UIPadding" { PaddingLeft = UDim.new(0, theme.rowPadding) },

            building:element "UIListLayout" {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, ICON_GAP),
            },

            icon(building, {
                layoutOrder = 1,

                name = "check",
                gradient = colors.passGradient,
            }),

            label(building, {
                layoutOrder = 2,

                text = building:computed(function(use: flux.Use): string
                    return `All {words.plural(use(tally).passedSpecs, "spec")} passed`
                end),
                font = theme.boldFont,
                size = theme.smallTextSize,
                color = colors.pass,
            }),
        }
    end

    local barSegments: { Frame } = {}
    for index, status in STATUSES do
        local count: flux.Computed<number> = countOf(scope, status)

        barSegments[index] = scope:element "Frame" {
            Name = status,
            LayoutOrder = index,

            Size = UDim2.fromScale(0, 1),
            Visible = scope:computed(function(use: flux.Use): boolean
                return use(count) > 0
            end),

            BackgroundColor3 = statusStyle(scope, status).color,
            BackgroundTransparency = 0,

            scope:element "UICorner" {},

            -- Segments share the bar's width in proportion to their counts
            scope:element "UIFlexItem" {
                FlexMode = Enum.UIFlexMode.Custom,
                GrowRatio = count,
            },
        }
    end

    return scope:element "Frame" {
        Name = "Summary",

        AnchorPoint = Vector2.zero,
        Position = UDim2.new(),
        Size = UDim2.new(1, 0, 0, STRIP_HEIGHT + BAR_HEIGHT),

        scope:element "Frame" {
            Name = "Strip",

            AnchorPoint = Vector2.zero,
            Position = UDim2.new(),
            Size = UDim2.new(1, 0, 0, STRIP_HEIGHT),

            scope:element "UIPadding" {
                -- A chip pads its own dot, which is what should land on the inset
                PaddingLeft = UDim.new(0, INSET - theme.rowPadding),
                PaddingRight = UDim.new(0, INSET),
            },

            scope:element "Frame" {
                Name = "Specs",

                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5),

                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromScale(0, 1),

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    Padding = UDim.new(0, CHIP_GAP),
                },

                scope:computed(function(use: flux.Use, inner: flux.Scope): any
                    return if use(allPassed) then allPassedLine(inner) else chips(inner)
                end),
            },

            scope:hydrate(label(scope, {
                richText = true,

                text = scope:computed(function(use: flux.Use): string
                    local counted: outcome.Tally = use(tally)
                    local parts: { string } = { words.plural(counted.failedTests + counted.passedTests, "test") }

                    -- With no test failed, the total alone already says they all passed
                    if counted.failedTests > 0 then
                        table.insert(parts, `<font color="#{use(colors.fail):ToHex()}">{counted.failedTests} failed</font>`)
                        table.insert(parts, `<font color="#{use(colors.pass):ToHex()}">{counted.passedTests} passed</font>`)
                    end

                    return table.concat(parts, "  ·  ")
                end),
                font = theme.mainFont,
                size = theme.smallTextSize,
                color = colors.subText,
            })) {
                Name = "Tests",

                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.fromScale(1, 0.5),
            },
        },

        -- Stands in for a line between the strip and the list
        scope:element "Frame" {
            Name = "Bar",

            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.new(1, -INSET * 2, 0, BAR_HEIGHT),

            scope:element "UIListLayout" {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, BAR_GAP),
            },

            barSegments,
        },
    }
end

return summary
