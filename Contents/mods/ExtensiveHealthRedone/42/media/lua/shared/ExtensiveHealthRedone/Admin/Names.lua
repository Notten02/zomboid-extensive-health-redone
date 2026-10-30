-- Finding the player an admin names in a chat command (/ehrfullheal Name). Pure: Server/Admin passes one candidate
-- per online player.
--
--   Names.match("bob", { { username = "Bob42", display = "Bob42", fullName = "Bob Smith" }, ... })
--     -> { status = "one", candidate = c } | { status = "many", usernames = { up to 5, sorted }, count = n }
--      | { status = "none" }
--
-- Tiers, the first that finds anyone decides: the exact username, then the exact display name or character name
-- ("Forename Surname"), then a part of the username. Case is ignored, surrounding spaces and one pair of double quotes
-- are stripped. Players are counted (not names), several exact name matches are reported as ambiguous instead of the
-- first one winning, and a full character name can match.

local Names = {}

Names.MAX_LISTED = 5

function Names.normalize(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local quoted = text:match('^"(.*)"$')
    if quoted then
        text = quoted:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return text:lower()
end

local function result(found)
    if #found == 1 then
        return { status = "one", candidate = found[1] }
    end
    local usernames = {}
    for _, c in ipairs(found) do
        usernames[#usernames + 1] = tostring(c.username)
    end
    table.sort(usernames)
    local listed = {}
    for i = 1, math.min(Names.MAX_LISTED, #usernames) do
        listed[i] = usernames[i]
    end
    return { status = "many", usernames = listed, count = #usernames }
end

local function exactName(c, wanted)
    return Names.normalize(c.display) == wanted or Names.normalize(c.fullName) == wanted
end

local function partOfUsername(c, wanted)
    return Names.normalize(c.username):find(wanted, 1, true) ~= nil
end

local TIERS = {
    function(c, wanted) return Names.normalize(c.username) == wanted end,
    exactName,
    partOfUsername,
}

function Names.match(wanted, candidates)
    wanted = Names.normalize(wanted)
    if wanted == "" then
        return { status = "none" }
    end
    for _, test in ipairs(TIERS) do
        local found = {}
        for _, c in ipairs(candidates) do
            if test(c, wanted) then
                found[#found + 1] = c
            end
        end
        if #found > 0 then
            return result(found)
        end
    end
    return { status = "none" }
end

return Names
