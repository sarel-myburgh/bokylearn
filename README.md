# BokyLearn

BokyLearn is a Flutter learning app that serves short facts, expands them with AI, answers follow-up questions, and lets readers pivot from selected text into a related explanation.

## AI providers

Users choose one provider in Settings, save its API key in platform secure storage, load the models available to that account, and select the model used for generation.

- OpenAI Platform API
- OpenRouter API
- Anthropic API
- Google Gemini API
- Ollama Cloud API
- Ollama Local with a configurable server URL
- OpenCode Go API

Model discovery uses each provider's authenticated model-list endpoint. OpenAI Platform billing is separate from a ChatGPT subscription. BokyLearn does not reuse Codex or ChatGPT login tokens; OpenAI does not document a public Codex OAuth flow for third-party mobile apps.

Local Ollama model discovery uses the server's `/api/tags` endpoint and generation uses `/api/chat`. Use HTTPS for mobile builds; the app does not globally weaken Android transport security to permit arbitrary cleartext HTTP destinations.

## Other capabilities

- Downloads and caches monthly fact data from the companion facts repository
- Filters the feed by interests and mature-content preference
- Tracks recently seen facts and keeps bookmarks
- Streams AI expansions and follow-up answers
- Uses Wikipedia summaries as lightweight grounding context when available

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Build a debug Android APK with:

```powershell
flutter build apk --debug
```
