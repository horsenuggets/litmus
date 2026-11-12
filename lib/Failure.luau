export type Failure = {
    message: string,
    source: string,
    line: number,
    trace: string,
}

-- Tells a failure raised here apart from any other table a test might throw
local raised: { [any]: true } = setmetatable({}, { __mode = "k" }) :: any

local function describe(thrown: unknown): Failure
    if raised[thrown] then
        return thrown :: any
    end

    -- Level 1 is this handler; C functions such as `error` come next and have no line
    local level: number = 2
    local source: string, line: number = debug.info(level, "sl")
    while line <= 0 do
        level += 1
        source, line = debug.info(level, "sl")
    end

    return {
        message = tostring(thrown),
        source = source,
        line = line,
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
function failure.catch(body: () -> ()): Failure?
    local _: boolean, problem: Failure? = xpcall(function(): Failure?
        body()
        return nil
    end, describe)

    return problem
end

return failure
