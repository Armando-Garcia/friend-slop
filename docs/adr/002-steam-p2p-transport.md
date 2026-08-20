# ADR 002: Steam P2P multiplayer transport

**Status:** Accepted  
**Date:** 2026-06-08

## Context

FriendSlop targets **Steam release** with friend invites, reliable NAT traversal, and no third-party relay dependency.

Godot high-level multiplayer (`@rpc`, `multiplayer.get_unique_id()`, built-in `MultiplayerSynchronizer`) stays unchanged; only the **peer layer** uses Steam.

## Decision

Adopt **GodotSteam** (4.17+) with **`SteamMultiplayerPeer`** as the **only** online transport.

- **Lobbies:** `Steam.createLobby` → `SteamMultiplayerPeer.host_with_lobby` / client join by lobby ID or Steam overlay invite.
- **Packets:** Steam P2P with **`Steam.allowP2PPacketRelay(true)`** so Valve relay backs up direct connections.
- **Authority:** Host = lobby owner = Godot multiplayer server (peer id `1`); existing `NetworkManager` RPC patterns unchanged.

## Non-goals (this ADR)

- **Proximity voice** is NOT Steam lobby voice chat. Game voice is Friend Slop’s Godot-mic + Steam P2P stack (ADR 001) on a **dedicated P2P virtual port**. **`SteamMultiplayerPeer` channel 0** carries game RPCs only.
- **Dedicated servers** — P2P host-authoritative only for v1.

## Implementation sketch

```
NetworkManager.transport := SteamTransport.new()

SteamTransport.host({ "max_members": 4 })
  → create lobby → host_with_lobby → multiplayer.multiplayer_peer = peer

SteamTransport.join({ "lobby_id": uint64 })
  → join lobby → connect_to_lobby → multiplayer.multiplayer_peer = peer
```

Key files:

- `scripts/network/steam_transport.gd`
- `scripts/network/steam_service.gd` — init, callbacks, `steam_appid.txt` handling
- `tests/unit/test_steam_transport.gd` — logic with mocked SteamService (no real Steam in CI)

## Build & CI

| Environment | Transport |
|-------------|-----------|
| GitHub Actions `make test` | Stock Godot + GodotSteam GDExtension (`make setup-steam`) — no live Steam client |
| Local dev | `make setup-steam` + GodotSteam editor or stock Godot |
| Release export | GodotSteam GDExtension bundled via `tools/run_setup_steam.sh` in CI |

## Lobby UX

| Feature | Behavior |
|---------|----------|
| Session ID | Steam lobby ID |
| Invite | Steam overlay **Invite friends** |
| Join | Paste lobby ID or accept Steam invite |
| Roster | Steam persona name via `Steam.getFriendPersonaName(steam_id)` |

## Risks

- GodotSteam requires **matching GDExtension** per OS/editor version.
- Host must `add_peer(steam_id)` for lobby members who join after `host_with_lobby`.
- Headless unit tests cannot load Steam — inject `SteamService` interface.

## Open questions

1. Steam App ID (production vs 480 dev)?
2. Friends-only vs public lobby default for horror sessions?

## References

- [GodotSteam MultiplayerPeer](https://godotsteam.com/classes/multiplayer_peer/)
- `scripts/network/multiplayer_transport.gd`, `steam_transport.gd`
