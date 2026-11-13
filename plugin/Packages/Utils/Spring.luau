-- Damped spring maths: `speed` is the natural frequency in radians per second, and a `damping` below 1 overshoots

-- Closer than this to rest, a spring counts as settled
local REST_TOLERANCE: number = 1e-3

local springUtils = {}

-- Position and velocity after `dt` seconds; exact for any dt
function springUtils.step(position: number, velocity: number, target: number, speed: number, damping: number, dt: number): (number, number)
    local time: number = dt * speed
    local d2: number = damping * damping
    local h: number, si: number, co: number

    if d2 < 1 then
        h = math.sqrt(1 - d2)
        local ep: number = math.exp(-damping * time) / h
        co = ep * math.cos(h * time)
        si = ep * math.sin(h * time)
    elseif d2 == 1 then
        h = 1
        local ep: number = math.exp(-damping * time)
        co = ep
        si = ep * time
    else
        h = math.sqrt(d2 - 1)
        local u: number = math.exp((-damping + h) * time) / (2 * h)
        local v: number = math.exp((-damping - h) * time) / (2 * h)
        co = u + v
        si = u - v
    end

    local a0: number = h * co + damping * si
    local a1: number = 1 - a0
    local a2: number = si / speed

    local b0: number = -speed * si
    local b1: number = speed * si
    local b2: number = h * co - damping * si

    return a0 * position + a1 * target + a2 * velocity,
           b0 * position + b1 * target + b2 * velocity
end

-- Close enough to rest to snap
function springUtils.settled(position: number, velocity: number, target: number): boolean
    return math.abs(target - position) <= REST_TOLERANCE and math.abs(velocity) <= REST_TOLERANCE
end

return springUtils
