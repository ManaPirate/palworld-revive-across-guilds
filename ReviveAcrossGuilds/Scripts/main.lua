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
-- PVP SAFETY
-- Letting any player revive any other player is a griefing vector on a PvP
-- server (e.g. reviving an enemy mid-fight to disrupt combat resolution, or
-- interfering with a raid). So this mod tries to detect whether the server
-- has PvP enabled (reading bIsPvP from PalWorldSettings.ini) and disables
-- its entire effect -- both the revive-permission hooks and the
-- downed-state hooks -- if it does, or if it can't confirm the setting
-- either way. See PVP_DETECTION and FORCE_MODE below.
--
-- HOW THIS WORKS
-- None of the UFunctions involved here are confirmed against a live
-- server/UE4SS Live View -- Palworld's guild-membership and
-- alone-in-guild checks aren't plain properties. So this takes a
-- best-effort approach:
--
--   1. It registers hooks on short lists of plausible candidate function
--      names (see CANDIDATE_HOOKS and DOWNED_STATE_HOOKS below) and forces
--      their boolean result to the value that produces the wanted
--      behavior, but only while the PvP check above says it's safe to.
--      Every candidate name is scoped to revive/downed-state specifically
--      -- none of them touch a shared/generic guild-membership utility, so
--      a wrong guess is a silent no-op, never a side effect on unrelated
--      systems (base building, storage, PvP damage, etc.).
--   2. It also hooks the confirmed ReviveCharacter_ToServer RPC purely for
--      logging, so UE4SS.log shows whether a revive actually completed.
--
-- If cross-guild revives, solo-guild downed state, or PvP detection don't
-- behave as expected after installing this, see ../../docs/TUNING.md.

local MOD_TAG = "[ReviveAcrossGuilds]"

local function log(message)
    print(string.format("%s %s\n", MOD_TAG, message))
end

-- Set to "always_on" or "always_off" to skip PvP auto-detection entirely
-- and force the mod's effect on or off regardless of server settings.
-- Leave as "auto" (default, recommended) to detect PvP from
-- PalWorldSettings.ini and disable the mod automatically when it's on.
local FORCE_MODE = "auto"

-- If PvP auto-detection can't find/read PalWorldSettings.ini in any of the
-- candidate locations below, this decides the fail-safe default. true
-- (recommended) keeps the mod's effect OFF when the PvP state can't be
-- confirmed, since an unconfirmed PvE server is a much smaller problem than
-- an unconfirmed PvP server getting the griefing vector by accident.
local ASSUME_PVP_IF_UNDETECTABLE = true

-- Relative paths tried, in order, to find PalWorldSettings.ini. The
-- correct number of "../" hops depends on what UE4SS treats as the
-- current working directory for Lua scripts, which isn't confirmed here --
-- add more candidates if none of these match your server's layout (see
-- docs/TUNING.md).
local INI_PATH_CANDIDATES = {
    "Pal/Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../Pal/Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../../Pal/Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../../../Pal/Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../../../../Pal/Saved/Config/LinuxServer/PalWorldSettings.ini",
    "Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../../Saved/Config/LinuxServer/PalWorldSettings.ini",
    "../../../Saved/Config/LinuxServer/PalWorldSettings.ini",
}

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Returns true/false for the detected bIsPvP value plus the path it was
-- read from, or nil, nil if no candidate path yielded a readable setting.
local function detect_pvp()
    for _, path in ipairs(INI_PATH_CANDIDATES) do
        local content = read_file(path)
        if content then
            local lower_content = content:lower()
            local value = lower_content:match("bispvp%s*=%s*(%a+)")
            if value then
                return value == "true", path
            end
        end
    end
    return nil, nil
end

local MOD_ACTIVE

if FORCE_MODE == "always_on" then
    MOD_ACTIVE = true
    log("FORCE_MODE=always_on -- skipping PvP auto-detection, mod is ACTIVE regardless of server settings.")
elseif FORCE_MODE == "always_off" then
    MOD_ACTIVE = false
    log("FORCE_MODE=always_off -- mod is INACTIVE regardless of server settings.")
else
    local pvp_enabled, ini_path = detect_pvp()

    if pvp_enabled == nil then
        MOD_ACTIVE = not ASSUME_PVP_IF_UNDETECTABLE
        log(string.format(
            "Could not read bIsPvP from PalWorldSettings.ini in any candidate location. "
                .. "Defaulting to %s for safety -- see docs/TUNING.md to fix path detection "
                .. "or set FORCE_MODE to override.",
            MOD_ACTIVE and "ACTIVE" or "INACTIVE"
        ))
    elseif pvp_enabled then
        MOD_ACTIVE = false
        log(string.format(
            "PvP is enabled (bIsPvP=True in %s) -- disabling cross-guild revive to prevent griefing.",
            ini_path
        ))
    else
        MOD_ACTIVE = true
        log(string.format(
            "PvP is disabled (bIsPvP=False in %s) -- cross-guild revive is active.",
            ini_path
        ))
    end
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
-- it fires with the opposite value, unless MOD_ACTIVE is false (PvP
-- detected or forced off), in which case it does nothing and the game's
-- own result stands. UE4SS appends a UFunction's return value as the last
-- hook parameter, so this reads whichever argument ends up last rather
-- than assuming a fixed parameter count, since the real signature of each
-- candidate is unverified. Comparing against the exact opposite boolean
-- (rather than just "is it falsy") means a wrong-candidate match on a
-- non-boolean return is always a silent no-op.
local function force_boolean_return(function_path, target_value, log_label)
    local attached, err = pcall(function()
        RegisterHook(function_path, function(...)
            if not MOD_ACTIVE then
                return
            end

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
            "ReviveCharacter_ToServer fired (HP=%s, mod active=%s) -- a revive is completing now",
            hp_text,
            tostring(MOD_ACTIVE)
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
