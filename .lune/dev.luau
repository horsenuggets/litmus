local cli = require "@link/Cli"
local rojo = require "@link/Rojo"

local BUILD_FILE: string = "build.rbxl"

cli.main(function(args: cli.ParsedArgs): ()
    if args.flags.open then
        rojo.build(BUILD_FILE)
        cli.open(BUILD_FILE)
    end

    rojo.serve()
end)
