-- One-time import from the original mod's player modData (the keys are in Data/LegacyEHR).
--
-- Carries over permanent identity only: blood type, disease knowledge (flyers, profession, journal discoveries, the
-- Knox Herald), radio broadcasts heard, wild-plant knowledge, the immunity score and the Knox gene-therapy and
-- Patient Zero flags. Everything else is active state and is reset: illnesses, treatments, infections, blood loss,
-- cooldowns, and a few borderline keys (painkiller addiction, Knox usage counters, disease history, XP
-- bookkeeping).
--
-- Then every EHR_* key is removed, so the import can't run twice: the caller only imports into a brand-new state,
-- and afterwards there is nothing left to detect. A dead character's data (EHR_DeadCharacter) imports nothing.
--
-- modData is read with type checks throughout: the original often created partial tables.

local Legacy = require "ExtensiveHealthRedone/Data/LegacyEHR"
local BloodTypes = require "ExtensiveHealthRedone/Core/BloodTypes"

local Importer = {}

local function isOldKey(key)
    return type(key) == "string" and key:sub(1, #Legacy.KEY_PREFIX) == Legacy.KEY_PREFIX
end

-- Old keys present, sorted.
function Importer.oldKeys(modData)
    local keys = {}
    for key in pairs(modData) do
        if isOldKey(key) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

function Importer.isDeadCharacter(modData)
    return modData.EHR_DeadCharacter == true
end

-- True when the character carries the original's data and it belongs to a living character.
function Importer.hasOldData(modData)
    return #Importer.oldKeys(modData) > 0 and not Importer.isDeadCharacter(modData)
end

-- Removes every old key. Returns how many were removed.
function Importer.removeOldKeys(modData)
    local keys = Importer.oldKeys(modData)
    for _, key in ipairs(keys) do
        modData[key] = nil
    end
    return #keys
end

local function isTrue(value)
    return value == true or value == "true"
end

local function asTable(value)
    return type(value) == "table" and value or nil
end

-- The original's knowledge id normaliser. Returns a known id or nil.
function Importer.normalizeKnowledgeId(id)
    if type(id) ~= "string" then
        return nil
    end
    if Legacy.KNOWLEDGE_IDS[id] then
        return id
    end
    local compact = id:gsub("[%s_%-%(%)]", ""):lower()
    local mapped = Legacy.COMPACT_ALIASES[compact]
    if mapped and Legacy.KNOWLEDGE_IDS[mapped] then
        return mapped
    end
    return nil
end

local function importKnowledge(modData, knowledge, report)
    local herald = isTrue(modData.EHR_KnoxHeraldRead) or modData.EHR_KnoxKnowledgeSource == Legacy.KNOX_HERALD_SOURCE
    knowledge.knoxHerald = herald

    local function learn(rawId)
        local id = Importer.normalizeKnowledgeId(rawId)
        if not id then
            report.unknownKnowledge[#report.unknownKnowledge + 1] = tostring(rawId)
        elseif id == Legacy.KNOX_KNOWLEDGE_ID and not herald then
            -- The original only counted Knox knowledge together with the Herald.
            report.unknownKnowledge[#report.unknownKnowledge + 1] = tostring(rawId) .. " (no Herald)"
        else
            knowledge.diseases[id] = true
        end
    end

    local known = asTable(modData.EHR_KnownDiseases)
    if known then
        for id, value in pairs(known) do
            if isTrue(value) then
                learn(id)
            end
        end
    end
    -- Journal discoveries are written next to every unlock; the journal's history (diagnoses, statistics) is not
    -- knowledge and is dropped.
    local journal = asTable(modData.EHR_MedicalJournal)
    local discoveries = journal and asTable(journal.discoveries)
    if discoveries then
        for id, value in pairs(discoveries) do
            if value ~= nil and value ~= false then
                learn(id)
            end
        end
    end
    table.sort(report.unknownKnowledge)

    local profession = modData.EHR_ProfessionDiseaseKnowledge
    if type(profession) == "string" and Legacy.PROFESSION_GRANTS[profession] then
        knowledge.professionGrant = profession
    end

    knowledge.wildPlants = isTrue(modData.EHR_MedicalWildPlantsKnown)

    -- Broadcast slot keys ("<day>:<hour>:<effect>") stay valid: the import happens in the same world.
    local radio = asTable(modData.EHR_Radio)
    local heard = radio and asTable(radio.heardEffects)
    if heard then
        for key, value in pairs(heard) do
            if type(key) == "string" and isTrue(value) then
                knowledge.radioHeard[key] = true
            end
        end
    end
end

-- Imports into a fresh state (from Schema.new) and removes all old keys.
-- Returns a report: { imported = bool, removedKeys = n, bloodType = "kept" | "rolled",
--   unknownKnowledge = { ids }, summary = "one line for the log" }.
function Importer.run(modData, state)
    local report = { imported = false, removedKeys = 0, bloodType = "rolled", unknownKnowledge = {} }

    if Importer.isDeadCharacter(modData) then
        report.removedKeys = Importer.removeOldKeys(modData)
        report.summary = "dead character, nothing imported, " .. report.removedKeys .. " old keys removed"
        return report
    end

    local blood = asTable(modData.EHR_Blood)
    if blood and BloodTypes.isValid(blood.bloodType) then
        state.identity.bloodType = blood.bloodType
        report.bloodType = "kept"
    end

    importKnowledge(modData, state.knowledge, report)

    local immunity = asTable(modData.EHR_Immunity)
    local score = immunity and immunity.score
    if type(score) == "number" and score == score then
        state.immunity.score = math.max(0, math.min(100, score))
    end

    local knox = asTable(modData.EHR_KnoxCure)
    if knox then
        state.knox.geneTherapyImmune = isTrue(knox.geneTherapyImmune)
        state.knox.immunityTraitGranted = isTrue(knox.immunityTraitGranted)
        state.knox.patientZeroTraitSource = isTrue(knox.patientZeroTraitSource)
    end

    state.meta.createdAs = "imported"
    state.meta.importedFrom = Legacy.MOD_ID
    report.imported = true
    report.removedKeys = Importer.removeOldKeys(modData)

    local knownCount = 0
    for _ in pairs(state.knowledge.diseases) do
        knownCount = knownCount + 1
    end
    report.summary = "blood type " .. report.bloodType .. ", " .. knownCount .. " diseases known, immunity "
        .. tostring(state.immunity.score) .. ", " .. report.removedKeys .. " old keys removed"
    if #report.unknownKnowledge > 0 then
        report.summary = report.summary .. ", ignored knowledge: " .. table.concat(report.unknownKnowledge, " ")
    end
    return report
end

return Importer
