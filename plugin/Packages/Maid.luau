local packages = script.Parent

local doCleaning = require(packages.DoCleaning)

local maid = {}

export type Class = {
    _tasks: { [any]: any },

    add: <T>(self: Class, job: T) -> T,
    set: <T>(self: Class, index: any, job: T) -> T,
    remove: (self: Class, index: any) -> (),

    get: (self: Class, index: any) -> any,
    doCleaning: (self: Class) -> (),
    destroy: (self: Class) -> (),

    [any]: any,
}

function maid.new(): Class
    local self: any = { _tasks = {} }
    return setmetatable(self, maid) :: any
end

function maid.__index(self: Class, index: any)
    if maid[index] then
        return maid[index]
    else
        return self._tasks[index]
    end
end

function maid.__newindex(self: Class, index: any, job: any?): ()
    if maid[index] then
        error(`[Maid]: cannot use index {index} as a valid job index`)
        return
    end

    self:set(index, job)
end

function maid.add<T>(self: Class, job: T): T
    local index: number = #self._tasks + 1
    self._tasks[index] = job
    return job
end

function maid.set<T>(self: Class, index: any, job: T): T
    local tasks: { [any]: any } = self._tasks
    local currentJob: any = tasks[index]

    if currentJob == job then
        return job
    end

    if currentJob then
        doCleaning(currentJob)
    end

    tasks[index] = job
    return job
end

--[[
    Forgets the job at `index` without cleaning it; the caller takes over its
    lifetime.
]]
function maid.remove(self: Class, index: any): ()
    self._tasks[index] = nil
end

function maid.destroy(self: Class): ()
    for index: any, job: any in self._tasks do
        if typeof(job) == "RBXScriptConnection" then
            self._tasks[index] = nil
            (job :: RBXScriptConnection):Disconnect()
        end
    end

    local index: any?, job: any = next(self._tasks)
    while job ~= nil do
        self._tasks[index] = nil
        doCleaning(job)

        index, job = next(self._tasks)
    end
end

maid.doCleaning = maid.destroy

return maid
