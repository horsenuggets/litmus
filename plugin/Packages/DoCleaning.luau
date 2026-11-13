--[[
    Cleans up a job of any supported shape:
      - function: called
      - thread: cancelled (deferred if it is the running thread)
      - RBXScriptConnection: disconnected
      - Instance: destroyed
      - table with a `destroy` or `Destroy` method: that method is called
      - array of jobs: each entry is cleaned last to first, then the array is cleared
      - empty table: nothing to clean
    Any other table errors; non-table values of other types are ignored.
]]

type Callback = () -> ()

local function callback(job: Callback)
    job()
end

local function destroy(job: any)
    job:destroy()
end

local function destroyPascal(job: any)
    job:Destroy()
end

local function doCleaning(job: unknown): ()

    -- case 1: function
    if typeof(job) == "function" then
        local object = job :: any
        callback(object)

    -- case 2: thread
    elseif typeof(job) == "thread" then

        -- cancel if its not active
        local cancelled: boolean = false
        if (coroutine.running() ~= job) then
            cancelled = pcall(task.cancel, job);
        end

        -- cancel next cycle
        if not cancelled then
            task.defer(function(): ()
                task.cancel(job);
            end);
        end

    -- case 3: Connection
    elseif typeof(job) == "RBXScriptConnection" then
        job:Disconnect();

    -- case 4: Instance
    elseif typeof(job) == "Instance" then
        job:Destroy()

    -- case 5: luau object
    elseif typeof(job) == "table" then

        local object = job :: any

        -- case 6: luau object with a destroy method
        if typeof(object.destroy) == "function" then
            destroy(object)
        elseif typeof(object.Destroy) == "function" then
            destroyPascal(object)

        -- case 7: empty scope or task list
        elseif next(object) == nil then
            return

        -- case 8: array of subtasks, in reverse so nothing outlives what it was created from
        elseif object[1] ~= nil then
            for index = #object, 1, -1 do

                -- One failed job mustn't strand the rest
                local ok: boolean, err: any = (xpcall :: any)(doCleaning, debug.traceback, object[index])
                if not ok then
                    warn(`[DoCleaning]: {err}`)
                end
            end

            table.clear(object);

        else
            error(`[DoCleaning]: cannot clean a table with no destroy method or array part`)
        end
    end
end

return doCleaning
