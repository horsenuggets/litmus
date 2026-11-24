local escapes: { [string]: string } = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function encodeString(text: string): string
    local escaped: string = string.gsub(text, '[%c"\\]', function(character: string): string
        return escapes[character] or string.format("\\u%04x", string.byte(character))
    end)

    return `"{escaped}"`
end

local function encode(value: any): string
    if type(value) == "string" then
        return encodeString(value)
    elseif type(value) ~= "table" then
        return tostring(value)
    end

    local parts: { string } = {}

    if #value > 0 or next(value) == nil then
        for _, item in ipairs(value) do
            table.insert(parts, encode(item))
        end

        return `[{table.concat(parts, ",")}]`
    end

    for key, item in value do
        table.insert(parts, `{encodeString(tostring(key))}:{encode(item)}`)
    end

    return `\{{table.concat(parts, ",")}}`
end

local function observe(event: any): ()
    print(progressMarker .. encode(event))
end

print(marker .. encode(litmus.run(adapter(options), observe)))
