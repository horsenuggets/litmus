local httpService = game:GetService("HttpService")

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

local CLI_PORTS: { number } = { 37100, 37101 }

local CLI_PROTOCOL: number = 3

type Method = "GET" | "POST"

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

local function post(offer: Offer, route: string, message: { [string]: any }): boolean
    message.runId = offer.runId
    return (send(offer.port, "POST", route, message))
end

local bridge = {}

bridge.CLI_PORTS = CLI_PORTS
bridge.CLI_PROTOCOL = CLI_PROTOCOL

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
