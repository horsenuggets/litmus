local litmus = require("../../Packages/Litmus")

local group = litmus.group
local test = litmus.test

test("sits outside every group", function(): () end)

group("outer", function(): ()
    test("sits in one group", function(): () end)

    group("inner", function(): ()
        test("sits in two groups", function(): () end)
    end)

    test("sits after a nested group", function(): () end)
end)

test("sits after every group", function(): () end)
