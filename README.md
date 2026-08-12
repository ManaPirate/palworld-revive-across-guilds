# Palworld Revive Across Guilds

A server-side [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod for
Palworld dedicated servers. It lets players revive a downed ally even when
they are **not** in the same guild — normally Palworld only allows a
guildmate to do this.

## Status

This is a first, best-effort implementation. Palworld's guild-membership
check for reviving isn't a plain property and there's no
`PalWorldSettings.ini` setting for it, so the mod hooks a short list of
plausible candidate functions rather than one confirmed one. See
[`docs/TUNING.md`](docs/TUNING.md) for how to verify it's working on your
server and how to adjust it if the default candidates don't match your game
version.

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
