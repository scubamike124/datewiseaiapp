# Kokoro speech service: contract

Status: stub only. `backend/kokoro_speech.mjs` validates requests and answers 503 until a renderer is wired in.
Nothing is deployed, and no Railway service exists for it yet.

## Endpoint

`POST {DW_KOKORO_SPEECH_URL}/v1/speech` with `content-type: application/json`. The app requires an `https` base URL.

Request body:

| field   | type   | rule |
|---------|--------|------|
| `text`  | string | non-empty, at most 1000 characters |
| `voice` | string | `af_bella`, `am_michael`, `ef_dora` or `em_alex` |
| `lang`  | string | `en-us` for the English voices, `es` for the Spanish voices |
| `speed` | number | 0.6 to 1.3 (the app sends about 0.84 to 0.87 for the coach rates) |

Success (200):

```json
{ "timeline": { "fps": 10, "sentences": [ { "text": "...", "start_s": 0.0, "duration_s": 0.5, "mouth": [0.0, 0.8] } ] },
  "audio_url": "/clips/<id>.wav" }
```

- `timeline.sentences` are in order by `start_s`. `mouth` holds one openness value (0 to 1) per frame of `fps`.
  Only measured loudness is used; word times are not part of the contract.
- `audio_url` must be on the same origin as the service (same scheme, host and port). The app refuses any other origin.

Errors: 400 invalid body, 405 not POST, 415 not JSON, 500 renderer reply invalid, 502 render failed, 503 not configured.
Error bodies carry a short code, never a stack trace or a file path.

## Limits and cost

- Text length capped at 1000 characters per request. The app sends one sentence per chunk.
- No renderer, storage or access control is in the stub. Before a real deployment the owner must decide on access
  control (the app currently sends no credential), rate limits and the hosting cost. Any new Railway service needs the
  owner's approval and a cost estimate first (AGENTS.md: no spending without authorization).

## Client

- `lib/services/voice_service.dart`: `DeviceVoiceService.audioBackendFor` (https check, falls back to the native path),
  `CoachVoiceProfile.kokoroVoice` (coach to Kokoro voice).
- `lib/avatar/kokoro_audio_backend.dart`: sends this contract; `speedFor` maps the coach rate to `speed`.
- Off by default: `DW_AVATAR_AUDIO_PATH` and `DW_KOKORO_SPEECH_URL` are empty in every build unless set.
