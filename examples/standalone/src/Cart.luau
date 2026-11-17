export type Prices = { [string]: number }
export type Held = { [string]: number }

local cart = {}

function cart.total(prices: Prices, held: Held): number
    local total: number = 0

    for item, count in held do
        local price: number? = prices[item]
        if not price then
            error(`nothing is priced as {item}`)
        end

        total += price * count
    end

    return total
end

return cart
