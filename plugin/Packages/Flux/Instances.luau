local package = script.Parent

local defaults = require(package.Defaults)
local types = require(package.Types)

type Scope = types.Scope
type Use = types.Use
type Action = (Scope, Instance) -> ()

local function applyChildren(scope: Scope, obj: any, value: any): ()
    local previousChildren: { [Instance]: true } = {}

    scope:effect(function(use: Use): ()
        local rawChildren: any = use(value)

        local currentChildren: { Instance }
        if typeof(rawChildren) == "Instance" then
            currentChildren = { rawChildren }
        elseif typeof(rawChildren) == "table" then
            currentChildren = rawChildren
        else
            currentChildren = {}
        end

        local currentChildrenSet: { [Instance]: true } = {}
        for _, currentChild: Instance in currentChildren do
            currentChildrenSet[currentChild] = true
        end

        -- Unparent any previous children who do not exist in current children
        for previousChild: Instance in previousChildren do
            if not currentChildrenSet[previousChild] then
                previousChild.Parent = nil
            end
        end

        -- Parent any children who exist in currentChildren, but not in previous children
        for currentChild: Instance in currentChildrenSet do
            if not previousChildren[currentChild] then
                currentChild.Parent = obj
            end
        end

        previousChildren = currentChildrenSet
    end)
end

local function applyProperty(scope: Scope, obj: any, prop: string, value: any): ()
    if types.isNode(value) then
        scope:effect(function(use: Use): ()
            obj[prop] = use(value)
        end)
    else
        obj[prop] = value
    end
end

-- Properties and children go on now; actions wait until they all have
local function apply(scope: Scope, instance: Instance, props: { [any]: any }, actions: { Action }): ()
    for key: any, value: any in props do
        if typeof(key) == "string" then
            applyProperty(scope, instance, key, value)
        elseif types.isNode(value) then
            applyChildren(scope, instance, value)
        elseif typeof(value) == "table" then
            apply(scope, instance, value, actions)
        elseif typeof(value) == "Instance" then
            value.Parent = instance
        elseif typeof(value) == "function" then
            table.insert(actions, value)
        end
    end
end

local function hydrate(scope: Scope, instance: Instance): (props: { [any]: any }) -> any
    return function(props: { [any]: any }): any
        local actions: { Action } = {}
        apply(scope, instance, props, actions)

        for _, action in actions do
            action(scope, instance)
        end

        return instance
    end
end

local function element(scope: Scope, classname: string): (props: { [any]: any }) -> any
    return function(props: { [any]: any }): any
        local instance: any = Instance.new(classname :: any)

        local classDefaults: { [string]: any }? = defaults[classname]
        if classDefaults then
            for prop, value in classDefaults do
                instance[prop] = value
            end
        end

        scope:insert(instance)
        return hydrate(scope, instance)(props)
    end
end

return {
    element = element,
    hydrate = hydrate,
}
