local litmus = require("@game/ReplicatedStorage/Litmus")

local test = litmus.test

test("never runs", function(): () end)

error("boom")
