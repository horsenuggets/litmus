local collector = require("@self/Collector")
local expect = require("@self/Expect")
local runner = require("@self/Runner")

export type Failure = runner.Failure
export type TestResult = runner.TestResult
export type SpecResult = runner.SpecResult
export type Spec = runner.Spec
export type Adapter = runner.Adapter
export type Run = runner.Run

local litmus = {
    test = collector.test,
    group = collector.group,
    after = collector.after,
    expect = expect,

    run = runner.run,
}

return litmus
