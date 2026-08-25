# Maldari (말다리) — Korean vocabulary flashcards

A polished Flutter app for studying Korean with a local Gemma 3n model.

## Quick start

```bash
flutter pub get
flutter run
```

## LLM server

Maldari talks to `llama.cpp`'s OpenAI-compatible `/v1/chat/completions`
endpoint on `http://127.0.0.1:8080`. The app spawns `llama-server.exe`
automatically on startup if it isn't already running. Configure paths in
**Settings → LLM Server**.

You can also start the server manually:

- Windows: `tools\start-llm.bat`
- PowerShell: `tools\start-llm.ps1`

Required server flags:

```
llama-server -m <model.gguf> --host 127.0.0.1 --port 8080 \
  -c 4096 -ngl 99 --jinja --alias maldari-gemma
```

## Features

- **Review** — typing-based flashcards with a 3D Y-axis flip animation, real-time validation, streak counter, auto-reshuffle.
- **Vocabulary** — searchable list with POS filters and reactive AI auto-fill in the add-word sheet.
- **Examples** — streaming TOPIK I-II sentences with word-level breakdowns.
- **Dark mode by default**, instantly toggleable.
- **Onboarding** on first launch.
- **Export** vocabulary as JSON.

## Architecture

```
lib/
├── main.dart
├── theme/
├── models/vocab_word.dart       (+ hand-written Hive adapter)
├── services/                    (storage, llm_service, llm_launcher)
├── providers/                   (Riverpod)
├── screens/
└── widgets/
```
