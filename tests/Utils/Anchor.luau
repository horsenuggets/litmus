local replicatedStorage = game:GetService("ReplicatedStorage")

local litmus = require("../../Litmus")

local SPEC_SUFFIX: string = ".spec"

local lib = replicatedStorage.Litmus
local root = script.Parent.Parent.Anchor

local anchor = {}

function anchor.run(folder: string, name: string): litmus.SpecResult
    local holder: Instance? = root:FindFirstChild(folder)
    if not holder then
        error(`[Anchor]: there is no folder named {folder}`, 2)
    end

    local copies: Instance = holder:Clone()

    local spec: Instance? = copies:FindFirstChild(name)
    if not spec then
        error(`[Anchor]: {folder} has no module named {name}`, 2)
    end

    spec.Name ..= SPEC_SUFFIX

    local entry = lib.Adapter.Roblox

    local chunk: ((...any) -> ...any)?, problem: string? = loadstring(entry.Source, `={entry:GetFullName()}`)
    if not chunk then
        error(`[Anchor]: {entry:GetFullName()} didn't compile: {problem}`, 0)
    end

    local ran: litmus.Run = chunk().run(lib, { spec })
    copies:Destroy()

    return ran.specs[1]
end

function anchor.resultOf(spec: litmus.SpecResult, name: string): litmus.TestResult
    for _, test in spec.tests do
        if test.name == name then
            return test
        end
    end

    error(`[Anchor]: there is no test named "{name}"`, 2)
end

function anchor.passed(spec: litmus.SpecResult, name: string): boolean
    return anchor.resultOf(spec, name).failure == nil
end

function anchor.failureOf(spec: litmus.SpecResult, name: string): litmus.Failure
    local failure: litmus.Failure? = anchor.resultOf(spec, name).failure
    if not failure then
        error(`[Anchor]: "{name}" passed, and was meant to fail`, 2)
    end

    return failure
end

function anchor.refusalOf(spec: litmus.SpecResult): litmus.Failure
    local failure: litmus.Failure? = spec.failure
    if not failure then
        error("[Anchor]: the spec loaded, and was meant not to", 2)
    end

    return failure
end

return anchor
