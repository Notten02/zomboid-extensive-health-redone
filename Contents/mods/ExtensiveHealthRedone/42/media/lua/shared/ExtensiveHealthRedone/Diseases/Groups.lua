-- The Phase 4 disease groups, in a fixed order. Each returns { conditions = { [id] = def }, systems = { ... } }.

return {
    require "ExtensiveHealthRedone/Diseases/Shared/Group",
    require "ExtensiveHealthRedone/Diseases/Food/Group",
    require "ExtensiveHealthRedone/Diseases/Weather/Group",
    require "ExtensiveHealthRedone/Diseases/Corpse/Group",
    require "ExtensiveHealthRedone/Diseases/Scabies/Group",
    require "ExtensiveHealthRedone/Diseases/Concussion/Group",
    require "ExtensiveHealthRedone/Diseases/Mind/Group",
    require "ExtensiveHealthRedone/Diseases/Knox/Group",
}
