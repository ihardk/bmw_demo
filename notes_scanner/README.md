# Notes Scanner

A Flutter app that turns photos of rough, handwritten notebook pages into clean, structured notes, **entirely on the phone**. No account, no API key, no cloud. Photos and notes never leave the device.

## How it reads your handwriting

Every scan runs two on-device engines:

1. **Google ML Kit text recognition** (Latin script, about 10 MB, bundled). This always runs first. It is instant, but only fair on messy handwriting.
2. **Gemma 4 E2B** (2.6 GB, downloaded once from Settings, Apache-2.0). This reads each page image, using ML Kit's text as a hint, and writes a structured Markdown note with headings, bullet and numbered lists, to-dos (`- [ ]` / `- [x]`), tables, and a short line for any drawing. It runs through [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) on the LiteRT-LM engine, using the GPU and falling back to the CPU.

If Gemma isn't downloaded, the phone can't run it, or it fails (usually for lack of memory), the app formats ML Kit's text into a note by simple rules. It recognises bullets, numbers, check boxes and `Heading:` lines, and tells you a quick scan was used. Each note card shows which engine made it (✨ for the model, ⚡ for a quick scan).

### Models and comparing them

**Settings → Models** lists 9 on-device models. You can download any of them, pick the one scans use, and delete them again. All are free to download (no Hugging Face login), and each file is pinned to a fixed commit and checked for size.

| Model | Maker | Kind | Size | Notes |
|---|---|---|---|---|
| Gemma 4 E2B | Google | general | 2.6 GB | the default |
| Gemma 4 E4B | Google | general | 3.7 GB | bigger and slower; 8 GB+ RAM |
| Qwen2-VL 2B | Alibaba Qwen | general | 1.8 GB | sees 672×672 |
| InternVL3.5 2B | Shanghai AI Lab | general | 1.6 GB | sees 448×448 |
| LFM2.5-VL 1.6B | Liquid AI | general | 1.3 GB | sees 512×512 |
| Xiaomi-OCR-0 | Xiaomi | OCR | 1.3 GB | CPU; sees 768×1344 |
| PaddleOCR-VL 1.6 | Baidu | OCR | 1.4 GB | GPU only; sees 560×560 |
| OvisOCR2 | Alibaba AIDC | OCR | 1.3 GB | CPU; sees 512×512 |
| Unlimited-OCR-2 | Baidu | OCR | 3.8 GB | CPU; ~8 GB storage incl. cache; 8 GB+ RAM |

Each model runs with the settings its Hugging Face card gives:
- **Image shape and padding:** the page is turned upright from its EXIF data, then padded to the model's fixed input shape, because the runtime would otherwise stretch it.
- **Prompt:** general models get the note-making instructions plus ML Kit's text as a hint. OCR specialists get their own task prompt, or none for Unlimited-OCR-2.
- **Hardware:** CPU or GPU, as the card recommends.
- **Decoding:** OCR models always pick the most likely word (greedy).
- **Engine per page:** hybrid models get a fresh engine for each page.

To compare models, open a note → **Compare** tab → **Compare models…**, and tick the downloaded models you want. They run in the background, one after another, on the note's own photos. Each result is saved with the note and shows its total time, model load, time to first word, tokens/s, peak app RAM, backend and word count. An "At a glance" table ranks them. **Use as note** makes one model's text the note, and the previous text is kept in Compare.

These are personal-use picks. The models come under their own licenses (mostly Apache-2.0; LFM2.5 has Liquid AI's license, Unlimited-OCR-2 is MIT).

### Chat

The 💬 icon on the home screen opens a text chat with an on-device model. It starts with the model used for scans if that one can chat, and a dropdown switches between your downloaded models that can chat:
- **Normal conversation:** Gemma 4 E2B, Gemma 4 E4B, Qwen2-VL 2B, LFM2.5-VL 1.6B.
- **One message at a time:** InternVL3.5 2B. Its card warns that later turns degrade on this runtime, so each message is answered on its own.
- OCR specialists can't chat, so they aren't offered.

Answers stream in as Markdown. **Stop** ends an answer early and **New chat** starts over; hybrid models get a fresh engine for this. Each answer shows its time to first word, tokens/s and token count. The bar at the top shows where the model runs, its load time and app RAM. The model loads without its image reader to save memory, and is freed when you leave the screen. Nothing is saved: the chat lasts only while the screen is open.

### Several pages in one go

**Scan notes → Scan pages** opens Google's document scanner, delivered through Google Play services. You can take pages one after another, with auto-capture, edge detection and cropping. You can also import from the gallery inside the scanner. If the scanner isn't available, the app falls back to the camera and asks "Next page" or "Scan N pages" after each photo. **Choose from gallery** picks up to 20 photos.

### Activity screen

Tap a running scan, or the ♥ monitor icon in the top bar, to see:
- **Memory:** this app's memory (now and peak) and the phone's RAM used and free, refreshed every 1.5 s. It warns when free memory gets low.
- **The running scan:** stage, page, elapsed time and model load time. It also shows *image + prompt* time (until the first word), speed in tokens/s, words and tokens written, per-page times, and where the model runs (e.g. `GPU · vision CPU`, as the engine reports it after any fallback).
- **Live output:** the note as the model writes it.
- When idle, it shows a summary of the last scan.

The model already runs off the UI thread. LiteRT-LM generates on native worker threads, and its slow setup steps run on separate Dart isolates, so the screen stays responsive during a scan.

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
