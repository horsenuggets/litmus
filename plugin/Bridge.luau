local httpService = game:GetService("HttpService")

-- The names leading from `game` to an instance; never joined, since a name can hold dots
export type Path = { string }

export type File = {
    path: Path,
    hash: string,
}

export type Offer = {
    protocol: number,
    project: string,
    run: string,
    files: { File },
    specs: { Path },
}

-- The CLI takes the first of these that is free, so the two lists have to stay the same
local PORTS: { number } = { 37100, 37101, 37102, 37103 }

-- Raised whenever the plugin and the CLI would stop understanding each other
local PROTOCOL: number = 1

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
    if not decoded or type(offer) ~= "table" or type(offer.run) ~= "string" then
        return nil
    end

    return offer
end

-- False when another place took the run first
function bridge.claim(port: number, run: string, placeName: string): boolean
    local ok: boolean = send(port, "POST", "/claim", { run = run, place = placeName })
    return ok
end

function bridge.reportMismatch(port: number, run: string, placeName: string, missing: { Path }, differing: { Path }): ()
    send(port, "POST", "/mismatch", { run = run, place = placeName, missing = missing, differing = differing })
end

function bridge.reportResults(port: number, run: string, results: any): boolean
    local ok: boolean = send(port, "POST", "/result", { run = run, results = results })
    return ok
end

function bridge.reportError(port: number, run: string, message: string): boolean
    local ok: boolean = send(port, "POST", "/result", { run = run, error = message })
    return ok
end

return bridge
