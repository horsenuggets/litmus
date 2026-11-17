local roblox = require("../../Litmus/Adapter/Roblox")
local litmus = require("../../Litmus")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

local function folderIn(parent: Instance?, name: string): Folder
    local folder: Folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent

    return folder
end

local function moduleIn(parent: Instance?, name: string): ModuleScript
    local module: ModuleScript = Instance.new("ModuleScript")
    module.Name = name
    module.Parent = parent

    return module
end

group("findSpecs", function(): ()
    test("takes the modules whose names end in .spec", function(): ()
        local root: Folder = folderIn(nil, "Root")
        local spec: ModuleScript = moduleIn(root, "Thing.spec")

        moduleIn(root, "Thing")
        folderIn(root, "Folder.spec")

        expect.same(roblox.findSpecs({ root }), { spec })
    end)

    test("looks all the way down a root", function(): ()
        local root: Folder = folderIn(nil, "Root")
        local spec: ModuleScript = moduleIn(folderIn(folderIn(root, "Outer"), "Inner"), "Thing.spec")

        expect.same(roblox.findSpecs({ root }), { spec })
    end)

    test("takes a root that is itself a spec", function(): ()
        local spec: ModuleScript = moduleIn(nil, "Thing.spec")

        expect.same(roblox.findSpecs({ spec }), { spec })
    end)

    test("takes a spec once when two roots hold it", function(): ()
        local root: Folder = folderIn(nil, "Root")
        local spec: ModuleScript = moduleIn(root, "Thing.spec")

        expect.same(roblox.findSpecs({ root, spec, root }), { spec })
    end)

    test("lists specs in the order of their full names", function(): ()
        local root: Folder = folderIn(nil, "Root")
        local second: ModuleScript = moduleIn(root, "Second.spec")
        local first: ModuleScript = moduleIn(root, "First.spec")

        expect.same(roblox.findSpecs({ root }), { first, second })
    end)
end)

group("path", function(): ()
    test("lists the names leading to a module, without the DataModel", function(): ()
        expect.same(roblox.path(script), { "ReplicatedStorage", "Tests", "Roblox", "Finding.spec" })
    end)

    test("starts from the top of a tree outside the place", function(): ()
        local module: ModuleScript = moduleIn(folderIn(folderIn(nil, "Outer"), "Inner"), "Thing")

        expect.same(roblox.path(module), { "Outer", "Inner", "Thing" })
    end)

    test("keeps a name with dots in it whole", function(): ()
        local module: ModuleScript = moduleIn(folderIn(nil, "v1.2"), "Thing.spec")

        expect.same(roblox.path(module), { "v1.2", "Thing.spec" })
    end)
end)
