local function shares(values: { number }, steps: number): { number }
    local total: number = 0
    for _, value in values do
        total += math.max(value, 0)
    end

    local given: { number } = {}
    local used: number = 0
    local widest: number = 0

    for index, value in values do
        local share: number = if total > 0 then math.max(value, 0) * steps / total else 0
        local step: number = math.floor(share + 0.5)

        if value > 0 then
            step = math.max(step, 1)
        end

        if total <= 0 and index == #values then
            step = steps
        end

        given[index] = step
        used += step

        if widest == 0 or step > given[widest] then
            widest = index
        end
    end

    if widest > 0 then
        given[widest] = math.max(given[widest] + steps - used, 0)
    end

    return given
end

return shares
