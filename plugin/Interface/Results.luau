local collapsible = require("./Components/Collapsible")
local flux = require("../Packages/Flux")
local outcome = require("./Outcome")
local specRow = require("./Components/SpecRow")
local summary = require("./Components/Summary")
local theme = require("./Theme")

export type SpecResult = outcome.SpecResult

export type Props = {
    results: flux.UsedAs<{ SpecResult }>,

    -- The source of the script with this full name, if it can still be found
    readSource: (name: string) -> string?,
}

local SUMMARY_HEIGHT: number = 44

local LIST_PADDING: number = 8
local FOLD_HEIGHT: number = 28
local FOLD_LINE: number = 1

local SCROLL_BAR_THICKNESS: number = 7
local SCROLL_BAR_TRANSPARENCY: number = 0.65

-- What the results window holds, built into whatever it is parented to
local function results(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local tally: flux.Computed<outcome.Tally> = scope:computed(function(use: flux.Use): outcome.Tally
        return outcome.tally(use(props.results))
    end)

    local picked: flux.Value<outcome.Status?> = scope:value(nil :: outcome.Status?)

    -- A pick only holds while some spec has that outcome, so new results can't leave the list empty
    local selected: flux.Computed<outcome.Status?> = scope:computed(function(use: flux.Use): outcome.Status?
        local status: outcome.Status? = use(picked)

        for _, spec in use(props.results) do
            if outcome.statusOf(spec) == status then
                return status
            end
        end

        return nil
    end)

    local function rowsOf(building: flux.Scope, specs: { SpecResult }, root: string): { Instance }
        local rows: { Instance } = {}

        for index, spec in specs do
            rows[index] = specRow(building, {
                layoutOrder = index,

                spec = spec,
                root = root,
                readSource = props.readSource,
            })
        end

        return rows
    end

    -- Passing specs fold behind a labelled line while anything is wrong, so what needs attention is all that shows
    local function foldOf(building: flux.Scope, passed: { SpecResult }, root: string, layoutOrder: number): Frame
        local tests: number = 0
        for _, spec in passed do
            tests += #spec.tests
        end

        return collapsible(building, {
            layoutOrder = layoutOrder,

            height = FOLD_HEIGHT,
            startsOpen = false,

            -- The specs behind the fold are the list's own rows, so they line up with the ones above it
            flush = true,

            head = {
                building:element "TextLabel" {
                    Name = "Label",
                    LayoutOrder = 1,

                    AutomaticSize = Enum.AutomaticSize.X,
                    Size = UDim2.fromScale(0, 1),

                    Text = `{outcome.plural(#passed, "spec")} passed  ·  {outcome.plural(tests, "test")}`,
                    TextScaled = false,
                    TextSize = theme.smallTextSize,
                    FontFace = theme.mainFont,
                    TextColor3 = colors.subText,
                },

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

    return scope:element "Frame" {
        Name = "Results",

        BackgroundColor3 = colors.background,
        BackgroundTransparency = 0,

        summary(scope, {
            height = SUMMARY_HEIGHT,
            tally = tally,
            selected = selected,

            statusActivated = function(status: outcome.Status): ()
                picked:set(if flux.peek(selected) == status then nil else status)
            end,
        }),

        scope:element "ScrollingFrame" {
            Name = "Specs",

            AnchorPoint = Vector2.zero,
            Position = UDim2.fromOffset(0, SUMMARY_HEIGHT),
            Size = UDim2.new(1, 0, 1, -SUMMARY_HEIGHT),

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

            -- New results or a new pick replace every row, since nothing ties one list's rows to the next's
            scope:computed(function(use: flux.Use, inner: flux.Scope): { Instance }
                local all: { SpecResult } = use(props.results)
                local status: outcome.Status? = use(selected)

                -- Worked out over every spec, so narrowing the list doesn't change how a row's path reads
                local root: string = outcome.sharedParent(all)

                local wrong: { SpecResult } = {}
                local passed: { SpecResult } = {}

                for _, spec in all do
                    local specStatus: outcome.Status = outcome.statusOf(spec)

                    if status and specStatus ~= status then
                        continue
                    end

                    table.insert(if specStatus == "PASS" then passed else wrong, spec)
                end

                if #wrong == 0 then
                    return rowsOf(inner, passed, root)
                end

                -- What went wrong comes first, in the order it ran
                local rows: { Instance } = rowsOf(inner, wrong, root)

                if #passed > 0 then
                    table.insert(rows, foldOf(inner, passed, root, #wrong + 1))
                end

                return rows
            end),
        },
    }
end

return results
