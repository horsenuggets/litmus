local appendix = require("@self/Appendix")
local collapsible = require("./Components/Collapsible")
local flux = require("../Packages/Flux")
local iconLine = require("./Components/IconLine")
local label = require("./Components/Label")
local outcome = require("../Outcome")
local paths = require("./Paths")
local specRow = require("@self/SpecRow")
local summary = require("@self/Summary")
local theme = require("./Theme")
local words = require("./Words")

export type Props = {
    -- The run to show: its results, or why it has none
    ran: flux.UsedAs<outcome.Run>,
}

local LIST_PADDING: number = 8
local FOLD_HEIGHT: number = 28
local FOLD_LINE: number = 1

local SCROLL_BAR_THICKNESS: number = 7
local SCROLL_BAR_TRANSPARENCY: number = 0.65

-- What the results window holds, built into whatever it is parented to
local function results(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local specs: flux.Computed<{ outcome.SpecResult }> = scope:computed(function(use: flux.Use): { outcome.SpecResult }
        return outcome.resultsOf(use(props.ran))
    end)

    local picked: flux.Value<outcome.Status?> = scope:value(nil :: outcome.Status?)

    local opened: { [string]: boolean } = {}

    -- A pick only holds while some spec has that outcome, so new results can't leave the list empty
    local selected: flux.Computed<outcome.Status?> = scope:computed(function(use: flux.Use): outcome.Status?
        local status: outcome.Status? = use(picked)

        for _, spec in use(specs) do
            if outcome.statusOf(spec) == status then
                return status
            end
        end

        return nil
    end)

    local function rowsOf(building: flux.Scope, shown: { outcome.SpecResult }, root: outcome.Path): { Instance }
        local rows: { Instance } = {}

        for index, spec in shown do
            rows[index] = specRow(building, { layoutOrder = index, spec = spec, root = root })
        end

        return rows
    end

    -- Passing specs fold behind a labelled line while anything is wrong, so what needs attention is all that shows
    local function foldOf(building: flux.Scope, passed: { outcome.SpecResult }, root: outcome.Path, layoutOrder: number): Frame
        local tests: number = 0
        for _, spec in passed do
            tests += #spec.tests
        end

        return collapsible(building, {
            layoutOrder = layoutOrder,

            height = FOLD_HEIGHT,
            startsOpen = false,

            -- The specs behind the fold are the list's own rows, so they line up with the ones above it
            indent = 0,

            head = {
                label(building, {
                    layoutOrder = 1,

                    text = `{words.plural(#passed, "spec")} passed  ·  {words.plural(tests, "test")}`,
                    font = theme.mainFont,
                    size = theme.smallTextSize,
                    color = colors.subText,
                }),

                building:element "Frame" {
                    Name = "Line",
                    LayoutOrder = 2,

                    Size = UDim2.fromOffset(0, FOLD_LINE),

                    BackgroundColor3 = colors.border,
                    BackgroundTransparency = 0,

                    building:element "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill },
                },
            },

            content = function(opened: flux.Scope): { Instance }
                return rowsOf(opened, passed, root)
            end,
        })
    end

    local function listOf(building: flux.Scope, ran: outcome.Run, only: outcome.Status?): { Instance }
        if ran.kind == "problem" then
            return {
                iconLine(building, {
                    icon = "warn",
                    gradient = colors.errorGradient,

                    text = words.untagged(ran.message),
                    color = colors.brightText,
                }),
            }
        end

        -- Worked out over every spec, so narrowing the list doesn't change how a row's path reads
        local specPaths: { outcome.Path } = {}
        for index, spec in ran.results do
            specPaths[index] = spec.path
        end

        local root: outcome.Path = paths.sharedParent(specPaths)
        local wrong: { outcome.SpecResult }, passed: { outcome.SpecResult } = outcome.arranged(ran.results, only)

        if #wrong == 0 then
            return rowsOf(building, passed, root)
        end

        local rows: { Instance } = rowsOf(building, wrong, root)

        if #passed > 0 then
            table.insert(rows, foldOf(building, passed, root, #wrong + 1))
        end

        return rows
    end

    local top: Frame = summary(scope, {
        tally = scope:computed(function(use: flux.Use): outcome.Tally
            return outcome.tally(use(specs))
        end),

        selected = selected,
        statusActivated = function(status: outcome.Status): ()
            picked:set(if flux.peek(selected) == status then nil else status)
        end,
    })

    -- The list starts where the summary ends, whatever height the summary gives itself
    local listTop: number = top.Size.Y.Offset

    return scope:element "Frame" {
        Name = "Results",

        BackgroundColor3 = colors.background,
        BackgroundTransparency = 0,

        top,

        scope:element "ScrollingFrame" {
            Name = "Specs",

            AnchorPoint = Vector2.zero,
            Position = UDim2.fromOffset(0, listTop),
            Size = UDim2.new(1, 0, 1, -listTop),

            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
            ScrollingDirection = Enum.ScrollingDirection.Y,

            -- Rows give up the bar's width while it shows, so it never covers them
            VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
            ScrollBarThickness = SCROLL_BAR_THICKNESS,
            ScrollBarImageColor3 = colors.brightText,
            ScrollBarImageTransparency = SCROLL_BAR_TRANSPARENCY,

            scope:element "UIPadding" {
                PaddingLeft = UDim.new(0, LIST_PADDING),
                PaddingRight = UDim.new(0, LIST_PADDING),
                PaddingTop = UDim.new(0, LIST_PADDING),
                PaddingBottom = UDim.new(0, LIST_PADDING),
            },

            scope:element "UIListLayout" {
                Padding = UDim.new(0, theme.listGap),
            },

            -- A new run or a new pick replaces every row, since nothing ties one list's rows to the next's
            scope:computed(function(use: flux.Use, inner: flux.Scope): { Instance }
                local ran: outcome.Run = use(props.ran)
                local rows: { Instance } = listOf(inner, ran, use(selected))

                if ran.kind == "results" and ran.appendix then
                    table.insert(rows, appendix(inner, {
                        layoutOrder = #ran.results + 2,

                        appendix = ran.appendix,
                        opened = opened,
                    }))
                end

                return rows
            end),
        },
    }
end

return results
