local outcome = require("../Outcome")

local paths = {}

function paths.fullName(path: outcome.Path): string
    return table.concat(path, ".")
end

function paths.name(path: outcome.Path): string
    return path[#path] or ""
end

function paths.parent(path: outcome.Path): outcome.Path
    return table.move(path, 1, #path - 1, 1, {})
end

function paths.sharedParent(specPaths: { outcome.Path }): outcome.Path
    local first: outcome.Path? = specPaths[1]
    if not first then
        return {}
    end

    local shared: outcome.Path = paths.parent(first)

    for _, path in specPaths do
        local parent: outcome.Path = paths.parent(path)

        local matching: number = 0
        while matching < #shared and shared[matching + 1] == parent[matching + 1] do
            matching += 1
        end

        for index = #shared, matching + 1, -1 do
            table.remove(shared, index)
        end
    end

    return shared
end

function paths.relativeTo(path: outcome.Path, root: outcome.Path): outcome.Path
    return table.move(path, #root + 1, #path, 1, {})
end

return paths
