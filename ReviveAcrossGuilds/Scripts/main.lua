-- ReviveAcrossGuilds
-- Server-side RE-UE4SS Lua mod for Palworld dedicated servers.
--
-- Palworld normally only lets a guildmate revive a downed player. This mod
-- tries to lift that restriction so any player nearby can revive any other
-- downed player, regardless of guild membership.
--
-- PVP SAFETY
-- Letting any player revive any other player is a griefing vector on a PvP
-- server (e.g. reviving an enemy mid-fight to disrupt combat resolution, or
-- interfering with a raid). So this mod tries to detect whether the server
-- has PvP enabled (reading bIsPvP from PalWorldSettings.ini) and disables
-- its entire effect if it does, or if it can't confirm the setting either
-- way. See PVP_DETECTION and FORCE_MODE below.
--
-- HOW THIS WORKS (v2 -- rewritten 21 Aug 2026)
-- The first version of this mod hooked a list of guessed UFunction names
-- that were meant to gate "can this player revive that player". A live
-- reflection dump (UE4SS's GenerateSDK()) against a real server proved
-- every single guessed name wrong, including one previously treated as
-- confirmed from community self-revive cheat tools. None of them exist in
-- this game version -- see docs/TUNING.md for the full findings.
--
-- The real revive RPC is
-- PalNetworkCharacterStatusOperationComponent::RequestReviveCharacterFromDying_ToServer,
-- and the real internal action that actually revives someone is
-- PalCharacterParameterComponent::ReviveFromDying(). There is no separate,
-- reflectable "is this allowed" boolean gate function anywhere in the
-- codebase under any guessable name -- whatever decides guild eligibility
-- is either inline native code inside the RPC's body (not reflectable) or
-- enforced earlier, possibly client-side (see docs/TUNING.md).
--
-- So instead of guessing at a permission check and trying to force its
-- result, this hooks the confirmed real RPC directly and, if the target is
-- actually in the dying state, calls the confirmed real ReviveFromDying()
-- itself -- bypassing whatever internal guild check may exist, rather than
-- trying to flip it. This still hasn't been live-tested against two
-- players in different guilds; see docs/TUNING.md for how to verify it and
-- what the log lines mean.
--
-- This version does not yet address the related solo-guild instant-death
-- problem (Palworld skipping the downed countdown and killing a player
-- outright when it decides no guildmate is available). A real candidate
-- function was found (IsAliveOrDyingFriendPlayers_ByUId) but not confirmed
-- to be the actual decision point -- see docs/TUNING.md.

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

-- Confirmed real via a live GenerateSDK() reflection dump (21 Aug 2026, see
-- docs/TUNING.md) -- the RPC a client sends when a player attempts to
-- revive a dying character.
local REVIVE_RPC = "/Script/Pal.PalNetworkCharacterStatusOperationComponent:RequestReviveCharacterFromDying_ToServer"

local attached, err = pcall(function()
    RegisterHook(REVIVE_RPC, function(Context, CharacterParam)
        local ok, target = pcall(function() return CharacterParam:get() end)
        if not ok or not target or not target:IsValid() then
            return
        end

        local target_name_ok, target_name = pcall(function() return target:GetFullName() end)
        log(string.format(
            "RequestReviveCharacterFromDying_ToServer fired for %s (mod active=%s)",
            target_name_ok and target_name or "<unknown>",
            tostring(MOD_ACTIVE)
        ))

        if not MOD_ACTIVE then
            return
        end

        local component_ok, component = pcall(function() return target.CharacterParameterComponent end)
        if not component_ok or not component or not component:IsValid() then
            log("Could not resolve CharacterParameterComponent on revive target -- cannot force revive.")
            return
        end

        local dying_ok, is_dying = pcall(function() return component:IsDying() end)
        if not dying_ok then
            log("IsDying() check failed on revive target -- cannot confirm state, skipping forced revive.")
            return
        end

        if not is_dying then
            -- Already handled normally (same-guild reviver, or not actually
            -- down), nothing for this mod to do.
            return
        end

        local revive_ok, revive_err = pcall(function() component:ReviveFromDying() end)
        if revive_ok then
            log(string.format("Forced revive via ReviveFromDying() on %s", target_name_ok and target_name or "<unknown>"))
        else
            log(string.format("ReviveFromDying() call failed: %s", tostring(revive_err)))
        end
    end)
end)

if attached then
    log(string.format("Registered hook: %s", REVIVE_RPC))
else
    log(string.format("Hook unavailable, skipped: %s (%s)", REVIVE_RPC, tostring(err)))
end

log("Loaded.")
