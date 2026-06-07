# Reversion TV — Roku

Roku (BrightScript / SceneGraph) port of the Reversion TV app. Backend is
always production `https://reversion.app`. The cross-platform contract lives in
`~/reversion-tv-assets/TV_APP_SPEC.md` — that doc is the source of truth.

## Status

This is the **setup pass**: a runnable channel with the foundations and the
Pairing screen.

Done:
- Channel scaffolding (manifest, splash, icons, entry point).
- Foundations: production API client (`§4` contract, 1:1 with Tizen `api.js`),
  async HTTP task with 3× retry + backoff, token storage (`roRegistry`),
  device-name detection, auth gate on boot.
- **Pairing** (`§5`): dash-grouped code + QR (scan to pair) + 1 s countdown with
  auto-regenerate on expiry + poll loop (`202` pending / `200` authorized →
  store token → Home / `410`·`404` → regenerate) + hard-error retry.
- Placeholder Home that confirms the token via `GET /me` and supports sign-out.

Not yet built (later passes): full Home (left nav, hero carousel/spotlight, the
4 rails, catalog mode), Event Detail, Search (incl. voice/STT), Player, Settings
+ legal reader.

## Project layout

```
manifest                      channel metadata, splash, icons
source/main.brs               entry point → MainScene
components/
  MainScene.xml/.brs          auth gate + screen stack
  screens/
    PairingScreen.xml/.brs    device-auth (§5)
    HomeScreen.xml/.brs        placeholder home
  tasks/ApiTask.xml/.brs       async HTTP (retry/backoff, Bearer, 401)
  lib/
    Config.brs                 base URL, keys, device name
    Registry.brs               token store (§11)
    Api.brs                    request builders (§4)
    qrCode/                     vendored MIT QR generator (see LICENSE.txt)
images/                        icons, splash, background, brand logo
scripts/package.sh             build sideload zip
```

## Build / sideload

1. Enable **Developer Mode** on the Roku (Home ×3, Up ×2, Right, Left, Right,
   Left, Right) and note the device IP + the dev password you set.
2. Build the package:

```bash
bash scripts/package.sh
```

3. Open `http://<roku-ip>` in a browser, sign in with the dev password, and
   upload `out/reversion-tv-roku.zip` on the **Installer** page (Replace).

The channel boots to Pairing when there's no token, or to Home when a token is
stored.

## Third-party

`components/lib/qrCode/` is the MIT-licensed
[QR-Code-generator-brightscript](https://github.com/paramount-engineering/QR-Code-generator-brightscript)
(a port of Project Nayuki's QR Code generator). License retained in
`components/lib/qrCode/LICENSE.txt`.
