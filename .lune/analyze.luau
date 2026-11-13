--[[
    Type-checks `lib` and `tests` the way the editor does, listing each
    problem once as a clickable `path:line:column`, and exiting 1 if there are
    any.
    Usage: lune run analyze [--full]
    `--full` shows long types and every reason in full.
    Roblox's definitions and a private sourcemap live in `luau-cache`, so the
    editor's `sourcemap.json` is left alone. Delete that folder to fetch newer
    definitions.
]]

local fs = require "@lune/fs"
local net = require "@lune/net"
local process = require "@lune/process"
local stdio = require "@lune/stdio"

local cli = require "@link/Cli"
local rojo = require "@link/Rojo"

local CACHE_DIR: string = "luau-cache"
local DEFS_FILE: string = `{CACHE_DIR}/globalTypes.d.luau`
local SOURCEMAP_FILE: string = `{CACHE_DIR}/sourcemap.json`
local DEFS_URL: string = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

local PATHS: { string } = { "lib", "tests" }

-- Holds fixtures that are broken on purpose, to prove the loader reports them
local IGNORED: { string } = { "tests/Loader/**" }

-- The analyzer asks for an editor feature it has no editor to give it; no setting turns this off
local NO_CLIENT_WARNING: string = "[WARN] client does not allow didChangeWatchedFiles registration"

-- What's shown of a problem without `--full`
local MAX_LINE_LENGTH: number = 200
local MAX_REASONS: number = 5

-- Lines up details under a problem's message, past its "warning" label
local LABEL_WIDTH: number = 7
local MESSAGE_INDENT: string = string.rep(" ", 2 + LABEL_WIDTH + 2)

type Problem = {
    path: string,
    line: number,
    column: number,

    -- `TypeError`, `SyntaxError`, or a lint's name
    kind: string,
    message: string,
    details: { string },
}

-- Cache

local function ensureCacheDir(): ()
    if not fs.isDir(CACHE_DIR) then
        fs.writeDir(CACHE_DIR)
    end
end

local function ensureDefs(): ()
    if fs.isFile(DEFS_FILE) then
        return
    end

    cli.log("analyze", "fetching Roblox definitions")

    local response = net.request(DEFS_URL)
    if not response.ok then
        cli.fail("analyze", `couldn't fetch definitions (HTTP {response.statusCode})`)
    end

    fs.writeFile(DEFS_FILE, response.body)
end

-- Running the analyzer

local function analyzerArgs(): { string }
    local args: { string } = {
        "analyze",
        `--defs={DEFS_FILE}`,
        `--sourcemap={SOURCEMAP_FILE}`,
        "--flag:LuauSolverV2=true",
    }

    for _, glob in IGNORED do
        table.insert(args, `--ignore={glob}`)
    end

    for _, path in PATHS do
        table.insert(args, path)
    end

    return args
end

-- Parsing its output

local function isLog(line: string): boolean
    return string.sub(line, 1, 7) == "[INFO] " or string.sub(line, 1, #NO_CLIENT_WARNING) == NO_CLIENT_WARNING
end

-- A notice from the tool itself, as opposed to more of a problem's message
local function isNotice(line: string): boolean
    return string.sub(line, 1, 1) == "["
end

-- Absolute paths and backslashes become a path from the repo's root
local function projectPath(path: string): string
    local normalized: string = string.gsub(path, "\\", "/")
    local root: string = string.gsub(process.cwd, "\\", "/")

    if string.lower(string.sub(normalized, 1, #root)) == string.lower(root) then
        return string.sub(normalized, #root + 1)
    end

    return normalized
end

-- Reads `path [game/Module](line,column): Kind: message`; the bracket is left out for lints
local function parseHeader(line: string): Problem?
    local location, row, column, kind, message = string.match(line, "^(.-)%((%d+),(%d+)%): (%a+): (.*)$")
    if not location then
        return nil
    end

    local path: string = string.gsub(location, " %[.*%]$", "")

    return {
        path = projectPath(path),
        line = tonumber(row) :: number,
        column = tonumber(column) :: number,

        kind = kind :: string,
        message = message :: string,
        details = {},
    }
end

-- Returns the problems, and any lines that couldn't be read as part of one
local function parseOutput(output: string): ({ Problem }, { string })
    local problems: { Problem } = {}
    local unparsed: { string } = {}
    local current: Problem? = nil

    for line in string.gmatch(output, "[^\r\n]+") do
        if isLog(line) then
            continue
        end

        local header: Problem? = parseHeader(line)
        if header then
            table.insert(problems, header)
            current = header
        elseif current and not isNotice(line) then
            table.insert(current.details, line)
        else
            table.insert(unparsed, line)
        end
    end

    return problems, unparsed
end

local function problemKey(problem: Problem): string
    local details: string = table.concat(problem.details, "\n")
    return `{problem.path}:{problem.line}:{problem.column}:{problem.kind}:{problem.message}\n{details}`
end

-- The analyzer repeats a problem once per module requiring its file
local function distinct(problems: { Problem }): { Problem }
    local kept: { Problem } = {}
    local seen: { [string]: true } = {}

    for _, problem in problems do
        local key: string = problemKey(problem)
        if not seen[key] then
            seen[key] = true
            table.insert(kept, problem)
        end
    end

    return kept
end

local function comesBefore(a: Problem, b: Problem): boolean
    if a.path ~= b.path then
        return a.path < b.path
    elseif a.line ~= b.line then
        return a.line < b.line
    elseif a.column ~= b.column then
        return a.column < b.column
    end

    return a.message < b.message
end

-- Formatting it

local function paint(color: stdio.Color, text: string): string
    return stdio.color(color) .. text .. stdio.color("reset")
end

local function bold(text: string): string
    return stdio.style("bold") .. text .. stdio.style("reset")
end

local function plural(count: number, noun: string): string
    return `{count} {noun}{if count == 1 then "" else "s"}`
end

-- Drops the "; " some lines end with, and cuts long ones short
local function tidy(text: string, full: boolean): string
    local trimmed: string = string.gsub(text, ";%s*$", "")
    if full or #trimmed <= MAX_LINE_LENGTH then
        return trimmed
    end

    return `{string.sub(trimmed, 1, MAX_LINE_LENGTH)}...`
end

local function isReason(detail: string): boolean
    return string.sub(detail, 1, 4) == "\t * "
end

-- Tabbed lines are types, starred lines reasons, and the rest join them up
local function formatDetail(detail: string, full: boolean): string
    if isReason(detail) then
        return `  • {tidy(string.sub(detail, 5), full)}`
    elseif string.sub(detail, 1, 1) == "\t" then
        return `  {tidy(string.sub(detail, 2), full)}`
    elseif string.find(detail, "^this is because") then
        return "because"
    end

    return tidy(detail, full)
end

local function formatDetails(details: { string }, full: boolean): { string }
    local lines: { string } = {}
    local reasons: number = 0

    for _, detail in details do
        if isReason(detail) then
            reasons += 1
        end

        if full or not isReason(detail) or reasons <= MAX_REASONS then
            table.insert(lines, formatDetail(detail, full))
        end
    end

    if not full and reasons > MAX_REASONS then
        table.insert(lines, `  • ...and {reasons - MAX_REASONS} more (--full shows them)`)
    end

    return lines
end

local function isError(problem: Problem): boolean
    return string.find(problem.kind, "Error$") ~= nil
end

local function formatLabel(problem: Problem): string
    local name: string = if isError(problem) then "error" else "warning"
    local padding: string = string.rep(" ", LABEL_WIDTH - #name)

    return paint(if isError(problem) then "red" else "yellow", name) .. padding
end

-- Errors explain themselves; a lint's name is what you'd search for or silence
local function formatMessage(problem: Problem, full: boolean): string
    local message: string = tidy(problem.message, full)
    return if isError(problem) then message else `{message} ({problem.kind})`
end

local function formatProblem(problem: Problem, full: boolean): string
    local lines: { string } = {
        bold(`{problem.path}:{problem.line}:{problem.column}`),
        `  {formatLabel(problem)}  {formatMessage(problem, full)}`,
    }

    for _, detail in formatDetails(problem.details, full) do
        table.insert(lines, MESSAGE_INDENT .. detail)
    end

    return table.concat(lines, "\n")
end

local function formatSummary(problems: { Problem }): string
    local files: { [string]: true } = {}
    local fileCount: number = 0

    for _, problem in problems do
        if not files[problem.path] then
            files[problem.path] = true
            fileCount += 1
        end
    end

    return `{plural(#problems, "problem")} in {plural(fileCount, "file")}`
end

local function printProblems(problems: { Problem }, full: boolean): ()
    for _, problem in problems do
        print(formatProblem(problem, full))
        print()
    end
end

cli.main(function(args: cli.ParsedArgs): ()
    ensureCacheDir()
    ensureDefs()
    rojo.sourcemap(SOURCEMAP_FILE)

    local result = cli.run("luau-lsp", analyzerArgs(), { check = false })
    local parsed: { Problem }, unparsed: { string } = parseOutput(`{result.stdout}\n{result.stderr}`)

    local problems: { Problem } = distinct(parsed)
    table.sort(problems, comesBefore)

    -- Whatever couldn't be read still gets shown, rather than disappearing
    for _, line in unparsed do
        print(line)
    end

    printProblems(problems, args.flags.full == true)

    if #problems > 0 then
        cli.fail("analyze", formatSummary(problems))
    elseif not result.ok then
        cli.fail("analyze", `luau-lsp exited with code {result.code} and no problems listed`)
    end

    cli.success("analyze", "no problems found")
end)
