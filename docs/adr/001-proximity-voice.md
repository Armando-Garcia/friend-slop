# ADR 001: Proximity voice

**Status:** Accepted (Friend Slop–owned voice stack, 2026-07)

## Context

Asymmetric horror requires spatial voice: players hear each other based on distance and maze occlusion. Global Steam lobby chat violates the proximity pillar.

Spell STT captures microphone input for incantations via Godot `MicCapture`. Steam’s `getVoice` capture API returned persistent `VOICE_NO_DATA` on Windows while Godot’s `AudioStreamMicrophone` worked — so VoIP must not depend on Steam Voice codec APIs.

## Decision

Own a small in-repo voice stack under [`scripts/voice/`](../../scripts/voice/):

| Piece | Role |
|-------|------|
| `SimpleVoiceChat` | Godot mic capture + remote `AudioStreamGenerator` playback (flat or spatial) |
| `SteamP2PVoiceTransport` | Steam `sendP2PPacket` / `readP2PPacket` on voice port `1` |
| `GameVoiceSession` | Per-state config (lobby open-mic vs match) driving the shared engine |
| `SteamMultiplayerPeerAdapter` | Peer ID → Steam ID helpers |

Product tree: [`scenes/game_app.tscn`](../../scenes/game_app.tscn)

```
GameApp
  MicCaptureBroker     # sole MicCapture drain; fans out to voip / stt / meter
  VoiceEngine          # SimpleVoiceChat — Peers + voip subscriber
  States
    MainMenu
    Lobby
      VoiceSession     # GameVoiceSession
      LobbyPanel
    Match
      VoiceSession
      Main             # instanced at runtime
  SettingsPanel
```

| State | Voice |
|-------|--------|
| MainMenu | all sessions stopped |
| Lobby | `Lobby/VoiceSession` toggled by host (open mic) |
| Match | `Match/VoiceSession` while gameplay active |

Call sites may still use the thin `SteamProximityVoiceHub` autoload shim → `GameApp` voice API.

**Not used:** Steam `startVoiceRecording` / `getVoice` / `decompressVoice`, and the former `addons/godot-steam-voice` codec library.

### Spatial playback

A remote peer is mixed spatially only when both hold:

1. The live session's Chat listener has `ProximityChatSettings.enabled` (match on, lobby off).
2. That peer has a world anchor — the match sets one per body via
   `SteamProximityVoiceHub.set_peer_anchor(peer_id, body)` as it places players.

Spatial peers play through an `AudioStreamPlayer3D` positioned on that body each frame.
Godot's own attenuation is **disabled**; `volume_db` comes from
`ProximityChatSettings.volume_db_for_distance()` measured from the active `Camera3D`,
so the authored range/dB values are the falloff, and the 3D player is there for panning.
The curve floors to `SILENT_DB` at `max_range_m`, which is the cull.

Anything unanchored stays flat (`AudioStreamPlayer`) — the lobby has no `Camera3D`, and 3D
audio without a listener is silent.

Not implemented: wall occlusion. Voice currently carries through maze geometry at full
distance-based volume.

### Packet format

Versioned PCM envelope: magic `FSVC` + uint16 LE sample rate + PCM16 mono samples (~16 kHz, ~40 ms frames).

### Mic capture ownership

`MicCaptureBroker` is the only caller of `AudioEffectCapture.get_buffer()`. Subscribers receive mono PCM copies.

| Policy | Set by | Subscribers |
|--------|--------|-------------|
| `CHAT_ONLY` | Lobby `VoiceSession/Listeners` has only `Chat` | `chat` only |
| `MATCH_FANOUT` | Match `VoiceSession/Listeners` includes `Spellcasting` | `chat` + optional `spellcasting` |

Author listeners as `MicCaptureListener` children under each `VoiceSession/Listeners`.
Chat listeners own `ProximityChatSettings` (enable + range/volume). When subscribed,
those same nodes show live `listening` / `chunks_received` / `last_rms` — no mirror
copies under `MicCaptureBroker`.

| Subscriber | When |
|------------|------|
| `chat` | `SimpleVoiceChat` while a voice session is active |
| `spellcasting` | `SpellCastingSession` while `STATE_LISTENING` (match fan-out only) |

Unit tests inject PCM via `MicCaptureBroker.inject_pcm()` (no real mic):
`tests/unit/test_mic_capture_pipeline.gd`, `tests/unit/test_mic_capture_broker.gd`.

Enable `GameApp.debug_voice` for `[friend-slop-mic-broker]` subscribe/fanout/heartbeat traces.

## Deprovisioning

Lifecycle events must stop voice (`set_mode(OFF)` / `stop_voice()`):

- Leave lobby / disconnect
- Host start-game RPC (all peers, before Match state)
- Match end / return to MainMenu
- App Exit / window close (`SteamService` teardown)

## Consequences

- Scene dock shows product states next to per-state VoiceSession configs and live `MicCaptureBroker/Mic` / `Peers/Peer_*` nodes
- Voice code lives with the game; no vendored addon sync step
- Proximity attenuation uses Chat listener `ProximityChatSettings`; mic share is broker fan-out
- Voice playback needs a peer→body anchor, so spatial audio only works where a scene supplies
  one (the match); every other state falls back to open mic
