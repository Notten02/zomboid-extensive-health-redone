-- Timings of the staged conditions Phase 3 brings (cellulitis, sepsis, tetanus, AHTR). Their effects live in
-- Conditions/<Name>.lua. Phase 4 adds the other diseases to this table.
--
-- Stage 1 lasts the incubation. The duration is then split 40/30/30 % over stages 2, 3 and 4 (v0.9's generic
-- schedule). Hours are divided by the speed option. Severity = baseSeverity +- 0.15.
-- Sources: docs/original-author-guides/disease-overview.md (timings, W11 decided: follow the guide) and
-- docs/porting/phase3/*.md (effects). knowledge: the flyer that names it (Conditions/Knowledge).

return {
    cellulitis = {
        enabledOption = "CellulitisEnabled", speedOption = "DiseaseSpeed",
        incubation = { 12, 36 }, duration = { 72, 144 }, baseSeverity = 0.6,
        -- Ambient lines while it lasts (W35, Phase 10); the stage-entry lines are spoken by the behaviour module.
        lines = {
            random = {
                [2] = { "UI_EHR_Ambient_Cellulitis_2_1", "UI_EHR_Ambient_Cellulitis_2_2", "UI_EHR_Ambient_Cellulitis_2_3" },
                [3] = { "UI_EHR_Ambient_Cellulitis_3_1", "UI_EHR_Ambient_Cellulitis_3_2", "UI_EHR_Ambient_Cellulitis_3_3" },
                [4] = { "UI_EHR_Ambient_Cellulitis_4_1", "UI_EHR_Ambient_Cellulitis_4_2", "UI_EHR_Ambient_Cellulitis_4_3" },
            },
            every = 240,
        },
        name = "UI_EHR_Disease_cellulitis",
        knowledge = "cellulitis",
    },
    sepsis = {
        enabledOption = "SepsisEnabled", speedOption = "SepsisSpeed",
        incubation = { 6, 24 }, duration = { 48, 96 }, baseSeverity = 1.0,
        -- Untreated sepsis never ends on its own: stage 4 stays deadly. Treated, the course cures it (Phase 5).
        persistsAt = 4,
        effectsInStage1 = true,     -- guide: stage 1 is "feverish and weak"
        blockAfterCureHours = 2,
        -- Ambient lines while it lasts (W35, Phase 10); the stage-entry lines are spoken by the behaviour module.
        lines = {
            random = {
                [1] = { "UI_EHR_Ambient_Sepsis_1_1", "UI_EHR_Ambient_Sepsis_1_2", "UI_EHR_Ambient_Sepsis_1_3" },
                [2] = { "UI_EHR_Ambient_Sepsis_2_1", "UI_EHR_Ambient_Sepsis_2_2", "UI_EHR_Ambient_Sepsis_2_3" },
                [3] = { "UI_EHR_Ambient_Sepsis_3_1", "UI_EHR_Ambient_Sepsis_3_2", "UI_EHR_Ambient_Sepsis_3_3" },
                [4] = { "UI_EHR_Ambient_Sepsis_4_1", "UI_EHR_Ambient_Sepsis_4_2", "UI_EHR_Ambient_Sepsis_4_3" },
            },
            every = 120,
        },
        name = "UI_EHR_Disease_sepsis",
        knowledge = "sepsis",
    },
    tetanus = {
        enabledOption = "TetanusEnabled", speedOption = "DiseaseSpeed",
        incubation = { 72, 168 }, duration = { 168, 336 }, baseSeverity = 0.95,
        -- Ambient lines while it lasts (W35, Phase 10); the stage-entry lines are spoken by the behaviour module.
        lines = {
            random = {
                [2] = { "UI_EHR_Ambient_Tetanus_2_1", "UI_EHR_Ambient_Tetanus_2_2", "UI_EHR_Ambient_Tetanus_2_3" },
                [3] = { "UI_EHR_Ambient_Tetanus_3_1", "UI_EHR_Ambient_Tetanus_3_2", "UI_EHR_Ambient_Tetanus_3_3" },
                [4] = { "UI_EHR_Ambient_Tetanus_4_1", "UI_EHR_Ambient_Tetanus_4_2", "UI_EHR_Ambient_Tetanus_4_3" },
            },
            every = 180,
        },
        name = "UI_EHR_Disease_tetanus",
        knowledge = "tetanus",
    },
    ahtr = {
        enabledOption = "AHTREnabled", speedOption = "DiseaseSpeed",
        incubation = { 1, 6 }, duration = { 48, 96 }, baseSeverity = 0.95,
        effectsInStage1 = true,
        -- Ambient lines while it lasts (W35, Phase 10); the stage-entry lines are spoken by the behaviour module.
        lines = {
            random = {
                [1] = { "UI_EHR_Ambient_AHTR_1_1", "UI_EHR_Ambient_AHTR_1_2", "UI_EHR_Ambient_AHTR_1_3" },
                [2] = { "UI_EHR_Ambient_AHTR_2_1", "UI_EHR_Ambient_AHTR_2_2", "UI_EHR_Ambient_AHTR_2_3" },
                [3] = { "UI_EHR_Ambient_AHTR_3_1", "UI_EHR_Ambient_AHTR_3_2", "UI_EHR_Ambient_AHTR_3_3" },
                [4] = { "UI_EHR_Ambient_AHTR_4_1", "UI_EHR_Ambient_AHTR_4_2", "UI_EHR_Ambient_AHTR_4_3" },
            },
            every = 120,
        },
        name = "UI_EHR_Disease_AHTR",
        knowledge = "ahtr",
    },
}
