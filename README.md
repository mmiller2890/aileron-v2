# Aileron

**Aileron** is a native, local-first macOS AI copilot for live interviews, technical discussions, and meetings — built from the ground up in **Swift 6 + SwiftUI + FluidAudio** for Apple Silicon.

No Electron, no WebView, no Rust↔Swift FFI bridge, and no mandatory cloud accounts. System audio capture, voice activity detection, live streaming speech-to-text, speaker diarization, and session storage all run directly on your Mac.

---

## Highlights

- **On-Device Speech Engine (FluidAudio CoreML):**
  - **Parakeet TDT v3** for high-accuracy final transcripts.
  - **Parakeet Realtime EOU** streaming live captions for **both system audio and microphone** with selectable chunk latency (**160 ms**, **320 ms recommended**, or **1280 ms**).
  - **Silero CoreML VAD** with hysteresis, pre-speech buffering, and long-turn splitting.
  - **Sortformer** live speaker labels with one-click speaker renaming (e.g., `Speaker 1` → `Interviewer`).
- **Native System Audio & Microphone Capture:**
  - Direct macOS 14.2+ **CoreAudio Process Tap** — no virtual audio drivers like BlackHole required.
  - Automatic default-output tracking (seamlessly rebinds when you switch to AirPods or headphones) and configurable idle silence auto-stop.
  - Real-time streaming microphone ask (`⌘⇧M`) so words appear live as you speak before refining and sending.
- **Stealth Floating Bar & Collapsible Workspace:**
  - Non-activating floating glass bar (`NSPanel`) with native **`NSWindow.SharingType.none`** screen-share invisibility (hidden from Zoom, Google Meet, Teams, and screen recordings).
  - One-click **Return to App** (`pip.exit`) to dock the floating bar back into the main window, plus collapsible navigation, transcript, session, and prep sidebars (`⌘⌥S` / `⌘⌥T`).
- **Slack-Style Theme Customization:**
  - **System / Light / Dark** modes, curated presets (including vintage print-inspired **Pierre Péron**, **Mostra Noir**, **Villa Amore**, plus **Graphite**, **Aubergine**, **Midnight**, **Forest**, **Espresso**, **Rosewood**, and **Monochrome**).
  - Custom 3-color picker (**Sidebar**, **Accent**, **Live Indicator**), **Window Gradient** toggle, spacing density, text size, and **paste-in Slack theme string** support.
- **Flexible, Keychain-Secured AI Providers:**
  - Native streaming (`URLSession.bytes`) for **Ollama** (auto-discovers local models + keep-alive warmup + reasoning toggle), **LM Studio**, **OpenAI**, **Anthropic**, **Google Gemini**, **Groq**, and **Custom OpenAI-compatible** endpoints.
  - API keys are stored exclusively in **macOS Keychain** (`Security.framework`).
- **Prep Profiles, Vision Q&A & Searchable Archive:**
  - **Prep Profiles** let you save role context, answering style, resume metrics, STAR stories, and job descriptions so answers sound naturally in your own voice.
  - **Screen Capture Q&A (`⌘⇧S`)** via native `ScreenCaptureKit` automatically excludes Aileron's own windows.
  - **SQLite WAL + FTS5** session library with instant full-text search, AI executive summaries, and one-click **Markdown export**.

---

## Requirements

- **Mac:** Apple Silicon (M1 / M2 / M3 / M4)
- **OS:** macOS 14.2 Sonoma or newer (required for CoreAudio Process Tap)
- **Toolchain (building from source):** Xcode 16+ or Swift 6 Command Line Tools
- **Local AI (optional):** [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai) — or use any cloud API key

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/mmiller2890/aileron-v2.git
cd aileron-v2
```

### 2. Build and bundle `Aileron.app`

```bash
chmod +x scripts/bundle-app.sh scripts/generate-icon.swift
./scripts/bundle-app.sh release
```

> Use `./scripts/bundle-app.sh debug` for faster incremental builds during development.

### 3. Launch Aileron

```bash
open build/Aileron.app
```

To install it in your Applications folder:

```bash
cp -R build/Aileron.app /Applications/Aileron.app
```

---

## First-Run Setup

### macOS Permissions

Aileron requests permissions only when you use the corresponding feature:

| Feature | macOS Permission | Where to Enable |
|---|---|---|
| System Audio Capture (`⌘⇧A`) | **System Audio Recording** | System Settings → Privacy & Security → Screen & System Audio Recording |
| Voice Ask (`⌘⇧M`) | **Microphone** | System Settings → Privacy & Security → Microphone |
| Screen Capture Q&A (`⌘⇧S`) | **Screen Recording** | System Settings → Privacy & Security → Screen & System Audio Recording |

> Global keyboard shortcuts use native macOS Carbon hotkeys and do **not** require Accessibility permission.

### Local AI with Ollama (Optional, 100% Private)

```bash
brew install ollama
ollama serve
ollama pull llama3.2
```

Then open **Models → AI Model → Ollama (Local)** and click **Refresh** to select your installed model, or switch to OpenAI, Anthropic, Gemini, Groq, LM Studio, or any custom endpoint and save your API key in macOS Keychain.

### On-Device Speech Models

The first time you click **Listen** (or **Models → Load Models**), FluidAudio downloads and compiles the CoreML speech models locally to `~/Library/Application Support/FluidAudio/`. Subsequent launches load straight from disk.

---

## Keyboard Shortcuts

### Global Shortcuts (Work From Any App)

| Shortcut | Action |
|---|---|
| `⌘\` | Show / Hide Floating Bar |
| `⌘⇧D` | Open / Focus Main Window |
| `⌘⇧A` | Start / Stop System Audio Listening |
| `⌘⇧L` | Answer Last Utterance |
| `⌘⇧S` | Capture Screen & Analyze |
| `⌘⇧M` | Start / Send Live Streaming Voice Ask |

### Window Layout Shortcuts

| Shortcut | Action |
|---|---|
| `⌘⌥S` | Collapse / Expand Navigation Sidebar |
| `⌘⌥T` | Collapse / Expand Live Transcript Panel |

---

## Streaming Latency Guide

You can choose your live streaming chunk size in **Settings → Audio & Capture → Streaming Chunk Latency**:

| Setting | Latency | Accuracy | Best For |
|---|---|---|---|
| **160 ms** | Fastest | ~8–9% WER | Instant word-by-word visual feedback |
| **320 ms (Default)** | ~⅓ second | **~5.7% WER** | Best balance of speed and accuracy |
| **1280 ms** | ~1.3 seconds | Lowest CPU | Battery-conscious long sessions |

Regardless of streaming chunk size, finished utterances are refined by **Parakeet TDT v3** for final accuracy and punctuation.

---

## Development & Testing

Run the unit test suite (`AileronCoreTests`):

```bash
swift test
```

### Project Layout

```text
Sources/
  AileronCore/
    Audio/          # CoreAudio Process Tap, MicCapture, RingBuffer, Preprocessor, VAD Segmenter
    Speech/         # Direct FluidAudio SpeechEngine (Parakeet v3, EOU Streaming, Sortformer) & heuristics
    AI/             # Typed SSE/NDJSON AIClient & PromptComposer
    Capture/        # ScreenCaptureKit screenshot service
    Storage/        # macOS KeychainStore, WAL SQLite3 + FTS5 DatabaseStore, SettingsStore
    Models/         # Domain, Settings, and Theme models
    Engine/         # @MainActor @Observable AileronEngine
  AileronApp/
    Theme/          # Dynamic ResolvedTheme, Art Deco logo/wordmark, native SwiftUI controls
    Windows/        # Stealth NSPanel, Dashboard NSWindow, Carbon HotKeyManager
    Views/          # HUDView, DashboardView, LiveStudioView, Sessions, Prep, Models, Settings
Tests/
  AileronCoreTests/ # Ring buffer, soft clipper, VAD segmenter, FTS5 SQLite, SSE & theme parsing tests
scripts/
  bundle-app.sh     # Builds, generates AppIcon.icns, packages, and ad-hoc signs Aileron.app
  generate-icon.swift
```

---

## Design Reference

- Graphic Art Deco logo & typography direction: [Fonts In Use — Art Deco](https://fontsinuse.com/tags/2431/art-deco)
