local outcome = require("../Outcome")

-- A test or a group among the tests, in the order the spec registered them; one holds exactly one of the two
export type Entry = {
    test: outcome.TestResult?,
    group: Group?,
}

export type Group = {
    name: string,
    entries: { Entry },
    byName: { [string]: Group },

    total: number,
    failed: number,
}

local function newGroup(name: string): Group
    return { name = name, entries = {}, byName = {}, total = 0, failed = 0 }
end

-- Each test names the groups it sits in from the outside in, which is enough to rebuild their nesting
local function testTree(tests: { outcome.TestResult }): Group
    local root: Group = newGroup("")

    for _, test in tests do
        local current: Group = root

        for _, name in test.groups do
            local existing: Group? = current.byName[name]
            local group: Group = existing or newGroup(name)

            if not existing then
                current.byName[name] = group
                table.insert(current.entries, { group = group })
            end

            group.total += 1
            if test.failure then
                group.failed += 1
            end

            current = group
        end

        table.insert(current.entries, { test = test })
    end

    return root
end

return testTree
