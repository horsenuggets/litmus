local modules = script.Parent.Parent

local tableUtils = require(modules.Utils.Table)

local defaults: { [string]: { [string]: any } } = {}

defaults.Part = {
    Size = Vector3.one,
    Anchored = true,
    CanCollide = false,
    CanQuery = false,
    CanTouch = false,
}

defaults.GuiObject = {
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromScale(1, 1),
}

-- Containers
defaults.Frame = defaults.GuiObject
defaults.ScrollingFrame = defaults.GuiObject
defaults.ViewportFrame = defaults.GuiObject

defaults.CanvasGroup = tableUtils.merge(defaults.GuiObject, {
    ClipsDescendants = true,
})

-- Roots
defaults.ScreenGui = {
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}

-- Labels
defaults.ImageLabel = tableUtils.merge(defaults.GuiObject, {
    ImageColor3 = Color3.fromRGB(255, 255, 255),
})

defaults.TextLabel = tableUtils.merge(defaults.GuiObject, {
    Text = "TEXT",
    TextScaled = true,
    TextStrokeTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    TextColor3 = Color3.fromRGB(255, 255, 255),
})

-- Buttons
defaults.GuiButton = tableUtils.merge(defaults.GuiObject, {
    AutoButtonColor = false,
})

defaults.TextButton = tableUtils.merge(defaults.GuiButton, {
    Text = "",
    TextScaled = true,
    TextStrokeTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextColor3 = Color3.fromRGB(255, 255, 255),
})

-- UI Effects
defaults.UIGridStyleLayout = {
    SortOrder = Enum.SortOrder.LayoutOrder,
}

defaults.UIListLayout = defaults.UIGridStyleLayout
defaults.UIGridLayout = defaults.UIGridStyleLayout

defaults.UICorner = {
    CornerRadius = UDim.new(0.5, 0),
}

defaults.UIGradient = {
    Rotation = 90,
}

-- Figma default: a drop shadow doesn't darken a translucent fill
defaults.UIShadow = {
    ShowBehindParent = false,
}

return defaults