-- The bridge from our shared timed actions to the authority.
--
-- B42 runs a timed action on both sides: the client animates it and calls perform(); the authority (single player, or
-- the dedicated server, which rebuilds the action from its constructor arguments) calls complete() when the time is
-- up. So complete() is where the effect happens, and a client can't skip the duration or fake the result. Our
-- actions' complete() calls Authority.run, which hands the intent to the server runtime (Server/Runtime.runAction):
-- the same command registry checks as a network command (item ownership, proximity, consent), minus the rate limit,
-- and only for commands registered with `action = true`, which a client can't send itself.
--
--   function EHRMedicationAction:complete()
--       return Authority.run(self.character, "medication.take", { item = self.item:getID() })
--   end
--
-- On an MP client complete() is not the authority's: run() does nothing there and returns false.

local Authority = {}

local runner = nil

-- Server/Runtime installs the runner when it loads (single player and the dedicated server).
function Authority.setRunner(fn)
    runner = fn
end

-- Runs command for character on the authority. Returns true when the command was accepted.
function Authority.run(character, command, args)
    if isClient() or not runner then
        return false
    end
    return runner(character, command, args or {}) == true
end

return Authority
