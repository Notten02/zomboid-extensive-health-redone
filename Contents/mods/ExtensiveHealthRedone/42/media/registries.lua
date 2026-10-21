EHRCharacterTraits = EHRCharacterTraits or {}
EHRCharacterProfessions = EHRCharacterProfessions or {}

EHRCharacterTraits.patientzero = CharacterTrait.register("ExtensiveHealth:patientzero")
EHRCharacterTraits.scalpelmaster = CharacterTrait.register("ExtensiveHealth:scalpelmaster")

EHRCharacterProfessions.ehrdoctor = CharacterProfession.register("ExtensiveHealth:ehrdoctor")
EHRCharacterProfessions.ehrsurgeon = CharacterProfession.register("ExtensiveHealth:ehrsurgeon")
