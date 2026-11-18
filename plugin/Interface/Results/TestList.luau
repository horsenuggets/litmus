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

local function testList(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local root: testTree.Group = testTree(props.tests)

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

            local nested: testTree.Group = entry.group

            built[index] = collapsible(building, {
                layoutOrder = index,

                height = GROUP_HEIGHT,
                startsOpen = allPassed or nested.failed > 0,

                head = {
                    label(building, {
                        layoutOrder = 1,

                        text = nested.name,
                        font = theme.boldFont,
                        size = theme.bodyTextSize,
                        color = if nested.failed > 0 then colors.brightText else colors.text,
                    }),

                    label(building, {
                        layoutOrder = 2,

                        text = words.testNote(nested.total, nested.failed),
                        font = theme.mainFont,
                        size = theme.smallTextSize,
                        color = colors.subText,
                    }),
                },

                content = function(inner: flux.Scope): { Instance }
                    return entriesOf(inner, nested)
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
