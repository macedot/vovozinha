# Multi-module architecture

Vovozinha is composed of **feature libraries** + a thin **host app**. Each feature has a **DEBUG harness app** (app + lib) so you can develop and accept behavior in isolation.

## Layout

```
Packages/
  VovoUI/                 # shared theme + screen chrome (all apps look the same)
  StoryPromptKit/         # first feature: seed prompt → story draft
Apps/
  Vovozinha/              # product host — wires feature libs
  StoryPromptDebug/       # DEBUG-only harness for StoryPromptKit
Legacy/
  VovozinhaLegacy/        # previous full app (run scheme VovozinhaLegacy)
```

## Schemes

| Scheme | What it runs |
|--------|----------------|
| **Vovozinha** | New host app (Story Prompt feature) |
| **StoryPromptDebug** | StoryPromptKit alone |
| **VovozinhaLegacy** | Old monolithic app (for reference / migration) |

## Feature pattern (app + lib)

1. **Lib** (`Packages/<Feature>Kit`): models, protocols, pure generation, `*FeatureView`.
2. **Debug app** (`Apps/<Feature>Debug`): `@main` that only shows the feature view with `VovoUI` chrome.
3. **Host** (`Apps/Vovozinha`): imports kits and composes them into the product flow.

## Story Prompt (current feature)

- Input: free-form **story seed** (base of the story).
- Constraint: **10–20 words** (inclusive).
- Output: title, summary, **10 scene paragraphs**; story language stored on `StoryDraft`.
- **Generator backends** (protocol `StoryFromPromptGenerating`):
  - `OfflineFirstStoryGenerator` — **default for both apps**. On-device LiteRT-LM when the model is present; deterministic offline fallback in the simulator, before the model download, or on any inference error (never breaks the offline guarantee).
  - `LiteRTLMStoryGenerator` — on-device LLM via **LiteRT-LM** (Gemma 3n E2B int4). Model downloaded once by `LiteRTLMModelStore` to `Documents/Vovozinha/Models/`. Always uses the `.gpu`/Metal backend. ⚠️ **Does NOT work in the iOS Simulator** — LiteRT-LM generation is device-only; `OfflineFirstStoryGenerator` routes to the offline generator in the simulator.
  - `OfflineStoryFromPromptGenerator` — deterministic fallback, always available.
- **Languages:** pt-BR / en-US / es-ES via `LanguageBar` + `LanguageStore` in **VovoUI**. UI strings (`VovoL10n`) and both story bodies follow the selected language.

## Static text (Markdown on disk)

All user-facing / generator copy lives in **Markdown** (`## key` sections, `{{placeholders}}`), loaded by `MarkdownTextCatalog`:

| Package | Path | Purpose |
|---------|------|---------|
| **VovoUI** | `Sources/VovoUI/Resources/Strings/{en-US,pt-BR,es-ES}.md` | UI strings |
| **StoryPromptKit** | `Sources/StoryPromptKit/Resources/Prompts/offline.<lang>.md` | Offline story templates (fallback generator) |
| **StoryPromptKit** | `Sources/StoryPromptKit/Resources/Prompts/litert.<lang>.md` | LiteRT-LM prompt templates (instruct `TITLE:`/`SUMMARY:` + 10 paragraphs) |

Edit the `.md` files and rebuild. See each folder’s `README.md`.

## Adding the next feature

1. `Packages/NewFeatureKit` + tests  
2. `Apps/NewFeatureDebug` target + scheme  
3. Host app navigates to / embeds `NewFeatureView`  
4. Keep UI via `VovoUI.VovoScreen` / buttons / colors  
