local runService = game:GetService("RunService")

local watcher = require("@self/Watcher")

local ENABLED_SETTING: string = "Enabled"

-- A play test starts its own copy of every plugin; only the copy editing the place should answer
if not runService:IsEdit() then
    return
end

local toolbar: PluginToolbar = plugin:CreateToolbar("Litmus")
local button: PluginToolbarButton = toolbar:CreateButton("Litmus", "Run this place's tests when `litmus run` asks", "")
button.ClickableWhenViewportHidden = true

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
