local flux = require("../Packages/Flux")
local icon = require("./Components/Icon")
local outcome = require("../Outcome")
local theme = require("./Theme")

-- How an outcome is shown, wherever it is shown
export type Style = {
    icon: icon.Name,
    word: string,

    color: flux.Computed<Color3>,
    gradient: flux.Computed<ColorSequence>,
}

local function statusStyle(scope: flux.Scope, status: outcome.Status): Style
    local colors: theme.Colors = theme.colors(scope)

    if status == "ERROR" then
        return { icon = "warn", word = "errored", color = colors.error, gradient = colors.errorGradient }
    elseif status == "FAIL" then
        return { icon = "cross", word = "failed", color = colors.fail, gradient = colors.failGradient }
    end

    return { icon = "check", word = "passed", color = colors.pass, gradient = colors.passGradient }
end

return statusStyle
