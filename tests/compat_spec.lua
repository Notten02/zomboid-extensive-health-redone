-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Compatibility checks that need no third-party mod: the original mod enabled beside ours is called out in the log,
-- and mod.info marks both spellings of the original's ids incompatible.
local LuaSource = require("LuaSource")

insulate("original mod beside the rewrite", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    require("ExtensiveHealthRedone/Server/Main")
    local Main = require("ExtensiveHealthRedone/Server/Main")

    it("says nothing without the original", function()
        assert.same({}, Main.checkOriginals())
    end)

    it("logs an error for the original and for its predecessor, with or without the backslash form", function()
        game.mods.ExtensiveHealthReworkEvolved = true
        game.mods.EHR = true
        assert.same({ "ExtensiveHealthReworkEvolved", "EHR" }, Main.checkOriginals())
        assert.is_true(game.logged("is enabled together with Extensive Health Redone"))
    end)
end)

describe("mod.info", function()
    local info = LuaSource.read("Contents/mods/ExtensiveHealthRedone/42/mod.info")

    it("marks the original and its predecessor incompatible in both id spellings", function()
        local list = info:match("\nincompatible=([^\n]*)")
        assert.truthy(list)
        local ids = {}
        for id in list:gmatch("[^,]+") do ids[id] = true end
        for _, id in ipairs({ "ExtensiveHealthReworkEvolved", "EHR" }) do
            assert.is_true(ids[id], id)
            assert.is_true(ids["\\" .. id], "\\" .. id)
        end
    end)

    it("names the poster and icon files that exist", function()
        for _, key in ipairs({ "poster", "icon" }) do
            local file = info:match("\n" .. key .. "=([^\n]*)")
            assert.truthy(file)
            assert.truthy(LuaSource.read("Contents/mods/ExtensiveHealthRedone/42/" .. file))
        end
    end)
end)
