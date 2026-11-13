local checkbox = require("./Components/Checkbox")
local flux = require("../Packages/Flux")
local header = require("./Components/Header")
local label = require("./Components/Label")
local textButton = require("./Components/TextButton")
local theme = require("./Theme")

-- Whether there are results from a CLI's run to open, and if so whether they have been opened yet
export type CliResults = "none" | "unseen" | "seen"

export type Props = {
    connected: flux.UsedAs<boolean>,
    connectActivated: () -> (),

    testActivated: () -> (),

    -- The button for the CLI's results exists only while there are some, and carries a dot until they are opened
    cliResults: flux.UsedAs<CliResults>,
    cliResultsActivated: () -> (),
}

local SIDE_PADDING: number = 20
local GAP: number = 10

local CONNECT_ROW_HEIGHT: number = 36
local BUTTON_ROW_HEIGHT: number = 34

-- What the control window holds, built into whatever it is parented to
local function control(scope: flux.Scope, props: Props): Frame
    local colors: theme.Colors = theme.colors(scope)

    -- Rebuilt only when results appear or go, and not when they are merely seen
    local hasCliResults: flux.Computed<boolean> = scope:computed(function(use: flux.Use): boolean
        return use(props.cliResults) ~= "none"
    end)

    return scope:element "Frame" {
        Name = "Control",

        BackgroundColor3 = colors.background,
        BackgroundTransparency = 0,

        scope:element "UIPadding" {
            PaddingLeft = UDim.new(0, SIDE_PADDING),
            PaddingRight = UDim.new(0, SIDE_PADDING),
        },

        scope:element "UIListLayout" {
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, GAP),
        },

        header(scope, { layoutOrder = 1 }),

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

        scope:element "Frame" {
            Name = "Buttons",
            LayoutOrder = 3,

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
