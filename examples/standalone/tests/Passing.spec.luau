local task = require("@lune/task")

local cart = require("../src/Cart")
local litmus = require("../../../lib")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local PRICES: cart.Prices = { apple = 2, pear = 3 }

group("total", function(): ()
    test("adds up what the cart holds", function(): ()
        expect.equal(cart.total(PRICES, { apple = 2, pear = 1 }), 7)
    end)

    test("is nothing for an empty cart", function(): ()
        expect.equal(cart.total(PRICES, {}), 0)
    end)

    test("is the same after a wait", function(): ()
        task.wait(0.05)

        expect.equal(cart.total(PRICES, { pear = 2 }), 6)
    end)
end)
