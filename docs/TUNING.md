# Tuning ReviveAcrossGuilds

This mod ships with best-effort guesses at which UFunctions gate two
behaviors: "can this player revive that player", and "should this player
enter the downed/reviveable state at all, or die outright". It was written
without access to a live Palworld server or a UE4SS reflection dump, so the
guesses may be wrong for your game version. This doc explains how to check,
and what to do if the default candidates don't work.

## PvP detection

Reviving strangers is a griefing vector on a PvP server (interrupting
combat resolution, interfering with raids, etc.), so the mod tries to read
`bIsPvP` out of `PalWorldSettings.ini` at startup and disables its entire
effect — both `CANDIDATE_HOOKS` and `DOWNED_STATE_HOOKS` — if PvP is on, or
if the setting can't be confirmed either way (fail-safe default; see
`ASSUME_PVP_IF_UNDETECTABLE` in `main.lua`).

Check `UE4SS.log` at startup for one of:

- `PvP is disabled (bIsPvP=False in <path>) -- cross-guild revive is
  active.` — detection worked and the mod is on.
- `PvP is enabled (bIsPvP=True in <path>) -- disabling cross-guild revive
  to prevent griefing.` — working as intended on a PvP server; the mod is
  a no-op.
- `Could not read bIsPvP from PalWorldSettings.ini in any candidate
  location. Defaulting to INACTIVE for safety ...` — path detection
  failed. `INI_PATH_CANDIDATES` in `main.lua` lists the relative paths
  tried; UE4SS's working directory for Lua scripts isn't confirmed, so add
  the correct one for your server layout (find it by checking where
  `PalWorldSettings.ini` actually sits relative to wherever `PalServer.sh`
  is launched from). Diagnostic hook lines also report the current
  `mod active=true/false` state on every revive, which is a fast way to
  confirm the effective state without restarting.

If you're confident about your server's PvP state and don't want to debug
path detection, set `FORCE_MODE` in `main.lua` to `"always_on"` or
`"always_off"` to skip auto-detection entirely. Setting `"always_on"` on a
PvP server re-introduces the griefing vector this check exists to prevent
— only do that deliberately.

## Solo/alone-in-guild instant death

Palworld skips the downed-state countdown and kills a player outright when
it decides no guildmate is available to revive them — e.g. they're the only
member of their guild online. That shortcut made sense when only
guildmates could revive you, but it defeats the purpose of this mod: a
stranger nearby might well be able to revive them if only they got the
countdown. `DOWNED_STATE_HOOKS` in `main.lua` tries to force that decision
to always allow the downed state. Watch for
`Forced downed state instead of instant death via ...` in `UE4SS.log` when
a solo-guild player drops to 0 HP; if a solo/alone player still dies
outright with no such line, none of the shipped candidates matched — see
"Finding the correct function name yourself" below and search for whatever
decides that outcome instead.

## How to tell if it's working

1. Install the mod (see the root [README](../README.md)).
2. Set `UE4SS.log` to a visible/tailable location on your server, or watch
   it live.
3. Have two players who are **not** in the same guild: down one of them,
   have the other try to revive them.
4. Look for lines starting with `[ReviveAcrossGuilds]` in `UE4SS.log`:
   - `Registered candidate hook: ...` / `Registered diagnostic hook: ...` —
     printed once at startup for every hook that successfully attached.
     This does **not** mean the hook fired, only that RE-UE4SS found a
     function at that path.
   - `Candidate hook unavailable, skipped: ...` — that candidate's function
     path doesn't exist in this build of the game. Harmless; the mod just
     ignores it.
   - `Allowed a revive via ...` — one of the candidate hooks fired with a
     blocked/`false` result and the mod forced it to `true`. If you see
     this and the revive then succeeds in-game, the mod is working.
   - `ReviveCharacter_ToServer fired (HP=...)` — a revive actually
     completed. If this line appears for a cross-guild revive but you never
     saw an `Allowed a revive via ...` line first, the block wasn't coming
     from any of the candidate functions — something else already let it
     through (good, nothing more to do), or the interaction was allowed by
     something this mod doesn't need to touch.

If a cross-guild revive attempt produces **none** of these lines at all,
the block is most likely happening earlier than any hook here reaches —
see "If nothing fires at all" below.

## Finding the correct function name yourself

RE-UE4SS ships a **Live View** you can use to search game classes and
functions in real time:

1. Enable the in-game/console Live View per your RE-UE4SS build's docs
   (`ConsoleEnabled = 1` and `GuiConsoleEnabled = 1` in `UE4SS-settings.ini`
   are the usual switches on Windows RE-UE4SS; check whether your Linux
   build exposes an equivalent debug UI or console command).
2. Search for `PalPlayerCharacter` and look at its function list for
   anything revive-related — likely a `Can...`, `Is...`, or `Check...`
   prefixed function returning a bool.
3. Interact with (attempt to revive) a downed, non-guild player while
   watching the Live View / log to see which function actually gets
   called.
4. Once you have the real name, add it to `CANDIDATE_HOOKS` (for the revive
   permission check) or `DOWNED_STATE_HOOKS` (for the instant-death check)
   at the top of `ReviveAcrossGuilds/Scripts/main.lua`. For
   `DOWNED_STATE_HOOKS`, set `target = true` if the function name reads as
   a positive check ("can/should/has ...") or `target = false` if it reads
   as a negative one ("alone/no reviver/should skip ..."), so the outcome
   is always "allow the downed state".

## If nothing fires at all

If Live View shows the revive prompt simply never appears for non-guild
players (rather than appearing and then being rejected), the restriction
may be enforced **client-side** — the client never sends a request to the
server at all, so there is nothing for a server-only mod to intercept.
That would mean this mod's approach can't fix it on its own, and a
client-side companion mod would be needed instead. Please report back
what you see in Live View if this is the case.

## Avoid hooking shared guild-membership utilities

If you find the real gate is a shared function like `IsSameGuildMember` or
`IsGuildMember` that's reused by other systems (base ownership, storage,
PvP friendly fire, etc.), do **not** just force it to always return `true`
— that would also disable guild checks everywhere else it's used. Prefer
hooking something revive-specific, or scope an override to only apply when
one of the two characters involved is in the downed state.
