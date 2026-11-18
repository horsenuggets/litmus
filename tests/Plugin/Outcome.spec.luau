local litmus = require("../../Litmus")
local outcome = require("../../Plugin/Outcome")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local FAILURE: outcome.Failure = { message = "wrong", source = { "Place", "Thing.spec" }, line = 1, trace = "" }

local function passing(name: string): outcome.TestResult
    return { name = name, groups = {} }
end

local function failing(name: string): outcome.TestResult
    return { name = name, groups = {}, failure = FAILURE }
end

local function spec(name: string, tests: { outcome.TestResult }, failure: outcome.Failure?): outcome.SpecResult
    return { path = { "Place", name }, tests = tests, failure = failure }
end

local PASSED: outcome.SpecResult = spec("Passed.spec", { passing("one"), passing("two") })
local EMPTY: outcome.SpecResult = spec("Empty.spec", {})
local FAILED: outcome.SpecResult = spec("Failed.spec", { passing("one"), failing("two") })
local ERRORED: outcome.SpecResult = spec("Errored.spec", {}, FAILURE)

group("statusOf", function(): ()
    test("passes a spec whose tests all passed", function(): ()
        expect.equal(outcome.statusOf(PASSED), "PASS")
    end)

    test("passes a spec without tests", function(): ()
        expect.equal(outcome.statusOf(EMPTY), "PASS")
    end)

    test("fails a spec with a failed test", function(): ()
        expect.equal(outcome.statusOf(FAILED), "FAIL")
    end)

    test("calls a spec that didn't load an error", function(): ()
        expect.equal(outcome.statusOf(ERRORED), "ERROR")
    end)
end)

group("failedCount", function(): ()
    test("counts the tests that failed", function(): ()
        expect.equal(outcome.failedCount({ passing("one"), failing("two"), failing("three") }), 2)
    end)

    test("counts none among no tests", function(): ()
        expect.equal(outcome.failedCount({}), 0)
    end)
end)

group("tally", function(): ()
    test("counts specs by how they went, and tests by whether they passed", function(): ()
        expect.same(outcome.tally({ PASSED, EMPTY, FAILED, ERRORED }), {
            passedSpecs = 2,
            failedSpecs = 1,
            erroredSpecs = 1,

            passedTests = 3,
            failedTests = 1,
        })
    end)

    test("counts nothing for no specs", function(): ()
        expect.same(outcome.tally({}), {
            passedSpecs = 0,
            failedSpecs = 0,
            erroredSpecs = 0,

            passedTests = 0,
            failedTests = 0,
        })
    end)
end)

group("specCount", function(): ()
    local tally: outcome.Tally = outcome.tally({ PASSED, EMPTY, FAILED, ERRORED })

    test("gives the count that goes with a status", function(): ()
        expect.equal(outcome.specCount(tally, "PASS"), 2)
        expect.equal(outcome.specCount(tally, "FAIL"), 1)
        expect.equal(outcome.specCount(tally, "ERROR"), 1)
    end)
end)

group("arranged", function(): ()
    test("puts the specs with something wrong first, each kind in the order it ran", function(): ()
        local arranged: outcome.Arranged = outcome.arranged({ PASSED, FAILED, EMPTY, ERRORED })

        expect.same(arranged, { wrong = { FAILED, ERRORED }, passed = { PASSED, EMPTY } })
    end)

    test("keeps one status when asked for it", function(): ()
        local arranged: outcome.Arranged = outcome.arranged({ PASSED, FAILED, EMPTY, ERRORED }, "FAIL")

        expect.same(arranged, { wrong = { FAILED }, passed = {} })
    end)

    test("keeps the passing specs when asked for those", function(): ()
        local arranged: outcome.Arranged = outcome.arranged({ PASSED, FAILED, EMPTY, ERRORED }, "PASS")

        expect.same(arranged, { wrong = {}, passed = { PASSED, EMPTY } })
    end)
end)

group("ofLib", function(): ()
    test("makes a run of what the lib returned", function(): ()
        local appendix: outcome.Appendix = { { kind = "text", text = "text" } }

        expect.same(outcome.ofLib({ specs = { PASSED }, appendix = appendix, failure = "too little ran" }), {
            kind = "results",
            specs = { PASSED },
            appendix = appendix,
            failure = "too little ran",
        })

        expect.same(outcome.ofLib({ specs = {} }), { kind = "results", specs = {} })
    end)
end)

group("specsOf", function(): ()
    test("gives a run's specs", function(): ()
        expect.same(outcome.specsOf({ kind = "results", specs = { PASSED, FAILED } }), { PASSED, FAILED })
    end)

    test("gives no specs for a run that couldn't happen", function(): ()
        expect.same(outcome.specsOf({ kind = "problem", message = "no specs" }), {})
    end)
end)
