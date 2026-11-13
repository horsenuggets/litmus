-- Checks the lib without its test API, so a broken expect can't pass itself
-- Run from the command bar: loadstring(game.ReplicatedStorage.Tests.Anchor.Source)()

local replicatedStorage = game:GetService("ReplicatedStorage")

local lib = replicatedStorage.Packages.Litmus
local tests = replicatedStorage.Tests

type Failure = {
    message: string,
    source: string,
    line: number,
    trace: string,
}

type TestResult = {
    name: string,
    groups: { string },
    failure: Failure?,
}

type SpecResult = {
    path: string,
    tests: { TestResult },
    failure: Failure?,
}

-- Lists only the fields to compare, which leaves out engine wording
type ExpectedFailure = {
    message: string?,
    source: string?,
    line: number?,
}

type ExpectedTest = {
    name: string,
    groups: { string },
    failure: ExpectedFailure?,
}

type ExpectedSpec = {
    path: string,
    tests: { ExpectedTest },
    failure: ExpectedFailure?,
}

local INTERFACE: string = "ReplicatedStorage.Tests.Interface"
local LOADER: string = "ReplicatedStorage.Tests.Loader"

local ERRORS: string = `{INTERFACE}.Errors.spec`
local EXPECT: string = `{INTERFACE}.Expect.spec`
local TOP_LEVEL_ERROR: string = `{LOADER}.TopLevelError.spec`

local EXPECTED: { ExpectedSpec } = {
    {
        path = ERRORS,
        tests = {
            {
                name = "reports a thrown error",
                groups = {},
                failure = { message = `{ERRORS}:8: boom`, source = ERRORS, line = 8 },
            },
            {
                name = "reports an error thrown without a position",
                groups = {},
                failure = { message = "boom", source = ERRORS, line = 12 },
            },
            {
                name = "reports an error the engine raised",
                groups = {},
                failure = { source = ERRORS, line = 17 },
            },
            { name = "runs after earlier tests failed", groups = {} },
            { name = "refuses a test registered while tests run", groups = {} },
            { name = "refuses a group opened while tests run", groups = {} },
        },
    },
    {
        path = EXPECT,
        tests = {
            { name = "passes on equal values", groups = { "equal" } },
            {
                name = "fails on different values",
                groups = { "equal" },
                failure = { message = "expected 2, got 1", source = EXPECT, line = 13 },
            },
            {
                name = "quotes strings",
                groups = { "equal" },
                failure = { message = 'expected "right", got "left"', source = EXPECT, line = 17 },
            },
            {
                name = "fails on separate tables with the same contents",
                groups = { "equal" },
                failure = { source = EXPECT, line = 21 },
            },
            { name = "passes on tables with the same contents", groups = { "same" } },
            {
                name = "fails where a nested value differs",
                groups = { "same" },
                failure = { message = "expected 2, got 1 at outer.inner", source = EXPECT, line = 31 },
            },
            {
                name = "fails on a missing entry",
                groups = { "same" },
                failure = { message = "expected 2, got nil at [2]", source = EXPECT, line = 35 },
            },
            {
                name = "fails on an extra entry",
                groups = { "same" },
                failure = { message = "expected nil, got 3 at [3]", source = EXPECT, line = 39 },
            },
            { name = "passes when the function throws", groups = { "error" } },
            {
                name = "fails when the function returns",
                groups = { "error" },
                failure = { message = "expected an error, got none", source = EXPECT, line = 51 },
            },
        },
    },
    {
        path = `{INTERFACE}.Groups.spec`,
        tests = {
            { name = "sits outside every group", groups = {} },
            { name = "sits in one group", groups = { "outer" } },
            { name = "sits in two groups", groups = { "outer", "inner" } },
            { name = "sits after a nested group", groups = { "outer" } },
            { name = "sits after every group", groups = {} },
        },
    },
    {
        path = `{LOADER}.Cycle.spec`,
        tests = {},
        failure = {
            message = `[Litmus]: modules require each other in a cycle: {LOADER}.CycleA -> {LOADER}.CycleB -> {LOADER}.CycleA`,
            source = `{LOADER}.CycleB`,
            line = 1,
        },
    },
    {
        path = `{LOADER}.Requires.spec`,
        tests = {
            { name = "requires a sibling with ./", groups = {} },
            { name = "requires a child with @self", groups = {} },
            { name = "requires from the DataModel with @game", groups = {} },
            { name = "requires an instance", groups = {} },
            { name = "gives a module its own script", groups = {} },
            { name = "starts each run with an empty _G that its modules share", groups = {} },
        },
    },
    {
        path = `{LOADER}.Syntax.spec`,
        tests = {},
        failure = { source = `{LOADER}.Syntax.spec`, line = 2 },
    },
    {
        path = TOP_LEVEL_ERROR,
        tests = {},
        failure = { message = `{TOP_LEVEL_ERROR}:7: boom`, source = TOP_LEVEL_ERROR, line = 7 },
    },
    {
        path = `{LOADER}.TwoValues.spec`,
        tests = {},
        failure = {
            message = `[Litmus]: {LOADER}.TwoValues returned 2 values; a module must return exactly one`,
            source = `{LOADER}.TwoValues.spec`,
            line = 1,
        },
    },
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

    if expected.source then
        compare(where, "source", actual.source, expected.source)
    end

    if expected.line then
        compare(where, "line", actual.line, expected.line)
    end

    if type(actual.trace) ~= "string" or actual.trace == "" then
        table.insert(mismatches, `{where}: trace is {show(actual.trace)}, expected a traceback`)
    end
end

local function compareTests(path: string, actual: { TestResult }, expected: { ExpectedTest }): ()
    compare(path, "test count", #actual, #expected)

    for index, wanted in expected do
        local result: TestResult? = actual[index]
        if not result then
            break
        end

        local where: string = `{path} > {wanted.name}`

        compare(where, "name", result.name, wanted.name)
        compare(where, "groups", table.concat(result.groups, " > "), table.concat(wanted.groups, " > "))
        compareFailure(where, result.failure, wanted.failure)
    end
end

-- Loads a module that requires nothing, straight from its source so Studio's require cache stays out of it
local function loadAlone(module: ModuleScript): any
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(module.Source, `={module:GetFullName()}`)
    if not chunk then
        error(`[Anchor]: {module:GetFullName()} didn't compile: {problem}`, 0)
    end

    return chunk()
end

local loader: any = loadAlone(lib.Loader)
local session: any = loader.new(loadAlone(lib.External))

local litmus: any = session:require(lib)
local results: { SpecResult } = litmus.run(session, { tests })

compare("run", "spec count", #results, #EXPECTED)

for index, wanted in EXPECTED do
    local result: SpecResult? = results[index]
    if not result then
        break
    end

    compare(`spec {index}`, "path", result.path, wanted.path)
    compareFailure(wanted.path, result.failure, wanted.failure)
    compareTests(wanted.path, result.tests, wanted.tests)
end

if #mismatches == 0 then
    print(`[Anchor]: all {#EXPECTED} specs match`)
else
    for _, mismatch in mismatches do
        warn(`[Anchor]: {mismatch}`)
    end

    warn(`[Anchor]: mismatches: {#mismatches}`)
end
