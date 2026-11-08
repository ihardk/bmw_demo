# Notes Scanner

A Flutter app that turns photos of rough, handwritten notebook pages into clean, structured notes, **entirely on the phone**. No account, no API key, no cloud. Photos and notes never leave the device.

## How it reads your handwriting

Every scan runs two on-device engines:

1. **Google ML Kit text recognition** (Latin script, about 10 MB, bundled). This always runs first. It is instant, but only fair on messy handwriting.
2. **Gemma 4 E2B** (2.6 GB, downloaded once from Settings, Apache-2.0). This reads each page image, using ML Kit's text as a hint, and writes a structured Markdown note with headings, bullet and numbered lists, to-dos (`- [ ]` / `- [x]`), tables, and a short line for any drawing. It runs through [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) on the LiteRT-LM engine, using the GPU and falling back to the CPU.

If Gemma isn't downloaded, the phone can't run it, or it fails (usually for lack of memory), the app formats ML Kit's text into a note by simple rules. It recognises bullets, numbers, check boxes and `Heading:` lines, and tells you a quick scan was used. Each note card shows which engine made it (✨ for the model, ⚡ for a quick scan).

### Scans run in the background

A scan doesn't block the app. Each one appears as a card at the top of the notes list, showing a progress bar and a live status ("Writing page 1 of 2 · 120 words"). You can open other notes, change settings or queue more scans while it runs; scans are processed one at a time. When a scan finishes, a "Note ready" message appears with an **Open** button.

You can also leave the app. On Android, a foreground service keeps the model running and shows an ongoing "Reading your notes" notification, so the system doesn't freeze the app. If you're still away when the scan finishes, the notification changes to "Note ready", and tapping it opens the app. On first scan the app asks for notification permission (Android 13+). If you decline, scans still run but the notification stays hidden. Swiping the app away from Recents stops a running scan.

**Settings → Reading mode** lets you choose between *Best quality* (Gemma when it's available) and *Quick scan* (ML Kit only).

## Requirements

| | Quick scan (ML Kit) | On-device model (Gemma 4 E2B) |
|---|---|---|
| Android | 11+ (minSdk 30) | 11+, 64-bit ARM, about 4 GB RAM or more (6 GB+ recommended) |
| iOS | 15+ | 15+, a recent iPhone (6 GB RAM or more recommended) |
| Speed | under a second per page | roughly 10–60 s per page, depending on the phone |
| Storage | included in the app | 2.6 GB, one-time download |

The app checks the phone's RAM and CPU at start-up. It hides the model download on phones that can't run it, and warns on phones where it may be slow. The model doesn't run on an Android emulator (x86) or the iOS simulator's GPU. Test on a real phone.

## Run it

```bash
cd notes_scanner
flutter pub get
flutter run --release   # release mode: the model is much faster than in debug
```

Then open **Settings → Download** to get the model. Use Wi-Fi, since the download is 2.6 GB. The download keeps going if you leave the Settings screen.

### iOS notes

- `ios/Runner/Runner.entitlements` turns on the *increased memory limit* and *extended virtual addressing* capabilities that the model needs. Signing needs a paid Apple Developer team that has these capabilities enabled for the app ID.
- All plugins use Swift Package Manager, so no Podfile is needed.

## Code layout

| File | Purpose |
| --- | --- |
| `lib/services/scan_pipeline.dart` | Runs ML Kit, then Gemma (or the rule-based formatter), and reports progress |
| `lib/services/local_model_service.dart` | Gemma: device check, download/cancel/delete, page-reading prompt |
| `lib/services/ocr_service.dart` | ML Kit text recognition |
| `lib/services/ocr_formatter.dart` | Turns raw OCR text into Markdown when the model isn't used |
| `lib/services/note_store.dart` | Saves notes and settings on the device |
| `lib/screens/` | Home (list, search, scan), note (view / edit / original pages), settings |

To change how notes are formatted, edit `_systemInstruction` in `local_model_service.dart`.

## Tests

```bash
flutter test
```
