local litmus = require("../../lib")
local lune = require("../../lib/Adapter/Lune")

local function counts(specs: { litmus.SpecResult }): litmus.Remarks
    local lines: { string } = { "Tests in each spec" }

    for _, spec in specs do
        table.insert(lines, `  {table.concat(spec.path, "/")}  {#spec.tests}`)
    end

    return { appendix = table.concat(lines, "\n") }
end

local function adapter(options: lune.Options): litmus.Adapter
    local adapted: litmus.Adapter = lune(options)

    if options.flags.counts then
        adapted.results = counts
    end

    return adapted
end

return adapter
