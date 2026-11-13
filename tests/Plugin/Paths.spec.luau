local litmus = require("../../Litmus")
local outcome = require("../../Plugin/Outcome")
local paths = require("../../Plugin/Interface/Paths")

local expect = litmus.expect
local group = litmus.group
local test = litmus.test

group("shown", function(): ()
    test("joins the names with dots", function(): ()
        expect.equal(paths.shown({ "Place", "Tests", "Thing.spec" }), "Place.Tests.Thing.spec")
    end)

    test("shows nothing for no names", function(): ()
        expect.equal(paths.shown({}), "")
    end)
end)

group("name", function(): ()
    test("gives the last name", function(): ()
        expect.equal(paths.name({ "Place", "Tests", "Thing.spec" }), "Thing.spec")
    end)
end)

group("parent", function(): ()
    test("gives every name but the last", function(): ()
        expect.same(paths.parent({ "Place", "Tests", "Thing.spec" }), { "Place", "Tests" })
    end)

    test("leaves the path it was given alone", function(): ()
        local path: outcome.Path = { "Place", "Thing.spec" }
        paths.parent(path)

        expect.same(path, { "Place", "Thing.spec" })
    end)
end)

group("sharedParent", function(): ()
    test("gives the start every spec's holder shares", function(): ()
        local shared: outcome.Path = paths.sharedParent({
            { "Place", "Tests", "Interface", "Expect.spec" },
            { "Place", "Tests", "Loader", "Requires.spec" },
        })

        expect.same(shared, { "Place", "Tests" })
    end)

    test("gives a lone spec's holder whole", function(): ()
        expect.same(paths.sharedParent({ { "Place", "Tests", "Thing.spec" } }), { "Place", "Tests" })
    end)

    test("stops at a holder one of the specs sits right inside", function(): ()
        local shared: outcome.Path = paths.sharedParent({
            { "Place", "Tests", "Deep", "First.spec" },
            { "Place", "Tests", "Second.spec" },
        })

        expect.same(shared, { "Place", "Tests" })
    end)

    test("takes a name with dots in it as one name", function(): ()
        local shared: outcome.Path = paths.sharedParent({
            { "Place", "v1.2", "First.spec" },
            { "Place", "v1.3", "Second.spec" },
        })

        expect.same(shared, { "Place" })
    end)

    test("gives nothing when the specs share nothing", function(): ()
        expect.same(paths.sharedParent({ { "Here", "First.spec" }, { "There", "Second.spec" } }), {})
    end)

    test("gives nothing for no specs", function(): ()
        expect.same(paths.sharedParent({}), {})
    end)
end)

group("relativeTo", function(): ()
    test("leaves out the names of the root", function(): ()
        expect.same(paths.relativeTo({ "Place", "Tests", "Interface" }, { "Place", "Tests" }), { "Interface" })
    end)

    test("gives nothing for the root itself", function(): ()
        expect.same(paths.relativeTo({ "Place", "Tests" }, { "Place", "Tests" }), {})
    end)

    test("gives the whole path from no root", function(): ()
        expect.same(paths.relativeTo({ "Place", "Tests" }, {}), { "Place", "Tests" })
    end)
end)
