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

local function describe(thrown: unknown): Failure
    if raised[thrown] then
        return thrown :: any
    end

    local message: string = tostring(thrown)

    -- Level 1 is this handler; C functions such as `error` come next and have no line
    local level: number = 2
    local source: string, line: number = debug.info(level, "sl")
    while line <= 0 do
        level += 1
        source, line = debug.info(level, "sl")
    end

    local trace: string = debug.traceback(nil, level)

    -- An error this lib raised on the caller's behalf belongs to the caller's line; `catch` is where the search ends
    local callerLevel: number = level
    local callerSource: string, callerLine: number = source, line
    while callerSource ~= OWN_SOURCE and (callerLine <= 0 or isLib(callerSource)) do
        callerLevel += 1
        callerSource, callerLine = debug.info(callerLevel, "sl")
    end

    if callerSource ~= OWN_SOURCE then
        source, line = callerSource, callerLine
    else
        -- None of the caller's code was running, as when a spec doesn't compile; the message names the place
        local namedSource: string?, namedLine: number? = positionIn(message)
        if namedSource and namedLine then
            source, line = namedSource, namedLine
        end
    end

    return {
        message = message,
        source = source,
        line = line,
        trace = trace,
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
function failure.catch(body: () -> ()): Failure?
    local _: boolean, problem: Failure? = xpcall(function(): Failure?
        body()
        return nil
    end, describe)

    return problem
end

return failure
