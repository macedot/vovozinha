# Multi-module architecture

Vovozinha is composed of **feature libraries** + a thin **host app**. Each feature has a **DEBUG harness app** (app + lib) so you can develop and accept behavior in isolation.

## Layout

```
Packages/
  VovoUI/                 # shared theme + screen chrome (all apps look the same)
  StoryPromptKit/         # feature: seed prompt → story draft
  PhotoDescribeKit/       # feature: photo → short on-device caption (DEBUG)
Apps/
  Vovozinha/              # product host — wires feature libs
  StoryPromptDebug/       # DEBUG-only harness for StoryPromptKit
  PhotoDescribeDebug/     # DEBUG-only harness for PhotoDescribeKit
Legacy/
  VovozinhaLegacy/        # previous full app (run scheme VovozinhaLegacy)
```

## Schemes

| Scheme | What it runs |
|--------|----------------|
| **Vovozinha** | New host app (Story Prompt feature) |
| **StoryPromptDebug** | StoryPromptKit alone |
| **PhotoDescribeDebug** | PhotoDescribeKit alone (VLM caption; not in host yet) |
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
  - `DeviceStoryGenerator` — **default**. Requires **Qwen3.5-4B MLX** pack on disk; **throws** if missing or on inference failure. **No static story body.**
  - `StoryPromptFeatureView` **gates** on model presence: auto-download zip → or HF backup page → **Import** zip/folder (or halt).
  - `MLXStoryGenerator` — on-device LLM via **MLX** + `mlx-community/Qwen3.5-4B-MLX-4bit`. Pack under private `Application Support/Vovozinha/Models/…` (not Documents). Fewer than 10 paragraphs → generation error (never pads empty scenes). See `docs/ON_DEVICE_LLM.md`.
- **Languages:** pt-BR / en-US / es-ES via `LanguageBar` + `LanguageStore` in **VovoUI**.

## Photo Describe (DEBUG kit)

- Input: one photo from Photos (on-device only; never uploaded).
- Output: one short paragraph; priority **persons → objects → scene**.
- **`DevicePhotoDescriber`** / **`MLXPhotoDescriber`**: same Qwen3.5-4B pack as Story Prompt, loaded via **`VLMModelFactory`** (vision weights kept). Reuses `OnDeviceMLXModelStore` from StoryPromptKit for download/import gate.
- Harness: scheme **PhotoDescribeDebug**. Not composed into the host yet.
- Prompts: `Packages/PhotoDescribeKit/.../Resources/Prompts/describe.<lang>.md`.

## Static text (Markdown on disk)

UI strings and **LLM prompt instructions** (not story bodies) live in **Markdown**:

| Package | Path | Purpose |
|---------|------|---------|
| **VovoUI** | `Sources/VovoUI/Resources/Strings/{en-US,pt-BR,es-ES}.md` | UI strings |
| **StoryPromptKit** | `Sources/StoryPromptKit/Resources/Prompts/story.<lang>.md` | Story LLM prompts (`TITLE:`/`SUMMARY:` + 10 paragraphs) |
| **PhotoDescribeKit** | `Sources/PhotoDescribeKit/Resources/Prompts/describe.<lang>.md` | Photo VLM caption prompts |

Edit the `.md` files and rebuild. See each folder’s `README.md`.

## Adding the next feature

1. `Packages/NewFeatureKit` + tests  
2. `Apps/NewFeatureDebug` target + scheme  
3. Host app navigates to / embeds `NewFeatureView`  
4. Keep UI via `VovoUI.VovoScreen` / buttons / colors  
