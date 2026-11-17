local httpService = game:GetService("HttpService")

-- The names leading from `game` to an instance; never joined, since a name can hold dots
export type Path = { string }

export type File = {
    path: Path,
    hash: string,
}

export type RunOffer = {
    protocol: number,
    kind: "run",
    project: string,
    runId: string,
    files: { File },
    specs: { Path },

    -- Not sent by the CLI: the port the offer was read from, which is where its answers go
    port: number,
}

export type ShowOffer = {
    protocol: number,
    kind: "show",
    project: string,
    runId: string,

    port: number,
}

export type Offer = RunOffer | ShowOffer

export type Source = {
    path: Path,
    text: string,
}

export type Collected = {
    results: any,
    sources: { Source },
}

-- The CLI takes the first of these that is free, so the two lists have to stay the same
local PORTS: { number } = { 37100, 37101 }

-- Raised whenever the plugin and the CLI would stop understanding each other
local PROTOCOL: number = 3

type Method = "GET" | "POST"

-- Returns whether the CLI accepted the request, and what it answered
local function send(port: number, method: Method, route: string, body: { [string]: any }?): (boolean, string)
    local url: string = `http://127.0.0.1:{port}{route}`

    local ok: boolean, response: any = pcall(function(): any
        if not body then
            return httpService:RequestAsync({ Url = url, Method = method })
        end

        return httpService:RequestAsync({
            Url = url,
            Method = method,
            Headers = { ["Content-Type"] = "application/json" },
            Body = httpService:JSONEncode(body),
        })
    end)

    if not ok then
        return false, ""
    end

    return response.Success, response.Body
end

-- Answers an offer, naming its run so the CLI can tell the message isn't for an earlier one
local function post(offer: Offer, route: string, message: { [string]: any }): boolean
    message.runId = offer.runId
    return (send(offer.port, "POST", route, message))
end

local bridge = {}

bridge.PORTS = PORTS
bridge.PROTOCOL = PROTOCOL

-- What the litmus run on this port is offering, or nil when no run is there
function bridge.offer(port: number): Offer?
    local ok: boolean, body: string = send(port, "GET", "/offer")
    if not ok then
        return nil
    end

    local decoded: boolean, offer: any = pcall(httpService.JSONDecode, httpService, body)
    if not decoded or type(offer) ~= "table" or type(offer.runId) ~= "string" then
        return nil
    end

    offer.port = port
    return offer
end

-- False when another place took the run first
function bridge.claim(offer: Offer): boolean
    return post(offer, "/claim", { place = game.Name })
end

function bridge.collect(offer: ShowOffer): Collected?
    local ok: boolean, body: string = send(offer.port, "POST", "/collect", { runId = offer.runId, place = game.Name })
    if not ok then
        return nil
    end

    local decoded: boolean, collected: any = pcall(httpService.JSONDecode, httpService, body)
    if not decoded or type(collected) ~= "table" or type(collected.results) ~= "table" or type(collected.sources) ~= "table" then
        return nil
    end

    return collected
end

function bridge.reportMismatch(offer: Offer, missing: { Path }, differing: { Path }): ()
    post(offer, "/mismatch", { place = game.Name, missing = missing, differing = differing })
end

function bridge.reportResults(offer: Offer, results: any): boolean
    return post(offer, "/result", { results = results })
end

function bridge.reportError(offer: Offer, message: string): boolean
    return post(offer, "/result", { error = message })
end

return bridge
