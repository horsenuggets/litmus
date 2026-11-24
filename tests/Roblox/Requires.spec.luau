local environment = require("../Anchor/Requires/Environment")
local litmus = require("../../Litmus")
local token = require("../Anchor/Requires/Token")

local expect = litmus.expect
local test = litmus.test

test("requires a sibling with ./", function(): ()
    expect.equal(require("../Anchor/Requires/Sibling"), token)
end)

test("requires a child with @self", function(): ()
    expect.equal(require("../Anchor/Requires/Folder"), "child")
end)

test("requires from the DataModel with @game", function(): ()
    expect.equal(require("@game/ReplicatedStorage/Tests/Anchor/Requires/Token"), token)
end)

test("requires an instance", function(): ()
    expect.equal(require(script.Parent.Parent.Anchor.Requires.Token), token)
end)

test("gives a module its own script", function(): ()
    expect.equal(environment.script, script.Parent.Parent.Anchor.Requires.Environment)
end)
