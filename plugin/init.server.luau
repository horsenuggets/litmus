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

-- The ports whose loop is still running, so switching off and on again doesn't start a second one
local watched: { [number]: true } = {}

-- Held while a run is answered, so two terminals can't make this place run tests at the same time
local answering: boolean = false

-- The last run seen on each port that needs no further answer from this place
local settled: { [number]: string } = {}

local function answer(port: number, offer: bridge.Offer): ()
    if offer.protocol ~= bridge.PROTOCOL then
        settled[port] = offer.runId
        warn(`[Litmus]: {offer.project} speaks protocol {offer.protocol} and this plugin speaks {bridge.PROTOCOL}; update the older one`)
        return
    end

    local specs: { Instance } = place.findAll(offer.specs)
    if #specs == 0 then
        settled[port] = offer.runId
        return
    end

    -- Left unsettled, so a place Rojo is still syncing gets compared again on the next poll
    local comparison: place.Comparison = place.compare(offer.files)
    if #comparison.missing > 0 or #comparison.differing > 0 then
        bridge.reportMismatch(port, offer.runId, game.Name, comparison.missing, comparison.differing)
        return
    end

    settled[port] = offer.runId

    if not bridge.claim(port, offer.runId, game.Name) then
        return
    end

    local ok: boolean, results: any = pcall(run.specs, specs)
    if not ok then
        bridge.reportError(port, offer.runId, tostring(results))
        warn(`[Litmus]: couldn't run {offer.project}: {results}`)
    elseif bridge.reportResults(port, offer.runId, results) then
        print(`[Litmus]: ran {#results} specs for CLI`)
    else
        warn(`[Litmus]: ran {offer.project}, but couldn't send the results back`)
    end
end

-- One loop per port: Windows takes two seconds to refuse an idle port, and a shared round made every run wait for all of them
local function watch(port: number): ()
    watched[port] = true

    while enabled do
        local started: number = os.clock()

        local offer: bridge.Offer? = bridge.offer(port)
        if offer and not answering and settled[port] ~= offer.runId then
            answering = true
            local ok: boolean, problem: unknown = pcall(answer, port, offer)
            answering = false

            if not ok then
                settled[port] = offer.runId
                warn(`[Litmus]: couldn't answer {offer.project}: {problem}`)
            end
        end

        -- A refused request has already taken its time; only a quick answer needs the pause
        local remaining: number = POLL_SECONDS - (os.clock() - started)
        if remaining > 0 then
            task.wait(remaining)
        end
    end

    watched[port] = nil
end

local function apply(): ()
    button:SetActive(enabled)

    if not enabled then
        return
    end

    for _, port in bridge.PORTS do
        if not watched[port] then
            task.spawn(watch, port)
        end
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
