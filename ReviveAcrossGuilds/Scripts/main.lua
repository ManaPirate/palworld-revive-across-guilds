-- ReviveAcrossGuilds
-- Server-side RE-UE4SS Lua mod for Palworld dedicated servers.
--
-- Palworld normally only lets a guildmate revive a downed player. This mod
-- tries to lift that restriction so any player nearby can revive any other
-- downed player, regardless of guild membership.
--
-- HOW THIS WORKS
-- Palworld's guild-membership check for reviving isn't a simple property on
-- the player, and there is no PalWorldSettings.ini toggle for it. The exact
-- UFunction that gates the revive interaction could not be confirmed against
-- a live server/UE4SS Live View at the time this mod was written, so it takes
-- a best-effort approach:
--
--   1. It registers hooks on a short list of plausible "can revive" function
--      names (see CANDIDATE_HOOKS below) and forces a false/blocked result to
--      true when one of them fires. Every candidate name mentions "Revive"
--      specifically -- none of them touch a shared/generic guild-membership
--      utility, so a wrong guess is a silent no-op, never a side effect on
--      unrelated systems (base building, storage, PvP, etc.).
--   2. It also hooks the confirmed ReviveCharacter_ToServer RPC purely for
--      logging, so UE4SS.log shows whether a revive actually completed.
--
-- If revives between non-guildmates still don't work after installing this,
-- see ../../docs/TUNING.md for how to find the correct function name with
-- UE4SS's Live View and add it to CANDIDATE_HOOKS.

local MOD_TAG = "[ReviveAcrossGuilds]"

local function log(message)
    print(string.format("%s %s\n", MOD_TAG, message))
end

-- Candidate UFunctions that might gate "can PlayerA revive PlayerB". All of
-- these are scoped to revive specifically -- add more candidates here as you
-- discover them, but avoid anything that looks like a generic/shared guild
-- check (e.g. "IsSameGuildMember") since forcing that to true would also
-- affect unrelated guild-gated systems like base ownership and storage.
local CANDIDATE_HOOKS = {
    "/Script/Pal.PalPlayerCharacter:CanRevive",
    "/Script/Pal.PalPlayerCharacter:CanReviveOtherPlayer",
    "/Script/Pal.PalPlayerCharacter:CanReviveTarget",
    "/Script/Pal.PalPlayerCharacter:IsReviveTarget",
    "/Script/Pal.PalPlayerCharacter:IsAbleToRevive",
    "/Script/Pal.PalPlayerCharacter:CheckCanRevive",
}

-- Confirmed to exist (used by community "instant self-revive" tools): the
-- RPC that actually applies a revive to a character. Hooked only for
-- diagnostics -- by the time this fires, whatever decided the interaction
-- was allowed has already run.
local DIAGNOSTIC_HOOK = "/Script/Pal.PalPlayerCharacter:ReviveCharacter_ToServer"

-- Forces a hooked function's return value to true whenever it fired with a
-- false/blocked result. UE4SS appends a UFunction's return value as the last
-- hook parameter, so this reads whichever argument ends up last rather than
-- assuming a fixed parameter count, since the real signature of each
-- candidate is unverified.
local function force_true_on_return(function_path)
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

            if current == false then
                local set_ok = pcall(function() return_value:set(true) end)
                if set_ok then
                    log(string.format("Allowed a revive via %s", function_path))
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
    force_true_on_return(function_path)
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
