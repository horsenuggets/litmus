local runService = game:GetService("RunService")

local imageIds = require("@self/ImageIds")
local watcher = require("@self/Watcher")

local ENABLED_SETTING: string = "Enabled"

local studio: Studio = settings().Studio

-- A play test starts its own copy of every plugin; only the copy editing the place should answer
if not runService:IsEdit() then
    return
end

-- `icon` is drawn to show on a dark toolbar, and `darkIcon` on a light one
local function themedIcon(): string
    return if studio.Theme.Name == "Dark" then imageIds.icon else imageIds.darkIcon
end

local toolbar: PluginToolbar = plugin:CreateToolbar("Litmus")
local button: PluginToolbarButton = toolbar:CreateButton("Litmus", "Run this place's tests when `litmus run` asks", themedIcon())
button.ClickableWhenViewportHidden = true

studio.ThemeChanged:Connect(function(): ()
    button.Icon = themedIcon()
end)

local enabled: boolean = plugin:GetSetting(ENABLED_SETTING) == true

local function apply(): ()
    button:SetActive(enabled)

    if enabled then
        watcher.start()
    else
        watcher.stop()
    end
end

button.Click:Connect(function(): ()
    enabled = not enabled

    plugin:SetSetting(ENABLED_SETTING, enabled)
    apply()
end)

plugin.Unloading:Connect(watcher.stop)

apply()
