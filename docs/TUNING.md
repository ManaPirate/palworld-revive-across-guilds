# Tuning ReviveAcrossGuilds

## Background

The first version of this mod hooked a list of guessed `UFunction` names
meant to gate "can this player revive that player" and "should this player
enter the downed state or die outright". It was written without access to
a live Palworld server, so those names were guesses.

On 21 Aug 2026 a live reflection dump (UE4SS's `GenerateSDK()`, the same
thing as the "Dump CXX Headers" button in the UE4SS debugging GUI) was run
against a real dedicated server. Every single guessed name was wrong,
including one previously treated as confirmed from community self-revive
cheat tools (`ReviveCharacter_ToServer` -- doesn't exist in this build).
None of them attached; UE4SS.log showed `Candidate hook unavailable` for
every one.

The real functions, found by grepping the reflection dump instead of
guessing:

- `PalNetworkCharacterStatusOperationComponent::RequestReviveCharacterFromDying_ToServer(APalCharacter* Character)`
  -- the actual RPC a client sends when attempting to revive a dying
  character.
- `PalCharacterParameterComponent::ReviveFromDying()` -- the actual
  internal action that revives a dying character. Also on this component:
  `ZeroDyingHP_ToServer()`/`ZeroDyingHP()` (enter the downed state),
  `SubDyingHP(float)` (the downed-state countdown tick), `IsDying()` /
  `IsDead()` / `IsDyingHPZero()` (state queries).

There is no separate, reflectable "is this revive allowed" boolean gate
function anywhere in the `/Script/Pal` package under any guessable name.
Whichever guild check blocks a cross-guild revive today is either inline
native code inside `RequestReviveCharacterFromDying_ToServer`'s own body
(not visible to reflection) or enforced earlier, possibly client-side --
see "If nothing fires at all" below.

## Current approach (v2)

Instead of guessing at a permission check and trying to force its result,
the mod hooks the confirmed real RPC directly. When it fires, if the
target is actually in the dying state (`IsDying()` is true), the mod calls
the confirmed real `ReviveFromDying()` itself on the target's
`CharacterParameterComponent` -- bypassing whatever internal guild check
may exist, rather than trying to flip it.

This has not yet been live-tested against two players in different
guilds. The hook is confirmed to *attach* (UE4SS.log shows `Registered
hook` rather than `Hook unavailable`, meaning the function genuinely
exists at that path in this build), but nobody has confirmed yet whether
it actually *fires* for a real cross-guild revive attempt.

## How to tell if it's working

1. Install the mod (see the root [README](../README.md)).
2. Set `UE4SS.log` to a visible/tailable location on your server, or watch
   it live.
3. Have two players who are **not** in the same guild: down one of them,
   have the other try to revive them.
4. Look for lines starting with `[ReviveAcrossGuilds]` in `UE4SS.log`:
   - `Registered hook: ...` -- printed once at startup. This does **not**
     mean a revive attempt happened, only that RE-UE4SS found the function
     and attached to it.
   - `RequestReviveCharacterFromDying_ToServer fired for ... (mod
     active=true/false)` -- printed every time *any* player (same-guild or
     not) attempts a revive. If this line **never appears** for a
     cross-guild attempt, see "If nothing fires at all" below.
   - `Forced revive via ReviveFromDying() on ...` -- the mod detected the
     target was still dying and called the real revive function itself. If
     the target is actually revived in-game after this, the mod is
     working.
   - `Could not resolve CharacterParameterComponent on revive target` /
     `IsDying() check failed` -- something about the target object's shape
     didn't match what the reflection dump showed; report this with the
     full log line.

## If nothing fires at all

If `RequestReviveCharacterFromDying_ToServer fired for ...` never appears
in the log for a genuine cross-guild revive attempt (i.e. the revive
prompt either never appears client-side, or appears but nothing is sent to
the server), the restriction is most likely enforced **client-side**. A
server-only mod fundamentally can't fix that on its own -- a client-side
companion mod would be needed instead, similar in spirit to how the
sibling [Integrated Storage](../../palworld-integrated-storage-linux)
project needed a throwaway client-side Lua mod to confirm replication
behaviour it couldn't observe from the server alone. Please report back
what you see if this turns out to be the case.

## PvP detection

Unchanged from v1. Reviving strangers is a griefing vector on a PvP
server (interrupting combat resolution, interfering with raids, etc.), so
the mod tries to read `bIsPvP` out of `PalWorldSettings.ini` at startup
and disables its entire effect if PvP is on, or if the setting can't be
confirmed either way (fail-safe default; see `ASSUME_PVP_IF_UNDETECTABLE`
in `main.lua`).

Check `UE4SS.log` at startup for one of:

- `PvP is disabled (bIsPvP=False in <path>) -- cross-guild revive is
  active.` -- detection worked and the mod is on.
- `PvP is enabled (bIsPvP=True in <path>) -- disabling cross-guild revive
  to prevent griefing.` -- working as intended on a PvP server; the mod is
  a no-op.
- `Could not read bIsPvP from PalWorldSettings.ini in any candidate
  location. Defaulting to INACTIVE for safety ...` -- path detection
  failed. `INI_PATH_CANDIDATES` in `main.lua` lists the relative paths
  tried; add the correct one for your server layout (find it by checking
  where `PalWorldSettings.ini` actually sits relative to wherever
  `PalServer.sh` is launched from). The `RequestReviveCharacterFromDying_
  ToServer fired ... (mod active=true/false)` log line also reports the
  current effective state on every revive attempt, which is a fast way to
  confirm it without restarting.

If you're confident about your server's PvP state and don't want to debug
path detection, set `FORCE_MODE` in `main.lua` to `"always_on"` or
`"always_off"` to skip auto-detection entirely. Setting `"always_on"` on a
PvP server re-introduces the griefing vector this check exists to
prevent -- only do that deliberately.

## Solo/alone-in-guild instant death (not yet fixed in v2)

Palworld skips the downed-state countdown and kills a player outright when
it decides no guildmate is available to revive them -- e.g. they're the
only member of their guild online. That shortcut made sense when only
guildmates could revive you, but it defeats the purpose of this mod: a
stranger nearby might well be able to revive them if only they got the
countdown.

v1 guessed at a list of `DOWNED_STATE_HOOKS` names for this. All of them
were confirmed wrong in the same 21 Aug 2026 reflection dump, and v2 does
not replace them with anything yet -- this problem is currently
unaddressed.

One real candidate was found:
`IsAliveOrDyingFriendPlayers_ByUId(WorldContextObject, PlayerUId)`, on the
same static Blueprint-function-library class as other global helpers like
`IsFriend` and `IsDead`. It's a plausible fit for whatever decides "is
there someone who could revive this player", but it hasn't been confirmed
as the actual decision point for the instant-death branch -- it could just
as easily be a query used somewhere else entirely (UI, AI). Before hooking
it, confirm with a live test: have a solo-guild player go down while a
non-guildmate is nearby, and check whether/when this function gets called
and what it returns.

## Finding function names yourself

If you need to verify or extend this for your own game version, don't
guess: a Lua mod can call UE4SS's `GenerateSDK()` function directly
(no GUI needed -- it's the same thing as the "Dump CXX Headers" button
under the UE4SS Debugging Tools GUI console) to get a full C++ reflection
header dump in `CXXHeaderDump/`, one file per package (Palworld's own
classes are in `Pal.hpp`). Grep that for whatever you're looking for
instead of guessing candidate names. This is how the functions in this doc
were found.

RE-UE4SS also ships a Live View for interactive searching, if your build
exposes it:

1. Enable the in-game/console Live View per your RE-UE4SS build's docs
   (`ConsoleEnabled = 1` and `GuiConsoleEnabled = 1` in
   `UE4SS-settings.ini` are the usual switches on Windows RE-UE4SS; check
   whether your Linux build exposes an equivalent debug UI or console
   command).
2. Interact with (attempt to revive) a downed, non-guild player while
   watching the Live View / log to see which function actually gets
   called.

## Avoid hooking shared guild-membership utilities

The reflection dump surfaced several other real, guild-related functions
that are **not** revive-specific and should not be blanket-hooked or
forced, since they're reused by other systems (base ownership, storage,
combat targeting, etc.):

- `IsFriend(ActorA, ActorB)` -- a broad relationship check reused across
  combat targeting and friendly-fire logic.
- `IsSameGuildWithPlayer(PlayerUId)` -- belongs to base-camp access
  control (`UPalLocationPointBaseCamp`), not player revive.
- `IsInGuild`, `HasGuildPermission`, `IsGuildMaster` -- general
  guild-permission systems.

If you find one of these is actually involved in the revive decision,
don't force it to always return true -- that would also disable guild
checks everywhere else it's used. Prefer scoping any override to only
apply when one of the two characters involved is in the dying state, the
same way the current `IsDying()` guard works.
