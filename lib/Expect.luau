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

local function difference(actual: any, expected: any, path: string, compared: { [any]: { [any]: true } }): string?
    if actual == expected then
        return nil
    end

    if type(actual) ~= "table" or type(expected) ~= "table" then
        local place: string = if path == "" then "" else ` at {path}`
        return `expected {show(expected)}, got {show(actual)}{place}`
    end

    local partners: { [any]: true } = compared[actual] or {}
    if partners[expected] then
        return nil
    end

    compared[actual] = partners
    partners[expected] = true

    for key: any, value: any in expected do
        local found: string? = difference(actual[key], value, extend(path, key), compared)
        if found then
            return found
        end
    end

    for key: any, value: any in actual do
        if expected[key] == nil then
            return difference(value, nil, extend(path, key), compared)
        end
    end

    return nil
end

local expect = {}

function expect.equal<T>(actual: T, expected: T): ()
    if actual ~= expected then
        failure.raise(`expected {show(expected)}, got {show(actual)}`, 2)
    end
end

function expect.same<T>(actual: T, expected: T): ()
    local found: string? = difference(actual, expected, "", {})
    if found then
        failure.raise(found, 2)
    end
end

function expect.truthy(value: unknown): ()
    if not value then
        failure.raise(`expected a truthy value, got {show(value)}`, 2)
    end
end

function expect.error(run: () -> ...unknown, text: string?): ()
    local succeeded: boolean, thrown: unknown = pcall(run)
    local wanted: string = if text then `an error containing {show(text)}` else "an error"

    if succeeded then
        failure.raise(`expected {wanted}, got none`, 2)
    end

    local message: string = tostring(thrown)
    if text and not string.find(message, text, 1, true) then
        failure.raise(`expected {wanted}, got {show(message)}`, 2)
    end
end

local never = {}

function never.equal<T>(actual: T, unwanted: T): ()
    if actual == unwanted then
        failure.raise(`expected anything but {show(unwanted)}`, 2)
    end
end

function never.same<T>(actual: T, unwanted: T): ()
    if not difference(actual, unwanted, "", {}) then
        failure.raise("expected different contents, got the same", 2)
    end
end

function never.truthy(value: unknown): ()
    if value then
        failure.raise(`expected nil or false, got {show(value)}`, 2)
    end
end

expect.never = never

return expect
