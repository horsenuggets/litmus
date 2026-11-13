local flux = require("../Packages/Flux")

-- The colours that depend on Studio's theme, which follow it when the user switches theme
export type Colors = {
    isDark: flux.Computed<boolean>,

    background: flux.Computed<Color3>,
    inputBackground: flux.Computed<Color3>,
    border: flux.Computed<Color3>,

    text: flux.Computed<Color3>,
    brightText: flux.Computed<Color3>,
    subText: flux.Computed<Color3>,
    mutedIcon: flux.Computed<Color3>,

    buttonText: flux.Computed<Color3>,
    buttonHover: flux.Computed<Color3>,

    pass: flux.Computed<Color3>,
    fail: flux.Computed<Color3>,
    error: flux.Computed<Color3>,

    -- The same colours as fills for the white icons, a little lighter at the top
    passGradient: flux.Computed<ColorSequence>,
    failGradient: flux.Computed<ColorSequence>,
    errorGradient: flux.Computed<ColorSequence>,
    mutedGradient: flux.Computed<ColorSequence>,
}

local WHITE: Color3 = Color3.fromRGB(255, 255, 255)

-- How far a gradient's top is lightened; less on a light background, where a pale top would fade into it
local DARK_THEME_LIGHTENING: number = 0.35
local LIGHT_THEME_LIGHTENING: number = 0.15

local FONTS: string = "rbxasset://fonts/families"

local studio: Studio = settings().Studio

local context: flux.Context<Colors?> = flux.context(nil :: Colors?)

local theme = {
    -- What fills a button or a checked box, and what is drawn on that fill; neither depends on Studio's theme
    brandGradient = ColorSequence.new(Color3.fromHex("#8448DC"), Color3.fromHex("#6230C8")),
    onBrand = WHITE,
    onBrandGradient = ColorSequence.new(WHITE, Color3.fromHex("#E6D6FF")),

    mainFont = Font.new(`{FONTS}/Montserrat.json`, Enum.FontWeight.Medium),
    boldFont = Font.new(`{FONTS}/Montserrat.json`, Enum.FontWeight.Bold),
    codeFont = Font.new(`{FONTS}/RobotoMono.json`),

    smallTextSize = 13,
    bodyTextSize = 15,
    mediumTextSize = 16,
    largeTextSize = 18,
    titleTextSize = 20,

    cornerRadius = UDim.new(0, 5),

    -- What every row of a list shares, so that rows nested in one another line up
    rowPadding = 8,
    rowGap = 6,
    iconSize = 16,
    listGap = 2,

    -- How strongly a hover fill shows, and how fast it comes and goes
    hoverAlpha = 0.1,
    hoverSpeed = 31,

    -- How see-through a fill is when it only tints what is behind it with an outcome's colour
    tintTransparency = 0.85,
}

-- Reads Studio's theme into `scope`; everything built under it finds the colours through `theme.colors`
function theme.provide(scope: flux.Scope): ()
    local studioTheme: flux.Value<StudioTheme> = scope:value(studio.Theme)

    scope:insert(studio.ThemeChanged:Connect(function(): ()
        studioTheme:set(studio.Theme)
    end))

    local isDark: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        return use(studioTheme).Name == "Dark"
    end)

    local function color(guide: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): flux.Computed<Color3>
        return scope:computed(function(use: flux.Use): Color3
            return use(studioTheme):GetColor(guide, modifier)
        end)
    end

    -- Studio has no colours for a test's outcome, so each is picked to read on its background
    local function byTheme(dark: string, light: string): flux.Computed<Color3>
        return scope:computed(function(use: flux.Use): Color3
            return Color3.fromHex(if use(isDark) then dark else light)
        end)
    end

    local function gradient(base: flux.Computed<Color3>): flux.Computed<ColorSequence>
        return scope:computed(function(use: flux.Use): ColorSequence
            local bottom: Color3 = use(base)
            local lightening: number = if use(isDark) then DARK_THEME_LIGHTENING else LIGHT_THEME_LIGHTENING

            return ColorSequence.new(bottom:Lerp(WHITE, lightening), bottom)
        end)
    end

    local pass: flux.Computed<Color3> = byTheme("#56D364", "#1A7F37")
    local fail: flux.Computed<Color3> = byTheme("#FF6B6B", "#CF222E")
    local errored: flux.Computed<Color3> = byTheme("#FFB042", "#B35900")
    local mutedIcon: flux.Computed<Color3> = color(Enum.StudioStyleGuideColor.CheckedFieldIndicator, Enum.StudioStyleGuideModifier.Disabled)

    local colors: Colors = {
        isDark = isDark,

        background = color(Enum.StudioStyleGuideColor.MainBackground),
        inputBackground = color(Enum.StudioStyleGuideColor.InputFieldBackground),
        border = color(Enum.StudioStyleGuideColor.CheckedFieldBorder, Enum.StudioStyleGuideModifier.Disabled),

        text = color(Enum.StudioStyleGuideColor.MainText),
        brightText = color(Enum.StudioStyleGuideColor.BrightText),
        subText = color(Enum.StudioStyleGuideColor.SubText),
        mutedIcon = mutedIcon,

        buttonText = color(Enum.StudioStyleGuideColor.ButtonText),
        buttonHover = color(Enum.StudioStyleGuideColor.ButtonText, Enum.StudioStyleGuideModifier.Selected),

        pass = pass,
        fail = fail,
        error = errored,

        passGradient = gradient(pass),
        failGradient = gradient(fail),
        errorGradient = gradient(errored),
        mutedGradient = gradient(mutedIcon),
    }

    context:provide(scope, colors)
end

function theme.colors(scope: flux.Scope): Colors
    local colors: Colors? = context:consume(scope)
    if not colors then
        error("[Theme]: no colours here; build this under theme.provide", 2)
    end

    return colors
end

return theme
