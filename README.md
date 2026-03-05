# Oral Scribe

A macOS dictation app that lives in your menu bar. Press a hotkey, speak, and your transcribed text is delivered wherever you need it — the active text field, clipboard, Apple Notes, or a file.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Multiple transcription backends** — Apple Speech (live, fast), WhisperKit (on-device, accurate), Whisper.cpp (on-device, CoreML accelerated), OpenAI Whisper (cloud)
- **LLM post-processing** — Clean up grammar, summarize, or apply a custom prompt via Ollama
- **Output destinations** — Active text field, clipboard, Apple Notes, append to file
- **Global hotkey** — Press once to start, once to stop (default ⌥⇧R, rebindable)
- **Floating pill overlay** — Shows recording timer and waveform while active
- **Transcript history** — Persisted log of all transcriptions with timestamps and copy buttons
- **Launch at Login** — Optional auto-start via SMAppService
- **Menu bar + Dock** — Slim popover with pipeline summary and record button; full settings window via Dock

---

## Requirements

- macOS 13.0 or later
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

For on-device Whisper:
- WhisperKit or Whisper.cpp model downloaded from within the app (Settings → Transcription)

For LLM post-processing:
- [Ollama](https://ollama.com) running locally with a model pulled (e.g. `ollama pull llama3.2:1b`)

---

## Building

```bash
git clone git@github.com:neverprepared/oral-scribe.git
cd oral-scribe
xcodegen generate
open OralScribe.xcodeproj
```

Then build and run in Xcode, or via command line:

```bash
xcodebuild -project OralScribe.xcodeproj -scheme OralScribe -configuration Debug \
  -destination "platform=macOS" build
```

### Required Permissions

On first launch (and after every ad-hoc rebuild), grant:

- **Microphone** — prompted automatically
- **Speech Recognition** — prompted automatically (Apple Speech backend only)
- **Accessibility** — required for text injection into active fields

> **Note for dev builds:** Ad-hoc signing changes the code signature on every build. After rebuilding, run `tccutil reset Accessibility com.oralscribe.app` and re-grant Accessibility in System Settings → Privacy & Security → Accessibility.

---

## Usage

| Action | How |
|---|---|
| Start / stop recording | Press ⌥⇧R (or click the record button) |
| Cancel recording | Click ✕ on the floating pill overlay |
| Open settings | Click the menu bar icon → **Open App** |
| View past transcriptions | App window → **History** sidebar |
| Change backend | App window → **Transcription** sidebar |
| Rebind hotkey | App window → **Shortcut** sidebar |

---

## Transcription Backends

| Backend | Speed | Accuracy | Internet | Notes |
|---|---|---|---|---|
| Apple Speech | Fast | Good | Optional | Live streaming, auto-stops on silence, ~60s limit |
| WhisperKit | Slow | Excellent | No | On-device, punctuated output, file-based |
| Whisper.cpp | Slow | Excellent | No | On-device, CoreML accelerated, file-based |
| OpenAI Whisper | Fast | Excellent | Yes | Requires API key |

---

## Project Structure

```
OralScribe/
├── App/                  # Entry point, AppDelegate
├── Audio/                # AVAudioEngine recording + WAV export
├── Coordinator/          # Recording pipeline orchestration
├── Hotkey/               # KeyboardShortcuts integration
├── Output/               # Clipboard, AX text injection, Notes, file
├── Processing/           # Ollama LLM post-processing
├── Settings/             # SettingsManager, AppSettings types
├── Transcription/        # Engine implementations + model managers
├── Translation/          # Translation.framework (macOS 15+)
└── UI/
    ├── Components/       # RecordButtonView, HotkeyRecorderView, EnginePickerView
    ├── AppContentView.swift      # Main window (NavigationSplitView)
    ├── MenuBarPopoverView.swift  # Slim menu bar popover
    └── RecordingOverlayWindow.swift  # Floating pill overlay
```

---

## License

MIT
