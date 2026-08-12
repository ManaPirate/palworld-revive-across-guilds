# Tuning ReviveAcrossGuilds

This mod ships with a best-effort guess at which UFunction gates "can this
player revive that player". It was written without access to a live
Palworld server or a UE4SS reflection dump, so the guess may be wrong for
your game version. This doc explains how to check, and what to do if the
default candidates don't work.

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
4. Once you have the real name, add it to `CANDIDATE_HOOKS` at the top of
   `ReviveAcrossGuilds/Scripts/main.lua`, in the same
   `"/Script/Pal.PalPlayerCharacter:FunctionName"` format as the existing
   entries.

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
