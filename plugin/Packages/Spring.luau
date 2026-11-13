local packages = script.Parent

local oklabUtils = require(packages.Utils.Oklab)
local quaternionUtils = require(packages.Utils.Quaternion)
local springUtils = require(packages.Utils.Spring)

-- Constants
local DEFAULT_SPEED: number = 10
local DEFAULT_DAMPING: number = 1

-- Helpers
local function unpackComponents(packed: any): { number }
    local kind: string = typeof(packed)

    if kind == "number" then
        return { packed }
    elseif kind == "Vector2" then
        return { packed.X, packed.Y }
    elseif kind == "Vector3" then
        return { packed.X, packed.Y, packed.Z }
    elseif kind == "Color3" then
        return oklabUtils.toOklab(packed)
    elseif kind == "CFrame" then
        local q: { number } = quaternionUtils.toQuaternion(packed)
        local pos: Vector3 = packed.Position
        return { pos.X, pos.Y, pos.Z, q[1], q[2], q[3], q[4] }
    elseif kind == "UDim2" then
        return {
            packed.X.Scale,
            packed.X.Offset,
            packed.Y.Scale,
            packed.Y.Offset,
        }
    elseif kind == "table" then
        return table.clone(packed)
    else
        error(`[Spring]: unable to unpack type {kind}`)
    end
end

local function packComponents(valueType: string, c: { number }): any
    if valueType == "number" then
        return c[1]
    elseif valueType == "Vector2" then
        return Vector2.new(c[1], c[2])
    elseif valueType == "Vector3" then
        return Vector3.new(c[1], c[2], c[3])
    elseif valueType == "Color3" then
        return oklabUtils.fromOklab(c)
    elseif valueType == "CFrame" then
        local rotation: CFrame = quaternionUtils.fromQuaternion({ c[4], c[5], c[6], c[7] })
        return rotation + Vector3.new(c[1], c[2], c[3])
    elseif valueType == "UDim2" then
        return UDim2.new(c[1], c[2], c[3], c[4])
    elseif valueType == "table" then
        return c
    else
        error(`[Spring]: unable to pack animatable type {valueType}`)
    end
end

-- Spring

export type Class<T> = {

    -- Private members
    _type: string,
    _time: number,

    _positions: { number },
    _velocities: { number },
    _targets: { number },

    _speed: number,
    _damping: number,
    _sleeping: boolean,

    _integrate: (self: Class<T>, nextTime: number) -> ({number}, {number}),
    _shouldSleep: (self: Class<T>, positions: {number}, velocities: {number}) -> boolean,
    _snapToTarget: (self: Class<T>) -> (),

    -- Public members
    p: T, position: T,
    v: T, velocity: T,
    t: T, target: T,
    s: number, speed: number,
    d: number, damping: number,

    step: (self: Class<T>, dt: number?) -> (),
    isSleeping: (self: Class<T>) -> boolean,
    destroy: (self: Class<T>) -> (),
}

local spring = {}

-- Metamethods

spring.__index = function<T>(self: Class<T>, key: string)
    if key == "p" or key == "position" then
        self:step()
        return packComponents(self._type, self._positions)
    elseif key == "v" or key == "velocity" then
        self:step()
        return packComponents(self._type, self._velocities)
    elseif key == "t" or key == "target" then
        return packComponents(self._type, self._targets)
    elseif key == "s" or key == "speed" then
        return self._speed
    elseif key == "d" or key == "damping" then
        return self._damping
    end

    return spring[key]
end

-- `field` already exists, so the write doesn't come back through __newindex
local function setComponents<T>(self: Class<T>, field: string, value: any): ()
    if typeof(value) ~= self._type then
        error(`[Spring]: invalid value type {typeof(value)}; expected {self._type}`)
    end

    self:step()

    local fields: any = self
    fields[field] = unpackComponents(value)
    self._sleeping = false
end

spring.__newindex = function<T>(self: Class<T>, key: string, value: any)
    if key == "p" or key == "position" then
        setComponents(self, "_positions", value)
    elseif key == "v" or key == "velocity" then
        setComponents(self, "_velocities", value)
    elseif key == "t" or key == "target" then
        setComponents(self, "_targets", value)
    elseif key == "s" or key == "speed" then
        if typeof(value) ~= "number" then
            error("[Spring]: speed must be a number")
        elseif value <= 0 then
            error("[Spring]: speed must be positive")
        end

        self:step()
        self._speed = value
    elseif key == "d" or key == "damping" then
        if typeof(value) ~= "number" then
            error("[Spring]: damping must be a number")
        elseif value < 0 then
            error("[Spring]: damping must be non-negative")
        end

        self:step()
        self._damping = value
    else
        error(`[Spring]: invalid or read-only key {key}`)
    end
end

-- Internal methods

function spring._shouldSleep<T>(self: Class<T>, pos: { number }, vel: { number }): boolean
    for i = 1, #pos do
        if not springUtils.settled(pos[i], vel[i], self._targets[i]) then
            return false
        end
    end
    return true
end

function spring._integrate<T>(self: Class<T>, nextTime: number): ({ number }, { number })
    if self._sleeping then
        return self._positions, self._velocities
    end
    
    local delta: number = nextTime - self._time
    local newPosition: {number} = table.create(#self._positions) :: any
    local newVelocity: {number} = table.create(#self._velocities) :: any

    for i = 1, #self._positions do
        newPosition[i], newVelocity[i] = springUtils.step(
            self._positions[i],
            self._velocities[i],
            self._targets[i],
            self._speed,
            self._damping,
            delta
        )
    end

    return newPosition, newVelocity
end

function spring._snapToTarget<T>(self: Class<T>)
    self._positions = table.clone(self._targets)
    table.clear(self._velocities)
    for i = 1, #self._positions do
        self._velocities[i] = 0
    end
    self._sleeping = true
end

-- Public interface

function spring.new<T>(initial: T?): Class<T>
    local self: Class<T> = {} :: any

    local init: T | number = initial or 0

    self._type = typeof(init)
    self._positions = unpackComponents(init)
    self._velocities = table.create(#self._positions, 0)
    self._targets = table.clone(self._positions)

    self._speed = DEFAULT_SPEED
    self._damping = DEFAULT_DAMPING
    self._time = os.clock()
    self._sleeping = true

    return setmetatable(self, spring) :: any
end

function spring.step<T>(self: Class<T>, dt: number?)
    local nextTime: number = if dt then self._time + dt else os.clock()
    self._positions, self._velocities = self:_integrate(nextTime)
    self._time = os.clock()

    if self:_shouldSleep(self._positions, self._velocities) then
        self:_snapToTarget()
    else
        self._sleeping = false
    end
end

function spring.destroy<T>(self: Class<T>)
    table.clear(self._positions)
    table.clear(self._velocities)
    table.clear(self._targets)
end

function spring.isSleeping<T>(self: Class<T>): boolean
    self:step()
    return self._sleeping
end

return spring
