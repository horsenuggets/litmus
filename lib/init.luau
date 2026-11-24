local collector = require("@self/Collector")
local expect = require("@self/Expect")
local report = require("@self/Report")
local runner = require("@self/Runner")

export type Failure = runner.Failure
export type TestResult = runner.TestResult
export type SpecResult = runner.SpecResult
export type Spec = runner.Spec
export type Adapter = runner.Adapter
export type Remarks = runner.Remarks
export type Run = runner.Run
export type Progress = runner.Progress

export type Piece = report.Piece
export type Row = report.Row
export type Cell = report.Cell
export type Styled = report.Styled
export type Meter = report.Meter
export type Part = report.Part
export type Stat = report.Stat
export type Key = report.Key
export type Tone = report.Tone
export type Align = report.Align
export type CellOptions = report.CellOptions
export type RowOptions = report.RowOptions

local litmus = {
    test = collector.test,
    group = collector.group,
    after = collector.after,
    expect = expect,
    report = report,

    run = runner.run,
}

return litmus
