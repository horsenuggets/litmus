local litmus = require("../../lib")
local lune = require("../../lib/Adapter/Lune")

local report = litmus.report

local function counts(specs: { litmus.SpecResult }): litmus.Remarks
    local rows: { litmus.Row } = {}

    for index, spec in specs do
        rows[index] = report.row({
            table.concat(spec.path, "/"),
            report.cell(tostring(#spec.tests), { align = "right" }),
        })
    end

    return { appendix = { report.heading("Tests in each spec"), report.tree(rows) } }
end

local function adapter(options: lune.Options): litmus.Adapter
    local adapted: litmus.Adapter = lune(options)

    if options.flags.counts then
        adapted.results = counts
    end

    return adapted
end

return adapter
