export type Failure = {
    message: string,
    source: string,
    line: number,
    trace: string,
}

-- Tells a failure raised here apart from any other table a test might throw
local raised: { [any]: true } = setmetatable({}, { __mode = "k" }) :: any

local OWN_SOURCE: string = debug.info(1, "s")

-- What every chunk name in this lib starts with, which is how its frames are told apart on the stack
local LIB_PREFIX: string = string.match(OWN_SOURCE, "^(.*)Failure") or OWN_SOURCE

local function isLib(source: string): boolean
    return string.sub(source, 1, #LIB_PREFIX) == LIB_PREFIX
end

-- Reads the position Luau puts at the front of an error message, as in "Module:12: message"
local function positionIn(message: string): (string?, number?)
    local source: string?, line: string? = string.match(message, "^(.-):(%d+): ")
    return source, tonumber(line)
end

-- The caller's own frame at or above `level`, or nothing if the walk reaches `catch`, this module's next frame up, first
local function findCaller(level: number, isProject: (chunk: string) -> boolean): (string?, number?)
    -- `level` is as the function calling this counts it, and this function's own frame sits one below
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

local function describe(thrown: unknown, isProject: (chunk: string) -> boolean): Failure
    if raised[thrown] then
        return thrown :: any
    end

    local message: string = tostring(thrown)

    -- Level 1 is this function and level 2 the handler calling it; C functions such as `error` come next and have no line
    local level: number = 3
    local source: string, line: number = debug.info(level, "sl")
    while line <= 0 do
        level += 1
        source, line = debug.info(level, "sl")
    end

    -- An error this lib raised on the caller's behalf belongs to the caller's line
    local callerSource: string?, callerLine: number? = findCaller(level, isProject)
    if not callerSource then
        -- None of the caller's code was running, as when a spec doesn't compile; the message names the place
        callerSource, callerLine = positionIn(message)
    end

    return {
        message = message,
        source = callerSource or source,
        line = callerLine or line,
        trace = debug.traceback(nil, level),
    }
end

local failure = {}

-- `level` counts as it does for `error`: 2 blames whoever called the function raising
function failure.raise(message: string, level: number): never
    local source: string, line: number = debug.info(level + 1, "sl")

    local value: Failure = {
        message = message,
        source = source,
        line = line,
        trace = debug.traceback(nil, level + 1),
    }

    raised[value] = true
    error(value, 0)
end

-- Runs `body` and returns how it failed, or nil if it didn't
function failure.catch(body: () -> (), isProject: (chunk: string) -> boolean): Failure?
    local _: boolean, problem: Failure? = xpcall(function(): Failure?
        body()
        return nil
    end, function(thrown: unknown): Failure
        return describe(thrown, isProject)
    end)

    return problem
end

return failure
