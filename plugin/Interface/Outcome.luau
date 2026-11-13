-- The lib's results, as it returns them
export type Failure = {
    message: string,
    source: string,
    line: number,
    trace: string,
}

export type TestResult = {
    name: string,
    groups: { string },
    failure: Failure?,
}

export type SpecResult = {
    path: string,
    tests: { TestResult },
    failure: Failure?,
}

export type Status = "PASS" | "FAIL" | "ERROR"

export type Tally = {
    passedSpecs: number,
    failedSpecs: number,
    erroredSpecs: number,

    passedTests: number,
    failedTests: number,
}

local SPEC_SUFFIX: string = ".spec"

local outcome = {}

-- The spec's own name, and the full name of what holds it
function outcome.splitPath(path: string): (string, string)
    local name: string? = string.match(path, `([^.]+%{SPEC_SUFFIX})$`)
    if not name or name == path then
        return path, ""
    end

    return name, string.sub(path, 1, #path - #name - 1)
end

-- The start that every spec's holder shares, which says nothing when repeated on every row
function outcome.sharedParent(results: { SpecResult }): string
    local first: SpecResult? = results[1]
    if not first then
        return ""
    end

    local _, firstParent: string = outcome.splitPath(first.path)
    local shared: { string } = string.split(firstParent, ".")

    for _, spec in results do
        local _, parent: string = outcome.splitPath(spec.path)
        local names: { string } = string.split(parent, ".")

        local matching: number = 0
        while matching < #shared and shared[matching + 1] == names[matching + 1] do
            matching += 1
        end

        for index = #shared, matching + 1, -1 do
            table.remove(shared, index)
        end
    end

    return table.concat(shared, ".")
end

-- `parent` as it reads from `root`, which is a start it shares or nothing
function outcome.relativeTo(parent: string, root: string): string
    if root == "" then
        return parent
    end

    return string.sub(parent, #root + 2)
end

function outcome.failedCount(tests: { TestResult }): number
    local failed: number = 0

    for _, test in tests do
        if test.failure then
            failed += 1
        end
    end

    return failed
end

-- A spec that didn't load is an error, apart from one that loaded and had a test fail
function outcome.statusOf(spec: SpecResult): Status
    if spec.failure then
        return "ERROR"
    end

    return if outcome.failedCount(spec.tests) > 0 then "FAIL" else "PASS"
end

function outcome.tally(results: { SpecResult }): Tally
    local tally: Tally = { passedSpecs = 0, failedSpecs = 0, erroredSpecs = 0, passedTests = 0, failedTests = 0 }

    for _, spec in results do
        local failed: number = outcome.failedCount(spec.tests)

        tally.failedTests += failed
        tally.passedTests += #spec.tests - failed

        local status: Status = outcome.statusOf(spec)
        if status == "ERROR" then
            tally.erroredSpecs += 1
        elseif status == "FAIL" then
            tally.failedSpecs += 1
        else
            tally.passedSpecs += 1
        end
    end

    return tally
end

function outcome.plural(count: number, noun: string): string
    return `{count} {noun}{if count == 1 then "" else "s"}`
end

-- How a set of tests went, in a few words
function outcome.note(total: number, failed: number): string
    return if failed == 0 then outcome.plural(total, "test") else `{total - failed} of {total} passed`
end

return outcome
