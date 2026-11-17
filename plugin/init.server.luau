local runService = game:GetService("RunService")

local control = require("@self/Interface/Control")
local flux = require("@self/Packages/Flux")
local imageIds = require("@self/ImageIds")
local outcome = require("@self/Outcome")
local place = require("@self/Place")
local results = require("@self/Interface/Results")
local run = require("@self/Run")
local sources = require("@self/Interface/Sources")
local studioColors = require("@self/Interface/StudioColors")
local theme = require("@self/Interface/Theme")
local watcher = require("@self/Watcher")

-- Where a run was started from, which the results window's title says
type Source = "Test" | "CLI" | "Standalone"

-- What the results window is showing
type Shown = {
    source: Source,
    ran: outcome.Run,
    sourceAt: sources.Reader,
}

-- The latest run carried out for a CLI or collected from one, and whether it has been opened since
type CliRun = {
    arrived: watcher.Arrival,
    seen: boolean,
}

-- Kept under its first name, from when the toolbar button was what switched this
local CONNECTED_SETTING: string = "Enabled"

local NOTHING_RAN: outcome.Run = { kind = "results", results = {} }

-- A play test starts its own copy of every plugin, and the test place holds a copy of this script as well; only
-- the copy editing the place should do anything, so nothing a plugin alone may use comes before this
if not runService:IsEdit() then
    return
end

local studio: Studio = settings().Studio

-- Docked beside Rojo's window by default, and the same size, so the two can share a slot
local controlWindowInfo: DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 210, 300, 210)

-- Always starts shut, since it has nothing to show until a run happens
local resultsWindowInfo: DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 560, 640, 360, 300)

-- `icon` is drawn to show on a dark toolbar, and `darkIcon` on a light one
local function themedIcon(): string
    return if studio.Theme.Name == "Dark" then imageIds.icon else imageIds.darkIcon
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

-- Whether this place answers `litmus test`; this holds whether or not the control window is showing
local connected: flux.Value<boolean> = scope:value(plugin:GetSetting(CONNECTED_SETTING) == true)

local shown: flux.Value<Shown?> = scope:value(nil :: Shown?)
local cliRun: flux.Value<CliRun?> = scope:value(nil :: CliRun?)

sources.provide(scope, function(path: outcome.Path): string?
    local showing: Shown? = flux.peek(shown)
    return if showing then showing.sourceAt(path) else nil
end)

local function show(showing: Shown): ()
    shown:set(showing)

    resultsWindow.Title = `Litmus: {showing.source}`
    resultsWindow.Enabled = true
end

local function showArrival(arrived: watcher.Arrival): ()
    show({
        source = if arrived.standalone then "Standalone" else "CLI",
        ran = arrived.ran,
        sourceAt = arrived.sourceAt,
    })
end

local function cliRan(arrived: watcher.Arrival): ()
    local showing: Shown? = flux.peek(shown)

    -- A window already open on the CLI's results takes the new ones at once, which leaves nothing unseen
    local seen: boolean = resultsWindow.Enabled and showing ~= nil and showing.source ~= "Test"
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
        show({ source = "Test", ran = run.all(), sourceAt = place.sourceAt })
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

-- The one place the checkbox's state takes effect, both when it changes and when the plugin loads
scope:effect(function(use: flux.Use): ()
    local now: boolean = use(connected)

    plugin:SetSetting(CONNECTED_SETTING, now)

    if now then
        watcher.start(cliRan)
    else
        watcher.stop()
    end
end)

-- Studio brings the control window back as it was left, so the button starts from the window and follows it
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
