# Sideloading Down Under Bird Collector onto your iPhone

You can install the full iPhone app — sound ID, offline field guide, camera
capture — without the App Store or a paid Apple developer account. You install
an `.ipa` file with a sideloading tool, which signs it with **your own Apple ID**.

Needs: an iPhone on **iOS 17 or later**, a Windows PC or Mac, a USB cable, and
an Apple ID (a free one works).

## 1. Get the app file

Download the latest `DownUnderBirdCollector-<version>.ipa` from the
repository's **Releases** page (on GitHub: *Releases* in the right-hand
column). Each release is built automatically by the *Sideload build* workflow.

To build a fresh one yourself: on GitHub open **Actions → Sideload build → Run
workflow**, wait ~15 minutes, and download the `.ipa` from the run's
*Artifacts* (it arrives zipped — unzip it). Pushing a tag such as `ios-1.0.1`
publishes it as a Release instead.

## 2. Install it

Both tools change their setup steps from time to time — if what you see
differs from below, follow the tool's own guide on its website.

### Option A — Sideloadly (simplest, Windows or Mac)

1. Install [Sideloadly](https://sideloadly.io). On Windows, also install
   **iTunes and iCloud from Apple's website** (not the Microsoft Store
   versions) so your PC can talk to the iPhone.
2. Plug in the iPhone, unlock it and tap **Trust This Computer**.
3. Open Sideloadly, drag the `.ipa` onto it, enter your Apple ID and click
   **Start**. (Sideloadly sends your Apple ID only to Apple, to make the
   signing certificate. Using a secondary Apple ID is fine too.)

### Option B — AltStore (refreshes itself over Wi-Fi)

1. Install AltServer from [altstore.io](https://altstore.io) on your PC/Mac
   (Windows also needs iTunes and iCloud from Apple's website), and use it to
   install AltStore on the iPhone.
2. Copy the `.ipa` to the iPhone (AirDrop, iCloud Drive, or download the
   Release in Safari), then in AltStore tap **My Apps → +** and choose it.

## 3. First launch on the iPhone

- **Enable Developer Mode** (iOS 16 and later): *Settings → Privacy & Security
  → Developer Mode* → on, then restart when asked. The option appears after
  the first sideloaded install.
- **Trust your Apple ID** as a developer: *Settings → General → VPN & Device
  Management* → your Apple ID → **Trust**.
- Open the app and allow camera, location and microphone when asked. Open
  *Identify by sound* once — the BirdNET model is already inside this build,
  so it works offline straight away.

## Keeping it working

- **With a free Apple ID the app stops opening after 7 days** until it's
  re-signed. Your sightings are kept — just refresh it: re-install the same
  `.ipa` with Sideloadly (or turn on its auto-refresh), or let AltStore
  refresh it while your phone and AltServer are on the same Wi-Fi.
- A free Apple ID can have **3 sideloaded apps** active at a time.
- With a **paid Apple Developer account** ($99/yr) a signed install lasts a
  year — or use TestFlight instead (see [DEPLOYMENT.md](DEPLOYMENT.md)).
- **Updating:** install the newer `.ipa` the same way; it replaces the app and
  keeps your sightings, as long as you use the same tool and Apple ID.
- **Don't delete the app** unless you mean to: sightings live only on the
  phone, so deleting it deletes them (they're in your iPhone backups).

## What's different from an App Store build

Nothing you'd notice: everything runs on the phone. Cloud sync (Firebase, with
Sign in with Apple) isn't included — the sideload build is the standard
on-device version. The app's bundle ID may be changed by the sideloading tool;
that's expected.
