local bridge = require("./Bridge")
local outcome = require("./Outcome")
local place = require("./Place")
local run = require("./Run")

-- Told what came of each run this place carries out for a CLI
export type Listener = (ran: outcome.Run) -> ()

local POLL_SECONDS: number = 1

local watching: boolean = false

-- The ports whose loop is still running, so stopping and starting again doesn't begin a second one
local watched: { [number]: true } = {}

-- Held while an offer is answered, so one from a second terminal waits its turn and isn't claimed only to be refused
local answering: boolean = false

-- The last run seen on each port that needs no further answer from this place
local settled: { [number]: string } = {}

local listener: Listener? = nil

-- Returns whether this place is done with the offer, and what came of the run if it carried one out
local function answer(offer: bridge.Offer): (boolean, outcome.Run?)
    if offer.protocol ~= bridge.PROTOCOL then
        warn(`[Litmus]: {offer.project} speaks protocol {offer.protocol} and this plugin speaks {bridge.PROTOCOL}; update the older one`)
        return true, nil
    end

    local specs: { Instance } = place.findAll(offer.specs)
    if #specs == 0 then
        return true, nil
    end

    local comparison: place.Comparison = place.compare(offer.files)
    if #comparison.missing > 0 or #comparison.differing > 0 then
        bridge.reportMismatch(offer, comparison.missing, comparison.differing)

        -- Not done: Rojo may still be syncing, so the place is compared again on the next poll
        return false, nil
    end

    if not bridge.claim(offer) then
        return true, nil
    end

    local ran: outcome.Run = run.specs(specs)

    if ran.kind == "problem" then
        bridge.reportError(offer, ran.message)
        warn(`[Litmus]: couldn't run {offer.project}: {ran.message}`)
    elseif bridge.reportResults(offer, ran.results) then
        print(`[Litmus]: ran {#ran.results} specs for {offer.project}`)
    else
        warn(`[Litmus]: ran {offer.project}, but couldn't send the results back`)
    end

    return true, ran
end

-- One loop per port: Windows takes two seconds to refuse an idle port, and a shared round made every run wait for all of them
local function watch(port: number): ()
    watched[port] = true

    while watching do
        local started: number = os.clock()

        local offer: bridge.Offer? = bridge.offer(port)
        if offer and not answering and settled[port] ~= offer.runId then
            answering = true
            local answered: boolean, done: unknown, ran: outcome.Run? = pcall(answer, offer)
            answering = false

            if not answered then
                warn(`[Litmus]: couldn't answer {offer.project}: {done}`)
            end

            -- An answer that failed is settled too, or it would fail again on every poll
            if not answered or done == true then
                settled[port] = offer.runId
            end

            -- Told on a thread of its own, so a fault in the listener reads as the listener's and polling goes on
            local told: Listener? = listener
            if answered and ran and told then
                task.spawn(told, ran)
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

function watcher.start(told: Listener): ()
    listener = told
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
