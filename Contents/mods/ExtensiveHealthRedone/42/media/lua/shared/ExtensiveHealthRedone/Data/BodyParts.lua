-- Body parts by vanilla BodyPartType name, in BodyPartType index order (0-16). The names are also our save format.

return {
    names = {
        "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper", "Torso_Lower",
        "Head", "Neck", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R",
    },
    -- Parts tetanus spasms and cellulitis without a known source act on.
    muscles = {
        "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper", "Torso_Lower",
        "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R",
    },
    feet = { Foot_L = true, Foot_R = true },
}
