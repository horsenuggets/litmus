local flux = require("../Packages/Flux")

-- The colours a provider decides, each free to change while the interface is up
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

    -- The same colours as fills for the white icons, a little lighter at the top
    passGradient: flux.Computed<ColorSequence>,
    failGradient: flux.Computed<ColorSequence>,
    errorGradient: flux.Computed<ColorSequence>,
    mutedGradient: flux.Computed<ColorSequence>,
}

local WHITE: Color3 = Color3.fromRGB(255, 255, 255)
local FONTS: string = "rbxasset://fonts/families"

local context: flux.Context<Colors?> = flux.context(nil :: Colors?)

local theme = {
    -- What fills a button or a checked box, and what is drawn on that fill; the same whatever the colours are
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

-- Everything built under `scope` finds these colours through `theme.colors`
function theme.provide(scope: flux.Scope, colors: Colors): ()
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
