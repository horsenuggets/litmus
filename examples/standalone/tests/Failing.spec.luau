local cart = require("../src/Cart")
local litmus = require("../../../lib")

local expect = litmus.expect
local test = litmus.test

local PRICES: cart.Prices = { apple = 2, pear = 3 }

test("adds up what the cart holds", function(): ()
    expect.equal(cart.total(PRICES, { apple = 2 }), 4)
end)

test("fails an expectation", function(): ()
    expect.equal(cart.total(PRICES, { apple = 2 }), 5)
end)

test("fails where the code under test throws", function(): ()
    cart.total(PRICES, { plum = 1 })
end)
