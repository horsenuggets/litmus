-- The names leading to a script from the top of the place
export type Path = { string }

-- The lib's results, as it returns them
export type Failure = {
    message: string,
    source: Path,
    line: number,
    trace: string,
}

export type TestResult = {
    name: string,
    groups: { string },
    failure: Failure?,
}

export type SpecResult = {
    path: Path,
    tests: { TestResult },
    failure: Failure?,
}

-- What came of a run: its results, or why there are none
export type Run = { kind: "results", results: { SpecResult } } | { kind: "problem", message: string }

export type Status = "PASS" | "FAIL" | "ERROR"

export type Tally = {
    passedSpecs: number,
    failedSpecs: number,
    erroredSpecs: number,

    passedTests: number,
    failedTests: number,
}

local outcome = {}

-- A run that couldn't happen has no specs to show, which is what everything counting them should see
function outcome.resultsOf(ran: Run): { SpecResult }
    return if ran.kind == "results" then ran.results else {}
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

function outcome.specCount(tally: Tally, status: Status): number
    if status == "ERROR" then
        return tally.erroredSpecs
    end

    return if status == "FAIL" then tally.failedSpecs else tally.passedSpecs
end

-- The specs with something wrong, then the ones that passed, each in the order they ran; `only` keeps one status
function outcome.arranged(results: { SpecResult }, only: Status?): ({ SpecResult }, { SpecResult })
    local wrong: { SpecResult } = {}
    local passed: { SpecResult } = {}

    for _, spec in results do
        local status: Status = outcome.statusOf(spec)

        if only and status ~= only then
            continue
        end

        table.insert(if status == "PASS" then passed else wrong, spec)
    end

    return wrong, passed
end

return outcome
