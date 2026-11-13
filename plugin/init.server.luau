local runService = game:GetService("RunService")

local bridge = require("@self/Bridge")
local place = require("@self/Place")
local run = require("@self/Run")

local ENABLED_SETTING: string = "Enabled"
local POLL_SECONDS: number = 1

-- A play test starts its own copy of every plugin; only the copy editing the place should answer
if not runService:IsEdit() then
    return
end

local toolbar: PluginToolbar = plugin:CreateToolbar("Litmus")
local button: PluginToolbarButton = toolbar:CreateButton("Litmus", "Run this place's tests when `litmus run` asks", "")
button.ClickableWhenViewportHidden = true

local enabled: boolean = plugin:GetSetting(ENABLED_SETTING) == true
local polling: boolean = false

-- The last run seen on each port that needs no further answer from this place
local settled: { [number]: string } = {}

local function answer(port: number, offer: bridge.Offer): ()
    if offer.protocol ~= bridge.PROTOCOL then
        settled[port] = offer.run
        warn(`[Litmus]: {offer.project} speaks protocol {offer.protocol} and this plugin speaks {bridge.PROTOCOL}; update the older one`)
        return
    end

    local specs: { Instance } = place.findAll(offer.specs)
    if #specs == 0 then
        settled[port] = offer.run
        return
    end

    -- Left unsettled, so a place Rojo is still syncing gets compared again on the next poll
    local comparison: place.Comparison = place.compare(offer.files)
    if #comparison.missing > 0 or #comparison.differing > 0 then
        bridge.reportMismatch(port, offer.run, game.Name, comparison.missing, comparison.differing)
        return
    end

    settled[port] = offer.run

    if not bridge.claim(port, offer.run, game.Name) then
        return
    end

    local ok: boolean, results: any = pcall(run.specs, specs)
    if not ok then
        bridge.reportError(port, offer.run, tostring(results))
        warn(`[Litmus]: couldn't run {offer.project}: {results}`)
    elseif bridge.reportResults(port, offer.run, results) then
        print(`[Litmus]: ran {#results} specs for {offer.project}`)
    else
        warn(`[Litmus]: ran {offer.project}, but couldn't send the results back`)
    end
end

local function poll(): ()
    polling = true

    while enabled do
        for _, port in bridge.PORTS do
            local offer: bridge.Offer? = bridge.offer(port)
            if not offer or settled[port] == offer.run then
                continue
            end

            local ok: boolean, problem: unknown = pcall(answer, port, offer)
            if not ok then
                settled[port] = offer.run
                warn(`[Litmus]: couldn't answer {offer.project}: {problem}`)
            end
        end

        task.wait(POLL_SECONDS)
    end

    polling = false
end

local function apply(): ()
    button:SetActive(enabled)

    if enabled and not polling then
        task.spawn(poll)
    end
end

button.Click:Connect(function(): ()
    enabled = not enabled
    plugin:SetSetting(ENABLED_SETTING, enabled)
    apply()
end)

plugin.Unloading:Connect(function(): ()
    enabled = false
end)

apply()
