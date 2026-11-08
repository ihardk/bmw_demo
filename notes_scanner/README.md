# Notes Scanner

A small Flutter app that turns photos of rough, handwritten notebook pages into clean, structured digital notes.

## How it works

1. Tap **Scan notes**, then take a photo or pick one or more pages from the gallery (up to 10).
2. The photos are sent to Claude (`claude-opus-5-5`), which reads the handwriting and rebuilds it as Markdown with headings, lists, to-do checkboxes, tables, and short descriptions of any diagrams.
3. The note is saved on the device. Each note has three tabs:
   - **Note** shows the formatted note (you can select text)
   - **Edit** lets you fix anything in the Markdown
   - **Pages** shows the original photos, with pinch-to-zoom
4. Copy, share or delete a note from the top bar, and search all notes from the home screen.

## Setup

```bash
cd notes_scanner
flutter pub get
flutter run
```

On first scan the app asks for an **Anthropic API key**. You can create one at https://console.anthropic.com. The key is stored only on the device, in `shared_preferences`.

> This is a quick personal or demo setup. Before you publish the app to a store, move the API call behind your own backend so the key never ships on users' devices.

## Code layout

| File | Purpose |
| --- | --- |
| `lib/services/claude_service.dart` | Builds the Messages API request (images + transcription prompt) and parses the reply |
| `lib/services/note_store.dart` | Saves notes and the API key on the device |
| `lib/screens/home_screen.dart` | Note list, search, camera/gallery picker, scanning overlay |
| `lib/screens/note_screen.dart` | Note view, Markdown editor, original pages |
| `lib/screens/settings_screen.dart` | API key entry |

To change how notes are formatted, edit `_systemPrompt` in `claude_service.dart`.

## Tests

```bash
flutter test
```
