local litmus = require("../../Litmus")

local test = litmus.test

test("never runs", function(): () end)

error("boom")
