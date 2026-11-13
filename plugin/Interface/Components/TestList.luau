local collapsible = require("./Collapsible")
local failureBox = require("./FailureBox")
local flux = require("../../Packages/Flux")
local icon = require("./Icon")
local outcome = require("../Outcome")
local theme = require("../Theme")
local wrappedText = require("./WrappedText")

export type Props = {
    tests: { outcome.TestResult },
    readSource: (name: string) -> string?,

    layoutOrder: number?,
}

-- A test or a group among the tests, in the order the spec registered them; one holds exactly one of the two
type Entry = {
    test: outcome.TestResult?,
    group: Group?,
}

type Group = {
    name: string,
    entries: { Entry },
    byName: { [string]: Group },

    total: number,
    failed: number,
}

local GROUP_HEIGHT: number = 26
local TEST_PADDING: number = 4

-- A test's name starts past its icon, and its failure starts under its name
local TEST_TEXT_INDENT: number = theme.iconSize + theme.rowGap
local FAILURE_INDENT: number = theme.rowPadding + TEST_TEXT_INDENT

local function newGroup(name: string): Group
    return { name = name, entries = {}, byName = {}, total = 0, failed = 0 }
end

-- Each test names the groups it sits in from the outside in, which is enough to rebuild their nesting
local function treeOf(tests: { outcome.TestResult }): Group
    local root: Group = newGroup("")

    for _, test in tests do
        local current: Group = root

        for _, name in test.groups do
            local group: Group? = current.byName[name]
            if not group then
                group = newGroup(name)

                current.byName[name] = group
                table.insert(current.entries, { group = group })
            end

            group.total += 1
            if test.failure then
                group.failed += 1
            end

            current = group
        end

        table.insert(current.entries, { test = test })
    end

    return root
end

local function testList(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local root: Group = treeOf(props.tests)

    -- With nothing wrong there is nothing to draw the eye, so every group shows; otherwise only the ones with a failure do
    local allPassed: boolean = outcome.failedCount(props.tests) == 0

    local function testLine(building: flux.Scope, test: outcome.TestResult, layoutOrder: number): Frame
        local failed: boolean = test.failure ~= nil

        return building:element "Frame" {
            Name = test.name,
            LayoutOrder = layoutOrder,

            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.fromScale(1, 0),

            building:element "UIPadding" {
                PaddingLeft = UDim.new(0, theme.rowPadding),
                PaddingRight = UDim.new(0, theme.rowPadding),
                PaddingTop = UDim.new(0, TEST_PADDING),
                PaddingBottom = UDim.new(0, TEST_PADDING),
            },

            building:hydrate(icon(building, {
                name = if failed then "cross" else "check",
                gradient = if failed then colors.failGradient else colors.passGradient,
            })) {
                AnchorPoint = Vector2.zero,
                Position = UDim2.new(),
            },

            wrappedText(building, {
                text = test.name,
                font = theme.mainFont,
                size = theme.bodyTextSize,
                color = if failed then colors.brightText else colors.text,

                leftPadding = TEST_TEXT_INDENT,
            }),
        }
    end

    local function entriesOf(building: flux.Scope, group: Group): { Instance }
        local built: { Instance } = {}

        for index, entry in group.entries do
            -- Two layout orders each, so a test's failure can follow it
            local layoutOrder: number = index * 2

            if entry.group then
                local inner: Group = entry.group

                table.insert(built, collapsible(building, {
                    layoutOrder = layoutOrder,

                    height = GROUP_HEIGHT,
                    startsOpen = allPassed or inner.failed > 0,

                    head = {
                        building:element "TextLabel" {
                            Name = "Name",
                            LayoutOrder = 1,

                            AutomaticSize = Enum.AutomaticSize.X,
                            Size = UDim2.fromScale(0, 1),

                            Text = inner.name,
                            TextScaled = false,
                            TextSize = theme.bodyTextSize,
                            FontFace = theme.boldFont,
                            TextColor3 = if inner.failed > 0 then colors.brightText else colors.text,
                        },

                        building:element "TextLabel" {
                            Name = "Note",
                            LayoutOrder = 2,

                            AutomaticSize = Enum.AutomaticSize.X,
                            Size = UDim2.fromScale(0, 1),

                            Text = outcome.note(inner.total, inner.failed),
                            TextScaled = false,
                            TextSize = theme.smallTextSize,
                            FontFace = theme.mainFont,
                            TextColor3 = colors.subText,
                        },
                    },

                    content = function(opened: flux.Scope): { Instance }
                        return entriesOf(opened, inner)
                    end,
                }))
            elseif entry.test then
                local test: outcome.TestResult = entry.test
                table.insert(built, testLine(building, test, layoutOrder))

                if test.failure then
                    table.insert(built, failureBox(building, {
                        layoutOrder = layoutOrder + 1,
                        indent = FAILURE_INDENT,

                        failure = test.failure,
                        color = colors.fail,
                        readSource = props.readSource,
                    }))
                end
            end
        end

        return built
    end

    return scope:element "Frame" {
        Name = "Tests",
        LayoutOrder = props.layoutOrder,

        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.fromScale(1, 0),

        scope:element "UIListLayout" {
            Padding = UDim.new(0, theme.listGap),
        },

        entriesOf(scope, root),
    }
end

return testList
