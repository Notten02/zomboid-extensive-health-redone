-- Our permission names, mapped to B42 role capabilities.
--
-- B42 replaced fixed access levels with configurable roles, so we never compare role names ("admin", "observer").
-- We ask for the capability vanilla itself uses for the same kind of power. A role gets our admin tools exactly
-- when it gets vanilla's medical cheats, so an observer role without them is refused.
-- In single player the local player owns the game and has every permission.

local Permissions = {}

Permissions.CAPABILITIES = {
    -- Debug menu, /ehrfullheal and other health-changing admin tools. Vanilla gates its medical cheats on this.
    medicalAdmin = "CanMedicalCheat",
}

function Permissions.has(player, name)
    local capabilityName = Permissions.CAPABILITIES[name]
    if not capabilityName then
        error("unknown permission " .. tostring(name), 2)
    end
    if not isClient() and not isServer() then
        return true
    end
    local role = player:getRole()
    local capability = Capability[capabilityName]
    return role ~= nil and capability ~= nil and role:hasCapability(capability)
end

return Permissions
