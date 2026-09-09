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
- `GET /api/v1/shortcuts/live`
- `PUT /api/v1/shortcuts/panel`
- `PUT /api/v1/presets/order`
- `PUT /api/v1/group-presets/order`
- `PUT /api/v1/group-presets/active`
- `PUT /api/v1/group-presets/add`
- `PUT /api/v1/group-presets/rename`
- `PUT /api/v1/group-presets/delete`
- `PUT /api/v1/group-presets/include`
- `PUT /api/v1/group-presets/assignment`
- `PUT /api/v1/devices/add`
- `PUT /api/v1/devices/rebind`
- `PUT /api/v1/devices/identify/cancel`
- `PUT /api/v1/devices/rename`
- `PUT /api/v1/devices/profile`
- `PUT /api/v1/devices/forget-binding`

The Shortcuts editor reuses `ShortcutSettingsModel` plus `GenericHIDShortcutCaptureModel` instead of introducing Web-only mapping logic. The editor panel exposes Action selection, ACK05 key/dial selection, Preset switching and management, rekordbox mode switching, unified ACK05 + Generic HID Learn, overwrite confirmation, binding removal, rotation, and mapping status. Learn pins the editor Preset using the existing native capture lifecycle.

`GET /api/v1/shortcuts/panel` returns the full editor model only for initial load and mutations. `GET /api/v1/shortcuts/live` is the lightweight 50 ms polling path and contains only physical pressed/dial state plus Learn status, so live visualization does not repeatedly serialize the complete rekordbox Action list.

Group Preset writes reuse `GroupPresetManagementModel`, so native SwiftUI and Web UI share the same validation and configuration mutation rules. Snapshot device entries include the Presets available for that Logical Device's profile so assignment UIs do not need a second lookup API.

Device writes reuse the shared `DeviceManagementModel`. Device identify pauses the controller runtime without changing the persisted Controller Input preference, then restores runtime after successful identification, failure, or cancellation. Snapshot device entries expose binding identity, profile options, and current identify state/candidate count so the Web UI can render the same lifecycle as the SwiftUI Devices surface.

Write requests require the startup-scoped token returned by `/session` in `X-OverCUE-Session`. The API binds only to `127.0.0.1`, does not emit permissive CORS headers, and rejects non-loopback browser origins for writes.

## Build

```sh
npm run typecheck
npm run build
```

`dist/` is generated output and must not be committed.
