local function shares(values: { number }, cells: number): { number }
    local total: number = 0
    for _, value in values do
        total += math.max(value, 0)
    end

    local given: { number } = {}
    local used: number = 0
    local widest: number = 0

    for index, value in values do
        local share: number = if total > 0 then math.max(value, 0) * cells / total else 0
        local cell: number = math.floor(share + 0.5)

        if value > 0 then
            cell = math.max(cell, 1)
        end

        if total <= 0 and index == #values then
            cell = cells
        end

        given[index] = cell
        used += cell

        if widest == 0 or cell > given[widest] then
            widest = index
        end
    end

    if widest > 0 then
        given[widest] = math.max(given[widest] + cells - used, 0)
    end

    return given
end

return shares
