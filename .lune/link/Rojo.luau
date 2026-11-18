local process = require "@lune/process"

local cli = require "./Cli"

local rojo = {}

function rojo.serve(): ()
    local watcher = process.create("rojo", { "sourcemap", "--output", "sourcemap.json", "--watch", "--include-non-scripts" })

    cli.run("rojo", { "serve" }, { forward = true, check = false })

    pcall(watcher.kill, watcher)
end

function rojo.build(output: string): ()
    cli.run("rojo", { "build", "--output", output })
end

function rojo.sourcemap(output: string, project: string?): ()
    local args: { string } = { "sourcemap", "--include-non-scripts", "--output", output }
    if project then
        table.insert(args, project)
    end

    cli.run("rojo", args)
end

return rojo
