local litmus = require("../../Litmus")

local function inline(loads: { () -> () }, results: ((specs: { litmus.SpecResult }) -> litmus.Remarks?)?): litmus.Adapter
    local specs: { litmus.Spec } = {}
    for index, load in loads do
        specs[index] = { path = { `Inline{index}.spec` }, load = load }
    end

    return {
        specs = specs,

        locate = function(_: string): { string }?
            return nil
        end,

        spawn = function(run: (() -> ()) | thread): ()
            task.spawn(run)
        end,

        results = results,
    }
end

return inline
