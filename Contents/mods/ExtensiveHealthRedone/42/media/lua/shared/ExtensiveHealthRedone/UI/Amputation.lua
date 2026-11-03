-- The EHR Monitor's rows for The Only Cure's amputations: one per arm with a stump, from state.onlyCure
-- (Wounds/Amputation; the exam copies it). An amputation is plain to see, so the rows need no knowledge. Without the
-- mod the section stays empty and there are no rows.

local Text = require "ExtensiveHealthRedone/UI/Text"
local Monitor = require "ExtensiveHealthRedone/UI/Monitor"
local Amputation = require "ExtensiveHealthRedone/Wounds/Amputation"

local Rows = {}

Rows.ICON = "EHR_Disease_Wound_Infection"

Rows.NAMES = {
    Hand_L = "UI_EHR_Amputation_Hand_L", ForeArm_L = "UI_EHR_Amputation_ForeArm_L",
    UpperArm_L = "UI_EHR_Amputation_UpperArm_L", Hand_R = "UI_EHR_Amputation_Hand_R",
    ForeArm_R = "UI_EHR_Amputation_ForeArm_R", UpperArm_R = "UI_EHR_Amputation_UpperArm_R",
}

-- Dirtiness from which an open stump shows orange.
Rows.DIRTY = 0.5

local function row(limb, st, prosthesis)
    local r = { id = "amputation_" .. limb, known = true, icon = Rows.ICON, name = Text.key(Rows.NAMES[limb]) }
    if st.cauterized then
        r.description = Text.key("UI_EHR_Amputation_SealedDesc")
        r.status, r.statusColor = Text.key("UI_EHR_Amputation_Cauterized"), "green"
    elseif st.healed then
        r.description = Text.key("UI_EHR_Amputation_SealedDesc")
        r.status, r.statusColor = Text.key("UI_EHR_Amputation_Healed"), "green"
    else
        local dirt = st.shown or 0
        r.description = Text.key("UI_EHR_Amputation_OpenDesc")
        r.progress = dirt
        r.progressText = Text.key("UI_EHR_Amputation_Dirt", Text.percent(dirt * 100))
        r.status = Text.key("UI_EHR_Amputation_Open")
        r.statusColor = dirt >= Rows.DIRTY and "orange" or "yellow"
    end
    if prosthesis then
        r.detail, r.detailColor = Text.key("UI_EHR_Amputation_Prosthesis"), "green"
    end
    return r
end

function Rows.build(input)
    local s = input.state and input.state[Amputation.SECTION]
    local out = {}
    if not (s and s.stumps) then
        return out
    end
    for _, limb in ipairs(Amputation.LIMBS) do
        local st = s.stumps[limb]
        if st then
            out[#out + 1] = row(limb, st, s.prosthesis and s.prosthesis[limb:sub(-1)])
        end
    end
    return out
end

Monitor.addRowProvider("amputation", Rows.build, 50)

return Rows
