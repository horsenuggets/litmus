local environment = require("../Utils/Environment")
local litmus = require("../../Litmus")
local token = require("../Utils/Token")

local expect = litmus.expect
local test = litmus.test

test("requires a sibling with ./", function(): ()
    expect.equal(require("../Utils/Sibling"), token)
end)

test("requires a child with @self", function(): ()
    expect.equal(require("../Utils/Folder"), "child")
end)

test("requires from the DataModel with @game", function(): ()
    expect.equal(require("@game/ReplicatedStorage/Tests/Utils/Token"), token)
end)

test("requires an instance", function(): ()
    expect.equal(require(script.Parent.Parent.Utils.Token), token)
end)

test("gives a module its own script", function(): ()
    expect.equal(environment.script, script.Parent.Parent.Utils.Environment)
end)

test("starts each run with an empty _G that its modules share", function(): ()
    expect.equal(_G.environmentLoads, 1)
end)
