local bridge = require("./Bridge")
local place = require("./Place")
local run = require("./Run")

local POLL_SECONDS: number = 1

local watching: boolean = false

-- The ports whose loop is still running, so stopping and starting again doesn't begin a second one
local watched: { [number]: true } = {}

-- Held while a run is answered, so two terminals can't make this place run tests at the same time
local answering: boolean = false

-- The last run seen on each port that needs no further answer from this place
local settled: { [number]: string } = {}

-- Returns whether this place is done with the offer
local function answer(offer: bridge.Offer): boolean
    if offer.protocol ~= bridge.PROTOCOL then
        warn(`[Litmus]: {offer.project} speaks protocol {offer.protocol} and this plugin speaks {bridge.PROTOCOL}; update the older one`)
        return true
    end

    local specs: { Instance } = place.findAll(offer.specs)
    if #specs == 0 then
        return true
    end

    local comparison: place.Comparison = place.compare(offer.files)
    if #comparison.missing > 0 or #comparison.differing > 0 then
        bridge.reportMismatch(offer, comparison.missing, comparison.differing)

        -- Not done: Rojo may still be syncing, so the place is compared again on the next poll
        return false
    end

    if not bridge.claim(offer) then
        return true
    end

    local ok: boolean, results: any = pcall(run.specs, specs)
    if not ok then
        bridge.reportError(offer, tostring(results))
        warn(`[Litmus]: couldn't run {offer.project}: {results}`)
    elseif bridge.reportResults(offer, results) then
        print(`[Litmus]: ran {#results} specs for {offer.project}`)
    else
        warn(`[Litmus]: ran {offer.project}, but couldn't send the results back`)
    end

    return true
end

-- One loop per port: Windows takes two seconds to refuse an idle port, and a shared round made every run wait for all of them
local function watch(port: number): ()
    watched[port] = true

    while watching do
        local started: number = os.clock()

        local offer: bridge.Offer? = bridge.offer(port)
        if offer and not answering and settled[port] ~= offer.runId then
            answering = true
            local answered: boolean, result: unknown = pcall(answer, offer)
            answering = false

            if not answered then
                warn(`[Litmus]: couldn't answer {offer.project}: {result}`)
            end

            -- An answer that failed is settled too, or it would fail again on every poll
            if not answered or result == true then
                settled[port] = offer.runId
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

local watcher = {}

function watcher.start(): ()
    watching = true

    for _, port in bridge.PORTS do
        if not watched[port] then
            task.spawn(watch, port)
        end
    end
end

function watcher.stop(): ()
    watching = false
end

return watcher
