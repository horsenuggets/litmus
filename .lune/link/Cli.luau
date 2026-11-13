--[[
    Terminal plumbing for the commands: argument parsing, logging, errors and
    child processes. Library functions throw already-formatted
    `[prefix]: message` errors; `Cli.main` runs a command, prints any error
    and exits with code 1.
]]

local process = require "@lune/process"
local stdio = require "@lune/stdio"

local cli = {}

-- Types
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
    check: boolean?, -- throw on a non-zero exit code (default true)
    forward: boolean?, -- forward stdio to the terminal instead of capturing it
}

-- Logging
function cli.log(prefix: string, message: string): ()
    print(`[{prefix}]: {message}`)
end

function cli.warn(prefix: string, message: string): ()
    stdio.ewrite(stdio.color("yellow") .. `[{prefix}]: {message}` .. stdio.color("reset") .. "\n")
end

function cli.success(prefix: string, message: string): ()
    print(stdio.color("green") .. `[{prefix}]: {message}` .. stdio.color("reset"))
end

function cli.fail(prefix: string, message: string): never
    error(`[{prefix}]: {message}`, 0)
end

-- Argument parsing: `--name=value` and `--flag` become flags, everything else
-- is positional
function cli.parseArgs(args: { string }): ParsedArgs
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

-- Process execution with friendly failures
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

-- Opens a file with the system's default handler, normally Roblox Studio
function cli.open(path: string): ()
    if process.os == "windows" then
        cli.run("explorer", { path }, { check = false })
    elseif process.os == "macos" then
        cli.run("open", { path })
    else
        cli.run("xdg-open", { path })
    end
end

-- Runs `command` with the parsed process arguments; any error it throws is
-- printed in red and exits the process with code 1
function cli.main(command: (args: ParsedArgs) -> ()): ()
    local parsed: ParsedArgs = cli.parseArgs(process.args)
    local ok, result = pcall(function(): string?
        command(parsed)
        return nil
    end)
    if not ok then
        stdio.ewrite(stdio.color("red") .. tostring(result) .. stdio.color("reset") .. "\n")
        process.exit(1)
    end
end

return cli
