local runService = game:GetService("RunService")

local control = require("@self/Interface/Control")
local flux = require("@self/Packages/Flux")
local harness = require("@self/Harness")
local imageIds = require("@self/ImageIds")
local outcome = require("@self/Outcome")
local place = require("@self/Place")
local results = require("@self/Interface/Results")
local sources = require("@self/Interface/Sources")
local studioColors = require("@self/Interface/StudioColors")
local theme = require("@self/Interface/Theme")
local watcher = require("@self/Watcher")

type Origin = "Test" | "CLI" | "Standalone"

type Shown = {
    origin: Origin,
    ran: outcome.Run,
    sourceAt: sources.Reader,
}

type CliRun = {
    arrived: watcher.Arrival,
    seen: boolean,
}

local CONNECTED_SETTING: string = "Connected"

local NOTHING_RAN: outcome.Run = { kind = "results", specs = {} }

local isTheCopyEditingThePlace: boolean = runService:IsEdit()
if not isTheCopyEditingThePlace then
    return
end

local studio: Studio = settings().Studio

local controlWindowInfo: DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 210, 300, 210)

local resultsWindowInfo: DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 560, 640, 360, 300)

local function themedIcon(): string
    return if studio.Theme.Name == "Dark" then imageIds.logoOnDark else imageIds.logoOnLight
end

local function window(id: string, title: string, info: DockWidgetPluginGuiInfo): DockWidgetPluginGui
    local widget: DockWidgetPluginGui = plugin:CreateDockWidgetPluginGuiAsync(id, info)
    widget.Name = id
    widget.Title = title
    widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    return widget
end

local toolbar: PluginToolbar = plugin:CreateToolbar("Litmus")
local button: PluginToolbarButton = toolbar:CreateButton("Litmus", "Show or hide the Litmus window", themedIcon())
button.ClickableWhenViewportHidden = true

local controlWindow: DockWidgetPluginGui = window("LitmusControl", "Litmus", controlWindowInfo)
local resultsWindow: DockWidgetPluginGui = window("LitmusResults", "Litmus results", resultsWindowInfo)

local scope: flux.Scope = flux.scope()

local studioTheme: flux.Value<StudioTheme> = scope:value(studio.Theme)
theme.provide(scope, studioColors(scope, studioTheme))

studio.ThemeChanged:Connect(function(): ()
    studioTheme:set(studio.Theme)
    button.Icon = themedIcon()
end)

local connected: flux.Value<boolean> = scope:value(plugin:GetSetting(CONNECTED_SETTING) == true)

local shown: flux.Value<Shown?> = scope:value(nil :: Shown?)
local cliRun: flux.Value<CliRun?> = scope:value(nil :: CliRun?)

sources.provide(scope, function(path: outcome.Path): string?
    local showing: Shown? = flux.peek(shown)
    return if showing then showing.sourceAt(path) else nil
end)

local function show(showing: Shown): ()
    shown:set(showing)

    resultsWindow.Title = `Litmus: {showing.origin}`
    resultsWindow.Enabled = true
end

local function showArrival(arrived: watcher.Arrival): ()
    show({
        origin = arrived.origin,
        ran = arrived.ran,
        sourceAt = arrived.sourceAt,
    })
end

local function cliRan(arrived: watcher.Arrival): ()
    local showing: Shown? = flux.peek(shown)

    local seen: boolean = resultsWindow.Enabled and showing ~= nil and showing.origin ~= "Test"
    cliRun:set({ arrived = arrived, seen = seen })

    if seen then
        showArrival(arrived)
    end
end

control(scope, {
    connected = connected,
    connectActivated = function(): ()
        connected:set(not flux.peek(connected))
    end,

    testActivated = function(): ()
        show({ origin = "Test", ran = harness.all(), sourceAt = place.sourceAt })
    end,

    cliResults = scope:computed(function(use: flux.Use): control.CliResults
        local latest: CliRun? = use(cliRun)
        if not latest then
            return "none"
        end

        return if latest.seen then "seen" else "unseen"
    end),

    cliResultsActivated = function(): ()
        local latest: CliRun? = flux.peek(cliRun)
        if not latest then
            return
        end

        cliRun:set({ arrived = latest.arrived, seen = true })
        showArrival(latest.arrived)
    end,
}).Parent = controlWindow

results(scope, {
    ran = scope:computed(function(use: flux.Use): outcome.Run
        local showing: Shown? = use(shown)
        return if showing then showing.ran else NOTHING_RAN
    end),
}).Parent = resultsWindow

scope:effect(function(use: flux.Use): ()
    local now: boolean = use(connected)

    plugin:SetSetting(CONNECTED_SETTING, now)

    if now then
        watcher.start(cliRan)
    else
        watcher.stop()
    end
end)

button:SetActive(controlWindow.Enabled)

button.Click:Connect(function(): ()
    controlWindow.Enabled = not controlWindow.Enabled
end)

controlWindow:GetPropertyChangedSignal("Enabled"):Connect(function(): ()
    button:SetActive(controlWindow.Enabled)
end)

plugin.Unloading:Connect(function(): ()
    watcher.stop()
    scope:destroy()
end)
