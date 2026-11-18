export type Caught = {
    message: string,
    chunk: string,
    line: number,
    trace: string,
}

type Position = {
    chunk: string,
    line: number,
}

local raised: { [any]: true } = setmetatable({}, { __mode = "k" }) :: any

local OWN_SOURCE: string = debug.info(1, "s")

local LIB_PREFIX: string = string.match(OWN_SOURCE, "^(.*)Failure") or OWN_SOURCE

local function isLib(source: string): boolean
    return string.sub(source, 1, #LIB_PREFIX) == LIB_PREFIX
end

local function positionIn(message: string): Position?
    local chunk: string?, line: string? = string.match(message, "^(.-):(%d+): ")
    if not chunk then
        return nil
    end

    return { chunk = chunk, line = tonumber(line) :: number }
end

local function findCaller(level: number, isProject: (chunk: string) -> boolean): Position?
    level += 1

    local source: string, line: number = debug.info(level, "sl")
    while source ~= OWN_SOURCE do
        if line > 0 and not isLib(source) and isProject(source) then
            return { chunk = source, line = line }
        end

        level += 1
        source, line = debug.info(level, "sl")
    end

    return nil
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

    local blamed: Position = findCaller(level, isProject) or positionIn(message) or { chunk = source, line = line }

    return {
        message = message,
        chunk = blamed.chunk,
        line = blamed.line,
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
    local function attempt(): Caught?
        body()
        return nil
    end

    local function handle(thrown: unknown): Caught
        return describe(thrown, isProject)
    end

    local _: boolean, problem: Caught? = xpcall(attempt, handle)

    return problem
end

return failure
