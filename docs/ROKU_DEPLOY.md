# Roku deployment & testing

Everything needed to build, sideload, and distribute the Reversion TV Roku channel.

## Identifiers

| Thing | Value | What it's for |
|---|---|---|
| Vanity access code | `ZCKHRKP` | Install URL for the beta / non-published channel: `https://my.roku.com/account/add/ZCKHRKP`. Visiting it adds the channel to a Roku account. Not a secret. |

## 1. Developer account

Free account at [developer.roku.com](https://developer.roku.com). One-time developer agreement. This is a personal, free app — nothing to pay or subscribe to.

## 2. Enable Developer Mode on the device

On the Roku, from the Home screen, enter this remote sequence:

**Home x3, Up x2, Right, Left, Right, Left, Right**

Then:
- Enable developer mode.
- Set a **web server password** (used for sideloading — remember it).
- Note the **device IP address** shown.

The device reboots into Developer Mode.

## 3. Build + sideload

The build is wired in `scripts/`:

```bash
bash scripts/build.sh        # validate (brighterscript) + package out/reversion-tv-roku.zip
bash scripts/build.sh --skip-validate
```

### Manual sideload (no config)

If no device is configured, `build.sh` just packages the zip and stops. Then:
1. Browser → `http://<device-ip>`
2. Login: user `rokudev` + the dev web password from step 2.
3. Upload `out/reversion-tv-roku.zip` → installs and launches.

### One-command auto-deploy (recommended once the stick is set up)

Create a gitignored `.env.roku` at the repo root:

```
ROKU_DEV_HOST=192.168.x.x
ROKU_DEV_PASSWORD=yourdevpassword
```

Then `bash scripts/build.sh` validates, packages, and sideloads straight to the
device via `scripts/deploy.sh`. You can also run the deploy on its own:

```bash
bash scripts/deploy.sh
```

`.env.roku` is gitignored, so credentials are never committed.

## 4. Distribute for testing (beta)

Non-published channels are added to a Roku account via the **vanity access code**
URL above (`https://my.roku.com/account/add/ZCKHRKP`). After adding, the channel
appears on the account's Roku devices (may need a device restart / channel
update to pull it down). Use this to test on a real device without sideloading.

## Notes

- **`DynamicKeyboard` (voice search, §8):** not available on the BrightScript
  simulator — requires a real device with firmware ~11.5+. Test voice search via
  sideload or the beta channel, not the sim.
- The packaged zip must contain `manifest`, `source/`, `components/`, `images/`,
  `fonts/` at its root (handled by `scripts/package.sh`).
