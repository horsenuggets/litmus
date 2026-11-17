local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local loader = require("../Loader")
local runner = require("../Runner")

export type Options = {
    lib: string,
    specs: { string },
    flags: { [string]: true },
}

local EXTENSIONS: { string } = { ".luau", ".lua" }

local CLIMBS: { [string]: number } = {
    ["@self"] = 0,
    ["."] = 1,
    [".."] = 2,
}

local function isAlias(path: string): boolean
    return string.sub(path, 1, 1) == "@"
end

local function withoutExtension(file: string): string
    for _, extension in EXTENSIONS do
        if string.sub(file, -#extension) == extension then
            return string.sub(file, 1, -#extension - 1)
        end
    end

    return file
end

local function placeOf(file: string): { string }
    local names: { string } = string.split(withoutExtension(file), "/")
    if names[#names] == "init" then
        table.remove(names)
    end

    return names
end

local function step(place: { string }, name: string): ()
    if name == "." or name == "" then
        return
    end

    if name ~= ".." or #place == 0 or place[#place] == ".." then
        table.insert(place, name)
    else
        table.remove(place)
    end
end

local function fileAt(place: { string }): string?
    local path: string = table.concat(place, "/")

    for _, extension in EXTENSIONS do
        if path ~= "" and fs.isFile(path .. extension) then
            return path .. extension
        end
    end

    for _, extension in EXTENSIONS do
        local file: string = if path == "" then `init{extension}` else `{path}/init{extension}`
        if fs.isFile(file) then
            return file
        end
    end

    return nil
end

local function resolve(from: string, target: unknown): string
    if type(target) ~= "string" then
        error(`[Litmus]: can't require {tostring(target)}: a path is a string`, 0)
    end

    local names: { string } = string.split(target, "/")
    local root: string = table.remove(names, 1) :: string

    local climbs: number? = CLIMBS[root]
    if not climbs and isAlias(root) then
        return target
    end

    if not climbs then
        error(`[Litmus]: can't require "{target}": "{root}" leads nowhere; a path starts with ./, ../, @self or an alias`, 0)
    end

    local place: { string } = placeOf(from)
    for _ = 1, climbs do
        step(place, "..")
    end

    for _, name in names do
        step(place, name)
    end

    local file: string? = fileAt(place)
    if not file then
        error(`[Litmus]: can't require "{target}": there is no module at that path`, 0)
    end

    return file
end

local function inLib(lib: string, module: string): string?
    local prefix: string = `{lib}/`
    if string.sub(module, 1, #prefix) ~= prefix then
        return nil
    end

    return `../{table.concat(placeOf(string.sub(module, #prefix + 1)), "/")}`
end

local function loadedByRuntime(path: string): (...any) -> ...any
    return function(): any
        return (require :: any)(path)
    end
end

local function compileProblem(thrown: unknown): string
    local text: string = string.gsub(tostring(thrown), "^syntax error: ", "")
    local trace: number? = string.find(text, "\nstack traceback:", 1, true)

    return if trace then string.sub(text, 1, trace - 1) else text
end

local function load(lib: string, module: string, globals: { [string]: any }): (...any) -> ...any
    if isAlias(module) then
        return loadedByRuntime(module)
    end

    local own: string? = inLib(lib, module)
    if own then
        return loadedByRuntime(own)
    end

    local loadOptions: luau.LoadOptions = {
        debugName = `={module}`,
        environment = globals,
    }

    local compiled: boolean, chunk: any = pcall(luau.load, fs.readFile(module), loadOptions)
    if not compiled then
        error(compileProblem(chunk), 0)
    end

    return chunk
end

local function lune(options: Options): runner.Adapter
    local session: loader.Class = loader.new({
        chunkName = function(module: string): string
            return module
        end,

        resolve = resolve,

        load = function(module: string, globals: { [string]: any }): (...any) -> ...any
            return load(options.lib, module, globals)
        end,
    })

    local specs: { runner.Spec } = {}
    for _, file in options.specs do
        table.insert(specs, {
            path = string.split(file, "/"),
            load = function(): ()
                session:execute(file)
            end,
        })
    end

    return {
        specs = specs,

        locate = function(chunk: string): { string }?
            local module: string? = session:moduleOf(chunk)
            return if module then string.split(module, "/") else nil
        end,

        spawn = function(run: (() -> ()) | thread): ()
            task.spawn(run)
        end,
    }
end

return lune
