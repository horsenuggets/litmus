export type Line = {
    number: number,
    text: string,
}

-- How many lines are shown on each side of the one asked for
local CONTEXT_LINES: number = 1
local TAB: string = "    "

-- The line of `source` numbered `line` with the lines around it, shifted left by the indentation they share
local function codeAround(source: string, line: number): { Line }
    local all: { string } = string.split(source, "\n")
    if line < 1 or line > #all then
        return {}
    end

    local lines: { Line } = {}
    local shared: number = math.huge

    for number = math.max(1, line - CONTEXT_LINES), math.min(#all, line + CONTEXT_LINES) do
        local text: string = string.gsub(string.gsub(all[number], "\r", ""), "\t", TAB)

        local indentation: string? = string.match(text, "^( *)%S")
        if indentation then
            shared = math.min(shared, #indentation)
        end

        table.insert(lines, { number = number, text = text })
    end

    if shared ~= math.huge then
        for _, entry in lines do
            entry.text = string.sub(entry.text, shared + 1)
        end
    end

    return lines
end

return codeAround
