-- Checks the lib without its test API, so a broken expect can't pass itself
-- Run from the command bar: loadstring(game.ReplicatedStorage.Tests.Core.Source)()

local replicatedStorage = game:GetService("ReplicatedStorage")

local lib = replicatedStorage.Litmus
local tests = replicatedStorage.Tests

type Failure = {
    message: string,
    source: { string },
    line: number,
    trace: string,
}

type TestResult = {
    name: string,
    groups: { string },
    failure: Failure?,
}

type SpecResult = {
    path: { string },
    tests: { TestResult },
    failure: Failure?,
}

-- Lists only the fields to compare, which leaves out engine wording
type ExpectedFailure = {
    message: string?,
    line: number,
}

type ExpectedTest = {
    name: string,
    groups: { string },
    failure: ExpectedFailure?,
}

-- Where the spec's copy sits once it is run, which is also where each of its failures must point
local PATH: string = "Interface/Expect.spec"

-- Every spec takes `expect` at its word, so its own results are the ones checked by hand
local EXPECTED: { ExpectedTest } = {
    { name = "passes on equal values", groups = { "equal" } },
    {
        name = "fails on different values",
        groups = { "equal" },
        failure = { message = "expected 2, got 1", line = 13 },
    },
    {
        name = "quotes strings",
        groups = { "equal" },
        failure = { message = 'expected "right", got "left"', line = 17 },
    },
    {
        name = "fails on separate tables with the same contents",
        groups = { "equal" },
        failure = { line = 21 },
    },
    { name = "passes on tables with the same contents", groups = { "same" } },
    {
        name = "fails where a nested value differs",
        groups = { "same" },
        failure = { message = "expected 2, got 1 at outer.inner", line = 31 },
    },
    {
        name = "fails on a missing entry",
        groups = { "same" },
        failure = { message = "expected 2, got nil at [2]", line = 35 },
    },
    {
        name = "fails on an extra entry",
        groups = { "same" },
        failure = { message = "expected nil, got 3 at [3]", line = 39 },
    },
    { name = "passes when the function throws", groups = { "error" } },
    {
        name = "fails when the function returns",
        groups = { "error" },
        failure = { message = "expected an error, got none", line = 51 },
    },
    { name = "passes on tables that contain themselves", groups = { "same" } },
}

local mismatches: { string } = {}

local function show(value: unknown): string
    return if type(value) == "string" then `"{value}"` else tostring(value)
end

local function compare(where: string, field: string, actual: unknown, expected: unknown): ()
    if actual ~= expected then
        table.insert(mismatches, `{where}: {field} is {show(actual)}, expected {show(expected)}`)
    end
end

local function compareFailure(where: string, actual: Failure?, expected: ExpectedFailure?): ()
    if not actual then
        if expected then
            table.insert(mismatches, `{where}: didn't fail, expected a failure`)
        end

        return
    end

    if not expected then
        table.insert(mismatches, `{where}: failed with {show(actual.message)}, expected no failure`)
        return
    end

    if expected.message then
        compare(where, "message", actual.message, expected.message)
    end

    compare(where, "source", table.concat(actual.source, "/"), PATH)
    compare(where, "line", actual.line, expected.line)

    if type(actual.trace) ~= "string" or actual.trace == "" then
        table.insert(mismatches, `{where}: trace is {show(actual.trace)}, expected a traceback`)
    end
end

local function compareTests(actual: { TestResult }, expected: { ExpectedTest }): ()
    compare(PATH, "test count", #actual, #expected)

    for index, wanted in expected do
        local result: TestResult? = actual[index]
        if not result then
            break
        end

        local where: string = `{PATH} > {wanted.name}`

        compare(where, "name", result.name, wanted.name)
        compare(where, "groups", table.concat(result.groups, " > "), table.concat(wanted.groups, " > "))
        compareFailure(where, result.failure, wanted.failure)
    end
end

-- Run as a copy kept out of the place: named as a spec there, it would fail in every other run
local copies: Instance = tests.Anchor.Interface:Clone()

local spec: Instance? = copies:FindFirstChild("Expect")
if not spec then
    error("[Core]: Tests.Anchor.Interface has no module named Expect", 0)
end

spec.Name ..= ".spec"

local entry = lib.Adapter.Roblox

-- Loaded straight from its source, so Studio's require cache stays out of it
local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
if not chunk then
    error(`[Core]: {entry:GetFullName()} didn't compile: {problem}`, 0)
end

local results: { SpecResult } = chunk().run(lib, { spec }).specs
copies:Destroy()

compare("run", "spec count", #results, 1)

local result: SpecResult? = results[1]
if result then
    compare("spec", "path", table.concat(result.path, "/"), PATH)
    compareFailure(PATH, result.failure, nil)
    compareTests(result.tests, EXPECTED)
end

if #mismatches == 0 then
    print(`[Core]: all {#EXPECTED} tests match`)
else
    for _, mismatch in mismatches do
        warn(`[Core]: {mismatch}`)
    end

    warn(`[Core]: mismatches: {#mismatches}`)
end
