-- Reads the full names the lib reports things by, which join an instance's ancestors with dots

local SPEC_SUFFIX: string = ".spec"

local paths = {}

-- The spec's own name, and the full name of what holds it
function paths.split(path: string): (string, string)
    local name: string? = string.match(path, `([^.]+%{SPEC_SUFFIX})$`)
    if not name or name == path then
        return path, ""
    end

    return name, string.sub(path, 1, #path - #name - 1)
end

-- The start that every one of these specs' holders shares, which says nothing when repeated beside each
function paths.sharedParent(specPaths: { string }): string
    local first: string? = specPaths[1]
    if not first then
        return ""
    end

    local _, firstParent: string = paths.split(first)
    local shared: { string } = string.split(firstParent, ".")

    for _, path in specPaths do
        local _, parent: string = paths.split(path)
        local names: { string } = string.split(parent, ".")

        local matching: number = 0
        while matching < #shared and shared[matching + 1] == names[matching + 1] do
            matching += 1
        end

        for index = #shared, matching + 1, -1 do
            table.remove(shared, index)
        end
    end

    return table.concat(shared, ".")
end

-- `parent` as it reads from `root`, which is a start it shares or nothing
function paths.relativeTo(parent: string, root: string): string
    if root == "" then
        return parent
    end

    return string.sub(parent, #root + 2)
end

return paths
