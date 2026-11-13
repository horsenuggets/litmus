local encodingService = game:GetService("EncodingService")

local bridge = require("./Bridge")

export type Comparison = {
    missing: { bridge.Path },
    differing: { bridge.Path },
}

local function descend(root: Instance, path: bridge.Path): Instance?
    local current: Instance? = root

    for _, name in path do
        if not current then
            return nil
        end

        current = current:FindFirstChild(name)
    end

    return current
end

local function sourceOf(instance: Instance): string?
    if instance:IsA("ModuleScript") then
        return instance.Source
    elseif instance:IsA("Script") then
        return instance.Source
    end

    return nil
end

-- Carriage returns are left out, as the CLI leaves them out of the file's hash
local function hash(source: string): string
    local normalized: string = string.gsub(source, "\r", "")
    local digest: buffer = encodingService:ComputeBufferHash(buffer.fromstring(normalized), Enum.HashAlgorithm.Sha256)

    local hex: { string } = {}
    for offset = 0, buffer.len(digest) - 1 do
        table.insert(hex, string.format("%02x", buffer.readu8(digest, offset)))
    end

    return table.concat(hex)
end

local place = {}

function place.find(path: bridge.Path): Instance?
    return descend(game, path)
end

-- The instances at `paths`, leaving out any this place doesn't have
function place.findAll(paths: { bridge.Path }): { Instance }
    local found: { Instance } = {}

    for _, path in paths do
        local instance: Instance? = place.find(path)
        if instance then
            table.insert(found, instance)
        end
    end

    return found
end

-- The source of the script at `path`, if this place has one there
function place.sourceAt(path: bridge.Path): string?
    local instance: Instance? = place.find(path)
    return instance and sourceOf(instance)
end

-- How this place's scripts differ from the files the CLI hashed on disk
function place.compare(files: { bridge.File }): Comparison
    local comparison: Comparison = { missing = {}, differing = {} }

    for _, file in files do
        local instance: Instance? = place.find(file.path)
        if not instance then
            table.insert(comparison.missing, file.path)
            continue
        end

        local source: string? = sourceOf(instance)
        if not source or hash(source) ~= file.hash then
            table.insert(comparison.differing, file.path)
        end
    end

    return comparison
end

return place
