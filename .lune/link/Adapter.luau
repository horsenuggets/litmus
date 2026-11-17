local fs = require "@lune/fs"
local luau = require "@lune/luau"
local roblox = require "@lune/roblox"
local serde = require "@lune/serde"
local task = require "@lune/task"

local cli = require "./Cli"

local litmus = require "../../lib"
local loader = require "../../lib/Loader"

export type Options = {
    lib: string,
    specs: { string },
    flags: { [string]: true },
}

type Node = {
    name: string,
    className: string,
    filePaths: { string }?,
    children: { Node }?,
}

type Place = {
    game: any,
    files: { [any]: string },
    scripts: { [string]: any },
}

type Chunk = (...any) -> ...any

local LIB_CHUNKS: string = string.match(debug.info(loader.new, "s"), "^(.*)Loader") :: string

local function scriptFile(node: Node): string?
    for _, file in node.filePaths or {} do
        local path: string = string.gsub(file, "\\", "/")
        if string.match(path, "%.luau?$") then
            return path
        end
    end

    return nil
end

local function grow(place: Place, node: Node, instance: any): ()
    instance.Name = node.name

    local file: string? = scriptFile(node)
    if file then
        instance.Source = fs.readFile(file)

        place.files[instance] = file
        place.scripts[file] = instance
    end

    for _, child in node.children or {} do
        local grown: any = roblox.Instance.new(child.className)
        grow(place, child, grown)
        grown.Parent = instance
    end
end

local function placeFrom(root: Node): Place
    local place: Place = {
        game = roblox.Instance.new("DataModel"),
        files = {},
        scripts = {},
    }

    for _, service in root.children or {} do
        grow(place, service, place.game:GetService(service.className))
    end

    return place
end

local function compileProblem(thrown: unknown): string
    local text: string = string.gsub(tostring(thrown), "^syntax error: ", "")
    local trace: number? = string.find(text, "\nstack traceback:", 1, true)

    return if trace then string.sub(text, 1, trace - 1) else text
end

local function globalsOf(place: Place): { [string]: any }
    local globals: { [string]: any } = {
        game = place.game,
        Instance = roblox.Instance,
        task = task,
    }

    globals.loadstring = function(source: string, name: string): (Chunk?, string?)
        local compiled: boolean, chunk: any = pcall(luau.load, source, {
            debugName = name,
            environment = globals,
        })

        if not compiled then
            return nil, compileProblem(chunk)
        end

        return chunk, nil
    end

    return globals
end

local function hostOf(place: Place, lib: any): any
    local globals: { [string]: any } = globalsOf(place)
    local libChunk: string = `={lib:GetFullName()}`

    local shared: { [string]: any } = table.clone(globals)
    shared.loadstring = function(source: string, name: string): (Chunk?, string?)
        if name == libChunk then
            return function(): any
                return litmus
            end, nil
        end

        return globals.loadstring(source, name)
    end

    return luau.load(lib.Adapter.Roblox.Source, {
        debugName = `={LIB_CHUNKS}Adapter/Roblox`,
        environment = shared,
    })()
end

local function scriptAt(place: Place, file: string): any
    local found: any = place.scripts[file]
    if not found then
        error(`[Adapter]: the Rojo project doesn't hold {file}`, 0)
    end

    return found
end

local function adapter(options: Options): litmus.Adapter
    local place: Place = placeFrom(serde.decode("json", cli.run("rojo", { "sourcemap" }).stdout))

    local host: any = hostOf(place, scriptAt(place, `{options.lib}/init.luau`))
    local session: loader.Class = loader.new(host)

    local specs: { any } = {}
    for _, file in options.specs do
        table.insert(specs, scriptAt(place, file))
    end

    local adapted: litmus.Adapter = host.adapter(session, specs)

    for index, spec in adapted.specs do
        spec.path = string.split(options.specs[index], "/")
    end

    adapted.locate = function(chunk: string): { string }?
        local module: any = session:named(chunk)
        local file: string? = if module then place.files[module] else nil

        return if file then string.split(file, "/") else nil
    end

    return adapted
end

return adapter
