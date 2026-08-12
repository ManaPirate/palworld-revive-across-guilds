# Palworld Revive Across Guilds

A server-side [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod for
Palworld dedicated servers. It lets players revive a downed ally even when
they are **not** in the same guild — normally Palworld only allows a
guildmate to do this.

It also fixes a related issue: Palworld normally skips the downed/revive
countdown and kills a player outright if it decides no guildmate is
available to revive them (e.g. they're alone in their guild). This mod
tries to force the downed state to always happen instead, since with
cross-guild revives enabled, a stranger nearby may still be able to save
them.

**PvP servers:** letting anyone revive anyone is a griefing vector in PvP
(reviving an enemy to disrupt a fight, interfering with a raid, etc.), so
the mod checks `bIsPvP` in `PalWorldSettings.ini` at startup and disables
itself entirely if PvP is on, or if the setting can't be confirmed. See
[`docs/TUNING.md`](docs/TUNING.md#pvp-detection) for how to verify this and
how to override it if you need to.

## Status

This is a first, best-effort implementation. Neither of Palworld's
underlying checks here (guild membership for reviving, and whether a
reviver is available before killing a downed player outright) are plain
properties, and there's no `PalWorldSettings.ini` setting for either, so
the mod hooks short lists of plausible candidate functions rather than
confirmed ones. See [`docs/TUNING.md`](docs/TUNING.md) for how to verify
it's working on your server and how to adjust it if the default candidates
don't match your game version.

## Requirements

- A Palworld dedicated server running [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)
  (or [NullPrism's RE-UE4SS-Linux](https://github.com/NullPrism/RE-UE4SS-Linux)
  port on native Linux servers) with Lua modding enabled.
- Server-side install only — no client-side mod is needed.

## Installing

1. Copy the `ReviveAcrossGuilds/` folder from this repo into your server's
   `Mods/` directory, so you end up with:
   ```
   Mods/ReviveAcrossGuilds/enabled.txt
   Mods/ReviveAcrossGuilds/Scripts/main.lua
   ```
2. Make sure `Mods/mods.txt` lists `ReviveAcrossGuilds : 1` (or add it if
   your UE4SS build tracks enabled mods that way — some builds only need
   `enabled.txt` to be present).
3. Restart the server.
4. Check `UE4SS.log` for lines starting with `[ReviveAcrossGuilds]` to
   confirm it loaded. See [`docs/TUNING.md`](docs/TUNING.md) for what those
   lines mean and how to confirm cross-guild revives actually work.

## How it works

See the comments at the top of
[`ReviveAcrossGuilds/Scripts/main.lua`](ReviveAcrossGuilds/Scripts/main.lua)
and [`docs/TUNING.md`](docs/TUNING.md) for the technical approach and its
known limitations.

## License

MIT — see [LICENSE](LICENSE).
