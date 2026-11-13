local oklabUtils = {}

function oklabUtils.fromOklab(lab: {number}): Color3
    local lRoot: number = lab[1] + lab[2] * 0.3963377774 + lab[3] * 0.2158037573
    local mRoot: number = lab[1] - lab[2] * 0.1055613458 - lab[3] * 0.0638541728
    local sRoot: number = lab[1] - lab[2] * 0.0894841775 - lab[3] * 1.2914855480

    local l: number = lRoot ^ 3
    local m: number = mRoot ^ 3
    local s: number = sRoot ^ 3

    local red: number = l * 4.0767416621 - m * 3.3077115913 + s * 0.2309699292
    local green: number = l * -1.2684380046 + m * 2.6097574011 - s * 0.3413193965
    local blue: number = l * -0.0041960863 - m * 0.7034186147 + s * 1.7076147010

    return Color3.new(
        math.clamp(red, 0, 1),
        math.clamp(green, 0, 1),
        math.clamp(blue, 0, 1)
    )
end

function oklabUtils.toOklab(rgb: Color3): {number}
    local l: number = rgb.R * 0.4122214708 + rgb.G * 0.5363325363 + rgb.B * 0.0514459929
    local m: number = rgb.R * 0.2119034982 + rgb.G * 0.6806995451 + rgb.B * 0.1073969566
    local s: number = rgb.R * 0.0883024619 + rgb.G * 0.2817188376 + rgb.B * 0.6299787005

    local lRoot: number = l ^ (1/3)
    local mRoot: number = m ^ (1/3)
    local sRoot: number = s ^ (1/3)

    return {
        lRoot * 0.2104542553 + mRoot * 0.7936177850 - sRoot * 0.0040720468,
        lRoot * 1.9779984951 - mRoot * 2.4285922050 + sRoot * 0.4505937099,
        lRoot * 0.0259040371 + mRoot * 0.7827717662 - sRoot * 0.8086757660
    }
end

-- Blends `from` toward `to` by `alpha` through Oklab, as a spring blends a Color3
function oklabUtils.lerp(from: Color3, to: Color3, alpha: number): Color3
    local a: {number} = oklabUtils.toOklab(from)
    local b: {number} = oklabUtils.toOklab(to)

    return oklabUtils.fromOklab({
        a[1] + (b[1] - a[1]) * alpha,
        a[2] + (b[2] - a[2]) * alpha,
        a[3] + (b[3] - a[3]) * alpha,
    })
end

return oklabUtils
