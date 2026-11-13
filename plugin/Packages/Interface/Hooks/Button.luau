local packages = script.Parent.Parent.Parent

local flux = require(packages.Flux)
local maid = require(packages.Maid)

export type Props = {
    pressing: flux.Value<boolean>?,
    hovering: flux.Value<boolean>?,

    activated: (InputObject, number) -> ()?,

    press: () -> ()?,
    release: () -> ()?,
}

local function button(props: Props): any
    local function action(scope: flux.Scope, instance: Instance)
        if not instance:IsA("GuiButton") then
            error("[Button]: can only be applied to GuiButtons")
        end

        local tasks: maid.Class = maid.new()

        local pressing: flux.Value<boolean>? = props.pressing
        local hovering: flux.Value<boolean>? = props.hovering

        local pressInputs: number = 0
        local hoverInputs: number = 0

        local function update(): ()
            if pressing then
                pressing:set(pressInputs > 0)
            end

            if hovering then
                hovering:set(hoverInputs > 0)
            end
        end

        local function untrack(input: InputObject): ()
            tasks[input] = nil
        end

        local function track(input: InputObject, callback: () -> ()): ()
            update()

            local inner = maid.new()
            inner:add(input:GetPropertyChangedSignal("UserInputState"):Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    untrack(input)
                end
            end))

            inner:add(function()
                callback()
                update()
            end)

            tasks[input] = inner
        end

        local function beginPress(input: InputObject): ()
            if pressInputs == 0 and typeof(props.press) == "function" then
                props.press()
            end

            pressInputs += 1

            track(input, function(): ()
                pressInputs -= 1

                -- TODO: consider if this is correct placement
                if pressInputs == 0 and typeof(props.release) == "function" then
                    props.release()
                end
            end)
        end

        local function beginHover(input: InputObject): ()
            hoverInputs += 1

            track(input, function(): ()
                hoverInputs -= 1
            end)
        end

        tasks:add(instance.InputBegan:Connect(function(input: InputObject)
            local state: Enum.UserInputState = input.UserInputState
            local kind: Enum.UserInputType = input.UserInputType

            if state == Enum.UserInputState.Begin and kind == Enum.UserInputType.MouseButton1 then
                beginPress(input)
            elseif state == Enum.UserInputState.Change and kind == Enum.UserInputType.MouseMovement then
                beginHover(input)
            end
        end))

        tasks:add(instance.InputEnded:Connect(function(input: InputObject)
            untrack(input)
        end))

        if props.activated then
            tasks:add(instance.Activated:Connect(props.activated))
        end

        scope:insert(tasks)
    end

    return action
end

return button
