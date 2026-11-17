local flux = require("../Packages/Flux")
local outcome = require("../Outcome")
local theme = require("./Theme")

local tone = {}

function tone.text(colors: theme.Colors, of: outcome.Tone): flux.Computed<Color3>
    if of == "good" then
        return colors.pass
    elseif of == "dim" then
        return colors.subText
    end

    return colors.text
end

function tone.fill(colors: theme.Colors, of: outcome.Tone): flux.Computed<Color3>
    if of == "good" then
        return colors.pass
    elseif of == "dim" then
        return colors.border
    end

    return colors.subText
end

return tone
