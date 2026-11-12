local collector = require("@self/Collector")
local expect = require("@self/Expect")
local failure = require("@self/Failure")
local runner = require("@self/Runner")

export type Failure = failure.Failure
export type TestResult = runner.TestResult
export type SpecResult = runner.SpecResult

local litmus = {
    test = collector.test,
    group = collector.group,
    expect = expect,

    run = runner.run,
}

return litmus
