local replicatedStorage = game:GetService("ReplicatedStorage")

local litmus = require("../../Litmus")

local SPEC_SUFFIX: string = ".spec"

local lib = replicatedStorage.Litmus
local root = script.Parent.Parent.Anchor

local anchor = {}

-- Runs the module called `name` in `folder` as the spec it is written to be, and gives how that went
function anchor.run(folder: string, name: string): litmus.SpecResult
    local holder: Instance? = root:FindFirstChild(folder)
    if not holder then
        error(`[Anchor]: there is no folder named {folder}`, 2)
    end

    -- Copied along with what sits beside it, which it may require, and never put in the place: named as a spec
    -- there, it would be picked up by every other run, and most of these are written to fail
    local copies: Instance = holder:Clone()

    local spec: Instance? = copies:FindFirstChild(name)
    if not spec then
        error(`[Anchor]: {folder} has no module named {name}`, 2)
    end

    spec.Name ..= SPEC_SUFFIX

    local entry = lib.Adapter.Roblox

    -- A second copy of the lib, so the run this is called from keeps its own tests
    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
    if not chunk then
        error(`[Anchor]: {entry:GetFullName()} didn't compile: {problem}`, 0)
    end

    local results: { litmus.SpecResult } = chunk().run(lib, { spec })
    copies:Destroy()

    return results[1]
end

function anchor.test(ran: litmus.SpecResult, name: string): litmus.TestResult
    for _, test in ran.tests do
        if test.name == name then
            return test
        end
    end

    error(`[Anchor]: there is no test named "{name}"`, 2)
end

-- How the test called `name` failed, for a test that is meant to
function anchor.failureOf(ran: litmus.SpecResult, name: string): litmus.Failure
    local failure: litmus.Failure? = anchor.test(ran, name).failure
    if not failure then
        error(`[Anchor]: "{name}" passed, and was meant to fail`, 2)
    end

    return failure
end

-- Why the spec didn't load, for a spec that is meant not to
function anchor.refusalOf(ran: litmus.SpecResult): litmus.Failure
    local failure: litmus.Failure? = ran.failure
    if not failure then
        error("[Anchor]: the spec loaded, and was meant not to", 2)
    end

    return failure
end

return anchor
