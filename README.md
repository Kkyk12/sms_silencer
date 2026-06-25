# SMS Guard (sms_silencer)

An Android app that **silences notifications from chosen SMS senders** while letting
everyone else ring normally.

It works by becoming the device's **default SMS app**, so it can intercept each
incoming text and decide — before any sound plays — whether it should ring or be
saved silently.

> **📱 Android only.** This app must be the device's default SMS app, which only
> Android allows. iOS does not let apps read or silence SMS, so it **cannot run on
> iPhone** — there is no iOS version.

## How it works

- Texts from senders on the **silence list** are saved to the inbox **without sound
  or vibration**.
- Texts from any other sender **ring** with a normal notification.
- Texts from **blocked** senders are **dropped on arrival** — not stored, no
  notification. Existing conversations are kept; only new messages are dropped.
- A curated set of automated/bulk senders (telecom, banks, government services,
  short codes) ships **silenced by default**; each can be toggled back on.
- You can **add your own senders** (by number or name) to silence, and remove them
  at any time.

Beyond filtering it works as a normal default SMS app: send/receive SMS, threaded
conversations, contact names/photos, dual-SIM send, scheduled messages, draft
persistence, and per-thread silence/block/pin.

### Sender matching

A single canonical rule decides whether two senders are "the same" (shared by the
native filter and the Dart UI, so silencing/blocking and threading always agree).
Ethiopian numbers collapse to their 9 national digits, so `+251912345678`,
`251912345678`, `0912345678` and `912345678` are treated as one contact, while
short codes (`830`, `8161`) and alphanumeric IDs (`telebirr`, `Awash Bank`) compare
as case-folded text and stay distinct.

## Privacy

SMS Guard does one job without touching your data:

- **No network access.** The release build declares **no `INTERNET` permission**, so
  your messages and contacts cannot be sent anywhere. There are no servers,
  accounts, ads, or analytics.
- **Read only to filter.** Texts are read solely to decide ring vs. silent and to
  show them in the app.
- **Everything stays on-device.** Your silence list lives only in the app's local
  storage on your phone.

## Architecture

The filtering decision must run even when the UI is closed, so the core lives in
native code:

- **Flutter (Dart)** — the UI: message list, silence-list manager, status/permissions.
- **Native Android (Kotlin)**
  - `SmsReceiver` handles `SMS_DELIVER`, persists the message, and posts a loud or
    silent notification depending on the silence list (or drops it if blocked).
  - `MmsReceiver` handles `WAP_PUSH_DELIVER`; `HeadlessSmsSendService` answers
    respond-via-message — both required so the app qualifies as the default SMS app.
  - `Identity` is the single canonical sender-matching rule, mirrored in
    `lib/identity.dart`, so the native filter and the UI always agree.
  - `SmsStore` is the shared write/send layer: it stamps `THREAD_ID` on every
    insert (so replies don't fork a second thread) and tracks real send status
    (`OUTBOX` → `SENT`/`FAILED`).
  - `Prefs` holds the silence/block/pin lists and scheduled messages.
  - A `MethodChannel` (`sms_guard/native`) exposes the silence list and inbox to Dart.

## Build & run

```bash
flutter pub get
flutter run                                                  # debug
flutter build apk --release --target-platform android-arm64  # small release APK
```

On first launch, grant SMS/Notification permissions and set the app as your default
SMS app (Status tab) to enable filtering.

### Release signing

Release builds are signed from `android/key.properties` (gitignored). Copy
`android/key.properties.example` to `android/key.properties` and fill in your
keystore details before publishing. **If the file is absent the release build
falls back to the debug key and prints a warning — do not publish that artifact**
(the debug key would lock you out of future updates). R8/resource shrinking is
enabled for release.

## Limitations

- **MMS is not rendered.** As the default app the system hands every incoming MMS
  to SMS Guard; rather than silently dropping it, the app stores a
  `[Multimedia message]` placeholder attributed to the sender and notifies you, but
  it does not download or display the picture/media. Sending MMS and group MMS are
  not implemented.
- **RCS is not supported.** Android exposes no practical public API for third-party
  apps to send or receive RCS — it requires carrier/OEM/Google integration. SMS
  Guard deliberately does not pretend to support it; it focuses on making SMS (and
  basic MMS attribution) solid.

## Notes

- Filtering is active only while SMS Guard remains the default messaging app.
- Android only — SMS interception is not possible on iOS.
