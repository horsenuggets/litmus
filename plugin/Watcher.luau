local bridge = require("./Bridge")
local harness = require("./Harness")
local outcome = require("./Outcome")
local place = require("./Place")

export type Arrival = {
    ran: outcome.Run,
    origin: "CLI" | "Standalone",
    sourceAt: (path: outcome.Path) -> string?,
}

export type Listener = (arrived: Arrival) -> ()

local POLL_SECONDS: number = 1

local watching: boolean = false

local watched: { [number]: true } = {}

local answering: boolean = false

local settled: { [number]: string } = {}

local listener: Listener? = nil

local function collected(offer: bridge.ShowOffer): Arrival?
    local received: bridge.Collected? = bridge.collect(offer)
    if not received then
        warn(`[Litmus]: couldn't collect the standalone run of {offer.project}`)
        return nil
    end

    local texts: { [string]: string } = {}
    for _, source in received.sources do
        texts[table.concat(source.path, "/")] = source.text
    end

    print(`[Litmus]: collected the standalone run of {offer.project}`)

    return {
        ran = outcome.ofLib(received.results),
        origin = "Standalone",

        sourceAt = function(path: outcome.Path): string?
            return texts[table.concat(path, "/")]
        end,
    }
end

local function answer(offer: bridge.Offer): (boolean, Arrival?)
    if offer.protocol ~= bridge.PROTOCOL then
        warn(`[Litmus]: {offer.project} speaks protocol {offer.protocol} and this plugin speaks {bridge.PROTOCOL}; update the older one`)
        return true, nil
    end

    if offer.kind == "show" then
        return true, collected(offer)
    end

    local specs: { Instance } = place.findAll(offer.specs)
    if #specs == 0 then
        return true, nil
    end

    local comparison: place.Comparison = place.compare(offer.files)
    if #comparison.missing > 0 or #comparison.differing > 0 then
        bridge.reportMismatch(offer, comparison.missing, comparison.differing)

        return false, nil
    end

    if not bridge.claim(offer) then
        return true, nil
    end

    local ran: outcome.Run = harness.specs(specs)

    if ran.kind == "problem" then
        bridge.reportError(offer, ran.message)
        warn(`[Litmus]: couldn't run {offer.project}: {ran.message}`)
    elseif bridge.reportResults(offer, { specs = ran.specs, appendix = ran.appendix, failure = ran.failure }) then
        print(`[Litmus]: ran {#ran.specs} specs for {offer.project}`)
    else
        warn(`[Litmus]: ran {offer.project}, but couldn't send the results back`)
    end

    return true, { ran = ran, origin = "CLI", sourceAt = place.sourceAt }
end

local function watch(port: number): ()
    watched[port] = true

    while watching do
        local started: number = os.clock()

        local offer: bridge.Offer? = bridge.offer(port)
        if offer and not answering and settled[port] ~= offer.runId then
            answering = true
            local answered: boolean, done: unknown, arrived: Arrival? = pcall(answer, offer)
            answering = false

            if not answered then
                warn(`[Litmus]: couldn't answer {offer.project}: {done}`)
            end

            if not answered or done == true then
                settled[port] = offer.runId
            end

            local told: Listener? = listener
            if answered and arrived and told then
                task.spawn(told, arrived)
            end
        end

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
