local collapsible = require("../Components/Collapsible")
local failureBox = require("./FailureBox")
local flux = require("../../Packages/Flux")
local iconLine = require("../Components/IconLine")
local label = require("../Components/Label")
local outcome = require("../../Outcome")
local statusStyle = require("./StatusStyle")
local testTree = require("../TestTree")
local theme = require("../Theme")
local words = require("../Words")

export type Props = {
    tests: { outcome.TestResult },

    layoutOrder: number?,
}

local GROUP_HEIGHT: number = 26

-- A spec's tests under the groups they sit in, each failed test with what went wrong beneath it
local function testList(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local root: testTree.Group = testTree(props.tests)

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

    local function entriesOf(building: flux.Scope, group: testTree.Group): { Instance }
        local built: { Instance } = {}

        for index, entry in group.entries do
            if entry.kind == "test" then
                built[index] = testLine(building, entry.test, index)
                continue
            end

            local inner: testTree.Group = entry.group

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
