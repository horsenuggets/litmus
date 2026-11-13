local collapsible = require("./Collapsible")
local failureBox = require("./FailureBox")
local flux = require("../../Packages/Flux")
local iconLine = require("./IconLine")
local label = require("./Label")
local outcome = require("../../Outcome")
local statusStyle = require("../Status")
local theme = require("../Theme")
local words = require("../Words")

export type Props = {
    tests: { outcome.TestResult },

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

local function newGroup(name: string): Group
    return { name = name, entries = {}, byName = {}, total = 0, failed = 0 }
end

-- Each test names the groups it sits in from the outside in, which is enough to rebuild their nesting
local function treeOf(tests: { outcome.TestResult }): Group
    local root: Group = newGroup("")

    for _, test in tests do
        local current: Group = root

        for _, name in test.groups do
            local existing: Group? = current.byName[name]
            local group: Group = existing or newGroup(name)

            if not existing then
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

-- A spec's tests under the groups they sit in, each failed test with what went wrong beneath it
local function testList(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local root: Group = treeOf(props.tests)

    -- With nothing wrong there is nothing to draw the eye, so every group shows; otherwise only the ones with a failure do
    local allPassed: boolean = outcome.failedCount(props.tests) == 0

    local function testLine(building: flux.Scope, test: outcome.TestResult, layoutOrder: number): Frame
        local failure: outcome.Failure? = test.failure
        local style: statusStyle.Style = statusStyle(building, if failure then "FAIL" else "PASS")

        return iconLine(building, {
            layoutOrder = layoutOrder,

            icon = style.icon,
            gradient = style.gradient,

            text = test.name,
            color = if failure then colors.brightText else colors.text,

            children = if failure then failureBox(building, { failure = failure, color = style.color }) else nil,
        })
    end

    local function entriesOf(building: flux.Scope, group: Group): { Instance }
        local built: { Instance } = {}

        for index, entry in group.entries do
            local inner: Group? = entry.group

            if entry.test then
                built[index] = testLine(building, entry.test, index)
            end

            if not inner then
                continue
            end

            built[index] = collapsible(building, {
                layoutOrder = index,

                height = GROUP_HEIGHT,
                startsOpen = allPassed or inner.failed > 0,

                head = {
                    label(building, {
                        layoutOrder = 1,

                        text = inner.name,
                        font = theme.boldFont,
                        size = theme.bodyTextSize,
                        color = if inner.failed > 0 then colors.brightText else colors.text,
                    }),

                    label(building, {
                        layoutOrder = 2,

                        text = words.testNote(inner.total, inner.failed),
                        font = theme.mainFont,
                        size = theme.smallTextSize,
                        color = colors.subText,
                    }),
                },

                content = function(opened: flux.Scope): { Instance }
                    return entriesOf(opened, inner)
                end,
            })
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
