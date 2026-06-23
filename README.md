# SMS Guard (sms_silencer)

An Android app that **silences notifications from chosen SMS senders** while letting
everyone else ring normally.

It works by becoming the device's **default SMS app**, so it can intercept each
incoming text and decide — before any sound plays — whether it should ring or be
saved silently.

## How it works

- Texts from senders on the **silence list** are saved to the inbox **without sound
  or vibration**.
- Texts from any other sender **ring** with a normal notification.
- A curated set of automated/bulk senders (telecom, banks, government services,
  short codes) ships **silenced by default**; each can be toggled back on.
- You can **add your own senders** (by number or name) to silence, and remove them
  at any time.

## Architecture

The filtering decision must run even when the UI is closed, so the core lives in
native code:

- **Flutter (Dart)** — the UI: message list, silence-list manager, status/permissions.
- **Native Android (Kotlin)**
  - `SmsReceiver` handles `SMS_DELIVER`, persists the message, and posts a loud or
    silent notification depending on the silence list.
  - `MmsReceiver` / `HeadlessSmsSendService` — required components so the app
    qualifies as the default SMS app.
  - `Prefs` holds the silence list (built-in defaults + user additions).
  - A `MethodChannel` (`sms_guard/native`) exposes the silence list and inbox to Dart.

## Build & run

```bash
flutter pub get
flutter run                                                  # debug
flutter build apk --release --target-platform android-arm64  # small release APK
```

On first launch, grant SMS/Notification permissions and set the app as your default
SMS app (Status tab) to enable filtering.

## Notes

- Filtering is active only while SMS Guard remains the default messaging app.
- Android only — SMS interception is not possible on iOS.
