local process = require "@lune/process"
local stdio = require "@lune/stdio"

local cli = {}

export type ParsedArgs = {
    positionals: { string },
    flags: { [string]: string | boolean },
}

export type RunResult = {
    ok: boolean,
    code: number,
    stdout: string,
    stderr: string,
}

export type RunOptions = {
    check: boolean?,
    forward: boolean?,
}

function cli.log(prefix: string, message: string): ()
    print(`[{prefix}]: {message}`)
end

function cli.success(prefix: string, message: string): ()
    print(stdio.color("green") .. `[{prefix}]: {message}` .. stdio.color("reset"))
end

function cli.fail(prefix: string, message: string): never
    error(`[{prefix}]: {message}`, 0)
end

local function parseArgs(args: { string }): ParsedArgs
    local positionals: { string } = {}
    local flags: { [string]: string | boolean } = {}

    for _, argument in args do
        local name, value = string.match(argument, "^%-%-([%w%-]+)=(.*)$")
        if name and value then
            flags[name] = value
            continue
        end

        local switch = string.match(argument, "^%-%-([%w%-]+)$")
        if switch then
            flags[switch] = true
            continue
        end

        table.insert(positionals, argument)
    end

    return { positionals = positionals, flags = flags }
end

function cli.run(command: string, args: { string }, options: RunOptions?): RunResult
    local runOptions: RunOptions = options or {}

    local execOptions: process.ExecOptions = {
        stdio = if runOptions.forward then "forward" else nil
    }

    local spawned, result = pcall(process.exec, command, args, execOptions)
    if not spawned then
        cli.fail("lune", `'{command}' could not be started; is it installed? Try 'rokit install' ({result})`)
    end

    local execResult = result :: RunResult
    if runOptions.check ~= false and not execResult.ok then
        local detail = if #execResult.stderr > 0
            then `:\n{execResult.stderr}`
            else ` (exit code {execResult.code})`
        cli.fail("lune", `'{command} {table.concat(args, " ")}' failed{detail}`)
    end

    return execResult
end

function cli.open(path: string): ()
    if process.os == "windows" then
        cli.run("explorer", { path }, { check = false })
    elseif process.os == "macos" then
        cli.run("open", { path })
    else
        cli.run("xdg-open", { path })
    end
end

function cli.main(command: (args: ParsedArgs) -> ()): ()
    local parsed: ParsedArgs = parseArgs(process.args)
    local ok: boolean, result: unknown = pcall(command, parsed)
    if not ok then
        stdio.ewrite(stdio.color("red") .. tostring(result) .. stdio.color("reset") .. "\n")
        process.exit(1)
    end
end

return cli
