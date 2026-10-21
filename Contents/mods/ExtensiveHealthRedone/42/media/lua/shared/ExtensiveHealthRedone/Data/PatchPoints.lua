-- Every vanilla Lua method we wrap, by point name. Core/PatchPoints wraps each exactly once; features attach
-- listeners to the name (see Game/Patches.lua). Adding a line here is the only way to patch vanilla Lua.
-- side: "shared" (default), "client" (UI code; skipped on a dedicated server) or "server" (authority; skipped on MP
-- clients). B42 timed actions run complete() on the authority, so effects hook complete().
--
-- Outcome-changing intercepts are used for five things only: the stitch minigame, lockjaw refusing food, insomnia
-- refusing sleep, the PrimaryHealthPanel option opening the EHR Monitor where vanilla opens its Health tab, and the
-- admin chat commands (/ehrfullheal, /ehrreset, /ehrinspect) kept from vanilla's server command path.

return {
    -- Wound model (Server/Health): a disinfected wound, an alcoholic bandage, a finished stitch.
    { name = "disinfectComplete", path = "ISDisinfect.complete", side = "server" },
    { name = "bandageComplete", path = "ISApplyBandage.complete", side = "server" },
    { name = "stitchComplete", path = "ISStitch.complete", side = "server" },
    -- Stitch minigame (Client/StitchMinigame): intercepts the vanilla stitch action to run the minigame first.
    { name = "stitchNew", path = "ISStitch.new", side = "client" },
    -- Eating: vanilla antibiotics on infected wounds (Server/Health); tetanus lockjaw refuses food (both sides).
    { name = "eatComplete", path = "ISEatFoodAction.complete", side = "server" },
    { name = "eatValid", path = "ISEatFoodAction.isValid", side = "client" },
    -- Food-borne diseases (Server/Food): eatComplete above, the partial bite of a cancelled meal, drinking from a
    -- container (taint read when the action is made) and from a world source.
    { name = "eatServerStop", path = "ISEatFoodAction.serverStop", side = "server" },
    { name = "drinkFluidNew", path = "ISDrinkFluidAction.new", side = "server" },
    { name = "drinkFluidComplete", path = "ISDrinkFluidAction.complete", side = "server" },
    { name = "takeWaterComplete", path = "ISTakeWaterAction.complete", side = "server" },
    -- Pills: vanilla pills are medication (Server/Medication; painkillers also count toward addiction).
    { name = "takePillComplete", path = "ISTakePillAction.complete", side = "server" },
    -- Sleep: every vanilla way to fall asleep ends here; insomnia (and later stimulants) refuse it (Client/Sleep).
    { name = "sleepWalkToComplete", path = "ISWorldObjectContextMenu.onSleepWalkToComplete", side = "client" },
    -- Reading: the Kentucky Herald, July 16 1993 unlocks Knox knowledge (Server/Knox); disease flyers and the Wild
    -- Plants guide unlock their knowledge (Server/Flyers).
    { name = "readBookComplete", path = "ISReadABook.complete", side = "server" },
    -- Character creation: PatientZeroTraitDisabled hides the Patient Zero trait (Client/PatientZero).
    { name = "traitListPopulated", path = "CharacterCreationProfession.populateTraitList", side = "client" },
    -- A custom sandbox is saved after the profession screen is built; the trait lists are rebuilt then so Patient Zero
    -- disappears at once (Client/PatientZero).
    { name = "sandboxVarsSet", path = "SandboxOptionsScreen.setSandboxVars", side = "client" },
    -- The character window (Client/CharacterWindow): our EHR Monitor and Immune System tabs are added after vanilla's
    -- views; with PrimaryHealthPanel on, a toggle of vanilla's Health view (the H key, the heart button) toggles the
    -- EHR Monitor instead.
    { name = "characterInfoCreate", path = "ISCharacterInfoWindow.createChildren", side = "client" },
    { name = "characterInfoToggle", path = "ISCharacterInfoWindow.toggleView", side = "client" },
    -- Item tooltips (Client/ItemTooltip): for EHR items, vanilla renders a stand-in whose DoTooltip draws vanilla's
    -- tooltip and then our lines (set before, restored after).
    { name = "tooltipInvRender", path = "ISToolTipInv.render", side = "client" },
    -- Admin chat commands (Client/AdminChat): a typed /ehrfullheal, /ehrreset or /ehrinspect becomes our command
    -- instead of going to the server as an unknown chat command. Wrapped at OnGameBoot, before the MP chat window
    -- copies the function into its text box at OnGameStart.
    { name = "chatCommandEntered", path = "ISChat.onCommandEntered", side = "client" },
}
