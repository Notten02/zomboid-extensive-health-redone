-- Item types by role. Homemade supplies work wherever the standard ones do.

local function set(list)
    local s = {}
    for _, v in ipairs(list) do
        s[v] = true
    end
    return s
end

local bags = {
    ["O-"] = "ExtensiveHealth.BloodBagONeg", ["O+"] = "ExtensiveHealth.BloodBagOPos",
    ["A-"] = "ExtensiveHealth.BloodBagANeg", ["A+"] = "ExtensiveHealth.BloodBagAPos",
    ["B-"] = "ExtensiveHealth.BloodBagBNeg", ["B+"] = "ExtensiveHealth.BloodBagBPos",
    ["AB-"] = "ExtensiveHealth.BloodBagABNeg", ["AB+"] = "ExtensiveHealth.BloodBagABPos",
}

local bagType = {}
for bloodType, fullType in pairs(bags) do
    bagType[fullType] = bloodType
end

local transfusable = {}
for fullType in pairs(bagType) do
    transfusable[fullType] = true
end
transfusable["ExtensiveHealth.SalineBag"] = true

return {
    bagFor = bags,                      -- blood type -> filled bag
    bloodTypeOf = bagType,              -- filled bag -> blood type
    saline = "ExtensiveHealth.SalineBag",
    transfusable = transfusable,        -- blood bags and saline
    ivKit = set({ "ExtensiveHealth.IVKit", "ExtensiveHealth.HomemadeIVKit" }),
    syringe = set({ "ExtensiveHealth.Syringe", "ExtensiveHealth.HomemadeSyringe" }),
    emptyBag = set({ "ExtensiveHealth.EmptyBloodBag", "ExtensiveHealth.HomemadeEmptyBloodBag" }),
    stitchItem = set({ "Base.Thread", "Base.SutureNeedle" }),
    antibiotics = set({ "Base.Antibiotics" }),
}
