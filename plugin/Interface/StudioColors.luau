local flux = require("../Packages/Flux")
local theme = require("./Theme")

local DARK_THEME_LIGHTENING: number = 0.35
local LIGHT_THEME_TOP_BRIGHTNESS: number = 1.4
local LIGHT_THEME_BOTTOM_BRIGHTNESS: number = 0.75

local function brightened(color: Color3, factor: number): Color3
    local hue: number, saturation: number, value: number = color:ToHSV()
    return Color3.fromHSV(hue, saturation, math.min(value * factor, 1))
end

local function studioColors(scope: flux.Scope, studioTheme: flux.UsedAs<StudioTheme>): theme.Colors
    local isDark: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        return use(studioTheme).Name == "Dark"
    end)

    local function color(guide: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): flux.Computed<Color3>
        return scope:computed(function(use: flux.Use): Color3
            return use(studioTheme):GetColor(guide, modifier)
        end)
    end

    local function byTheme(dark: string, light: string): flux.Computed<Color3>
        return scope:computed(function(use: flux.Use): Color3
            return Color3.fromHex(if use(isDark) then dark else light)
        end)
    end

    local function gradient(base: flux.Computed<Color3>): flux.Computed<ColorSequence>
        return scope:computed(function(use: flux.Use): ColorSequence
            local middle: Color3 = use(base)

            if use(isDark) then
                return ColorSequence.new(middle:Lerp(theme.white, DARK_THEME_LIGHTENING), middle)
            end

            return ColorSequence.new(
                brightened(middle, LIGHT_THEME_TOP_BRIGHTNESS),
                brightened(middle, LIGHT_THEME_BOTTOM_BRIGHTNESS)
            )
        end)
    end

    local pass: flux.Computed<Color3> = byTheme("#56D364", "#1A7F37")
    local fail: flux.Computed<Color3> = byTheme("#FF6B6B", "#CF222E")
    local errored: flux.Computed<Color3> = byTheme("#FFB042", "#B35900")
    local muted: flux.Computed<Color3> = color(Enum.StudioStyleGuideColor.CheckedFieldIndicator, Enum.StudioStyleGuideModifier.Disabled)

    return {
        isDark = isDark,

        background = color(Enum.StudioStyleGuideColor.MainBackground),
        inputBackground = color(Enum.StudioStyleGuideColor.InputFieldBackground),
        border = color(Enum.StudioStyleGuideColor.CheckedFieldBorder, Enum.StudioStyleGuideModifier.Disabled),

        text = color(Enum.StudioStyleGuideColor.MainText),
        brightText = color(Enum.StudioStyleGuideColor.BrightText),
        subText = color(Enum.StudioStyleGuideColor.SubText),

        buttonText = color(Enum.StudioStyleGuideColor.ButtonText),
        buttonHover = color(Enum.StudioStyleGuideColor.ButtonText, Enum.StudioStyleGuideModifier.Selected),

        pass = pass,
        fail = fail,
        error = errored,

        passGradient = gradient(pass),
        failGradient = gradient(fail),
        errorGradient = gradient(errored),
        mutedGradient = gradient(muted),
    }
end

return studioColors
