--[[
    Wrappers around the rojo CLI.
]]

local process = require "@lune/process"

local cli = require "./Cli"

local rojo = {}

-- Serves the project until stopped, keeping sourcemap.json up to date in a
-- child process that is killed once serving stops
function rojo.serve(): ()
    local watcher = process.create("rojo", { "sourcemap", "--output", "sourcemap.json", "--watch", "--include-non-scripts" })

    cli.run("rojo", { "serve" }, { forward = true, check = false })

    pcall(function()
        watcher:kill()
    end)
end

-- Builds the project tree into a single file
function rojo.build(output: string): ()
    cli.run("rojo", { "build", "--output", output })
end

-- Writes the sourcemap luau-lsp reads, including the non-script instances that scripts index
-- `project` is a project file other than the default one
function rojo.sourcemap(output: string, project: string?): ()
    local args: { string } = { "sourcemap", "--include-non-scripts", "--output", output }
    if project then
        table.insert(args, project)
    end

    cli.run("rojo", args)
end

return rojo
