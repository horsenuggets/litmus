local litmus = require("../../Packages/Litmus")

local test = litmus.test

test("never runs", function(): () end)

error("boom")
