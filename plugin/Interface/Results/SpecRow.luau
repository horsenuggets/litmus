local collapsible = require("../Components/Collapsible")
local failureBox = require("./FailureBox")
local flux = require("../../Packages/Flux")
local icon = require("../Components/Icon")
local label = require("../Components/Label")
local outcome = require("../../Outcome")
local paths = require("../Paths")
local statusStyle = require("./StatusStyle")
local testList = require("./TestList")
local theme = require("../Theme")
local words = require("../Words")

export type Props = {
    spec: outcome.SpecResult,

    -- The start of the spec's path that every spec shares, which the row leaves out
    root: outcome.Path,

    layoutOrder: number?,
}

local HEIGHT: number = 30

-- Room under a spec's own failure, before its tests or the next row
local FAILURE_BOTTOM: number = 4

local function specRow(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local spec: outcome.SpecResult = props.spec

    local status: outcome.Status = outcome.statusOf(spec)
    local style: statusStyle.Style = statusStyle(scope, status)

    local specFailure: outcome.Failure? = spec.failure
    local hasDetails: boolean = specFailure ~= nil or #spec.tests > 0

    return collapsible(scope, {
        layoutOrder = props.layoutOrder,

        height = HEIGHT,

        -- A spec with something wrong opens by itself; the rest wait to be asked
        startsOpen = status ~= "PASS",

        head = {
            icon(scope, {
                layoutOrder = 1,

                name = style.icon,
                gradient = style.gradient,
            }),

            label(scope, {
                layoutOrder = 2,

                text = paths.name(spec.path),
                font = theme.boldFont,
                size = theme.bodyTextSize,
                color = colors.brightText,
            }),

            -- Takes whatever width the rest leave, which pushes the note to the right edge
            label(scope, {
                layoutOrder = 3,
                truncated = true,

                text = paths.shown(paths.relativeTo(paths.parent(spec.path), props.root)),
                font = theme.mainFont,
                size = theme.smallTextSize,
                color = colors.subText,
            }),

            label(scope, {
                layoutOrder = 4,

                text = if status == "ERROR" then "didn't load" else words.testNote(#spec.tests, outcome.failedCount(spec.tests)),
                font = theme.mainFont,
                size = theme.smallTextSize,
                color = if status == "PASS" then colors.subText else style.color,
            }),
        },

        content = if hasDetails
            then function(inner: flux.Scope): { Instance }
                local built: { Instance } = {}

                if specFailure then
                    -- Padded as the rows around it are, so the box starts under the spec's icon
                    table.insert(built, inner:element "Frame" {
                        Name = "Failure",
                        LayoutOrder = 1,

                        AutomaticSize = Enum.AutomaticSize.Y,
                        Size = UDim2.fromScale(1, 0),

                        inner:element "UIPadding" {
                            PaddingLeft = UDim.new(0, theme.rowPadding),
                            PaddingRight = UDim.new(0, theme.rowPadding),
                            PaddingBottom = UDim.new(0, FAILURE_BOTTOM),
                        },

                        failureBox(inner, { failure = specFailure, color = style.color }),
                    })
                end

                if #spec.tests > 0 then
                    table.insert(built, testList(inner, {
                        layoutOrder = 2,
                        tests = spec.tests,
                    }))
                end

                return built
            end
            else nil,
    })
end

return specRow
