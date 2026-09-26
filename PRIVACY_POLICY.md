# BokyLearn — Privacy Policy

**Last updated:** 2026-08-17

BokyLearn is an educational mobile app that serves short facts and lets you
expand them with AI. This policy explains what data the app handles, where it
goes, and how you can control or delete it.

## The short version

- BokyLearn has **no account, no login, and no backend server**. There is no
  BokyLearn server that receives, stores, or processes your personal data.
- Your AI provider **API key** stays on your device in the operating system's
  secure storage. It is sent only to the AI provider you choose.
- The fact text you tap, the questions you ask, and the words you look up are
  sent **only** to the AI provider you configured — never to BokyLearn.
- Everything else (your reading history, bookmarks, likes, interests, cached
  articles) lives **locally on your device** in app-private storage.
- There are **no analytics, no advertising SDKs, and no third-party trackers**.

## 1. Data stored on your device

BokyLearn uses on-device storage only. Nothing here leaves your phone unless
you explicitly use the Share feature.

| Data | Where | Purpose |
|------|-------|---------|
| API keys for your chosen AI provider(s) | OS secure storage (iOS Keychain / Android EncryptedSharedPreferences) | Authenticate requests to your AI provider |
| Selected provider, model, mature-content preference, onboarding completion | App preferences | Remember your settings |
| Chosen interests / topics | App preferences | Curate the feed when present; random feed when empty |
| Seen fact history (14-day expiry) | App database | Avoid repeating facts you've already seen |
| Bookmarks and like/dislike reactions | App database | Personalise and let you revisit facts |
| Tag affinity weights | App database | Adjust the feed toward topics you engage with |
| Cached AI-generated articles | App database | Instant re-open without re-calling the AI |
| Downloaded facts catalogue | App database | The local fact feed (sourced from a public GitHub repository) |

You can clear all of the above at any time by using your device's
**"Clear app data"** option, or by uninstalling the app.

## 2. API keys

BokyLearn is "Bring Your Own Key" (BYOK). You supply your own API key for the
AI provider you select in Settings.

- API keys are written to the platform secure storage using
  `flutter_secure_storage` and are **never** written to plain storage, logs, or
  network requests except to the AI provider's own authenticated endpoint.
- API keys are **never** transmitted to BokyLearn or any BokyLearn-operated
  service (there are none).
- Removing the key in Settings deletes it from secure storage.

## 3. Data sent to third-party AI providers

When you choose to expand a fact, ask a follow-up question, or look up a word
or phrase, BokyLearn builds a prompt and sends it to the AI provider you
configured. The data sent includes:

- the fact text you tapped,
- your follow-up question or selected text,
- lightweight background context (a short Wikipedia summary related to the
  fact), and
- your configured model name.

Supported providers:

- OpenAI Platform API
- OpenRouter API
- Anthropic API
- Google Gemini API
- Ollama Cloud API
- Ollama (self-hosted, configurable URL)
- OpenCode Go API

This data is handled under each provider's own privacy policy and terms.
BokyLearn does **not** retain these prompts or responses on any server; cached
articles are kept only in your local app database (see Section 1).

## 4. Facts content and Wikipedia lookups

- The fact feed is downloaded from a **public GitHub repository**
  (`sarel-myburgh/facts`) over HTTPS. Downloading facts sends only standard
  request metadata (IP address, etc.) to GitHub's CDN, which is governed by
  GitHub's privacy policy.
- To ground AI responses, BokyLearn may fetch a short summary or search result
  from **Wikipedia** (and the Wikimedia REST API). This sends the relevant
  article title or your selected term as a query. No personal data is included.
- BokyLearn does not modify, resell, or analyse this content beyond displaying
  it to you.

## 5. Sharing

The Share feature uses your device's native share sheet to send fact text and
a source link to an app you choose (e.g. messaging, email). BokyLearn only
passes the selected text to the share sheet; it does not receive or store
anything you do with it.

## 6. Children

BokyLearn is an educational app suitable for general audiences, with a
mature-content filter that is **off by default**. It is not directed
specifically at children under 13, and it collects no personal information
from any user.

## 7. Your rights and data deletion

Because all personal data is stored locally on your device, you control it
entirely:

- **Delete cached articles, history, bookmarks, and reactions:** clear app data
  or uninstall.
- **Remove your API key:** delete it in Settings.
- **Stop AI calls:** you are never required to provide a key; the feed works
  without any AI provider configured.

## 8. Changes to this policy

If this policy changes, the updated version will be posted at the same location
and the "Last updated" date revised.

## 9. Contact

Questions about privacy can be directed to the project maintainer via the
BokyLearn repository: https://github.com/sarel-myburgh/BokyLearn

---

*This policy is provided as a starting point. Before publishing to Google Play
or the Apple App Store, have it reviewed for your specific jurisdiction and
link it from your store listing and an in-app "Privacy Policy" entry.*
