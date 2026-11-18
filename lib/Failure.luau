export type Caught = {
    message: string,
    chunk: string,
    line: number,
    trace: string,
}

local raised: { [any]: true } = setmetatable({}, { __mode = "k" }) :: any

local OWN_SOURCE: string = debug.info(1, "s")

local LIB_PREFIX: string = string.match(OWN_SOURCE, "^(.*)Failure") or OWN_SOURCE

local function isLib(source: string): boolean
    return string.sub(source, 1, #LIB_PREFIX) == LIB_PREFIX
end

local function positionIn(message: string): (string?, number?)
    local source: string?, line: string? = string.match(message, "^(.-):(%d+): ")
    return source, tonumber(line)
end

local function findCaller(level: number, isProject: (chunk: string) -> boolean): (string?, number?)
    level += 1

    local source: string, line: number = debug.info(level, "sl")
    while source ~= OWN_SOURCE do
        if line > 0 and not isLib(source) and isProject(source) then
            return source, line
        end

        level += 1
        source, line = debug.info(level, "sl")
    end

    return nil, nil
end

local function describe(thrown: unknown, isProject: (chunk: string) -> boolean): Caught
    if raised[thrown] then
        return thrown :: any
    end

    local message: string = tostring(thrown)

    local level: number = 3
    local source: string, line: number = debug.info(level, "sl")
    while line <= 0 do
        level += 1
        source, line = debug.info(level, "sl")
    end

    local callerSource: string?, callerLine: number? = findCaller(level, isProject)
    if not callerSource then
        callerSource, callerLine = positionIn(message)
    end

    return {
        message = message,
        chunk = callerSource or source,
        line = callerLine or line,
        trace = debug.traceback(nil, level),
    }
end

local failure = {}

function failure.raise(message: string, level: number): never
    local source: string, line: number = debug.info(level + 1, "sl")

    local value: Caught = {
        message = message,
        chunk = source,
        line = line,
        trace = debug.traceback(nil, level + 1),
    }

    raised[value] = true
    error(value, 0)
end

function failure.catch(body: () -> (), isProject: (chunk: string) -> boolean): Caught?
    local _: boolean, problem: Caught? = xpcall(function(): Caught?
        body()
        return nil
    end, function(thrown: unknown): Caught
        return describe(thrown, isProject)
    end)

    return problem
end

return failure
