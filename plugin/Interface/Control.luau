local checkbox = require("./Components/Checkbox")
local flux = require("../Packages/Flux")
local imageIds = require("../ImageIds")
local label = require("./Components/Label")
local textButton = require("./Components/TextButton")
local theme = require("./Theme")

export type CliResults = "none" | "unseen" | "seen"

export type Props = {
    connected: flux.UsedAs<boolean>,
    connectActivated: () -> (),

    testActivated: () -> (),

    cliResults: flux.UsedAs<CliResults>,
    cliResultsActivated: () -> (),
}

local PADDING: number = 20
local GAP: number = 10

local HEADER_HEIGHT: number = 32
local HEADER_GAP: number = 8
local LOGO_SIZE: number = 28

local CONNECT_ROW_HEIGHT: number = 36
local BUTTON_ROW_HEIGHT: number = 34

local function control(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    local hasCliResults: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        return use(props.cliResults) ~= "none"
    end)

    return scope:element "Frame" {
        Name = "Control",

        BackgroundColor3 = colors.background,
        BackgroundTransparency = 0,

        scope:element "UIPadding" {
            PaddingTop = UDim.new(0, PADDING),
            PaddingBottom = UDim.new(0, PADDING),
            PaddingLeft = UDim.new(0, PADDING),
            PaddingRight = UDim.new(0, PADDING),
        },

        scope:element "Frame" {
            Name = "Top",

            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),

            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.fromScale(1, 0),

            scope:element "UIListLayout" {
                Padding = UDim.new(0, GAP),
            },

            scope:element "Frame" {
                Name = "Header",
                LayoutOrder = 1,

                Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    Padding = UDim.new(0, HEADER_GAP),
                },

                scope:element "ImageLabel" {
                    Name = "Logo",
                    LayoutOrder = 1,

                    Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),

                    Image = scope:computed(function(use: flux.Use): string
                        return if use(colors.isDark) then imageIds.logoOnDark else imageIds.logoOnLight
                    end),
                },

                label(scope, {
                    layoutOrder = 2,

                    text = "Litmus",
                    font = theme.boldFont,
                    size = theme.titleTextSize,
                    color = colors.brightText,
                }),
            },

            scope:element "Frame" {
                Name = "Connect",
                LayoutOrder = 2,

                Size = UDim2.new(1, 0, 0, CONNECT_ROW_HEIGHT),

                scope:element "UIListLayout" {
                    FillDirection = Enum.FillDirection.Horizontal,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
                },

                label(scope, {
                    layoutOrder = 1,

                    text = "Connect to CLI",
                    font = theme.mainFont,
                    size = theme.mediumTextSize,
                    color = colors.text,
                }),

                checkbox(scope, {
                    layoutOrder = 2,

                    checked = props.connected,
                    activated = props.connectActivated,
                }),
            },
        },

        scope:element "Frame" {
            Name = "Buttons",

            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),

            Size = UDim2.new(1, 0, 0, BUTTON_ROW_HEIGHT),

            scope:element "UIListLayout" {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                Padding = UDim.new(0, GAP),
            },

            scope:computed(function(use: flux.Use, inner: flux.Scope): TextButton?
                if not use(hasCliResults) then
                    return nil
                end

                return textButton(inner, {
                    layoutOrder = 1,

                    text = "CLI",
                    style = "bordered",
                    activated = props.cliResultsActivated,

                    hasNotice = inner:computed(function(useInner: flux.Use): boolean
                        return useInner(props.cliResults) == "unseen"
                    end),
                })
            end),

            textButton(scope, {
                layoutOrder = 2,

                text = "Test",
                style = "solid",
                activated = props.testActivated,
            }),
        },
    }
end

return control
