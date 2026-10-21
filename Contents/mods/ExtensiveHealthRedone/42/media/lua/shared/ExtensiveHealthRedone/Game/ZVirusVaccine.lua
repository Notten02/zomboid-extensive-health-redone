-- Whether the Zombie Virus Vaccine mod (B42 port by rEXX, Workshop 3615135168) is enabled in this game. Never errors.
-- Server/ZVirusVaccine does the work; docs/porting/phase10/zombie-virus-vaccine.md has the audit and the decisions.

local ZVirusVaccine = {}

ZVirusVaccine.MOD_ID = "ZVirusVaccine42BETA"

local cached      -- nil until asked, then true or false for the session

-- A save has its own mod list, so this is asked at play time, once.
function ZVirusVaccine.active()
    if cached == nil then
        local mods = getActivatedMods()
        cached = mods:contains(ZVirusVaccine.MOD_ID) or mods:contains("\\" .. ZVirusVaccine.MOD_ID)
    end
    return cached
end

-- Forgets what was learned about the mod list (tests, and a new game in the same session).
function ZVirusVaccine.reset()
    cached = nil
end

return ZVirusVaccine
