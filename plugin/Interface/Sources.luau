local flux = require("../Packages/Flux")

-- Gives the source of the script with this full name, or nothing if it can't be found
export type Reader = (name: string) -> string?

-- Without a reader nothing can be found, which leaves a failure without its lines of code and nothing worse
local function findNothing(_: string): string?
    return nil
end

local context: flux.Context<Reader> = flux.context(findNothing)

local sources = {}

-- Everything built under `scope` reads scripts through `reader`
function sources.provide(scope: flux.Scope, reader: Reader): ()
    context:provide(scope, reader)
end

function sources.read(scope: flux.Scope, name: string): string?
    return context:consume(scope)(name)
end

return sources
