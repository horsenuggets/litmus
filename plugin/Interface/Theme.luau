local flux = require("../Packages/Flux")

export type Colors = {
    isDark: flux.Computed<boolean>,

    background: flux.Computed<Color3>,
    inputBackground: flux.Computed<Color3>,
    border: flux.Computed<Color3>,

    text: flux.Computed<Color3>,
    brightText: flux.Computed<Color3>,
    subText: flux.Computed<Color3>,

    buttonText: flux.Computed<Color3>,
    buttonHover: flux.Computed<Color3>,

    pass: flux.Computed<Color3>,
    fail: flux.Computed<Color3>,
    error: flux.Computed<Color3>,

    passGradient: flux.Computed<ColorSequence>,
    failGradient: flux.Computed<ColorSequence>,
    errorGradient: flux.Computed<ColorSequence>,
    mutedGradient: flux.Computed<ColorSequence>,
}

local WHITE: Color3 = Color3.fromRGB(255, 255, 255)
local FONTS: string = "rbxasset://fonts/families"

local ICON_SIZE: number = 16
local ROW_GAP: number = 6

local context: flux.Context<Colors?> = flux.context(nil :: Colors?)

local theme = {
    white = WHITE,

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
    stroke = 1,

    rowPadding = 8,
    rowGap = ROW_GAP,
    iconSize = ICON_SIZE,
    rowIndent = ICON_SIZE + ROW_GAP,
    listGap = 2,

    hoverAlpha = 0.1,
    hoverSpeed = 31,

    toggleSpeed = 38,
    toggleDamping = 1.1,

    tintTransparency = 0.85,
}

function theme.provide(scope: flux.Scope, colors: Colors): ()
    context:provide(scope, colors)
end

function theme.colors(scope: flux.Scope): Colors
    local colors: Colors? = context:consume(scope)
    if not colors then
        error("[Litmus]: no colours here; build this under theme.provide", 2)
    end

    return colors
end

return theme
