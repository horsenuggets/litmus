local failure = require("./Failure")

local function show(value: unknown): string
    return if type(value) == "string" then `"{value}"` else tostring(value)
end

local function extend(path: string, key: unknown): string
    if type(key) ~= "string" then
        return `{path}[{tostring(key)}]`
    end

    return if path == "" then key else `{path}.{key}`
end

-- Describes where two values first differ, or returns nil when they match
local function difference(actual: any, expected: any, path: string): string?
    if actual == expected then
        return nil
    end

    if type(actual) ~= "table" or type(expected) ~= "table" then
        local place: string = if path == "" then "" else ` at {path}`
        return `expected {show(expected)}, got {show(actual)}{place}`
    end

    for key: any, value: any in expected do
        local found: string? = difference(actual[key], value, extend(path, key))
        if found then
            return found
        end
    end

    for key: any, value: any in actual do
        if expected[key] == nil then
            return difference(value, nil, extend(path, key))
        end
    end

    return nil
end

local expect = {}

-- Compares with ==, so two separate tables never match; `same` compares their contents
function expect.equal<T>(actual: T, expected: T): ()
    if actual ~= expected then
        failure.raise(`expected {show(expected)}, got {show(actual)}`, 2)
    end
end

function expect.same<T>(actual: T, expected: T): ()
    local found: string? = difference(actual, expected, "")
    if found then
        failure.raise(found, 2)
    end
end

function expect.error(run: () -> ...unknown): ()
    if pcall(run) then
        failure.raise("expected an error, got none", 2)
    end
end

return expect
