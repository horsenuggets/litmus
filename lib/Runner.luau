local collector = require("./Collector")
local failure = require("./Failure")
local loader = require("./Loader")

local SPEC_SUFFIX: string = ".spec"

export type TestResult = {
    name: string,
    groups: { string },
    failure: failure.Failure?,
}

export type SpecResult = {
    path: string,
    tests: { TestResult },

    -- Set when the spec itself didn't load, in which case none of its tests ran
    failure: failure.Failure?,
}

local function addIfSpec(specs: { ModuleScript }, instance: Instance): ()
    if instance:IsA("ModuleScript") and string.sub(instance.Name, -#SPEC_SUFFIX) == SPEC_SUFFIX then
        table.insert(specs, instance)
    end
end

local function findSpecs(roots: { Instance }): { ModuleScript }
    local specs: { ModuleScript } = {}

    for _, root in roots do
        addIfSpec(specs, root)

        for _, descendant in root:GetDescendants() do
            addIfSpec(specs, descendant)
        end
    end

    table.sort(specs, function(a: ModuleScript, b: ModuleScript): boolean
        return a:GetFullName() < b:GetFullName()
    end)

    return specs
end

local function runSpec(session: loader.Class, spec: ModuleScript): SpecResult
    collector.begin()

    local problem: failure.Failure? = failure.catch(function(): ()
        session:execute(spec)
    end)

    local tests: { collector.Test } = collector.finish()
    local results: { TestResult } = {}

    if not problem then
        for _, test in tests do
            table.insert(results, {
                name = test.name,
                groups = test.groups,
                failure = failure.catch(test.run),
            })
        end
    end

    return {
        path = spec:GetFullName(),
        tests = results,
        failure = problem,
    }
end

local runner = {}

-- `session` must be the one this lib was loaded through, or specs register with another copy
function runner.run(session: loader.Class, roots: { Instance }): { SpecResult }
    local results: { SpecResult } = {}

    for _, spec in findSpecs(roots) do
        table.insert(results, runSpec(session, spec))
    end

    return results
end

return runner
