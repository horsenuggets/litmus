local flux = require("../Packages/Flux")
local outcome = require("../Outcome")

export type Reader = (path: outcome.Path) -> string?

local function findNothing(_: outcome.Path): string?
    return nil
end

local context: flux.Context<Reader> = flux.context(findNothing)

local sources = {}

function sources.provide(scope: flux.Scope, reader: Reader): ()
    context:provide(scope, reader)
end

function sources.read(scope: flux.Scope, path: outcome.Path): string?
    return context:consume(scope)(path)
end

return sources
