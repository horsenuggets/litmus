local flux = require("../Packages/Flux")
local outcome = require("../Outcome")

-- Gives the source of the script at this path, or nothing if it can't be found
export type Reader = (path: outcome.Path) -> string?

-- Without a reader nothing can be found, which leaves a failure without its lines of code and nothing worse
local function findNothing(_: outcome.Path): string?
    return nil
end

local context: flux.Context<Reader> = flux.context(findNothing)

local sources = {}

-- Everything built under `scope` reads scripts through `reader`
function sources.provide(scope: flux.Scope, reader: Reader): ()
    context:provide(scope, reader)
end

function sources.read(scope: flux.Scope, path: outcome.Path): string?
    return context:consume(scope)(path)
end

return sources
