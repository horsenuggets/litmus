local control = require("../Interface/Control")
local flux = require("../Packages/Flux")
local place = require("../Place")
local results = require("../Interface/Results")
local studioColors = require("../Interface/StudioColors")
local textButton = require("../Interface/Components/TextButton")
local theme = require("../Interface/Theme")

local studio: Studio = settings().Studio

-- The sizes the windows open at, so the story shows what each window will
local CONTROL_SIZE: UDim2 = UDim2.fromOffset(320, 210)
local RESULTS_SIZE: UDim2 = UDim2.fromOffset(560, 640)
local GAP: number = 20

local TESTS: string = "ReplicatedStorage.Tests"

-- One of each thing the results window has to show, in the shape the lib returns
local SAMPLE_RESULTS: { results.SpecResult } = {
    {
        path = `{TESTS}.Interface.Empty.spec`,
        tests = {},
    },
    {
        path = `{TESTS}.Interface.Expect.spec`,
        tests = {
            { name = "passes on equal values", groups = { "equal" } },
            {
                name = "fails on different values",
                groups = { "equal" },
                failure = {
                    message = "expected 2, got 1",
                    source = `{TESTS}.Interface.Expect.spec`,
                    line = 13,
                    trace = "",
                },
            },
            { name = "passes on tables with the same contents", groups = { "same" } },
            {
                name = "fails where a nested value differs",
                groups = { "same" },
                failure = {
                    message = "expected 2, got 1 at outer.inner",
                    source = `{TESTS}.Interface.Expect.spec`,
                    line = 31,
                    trace = "",
                },
            },
        },
    },
    {
        path = `{TESTS}.Interface.Failures.spec`,
        tests = {
            {
                name = "reports every line of a message",
                groups = {},
                failure = {
                    message = "first line\nsecond line\nthird line",
                    source = `{TESTS}.Interface.Failures.spec`,
                    line = 9,
                    trace = "",
                },
            },
            {
                name = "reports a long message",
                groups = {},
                failure = {
                    message = `expected "{string.rep("right ", 30)}", got "{string.rep("left ", 30)}"`,
                    source = `{TESTS}.Interface.Failures.spec`,
                    line = 13,
                    trace = "",
                },
            },
            {
                name = "points at the helper that threw",
                groups = {},
                failure = {
                    message = `{TESTS}.Utils.Thrower:3: thrown from a helper`,
                    source = `{TESTS}.Utils.Thrower`,
                    line = 3,
                    trace = "",
                },
            },
            {
                name = "names every group it sits in",
                groups = { "outer", "inner" },
                failure = {
                    message = 'expected "expected", got "actual"',
                    source = `{TESTS}.Interface.Failures.spec`,
                    line = 31,
                    trace = "",
                },
            },
        },
    },
    {
        path = `{TESTS}.Interface.Groups.spec`,
        tests = {
            { name = "sits outside every group", groups = {} },
            { name = "sits in one group", groups = { "outer" } },
            { name = "sits in two groups", groups = { "outer", "inner" } },
            { name = "sits after a nested group", groups = { "outer" } },
            { name = "sits after every group", groups = {} },
        },
    },
    {
        path = `{TESTS}.Interface.Single.spec`,
        tests = {
            { name = "stands alone", groups = {} },
        },
    },
    {
        path = `{TESTS}.Loader.Cycle.spec`,
        tests = {},
        failure = {
            message = `[Litmus]: modules require each other in a cycle: {TESTS}.Loader.CycleA -> {TESTS}.Loader.CycleB -> {TESTS}.Loader.CycleA`,
            source = `{TESTS}.Loader.CycleB`,
            line = 1,
            trace = "",
        },
    },
    {
        path = `{TESTS}.Loader.MissingModule.spec`,
        tests = {},
        failure = {
            message = '[Litmus]: can\'t require "./Missing": there is no ModuleScript at that path',
            source = `{TESTS}.Loader.MissingModule.spec`,
            line = 1,
            trace = "",
        },
    },
    {
        path = `{TESTS}.Loader.Requires.spec`,
        tests = {
            { name = "requires a sibling with ./", groups = {} },
            { name = "requires a child with @self", groups = {} },
            { name = "requires from the DataModel with @game", groups = {} },
        },
    },
}

-- Shows the control window without and with results from the CLI, sharing one checkbox state, beside the results window
local function story(target: Frame): () -> ()
    local scope: flux.Scope = flux.scope()

    -- Starts on the theme Studio is using, and from then on shows whichever the button below picks
    local shownTheme: flux.Value<StudioTheme> = scope:value(studio.Theme)
    theme.provide(scope, studioColors(scope, shownTheme))

    local isDark: flux.Computed<boolean> = theme.colors(scope).isDark

    local connected: flux.Value<boolean> = scope:value(false)
    local cliResultsUnseen: flux.Value<boolean> = scope:value(true)

    local function controlWindow(layoutOrder: number, hasCliResults: boolean): Frame
        return scope:element "Frame" {
            Name = if hasCliResults then "WithCliResults" else "WithoutCliResults",
            LayoutOrder = layoutOrder,

            Size = CONTROL_SIZE,

            control(scope, {
                connected = connected,
                connectActivated = function(): ()
                    connected:set(not flux.peek(connected))
                end,

                -- Stands in for a new result arriving from the CLI, so the dot can be brought back
                testActivated = function(): ()
                    cliResultsUnseen:set(true)
                end,

                hasCliResults = hasCliResults,
                cliResultsUnseen = cliResultsUnseen,
                cliResultsActivated = function(): ()
                    cliResultsUnseen:set(false)
                end,
            }),
        }
    end

    scope:element "Frame" {
        Name = "Litmus",
        Parent = target,

        scope:element "UIListLayout" {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, GAP),
        },

        scope:element "Frame" {
            Name = "ControlWindows",
            LayoutOrder = 1,

            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.new(),

            scope:element "UIListLayout" {
                Padding = UDim.new(0, GAP),
            },

            -- Rebuilt on each switch, since its text says which theme a press leads to
            scope:computed(function(use: flux.Use, inner: flux.Scope): TextButton
                local dark: boolean = use(isDark)

                return textButton(inner, {
                    layoutOrder = 0,

                    text = if dark then "Switch to light" else "Switch to dark",
                    style = "solid",

                    activated = function(): ()
                        local wanted: string = if dark then "Light" else "Dark"

                        for _, available: StudioTheme in studio:GetAvailableThemes() do
                            if available.Name == wanted then
                                shownTheme:set(available)
                            end
                        end
                    end,
                })
            end),

            controlWindow(1, false),
            controlWindow(2, true),
        },

        scope:element "Frame" {
            Name = "ResultsWindow",
            LayoutOrder = 2,

            Size = RESULTS_SIZE,

            -- The sample names scripts this place really has, so their lines of code show
            results(scope, {
                results = SAMPLE_RESULTS,
                readSource = place.sourceNamed,
            }),
        },
    }

    return function(): ()
        scope:destroy()
    end
end

return story
