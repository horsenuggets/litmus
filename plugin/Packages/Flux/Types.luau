type Set<T> = { [T]: true }

export type UsedAs<T> = Readable<T> | T

--[[
    The type a state object holds, or the type itself if it isn't one. `use`
    computes its result with this because solving `UsedAs<T>` backwards is
    ambiguous: a Value<number> could be T = number or T = Value<number>.
]]
export type function Unwrap(input: type): type
    local function held(t: type): type?
        if t:is("table") then
            return t:readproperty(types.singleton("_value"))
        elseif t:is("intersection") then
            for _, part in t:components() do
                local value = held(part)
                if value then
                    return value
                end
            end
        end

        return nil
    end

    local function unwrap(t: type): type
        if t:is("union") then
            local parts = {}
            for _, part in t:components() do
                table.insert(parts, unwrap(part))
            end

            return types.unionof(table.unpack(parts))
        end

        return held(t) or t
    end

    return unwrap(input)
end

export type Use = <T>(dependency: T) -> Unwrap<T>

export type Node = {
    _execution: "eager" | "lazy",
    _status: "invalid" | "current" | "busy",
    _dead: boolean,

    -- When the value last changed, and when the node last looked at its dependencies
    _time: number,
    _checked: number,

    _dependencies: Set<Node>,
    _dependents: Set<Node>,

    update: (Node) -> boolean,
    destroy: (Node) -> (),
}

export type Readable<T> = Node & {
    _value: T,
}

export type Value<T> = Readable<T> & {
    -- A recursive `self` stops the solver matching `value.new` against Scope
    set: (self: any, new: T) -> (),
}

export type Computed<T> = Readable<T>

export type Spring<T> = Readable<T> & {
    outVelocity: (self: Spring<T>) -> Value<T>,

    setVelocity: (self: Spring<T>, vel: T) -> (),
    setPosition: (self: Spring<T>, pos: T) -> (),
}

-- A computed or an effect
export type Capture = Node & {
    _use: Use,
    _capture: (Use, Scope) -> any,
    _inner: ScopeInternal,
    _value: any,
}

export type Context<T> = {
    _default: T,

    provide: (self: Context<T>, scope: Scope, provided: T) -> (),
    consume: (self: Context<T>, scope: Scope) -> T,
}

-- Instances
export type Elements = {
    Folder: Folder,
    CanvasGroup: CanvasGroup,
    ViewportFrame: ViewportFrame,
    Frame: Frame,

    ImageButton: ImageButton,
    ImageLabel: ImageLabel,
    ScreenGui: ScreenGui,
    BillboardGui: BillboardGui,
    ScrollingFrame: ScrollingFrame,
    TextButton: TextButton,
    TextBox: TextBox,
    TextLabel: TextLabel,

    UIStroke: UIStroke,
    UICorner: UICorner,
    UIGradient: UIGradient,
    UIAspectRatioConstraint: UIAspectRatioConstraint,
    UIGridLayout: UIGridLayout,
    UIListLayout: UIListLayout,
    UIFlexItem: UIFlexItem,
    UIScale: UIScale,
    UIPadding: UIPadding,
    UIShadow: UIShadow,

    Camera: Camera,
    WorldModel: WorldModel,
    BlurEffect: BlurEffect,

    Part: Part,
    Attachment: Attachment,
    Model: Model,
}

export type function HydrateProperties(instance: type?): type
    local properties = types.newtable()

    while instance do
        for i, v in instance:properties() do
            local connector = v.read and v.read.tag == "table"
            local method = v.read and v.read.tag == "function"

            if not connector and not method and v.write then
                properties:setproperty(i, types.optional(UsedAs(v.write)))
            end
        end

        instance = instance:readparent()
    end

    properties:setindexer(types.number, types.any)

    return properties
end

--[[
    Owns everything made through it, destroying it all last to first. Methods
    pass `self` through as S, so a scope widened by `with` keeps its methods
    through `inner` and into capture callbacks.
]]
export type Scope = {
    value: <T>(self: Scope, initial: T) -> Value<T>,
    computed: <T, S>(self: S, capture: (use: Use, scope: S) -> T) -> Computed<T>,
    effect: <S>(self: S, capture: (use: Use, scope: S) -> ()) -> (),
    spring: <T>(self: Scope, target: T, speed: UsedAs<number>?, damping: UsedAs<number>?) -> Spring<Unwrap<T>>,

    element: <Name>(self: Scope, classname: Name | keyof<Elements> | "") -> (props: HydrateProperties<index<Elements, Name>>) -> index<Elements, Name>,
    hydrate: <T>(self: Scope, instance: T) -> (props: HydrateProperties<T>) -> T,

    insert: <T>(self: Scope, job: T) -> T,
    inner: <S>(self: S) -> S,
    with: <S, A>(self: S, methods: A) -> S & A,
    destroy: (self: Scope) -> (),
}

-- What every scope really holds; only Flux reads these
export type ScopeInternal = Scope & {
    _tasks: { any },
    _dead: boolean,
    _parent: ScopeInternal?,
    _context: { [any]: any }?,
}

-- Every scope is made by Flux, so this always holds
local function internal(scope: Scope): ScopeInternal
    return scope :: any
end

local function isNode(x: any): boolean
    return typeof(x) == "table" and x._execution ~= nil
end

return {
    internal = internal,
    isNode = isNode,
}
