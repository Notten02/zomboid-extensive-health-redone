---@diagnostic disable: undefined-global
-- E2E (dev only, issue #3): on a dedicated server, a doctor (admin) treats a remote patient (player2) from the EHR
-- exam window: right click on the diagram opens vanilla's treatment menu for the patient (Hand_L bandaged through it),
-- and a bandage dropped on a part treats it (Hand_R). The server checks the patient's own body parts.
-- Before the steps can pass, the patient must stand by the doctor: `pz-e2e.sh server-cmd 'teleport "player2" "admin"'`.
if not isServer() then return end
require "PZE2E/PZE2E"

local SYNC_ALL = 0xFFFFFFFFFFF

local function byName(players, name)
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getUsername() == name then return p end
    end
    return nil
end

local function part(player, name)
    return player:getBodyDamage():getBodyPart(BodyPartType.FromString(name))
end

local function wound(player, name)
    local bp = part(player, name)
    bp:setScratched(true, true)
    syncBodyPart(bp, SYNC_ALL)
end

local function give(player, fullType)
    local inv = player:getInventory()
    local item = inv:AddItem(fullType)
    sendAddItemToContainer(inv, item)
end

PZE2E.test("exam window treats a remote patient", {
    -- 1: both players online and standing together.
    function(ctx)
        local players = getOnlinePlayers()
        local doctor, patient = byName(players, "admin"), byName(players, "player2")
        if not doctor or not patient then return "wait" end
        if math.abs(doctor:getX() - patient:getX()) > 1 or math.abs(doctor:getY() - patient:getY()) > 1 then
            return "wait"
        end
        ctx.state.doctor, ctx.state.patient = doctor, patient
        PZE2E.check(true, "doctor %s and patient %s together at %d,%d", doctor:getUsername(), patient:getUsername(),
            math.floor(patient:getX()), math.floor(patient:getY()))
        wound(patient, "Hand_L")
        wound(patient, "Hand_R")
        give(doctor, "Base.Bandage")
        give(doctor, "Base.Bandage")
        PZE2E.check(part(patient, "Hand_L"):scratched() and not part(patient, "Hand_L"):bandaged(),
            "patient Hand_L scratched, not bandaged")
    end,
    -- 2: the patient's own client has the wound; the doctor asks to examine.
    function(ctx)
        if not ctx.state.doctor then return end
        PZE2E.ask(ctx.state.patient, "ownHand", {}, "own")
        PZE2E.ask(ctx.state.doctor, "openExam", { patient = ctx.state.patient:getOnlineID() }, "open")
    end,
    -- 3: the patient says yes.
    function(ctx)
        if not ctx.state.doctor then return end
        if not ctx.answers.open then return "wait" end
        PZE2E.check(ctx.answers.open.asked == true, "doctor asked: %s", PZE2E.describe(ctx.answers.open))
        PZE2E.check(ctx.answers.own ~= nil and ctx.answers.own.scratched == true,
            "patient's own client sees Hand_L scratched: %s", PZE2E.describe(ctx.answers.own))
        PZE2E.ask(ctx.state.patient, "consentYes", { from = ctx.state.doctor:getOnlineID() }, "yes")
    end,
    -- 4: the doctor's exam window is open and sees the patient's wound through the remote body damage.
    function(ctx)
        if not ctx.state.doctor then return end
        if not ctx.answers.yes then return "wait" end
        PZE2E.ask(ctx.state.doctor, "examState", { patient = ctx.state.patient:getOnlineID() }, "state")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        local s = ctx.answers.state
        if not s then return "wait" end
        if not s.window or not s.injured then
            ctx.answers.state = nil
            ctx.state.stateTries = (ctx.state.stateTries or 0) + 1
            if ctx.state.stateTries < 6 then
                PZE2E.ask(ctx.state.doctor, "examState", { patient = ctx.state.patient:getOnlineID() }, "state")
                return "wait"
            end
        end
        PZE2E.check(s.window == true, "doctor's exam window is open")
        PZE2E.check(s.remote == true, "patient is remote on the doctor's client")
        PZE2E.check(s.injured == true, "doctor's client sees the patient's Hand_L injury (%s)", PZE2E.describe(s))
        -- 5: right click on Hand_L in the exam diagram, choose Bandage.
        PZE2E.ask(ctx.state.doctor, "treatMenu", { part = "Hand_L" }, "menu")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        local m = ctx.answers.menu
        if not m then return "wait" end
        PZE2E.check(m.menu == true, "right click opened a treatment menu: %s", PZE2E.describe(m))
        PZE2E.check(m.chose ~= nil, "chose a bandage from the menu (%s)", tostring(m.chose))
    end,
    -- 6: the bandage reaches the patient on the server.
    function(ctx)
        if not ctx.state.doctor then return end
        if not part(ctx.state.patient, "Hand_L"):bandaged() then return "wait" end
        PZE2E.check(true, "patient Hand_L bandaged on the server (right click path)")
        -- 7: drop the other bandage on Hand_R.
        PZE2E.ask(ctx.state.doctor, "treatDrop", { part = "Hand_R" }, "drop")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        local d = ctx.answers.drop
        if not d then return "wait" end
        PZE2E.check(d.dropped == true, "doctor dropped a bandage on Hand_R: %s", PZE2E.describe(d))
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        if not part(ctx.state.patient, "Hand_R"):bandaged() then return "wait" end
        PZE2E.check(true, "patient Hand_R bandaged on the server (drag and drop path)")
        PZE2E.ask(ctx.state.doctor, "closeExam", { patient = ctx.state.patient:getOnlineID() }, "close")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        local c = ctx.answers.close
        if not c then return "wait" end
        PZE2E.check(c.closed == true, "exam window closed cleanly: %s", PZE2E.describe(c))
    end,
}, { startAfter = 2, every = 2, maxWaits = 30 })
