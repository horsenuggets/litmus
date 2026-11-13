local quaternionUtils = {}

export type Quaternion = {number}

function quaternionUtils.fromQuaternion(q: Quaternion): CFrame
    local w: number, x: number, y: number, z: number = table.unpack(q)
    return CFrame.new(0, 0, 0, w, x, y, z)
end

function quaternionUtils.toQuaternion(cframe: CFrame): Quaternion
    local axis: Vector3, theta: number = cframe:ToAxisAngle()
    local halfTheta: number = theta * 0.5
    local pos: Vector3 = math.sin(halfTheta) * axis
    return { pos.X, pos.Y, pos.Z, math.cos(halfTheta) }
end

function quaternionUtils.closestQuaternion(current: Quaternion, target: Quaternion): Quaternion
    local cross: number = 0
    for i: number, c: number in current do
        cross += c * target[i]
    end

    local copy: Quaternion = table.clone(target)
    if cross <= 0 then
        for i: number, t: number in target do
            copy[i] = -t
        end
    end

    return copy
end

return quaternionUtils
