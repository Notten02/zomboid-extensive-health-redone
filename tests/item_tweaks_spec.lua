-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local ItemTweaks = require("ExtensiveHealthRedone/Core/ItemTweaks")

-- A stand-in for script items: records DoParam calls.
local function fakeScripts(names)
    local items, calls = {}, {}
    for _, name in ipairs(names) do
        items[name] = {
            DoParam = function(_, property, value)
                calls[#calls + 1] = name .. " " .. property .. "=" .. value
            end,
        }
    end
    return function(fullType)
        return items[fullType]
    end, calls
end

local function tweak(item, property, value)
    return { item = item, property = property, value = value, reason = "test" }
end

describe("ItemTweaks.validate", function()
    it("accepts a well-formed list", function()
        assert.same({}, ItemTweaks.validate({ tweak("Base.Pills", "UseDelta", "0.0625") }))
    end)

    it("rejects malformed entries", function()
        local problems = ItemTweaks.validate({
            tweak("Pills", "UseDelta", "0.0625"),
            tweak("Base.Pills", "Use Delta", "0.0625"),
            tweak("Base.Pills", "Weight", 0.2),
            { item = "Base.Pills", property = "Icon", value = "X" },
        })
        assert.equal(4, #problems)
        assert.truthy(problems[1]:find("full type", 1, true))
        assert.truthy(problems[2]:find("property", 1, true))
        assert.truthy(problems[3]:find("string", 1, true))
        assert.truthy(problems[4]:find("reason", 1, true))
    end)

    it("allows only one entry per item property", function()
        local problems = ItemTweaks.validate({
            tweak("Base.Pills", "UseDelta", "0.0625"),
            tweak("Base.Pills", "UseDelta", "0.05"),
        })
        assert.equal(1, #problems)
        assert.truthy(problems[1]:find("duplicates tweak #1", 1, true))
    end)
end)

describe("ItemTweaks.apply", function()
    it("calls DoParam on each item that exists and reports the missing ones", function()
        local getItem, calls = fakeScripts({ "Base.Pills" })
        local result = ItemTweaks.apply({
            tweak("Base.Pills", "UseDelta", "0.0625"),
            tweak("Base.Pills", "Icon", "Painkillers"),
            tweak("OtherMod.Gone", "Weight", "1"),
        }, getItem)
        assert.same({ "Base.Pills UseDelta=0.0625", "Base.Pills Icon=Painkillers" }, calls)
        assert.equal(2, #result.applied)
        assert.equal(1, #result.missing)
        assert.equal("OtherMod.Gone", result.missing[1].item)
    end)

    it("changes nothing when the list is invalid", function()
        local getItem, calls = fakeScripts({ "Base.Pills" })
        assert.has_error(function()
            ItemTweaks.apply({ tweak("Base.Pills", "UseDelta", "0.1"), tweak("Base.Pills", "UseDelta", "0.2") }, getItem)
        end)
        assert.same({}, calls)
    end)
end)

describe("Data/ItemTweaks", function()
    it("is a valid tweak list", function()
        assert.same({}, ItemTweaks.validate(require("ExtensiveHealthRedone/Data/ItemTweaks")))
    end)
end)
