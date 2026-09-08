# OverCUE Web UI

Primary configuration UI for OverCUE.

## Stack

- Vue 3
- TypeScript
- Vite
- Vue Router
- Pinia

The Web UI does not own runtime or configuration persistence. It talks to the loopback-only local API exposed by the native OverCUE app. `config.json` and runtime state remain owned by the Swift side.

## Development

```sh
cd WebUI
npm install
npm run dev
```

Vite runs on `127.0.0.1:4174` and proxies `/api` to `127.0.0.1:4173` by default. Override the API target with `OVERCUE_API_ORIGIN` when starting Vite.

The native app exposes:

- `GET /api/v1/session`
- `GET /api/v1/snapshot`
- `PUT /api/v1/presets/order`
- `PUT /api/v1/group-presets/order`

Write requests require the startup-scoped token returned by `/session` in `X-OverCUE-Session`. The API binds only to `127.0.0.1`, does not emit permissive CORS headers, and rejects non-loopback browser origins for writes.

## Build

```sh
npm run typecheck
npm run build
```

`dist/` is generated output and must not be committed.
