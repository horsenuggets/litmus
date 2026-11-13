local tableUtils = {}

function tableUtils.deepCopy<T>(origin: T): T
    local copy: { [any]: any } = {}
    for key: any, value: any in pairs(origin :: any) do
        if typeof(value) ~= "table" then
            copy[key] = value
        else
            copy[key] = tableUtils.deepCopy(value)
        end
    end
    return copy :: T
end

-- TODO: account for tables with self-references, which could
-- cause a stack overflow error due to an infinite loop.
function tableUtils.countLeaves(dictionary: { [any]: any }): number
    local count: number = 0
    for key, value in dictionary do
        if typeof(value) ~= "table" then
            count += 1
        else
            count += tableUtils.countLeaves(value)
        end
    end
    return count
end

function tableUtils.count(dictionary: { [any]: any }): number
    local count: number = 0
    for _ in dictionary do
        count += 1
    end
    return count
end

function tableUtils.merge<T, M>(template: T, toMerge: M): (T & M)
    local origin: any = tableUtils.deepCopy(template)
    for key: any, value: any in (toMerge :: any) do
        origin[key] = value
    end
    return origin
end

--[=[
    Utility for arrays. Runs a `map` function for each value in an array.
]=]
function tableUtils.forEach<V, R>(source: { V }, map: (V) -> R): { R }
    local output: { R } = {}
    for _, value: V in source do
        table.insert(output, map(value))
    end
    return output
end

function tableUtils.filter<V>(source: { V }, predicate: (V) -> boolean): { any }
    local output: { V } = {}
    for _, value: V in source do
        if predicate(value) then
            table.insert(output, value)
        end
    end
    return output
end

function tableUtils.strip(source: { [any]: any }, keys: { any }): { [any]: any }
    local output = {}
    for key in source do
        if table.find(keys, key) then continue end
        output[key] = source[key]
    end
    return output
end

function tableUtils.keyof<T>(source: T): { keyof<T> }
    local output = {}
    for key in source :: any do
        table.insert(output, key)
    end
    return output :: any
end

return tableUtils
