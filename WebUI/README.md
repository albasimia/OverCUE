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

For frontend-only development:

```sh
cd WebUI
npm install
npm run dev
```

Vite runs on `127.0.0.1:4174` and proxies `/api` to `127.0.0.1:4173` by default. Override the API target with `OVERCUE_API_ORIGIN` when starting Vite.

For the real app-shell path used by OverCUE, build the frontend and launch the native app:

```sh
cd WebUI
npm run build
cd ..
swift run OverCUE
```

The native `OverCUE.app` window hosts a `WKWebView` that loads `http://127.0.0.1:4173/`. The same loopback server serves both the built Vue assets and `/api`, so the packaged UI is same-origin with the Local API. `Scripts/build-app.sh` builds the frontend automatically and copies `WebUI/dist/` into `OverCUE.app/Contents/Resources/WebUI/`.

`OVERCUE_WEB_UI_ROOT` can point the native app at an alternate built asset directory for development. Set `OVERCUE_NATIVE_UI=1` when launching the app to temporarily use the legacy SwiftUI settings surface while Web UI feature parity is still incomplete.

The native app exposes:

- `GET /api/v1/session`
- `GET /api/v1/snapshot`
- `GET /api/v1/shortcuts/panel`
- `PUT /api/v1/presets/order`
- `PUT /api/v1/group-presets/order`
- `PUT /api/v1/group-presets/active`
- `PUT /api/v1/group-presets/add`
- `PUT /api/v1/group-presets/rename`
- `PUT /api/v1/group-presets/delete`
- `PUT /api/v1/group-presets/include`
- `PUT /api/v1/group-presets/assignment`

Group Preset writes reuse `GroupPresetManagementModel`, so native SwiftUI and Web UI share the same validation and configuration mutation rules. Snapshot device entries include the Presets available for that Logical Device's profile so assignment UIs do not need a second lookup API.

Write requests require the startup-scoped token returned by `/session` in `X-OverCUE-Session`. The API binds only to `127.0.0.1`, does not emit permissive CORS headers, and rejects non-loopback browser origins for writes.

## Build

```sh
npm run typecheck
npm run build
```

`dist/` is generated output and must not be committed.
