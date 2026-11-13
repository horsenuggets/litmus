local runService = game:GetService("RunService")

local package = script.Parent
local modules = package.Parent

local graph = require(package.Graph)
local node = require(package.Node)
local springImpl = require(modules.Spring)
local types = require(package.Types)

type Scope = types.Scope
type Use = types.Use
type Spring<T> = types.Spring<T>
type UsedAs<T> = types.UsedAs<T>
type Unwrap<T> = types.Unwrap<T>
type Value<T> = types.Value<T>

type Members<T> = Spring<T> & {
    _owner: Scope,
    _impl: springImpl.Class<T>,

    _heartbeatConn: RBXScriptConnection?,
    _velocity: Value<T>?,
}

local DEFAULT_SPEED: number = 15
local DEFAULT_DAMPING: number = 1

local spring = {}
spring.__index = spring
setmetatable(spring, node)

local function disconnect(self: Members<any>): ()
    local connection: RBXScriptConnection? = self._heartbeatConn
    if connection then
        connection:Disconnect()
        self._heartbeatConn = nil
    end
end

local function listen(self: Members<any>): ()
    if self._heartbeatConn or self._dead then
        return
    end

    self._heartbeatConn = runService.Heartbeat:Connect(function()

        -- Checked before reading, so a spring only stops on a frame that read its exact target
        local settled: boolean = self._impl:isSleeping()

        self._value = self._impl.position
        self._time = graph.counter()

        graph.push(self)

        if self._velocity then
            self._velocity:set(self._impl.velocity)
        end

        graph.flush()

        -- Checked again in case the flush woke it
        if settled and self._impl:isSleeping() then
            disconnect(self)
        end
    end)
end

function spring.new<T>(scope: Scope, target: T, s: UsedAs<number>?, d: UsedAs<number>?): Spring<Unwrap<T>>
    local self: Members<Unwrap<T>> = setmetatable(node.new(), spring) :: any

    local speed: UsedAs<number> = s or DEFAULT_SPEED
    local damping: UsedAs<number> = d or DEFAULT_DAMPING

    local initial: any = graph.peek(target)
    self._value = initial
    self._owner = scope
    self._impl = springImpl.new(initial)

    scope:effect(function(use: Use): ()
        self._impl.target = use(target) :: any
        self._impl.speed = use(speed)
        self._impl.damping = use(damping)

        if not self._impl:isSleeping() then
            listen(self)
        end
    end)

    scope:insert(self)

    return self
end

-- Reactive velocity, created on first request so springs nobody
-- interrogates never pay for the per-frame update
function spring.outVelocity<T>(self: Members<T>): Value<T>
    local existing: Value<T>? = self._velocity
    if existing then
        return existing
    end

    local velocity: Value<T> = self._owner:value(self._impl.velocity)

    self._velocity = velocity
    return velocity
end

function spring.setVelocity<T>(self: Members<T>, vel: T): ()
    self._impl.velocity = vel
    listen(self)
end

-- Takes effect at once rather than on the next Heartbeat, so a jump made
-- before a frame renders is drawn on that same frame
function spring.setPosition<T>(self: Members<T>, pos: T): ()
    self._impl.position = pos

    self._value = pos
    self._time = graph.counter()

    graph.push(self)
    graph.flush()

    listen(self)
end

function spring.destroy<T>(self: Members<T>): ()
    disconnect(self)
    node.destroy(self)
end

return spring
