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
  - `DeviceStoryGenerator` — **default**. Requires LiteRT-LM model on disk; **throws** if missing or on inference failure. **No static story body.**
  - `StoryPromptFeatureView` **gates** on model presence: open HF download link → user saves to **Downloads** → **Import** into the app (or halt).
  - `LiteRTLMStoryGenerator` — on-device LLM via **LiteRT-LM**. Model file `gemma-4-E4B-it.litertlm` imported via gate into `Documents/Vovozinha/Models/`. Metal `.gpu` backend. Fewer than 10 paragraphs → generation error (never pads empty scenes).
- **Languages:** pt-BR / en-US / es-ES via `LanguageBar` + `LanguageStore` in **VovoUI**.

## Static text (Markdown on disk)

UI strings and **LLM prompt instructions** (not story bodies) live in **Markdown**:

| Package | Path | Purpose |
|---------|------|---------|
| **VovoUI** | `Sources/VovoUI/Resources/Strings/{en-US,pt-BR,es-ES}.md` | UI strings |
| **StoryPromptKit** | `Sources/StoryPromptKit/Resources/Prompts/litert.<lang>.md` | LiteRT-LM prompts (`TITLE:`/`SUMMARY:` + 10 paragraphs) |

Edit the `.md` files and rebuild. See each folder’s `README.md`.

## Adding the next feature

1. `Packages/NewFeatureKit` + tests  
2. `Apps/NewFeatureDebug` target + scheme  
3. Host app navigates to / embeds `NewFeatureView`  
4. Keep UI via `VovoUI.VovoScreen` / buttons / colors  
