local collapsible = require("./Collapsible")
local failureBox = require("./FailureBox")
local flux = require("../../Packages/Flux")
local icon = require("./Icon")
local outcome = require("../Outcome")
local testList = require("./TestList")
local theme = require("../Theme")

export type Props = {
    spec: outcome.SpecResult,

    -- The start of the spec's path that every spec shares, which the row leaves out
    root: string,
    readSource: (name: string) -> string?,

    layoutOrder: number?,
}

local HEIGHT: number = 30

local STATUS_ICONS: { [outcome.Status]: icon.Name } = {
    PASS = "check",
    FAIL = "cross",
    ERROR = "warn",
}

local function specRow(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)
    local spec: outcome.SpecResult = props.spec

    local status: outcome.Status = outcome.statusOf(spec)
    local name: string, parent: string = outcome.splitPath(spec.path)

    local statusColors: { [outcome.Status]: flux.Computed<Color3> } = {
        PASS = colors.pass,
        FAIL = colors.fail,
        ERROR = colors.error,
    }
    local statusColor: flux.Computed<Color3> = statusColors[status]

    local statusGradients: { [outcome.Status]: flux.Computed<ColorSequence> } = {
        PASS = colors.passGradient,
        FAIL = colors.failGradient,
        ERROR = colors.errorGradient,
    }

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

                name = STATUS_ICONS[status],
                gradient = statusGradients[status],
            }),

            scope:element "TextLabel" {
                Name = "Name",
                LayoutOrder = 2,

                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromScale(0, 1),

                Text = name,
                TextScaled = false,
                TextSize = theme.bodyTextSize,
                FontFace = theme.boldFont,
                TextColor3 = colors.brightText,
            },

            scope:element "TextLabel" {
                Name = "Parent",
                LayoutOrder = 3,

                Size = UDim2.fromScale(0, 1),

                Text = outcome.relativeTo(parent, props.root),
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.mainFont,
                TextColor3 = colors.subText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,

                -- Takes whatever width the rest leave, which pushes the note to the right edge
                scope:element "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill },
            },

            scope:element "TextLabel" {
                Name = "Note",
                LayoutOrder = 4,

                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromScale(0, 1),

                Text = if status == "ERROR" then "didn't load" else outcome.note(#spec.tests, outcome.failedCount(spec.tests)),
                TextScaled = false,
                TextSize = theme.smallTextSize,
                FontFace = theme.mainFont,
                TextColor3 = if status == "PASS" then colors.subText else statusColor,
            },
        },

        content = if hasDetails
            then function(opened: flux.Scope): { Instance }
                local built: { Instance } = {}

                if specFailure then
                    table.insert(built, failureBox(opened, {
                        layoutOrder = 1,
                        indent = theme.rowPadding,

                        failure = specFailure,
                        color = statusColor,
                        readSource = props.readSource,
                    }))
                end

                if #spec.tests > 0 then
                    table.insert(built, testList(opened, {
                        layoutOrder = 2,

                        tests = spec.tests,
                        readSource = props.readSource,
                    }))
                end

                return built
            end
            else nil,
    })
end

return specRow
