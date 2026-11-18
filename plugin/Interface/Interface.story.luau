local control = require("./Control")
local flux = require("../Packages/Flux")
local outcome = require("../Outcome")
local place = require("../Place")
local results = require("./Results")
local sources = require("./Sources")
local studioColors = require("./StudioColors")
local textButton = require("./Components/TextButton")
local theme = require("./Theme")

local studio: Studio = settings().Studio

local CONTROL_SIZE: UDim2 = UDim2.fromOffset(320, 210)
local RESULTS_SIZE: UDim2 = UDim2.fromOffset(560, 640)
local GAP: number = 20

local function inTests(...: string): outcome.Path
    return { "ReplicatedStorage", "Tests", ... }
end

local EXPECT: outcome.Path = inTests("Anchor", "Lib", "Expect")
local FAILURES: outcome.Path = inTests("Anchor", "Lib", "Failures")
local THROWER: outcome.Path = inTests("Utils", "Thrower")

local SAMPLE_RESULTS: { outcome.SpecResult } = {
    {
        path = inTests("Lib", "Empty.spec"),
        tests = {},
    },
    {
        path = inTests("Lib", "Expect.spec"),
        tests = {
            { name = "passes on equal values", groups = { "equal" } },
            {
                name = "fails on different values",
                groups = { "equal" },
                failure = { message = "expected 2, got 1", source = EXPECT, line = 13, trace = "" },
            },
            { name = "passes on tables with the same contents", groups = { "same" } },
            {
                name = "fails where a nested value differs",
                groups = { "same" },
                failure = { message = "expected 2, got 1 at outer.inner", source = EXPECT, line = 31, trace = "" },
            },
        },
    },
    {
        path = inTests("Lib", "Failures.spec"),
        tests = {
            {
                name = "reports every line of a message",
                groups = {},
                failure = { message = "first line\nsecond line\nthird line", source = FAILURES, line = 9, trace = "" },
            },
            {
                name = "reports a long message",
                groups = {},
                failure = {
                    message = `expected "{string.rep("right ", 30)}", got "{string.rep("left ", 30)}"`,
                    source = FAILURES,
                    line = 13,
                    trace = "",
                },
            },
            {
                name = "points at the helper that threw",
                groups = {},
                failure = {
                    message = "ReplicatedStorage.Tests.Utils.Thrower:2: thrown from a helper",
                    source = THROWER,
                    line = 2,
                    trace = "",
                },
            },
            {
                name = "names every group it sits in",
                groups = { "outer", "inner" },
                failure = { message = 'expected "expected", got "actual"', source = FAILURES, line = 31, trace = "" },
            },
        },
    },
    {
        path = inTests("Lib", "Groups.spec"),
        tests = {
            { name = "sits outside every group", groups = {} },
            { name = "sits in one group", groups = { "outer" } },
            { name = "sits in two groups", groups = { "outer", "inner" } },
            { name = "sits after a nested group", groups = { "outer" } },
            { name = "sits after every group", groups = {} },
        },
    },
    {
        path = inTests("Lib", "Single.spec"),
        tests = {
            { name = "stands alone", groups = {} },
        },
    },
    {
        path = inTests("Loader", "Cycle.spec"),
        tests = {},
        failure = {
            message = "[Litmus]: modules require each other in a cycle: Loader.CycleA -> Loader.CycleB -> Loader.CycleA",
            source = inTests("Anchor", "Loader", "CycleB"),
            line = 1,
            trace = "",
        },
    },
    {
        path = inTests("Loader", "MissingModule.spec"),
        tests = {},
        failure = {
            message = '[Litmus]: can\'t require "./Missing": there is no ModuleScript at that path',
            source = inTests("Anchor", "Loader", "MissingModule"),
            line = 1,
            trace = "",
        },
    },
    {
        path = inTests("Roblox", "Requires.spec"),
        tests = {
            { name = "requires a sibling with ./", groups = {} },
            { name = "requires a child with @self", groups = {} },
            { name = "requires from the DataModel with @game", groups = {} },
        },
    },
}

local function lines(ran: number, loaded: number, all: number): { outcome.Cell }
    return {
        {
            kind = "meter",
            parts = {
                { value = ran, tone = "good" },
                { value = loaded - ran, tone = "plain" },
                { value = all - loaded, tone = "dim" },
            },
        },
        { kind = "cell", text = `{math.floor(ran * 1000 / all) / 10}%`, align = "right", tone = "plain" },
        { kind = "cell", text = tostring(ran), align = "right", tone = "dim" },
        { kind = "cell", text = tostring(all), align = "right", tone = "dim" },
    }
end

local function folder(name: outcome.Cell, counts: { outcome.Cell }, open: boolean, rows: { outcome.Row }?): outcome.Row
    return { cells = { name, table.unpack(counts) }, open = open, rows = rows or {} }
end

local function dim(name: string): outcome.Cell
    return { kind = "cell", text = name, align = "left", tone = "dim" }
end

local SAMPLE_APPENDIX: outcome.Appendix = {
    { kind = "heading", text = "Lines run by folder" },
    {
        kind = "legend",
        items = {
            { label = "ran", tone = "good" },
            { label = "loaded but not run", tone = "plain" },
            { label = "never loaded", tone = "dim" },
        },
    },
    {
        kind = "tree",
        rows = {
            folder("src", lines(1840, 5200, 24000), true, {
                folder("Shop", lines(1700, 4900, 23800), true, {
                    folder("Checkout", lines(980, 2900, 9600), false, {
                        folder("Cart", lines(700, 2500, 3400), false, {
                            folder("Totals.luau", lines(140, 610, 610), false),
                            folder("AVeryLongModuleNameThatHasToBeCutShortToFit.luau", lines(80, 576, 576), false),
                        }),
                        folder("Receipts", lines(9, 9, 9), false),
                        folder(dim("2 folders no test loaded"), lines(0, 0, 1200), false, {
                            folder(dim("Coupons"), lines(0, 0, 1100), false),
                            folder(dim("Refunds"), lines(0, 0, 100), false),
                        }),
                    }),
                    folder(dim("Catalog"), lines(0, 0, 4100), false),
                }),
                folder("Shared", lines(124, 150, 155), false, {
                    folder("Format.luau", lines(119, 125, 125), false),
                }),
                folder("Tools", lines(16, 22, 22), false),
            }),
        },
    },
    {
        kind = "stats",
        items = {
            { label = "Coverage", text = "7.7% of 24,000 lines ran" },
            { label = "Loaded", text = "96 of 310 modules, 35.4% of their lines ran" },
        },
    },
}

local SAMPLE_RUN: outcome.Run = { kind = "results", specs = SAMPLE_RESULTS, appendix = SAMPLE_APPENDIX }

local function story(target: Frame): () -> ()
    local scope: flux.Scope = flux.scope()

    local shownTheme: flux.Value<StudioTheme> = scope:value(studio.Theme)
    theme.provide(scope, studioColors(scope, shownTheme))

    sources.provide(scope, place.sourceAt)

    local isDark: flux.Computed<boolean> = theme.colors(scope).isDark

    local connected: flux.Value<boolean> = scope:value(false)
    local cliResults: flux.Value<control.CliResults> = scope:value("unseen" :: control.CliResults)

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

                testActivated = function(): ()
                    cliResults:set("unseen")
                end,

                cliResults = if hasCliResults then cliResults else "none",
                cliResultsActivated = function(): ()
                    cliResults:set("seen")
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

            results(scope, {
                ran = SAMPLE_RUN,
            }),
        },
    }

    return function(): ()
        scope:destroy()
    end
end

return story
