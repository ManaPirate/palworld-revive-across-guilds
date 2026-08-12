-- ReviveAcrossGuilds
-- Server-side RE-UE4SS Lua mod for Palworld dedicated servers.
--
-- Palworld normally only lets a guildmate revive a downed player. This mod
-- tries to lift that restriction so any player nearby can revive any other
-- downed player, regardless of guild membership.
--
-- It also addresses a related problem this restriction creates: Palworld
-- skips the downed/revive-countdown state entirely and kills a player
-- outright when it decides no guildmate is available to revive them (e.g.
-- they're alone in their guild, or their only guildmate is offline). With
-- strangers now able to revive anyone, that shortcut is no longer correct --
-- someone nearby might well be able to revive them if only they were given
-- the countdown. See the DOWNED_STATE_HOOKS section below.
--
-- HOW THIS WORKS
-- None of the UFunctions involved here are confirmed against a live
-- server/UE4SS Live View -- Palworld's guild-membership and
-- alone-in-guild checks aren't plain properties, and there's no
-- PalWorldSettings.ini toggle for either behavior. So this takes a
-- best-effort approach:
--
--   1. It registers hooks on short lists of plausible candidate function
--      names (see CANDIDATE_HOOKS and DOWNED_STATE_HOOKS below) and forces
--      their boolean result to the value that produces the wanted
--      behavior. Every candidate name is scoped to revive/downed-state
--      specifically -- none of them touch a shared/generic guild-membership
--      utility, so a wrong guess is a silent no-op, never a side effect on
--      unrelated systems (base building, storage, PvP, etc.).
--   2. It also hooks the confirmed ReviveCharacter_ToServer RPC purely for
--      logging, so UE4SS.log shows whether a revive actually completed.
--
-- If cross-guild revives or solo-guild downed state still don't work after
-- installing this, see ../../docs/TUNING.md for how to find the correct
-- function names with UE4SS's Live View and add them below.

local MOD_TAG = "[ReviveAcrossGuilds]"

local function log(message)
    print(string.format("%s %s\n", MOD_TAG, message))
end

-- Candidate UFunctions that might gate "can PlayerA revive PlayerB". Forced
-- to true whenever they fire with a false/blocked result.
local CANDIDATE_HOOKS = {
    "/Script/Pal.PalPlayerCharacter:CanRevive",
    "/Script/Pal.PalPlayerCharacter:CanReviveOtherPlayer",
    "/Script/Pal.PalPlayerCharacter:CanReviveTarget",
    "/Script/Pal.PalPlayerCharacter:IsReviveTarget",
    "/Script/Pal.PalPlayerCharacter:IsAbleToRevive",
    "/Script/Pal.PalPlayerCharacter:CheckCanRevive",
}

-- Candidate UFunctions that might gate "should this player enter the downed
-- (reviveable) state at all, or die outright". Each entry lists the target
-- value the mod forces it to whenever it fires with the opposite result --
-- "positive" names (can/should/has) are forced true, "negative" names
-- (alone/no reviver) are forced false, so that in every case the outcome is
-- "always allow the downed state instead of instant death".
local DOWNED_STATE_HOOKS = {
    { path = "/Script/Pal.PalPlayerCharacter:CanEnterDownedState", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:ShouldEnterDownedState", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:CanDown", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:CanBeDowned", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:HasReviveTarget", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:HasAvailableReviver", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:IsPossibleToRevive", target = true },
    { path = "/Script/Pal.PalPlayerCharacter:IsAloneInGuild", target = false },
    { path = "/Script/Pal.PalPlayerCharacter:IsGuildMemberOffline", target = false },
    { path = "/Script/Pal.PalPlayerCharacter:ShouldSkipDownedState", target = false },
    { path = "/Script/Pal.PalPlayerCharacter:ShouldDieImmediately", target = false },
}

-- Confirmed to exist (used by community "instant self-revive" tools): the
-- RPC that actually applies a revive to a character. Hooked only for
-- diagnostics -- by the time this fires, whatever decided the interaction
-- was allowed has already run.
local DIAGNOSTIC_HOOK = "/Script/Pal.PalPlayerCharacter:ReviveCharacter_ToServer"

-- Forces a hooked function's boolean return value to target_value whenever
-- it fires with the opposite value. UE4SS appends a UFunction's return
-- value as the last hook parameter, so this reads whichever argument ends
-- up last rather than assuming a fixed parameter count, since the real
-- signature of each candidate is unverified. Comparing against the exact
-- opposite boolean (rather than just "is it falsy") means a wrong-candidate
-- match on a non-boolean return is always a silent no-op.
local function force_boolean_return(function_path, target_value, log_label)
    local attached, err = pcall(function()
        RegisterHook(function_path, function(...)
            local count = select("#", ...)
            if count == 0 then
                return
            end

            local return_value = select(count, ...)
            if return_value == nil then
                return
            end

            local ok, current = pcall(function() return return_value:get() end)
            if not ok then
                return
            end

            if current == (not target_value) then
                local set_ok = pcall(function() return_value:set(target_value) end)
                if set_ok then
                    log(string.format("%s via %s", log_label, function_path))
                end
            end
        end)
    end)

    if attached then
        log(string.format("Registered candidate hook: %s", function_path))
    else
        log(string.format(
            "Candidate hook unavailable, skipped: %s (%s)",
            function_path,
            tostring(err)
        ))
    end
end

for _, function_path in ipairs(CANDIDATE_HOOKS) do
    force_boolean_return(function_path, true, "Allowed a revive")
end

for _, hook in ipairs(DOWNED_STATE_HOOKS) do
    force_boolean_return(hook.path, hook.target, "Forced downed state instead of instant death")
end

local diagnostic_attached, diagnostic_err = pcall(function()
    RegisterHook(DIAGNOSTIC_HOOK, function(Context, HP)
        local hp_text = "?"
        local ok, hp_value = pcall(function() return HP:get() end)
        if ok then
            hp_text = tostring(hp_value)
        end

        log(string.format(
            "ReviveCharacter_ToServer fired (HP=%s) -- a revive is completing now",
            hp_text
        ))
    end)
end)

if diagnostic_attached then
    log(string.format("Registered diagnostic hook: %s", DIAGNOSTIC_HOOK))
else
    log(string.format(
        "Diagnostic hook unavailable: %s (%s)",
        DIAGNOSTIC_HOOK,
        tostring(diagnostic_err)
    ))
end

log("Loaded.")
